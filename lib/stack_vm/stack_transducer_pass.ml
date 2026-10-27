(** Phase 5d: Stateful Transducer Pass (Key-Coupled Micro-Ops)
    ──────────────────────────────────────────────────────────
    Defeats Inductive Program Synthesis (Syntia, QSynth, MCTS formula search)
    by transforming pure ALU expressions into stateful transducer operations
    coupled to an evolving internal state register.

    Soundness Invariants:
      1. Zero Net Stack Delta: Transducer cluster matches original op delta (-1).
      2. Flag Preservation: Only applied when downstream flags are dead
         (Stack_flag_liveness.analyze_list b.ops gives live.(idx + 1) == false).
      3. Exact Modular Equivalence: Guaranteed across all 2^64 values:
         (B - S) + (A + S) == A + B (mod 2^64)
         (A + S) - (B + S) == A - B (mod 2^64)
      4. State Evolution: S advances via LCG over Z_{2^64} with Hull-Dobell period.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type transducer_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_transducer_config seed = {
  enabled = true;
  rate = 50;
  seed;
}

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  (s, logxor z (shift_right_logical z 31))

let next_int rng n =
  if n <= 1 then 0
  else
    let s, z = splitmix64 rng.state in
    rng.state <- s;
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

let emit_step ~state_slot =
  [
    PushReg state_slot;
    PushImm transducer_step_mul;
    Mul;
    PushImm transducer_step_add;
    Add;
    PopReg state_slot;
  ]

(** Transforms [B, A] on stack into (B - S) + (A + S) == A + B *)
let transform_add ~state_slot =
  emit_step ~state_slot @ [
    PushReg state_slot;  (* [S, B, A] *)
    Sub;                 (* [B - S, A] *)
    Swap;                (* [A, B - S] *)
    PushReg state_slot;  (* [S, A, B - S] *)
    Add;                 (* [A + S, B - S] *)
    Add;                 (* [(A + S) + (B - S)] = [A + B] *)
  ]

(** Transforms [B, A] on stack into (A + S) - (B + S) == A - B *)
let transform_sub ~state_slot =
  emit_step ~state_slot @ [
    Swap;                (* [A, B] *)
    PushReg state_slot;  (* [S, A, B] *)
    Add;                 (* [A + S, B] *)
    Swap;                (* [B, A + S] *)
    PushReg state_slot;  (* [S, B, A + S] *)
    Add;                 (* [B + S, A + S] *)
    Sub;                 (* (A + S) - (B + S) = A - B *)
  ]

let apply_block (cfg : transducer_config) ~state_slot _ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x3141 + 0x5926)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    List.iteri (fun idx op ->
      let flags_dead =
        if idx + 1 < Array.length live then not live.(idx + 1)
        else true
      in
      if flags_dead && next_int rng 100 < cfg.rate then
        match op with
        | Add ->
            let cluster = transform_add ~state_slot in
            new_ops := List.rev cluster @ !new_ops
        | Sub ->
            let cluster = transform_sub ~state_slot in
            new_ops := List.rev cluster @ !new_ops
        | other ->
            new_ops := other :: !new_ops
      else
        new_ops := op :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program ?state_slot (cfg : transducer_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let state_slot =
      match state_slot with
      | Some s -> s
      | None -> Context_allocator.alloc_scratch ctx
    in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~state_slot ctx b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let transducer_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let b_before = count_ops prog_before in
  let b_after = count_ops prog_after in
  Printf.sprintf "Transducer Coupling: %d ops -> %d ops (+%d transducer steps, +%.1f%%)"
    b_before b_after (b_after - b_before)
    (if b_before = 0 then 0.0 else float_of_int (b_after - b_before) /. float_of_int b_before *. 100.0)
