(** Phase 3: Ghost Stack Padding Pass
    ─────────────────────────────────
    Inserts semantically neutral "ghost" stack operations between real
    instructions. Ghost pairs have stack delta = 0, so block balance is
    preserved exactly. Their presence breaks symbolic VSP tracking used
    by devirtualization tools (VTIL stack-pinning, NoVmp, Mergen).

    Ghost operation repertoire (all delta = 0):
      • GhostPushPop:  PushImm <rng>  ; PopReg <scratch>
      • GhostDupDrop:  Dup            ; PopReg <scratch>
                       (only when stack depth >= 1 at insertion point)
      • GhostArith:    PushImm <a>    ; PushImm <b>  ; Add  ; PopReg <scratch>
                       (always delta = 0: +2 then −2)
      • GhostKeyAdj:   KeyAdjust 0L
                       (XOR with 0 is identity; adds an opaque key mutation)

    Insertion is seed-deterministic using SplitMix64, at configurable
    density (ghost_rate: probability 0.0–1.0 per real instruction gap).
*)

open Stack_ir

(* ── SplitMix64 PRNG (same as stack_encoder.ml) ──────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

type ghost_rng = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

(* Uniform [0, n) *)
let next_int rng n =
  let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFFFFFFL) in
  v mod n

(* Boolean with probability p/100 *)
let maybe rng prob =
  next_int rng 100 < prob

(* ── Ghost operation types ────────────────────────────────────────────── *)
type ghost_kind = GhostPushPop | GhostDupDrop | GhostArith | GhostKeyAdj

(* ── Emitting a ghost sequence ────────────────────────────────────────── *)
(** [emit_ghost rng ctx stack_depth] returns a list of ops forming a
    stack-neutral ghost sequence. Choices depend on current stack depth. *)
let emit_ghost rng ctx stack_depth =
  let scratch () = Context_allocator.alloc_scratch ctx in
  (* Choose ghost kind; GhostDupDrop needs depth >= 1 *)
  let kinds =
    if stack_depth >= 1
    then [| GhostPushPop; GhostDupDrop; GhostArith; GhostKeyAdj |]
    else [| GhostPushPop; GhostArith; GhostKeyAdj |]
  in
  let kind = kinds.(next_int rng (Array.length kinds)) in
  match kind with
  | GhostPushPop ->
    let imm = next_int64 rng in
    [ PushImm imm; PopReg (scratch ()) ]
  | GhostDupDrop ->
    [ Dup; PopReg (scratch ()) ]
  | GhostArith ->
    let a = next_int64 rng in
    let b = next_int64 rng in
    [ PushImm a; PushImm b; Add; PopReg (scratch ()) ]
  | GhostKeyAdj ->
    [ KeyAdjust 0L ]

(** [insert_ghosts_into_ops rng ctx ops ghost_rate] walks through [ops]
    and inserts ghost sequences at each non-terminator gap with probability
    [ghost_rate] (0–100 integer percent). Terminators are never padded. *)
let insert_ghosts_into_ops rng ctx ops ghost_rate =
  let depth = ref 0 in
  let out = Buffer.create 32 in
  (* We operate on a list-accumulator for efficiency *)
  let result = ref [] in
  let emit op = result := op :: !result in
  let emit_ghost_here () =
    let ghost_ops = emit_ghost rng ctx !depth in
    List.iter (fun gop ->
      emit gop;
      depth := !depth + stack_delta gop
    ) ghost_ops
  in
  (* Suppress unused Buffer.create warning - use result list directly *)
  ignore out;
  List.iter (fun op ->
    if Stack_balance_pass.is_terminator op then begin
      (* Before the terminator, optionally insert a ghost *)
      if maybe rng ghost_rate then emit_ghost_here ();
      emit op
      (* depth after terminator doesn't matter *)
    end else begin
      emit op;
      depth := !depth + stack_delta op;
      (* After the real op, maybe insert a ghost *)
      if maybe rng ghost_rate then emit_ghost_here ()
    end
  ) ops;
  List.rev !result

(* ── Public API ───────────────────────────────────────────────────────── *)

type ghost_config = {
  seed        : int64;   (** Entropy seed for this build *)
  ghost_rate  : int;     (** Probability 0–100 of inserting a ghost after each op *)
  max_ghosts  : int;     (** Max ghost ops per block (0 = unlimited) *)
}

let default_ghost_config seed = {
  seed;
  ghost_rate = 40;    (* ~40% chance after each real instruction *)
  max_ghosts = 0;
}

(** [apply_block cfg ctx block] applies ghost padding to a single block. *)
let apply_block cfg ctx block =
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
  let new_ops = insert_ghosts_into_ops rng ctx block.ops cfg.ghost_rate in
  (* If max_ghosts is set, trim ghost ops beyond the limit *)
  let new_ops =
    if cfg.max_ghosts <= 0 then new_ops
    else begin
      let real_count = List.length block.ops in
      let total = List.length new_ops in
      let ghost_count = total - real_count in
      if ghost_count <= cfg.max_ghosts then new_ops
      else begin
        (* Keep real ops and first max_ghosts ghost ops; rebuild *)
        (* Simple approach: re-run with lower rate *)
        let rng2 = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
        let capped_rate = cfg.ghost_rate * cfg.max_ghosts / (max 1 ghost_count) in
        insert_ghosts_into_ops rng2 ctx block.ops capped_rate
      end
    end
  in
  { block with ops = new_ops }

(** [apply_program cfg ctx prog] applies ghost padding to every block in
    [prog]. The stack balance of each block is preserved exactly by
    construction (each ghost sequence has delta = 0). *)
let apply_program cfg ctx prog =
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    Hashtbl.replace new_blocks id (apply_block cfg ctx b)
  ) prog.blocks;
  { prog with blocks = new_blocks }

(** [ghost_stats prog_before prog_after] returns a human-readable summary
    of how many ghost ops were injected. *)
let ghost_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after  = count_ops prog_after in
  Printf.sprintf "Ghost padding: %d real ops → %d total ops (%d ghost, +%.0f%%)"
    before after (after - before)
    (float_of_int (after - before) /. float_of_int before *. 100.0)
