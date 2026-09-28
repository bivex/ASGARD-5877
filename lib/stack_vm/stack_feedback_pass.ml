(** Phase 2c / Anti-Tracing: State-Feedback Rolling Key Pass
    ───────────────────────────────────────────────────────
    Couples bytecode rolling key decryption with dynamic VM execution state,
    defeating static and isolated-block dynamic tracing attacks.
*)

open Stack_ir

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 0 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFF_FFFFL) in
    v mod n

let maybe rng prob = next_int rng 100 < prob

(* ── Public API & Configuration ───────────────────────────────────────── *)

type feedback_config = {
  seed                : int64;
  feedback_rate       : int;   (** Probability (0–100) of injecting feedback on known registers *)
  enable_cff_feedback : bool;  (** Inject VPC token feedback at CFF block entries *)
}

let default_feedback_config seed = {
  seed;
  feedback_rate = 80;
  enable_cff_feedback = true;
}

type feedback_stats = {
  initial_ops       : int;
  final_ops         : int;
  feedback_injected : int;
}

let apply_block cfg ~rng ?entry_feedback block =
  let rec aux = function
    | [] -> []
    | SetRegImm (slot, imm) :: rest ->
        if maybe rng cfg.feedback_rate then
          SetRegImm (slot, imm) :: KeyFeedback (slot, imm) :: aux rest
        else
          SetRegImm (slot, imm) :: aux rest
    | PushImm imm :: PopReg slot :: rest ->
        if maybe rng cfg.feedback_rate then
          PushImm imm :: PopReg slot :: KeyFeedback (slot, imm) :: aux rest
        else
          PushImm imm :: PopReg slot :: aux rest
    | op :: rest ->
        op :: aux rest
  in
  let ops = aux block.ops in
  let ops_with_head =
    match entry_feedback with
    | Some (slot, token) -> KeyFeedback (slot, token) :: ops
    | None -> ops
  in
  { block with ops = ops_with_head }

let apply_program ?vpc_slot ?block_tokens cfg prog =
  let rng = make_rng cfg.seed in
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    let entry_feedback =
      if cfg.enable_cff_feedback && id <> prog.entry_id then
        match vpc_slot, block_tokens with
        | Some vpc, Some tokens ->
            (match Hashtbl.find_opt tokens id with
             | Some t -> Some (vpc, t)
             | None -> None)
        | _ -> None
      else None
    in
    Hashtbl.replace new_blocks id (apply_block cfg ~rng ?entry_feedback b)
  ) prog.blocks;
  { prog with blocks = new_blocks }

let feedback_stats prog_before prog_after =
  let count_feedback prog =
    Hashtbl.fold (fun _ b acc ->
      List.fold_left (fun count -> function
        | KeyFeedback _ -> count + 1
        | _ -> count
      ) acc b.ops
    ) prog.blocks 0
  in
  let initial_ops = Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog_before.blocks 0 in
  let final_ops   = Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog_after.blocks 0 in
  let injected    = count_feedback prog_after in
  {
    initial_ops;
    final_ops;
    feedback_injected = injected;
  }
