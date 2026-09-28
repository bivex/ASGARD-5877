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
      • GhostKeyAdj:   KeyAdjust d ; KeyAdjust d   (d ≠ 0, random)
                       (d XOR d = 0 → key unchanged; but breaks linear key recovery)
      • GhostFlags:    PushFlags   ; PopFlags
                       (saves & restores RFLAGS; neutral even when flags are live)
      • GhostMemRead:  PushReg <sp>; ReadMem 8   ; PopReg <scratch>
                       (canonical host-stack read; neutral to flags and stack depth)

    Insertion is seed-deterministic using SplitMix64, at configurable
    density (ghost_rate: probability 0.0–1.0 per real instruction gap).
*)

open Stack_ir
open Vm_ir

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
type ghost_kind =
  | GhostPushPop
  | GhostDupDrop
  | GhostArith
  | GhostKeyAdj
  | GhostFlags
  | GhostMemRead

(* ── Emitting a ghost sequence ────────────────────────────────────────── *)
(** [emit_ghost rng ctx stack_depth flags_live] returns a list of ops forming
    a stack-neutral ghost sequence. Choices depend on current stack depth and
    on whether architectural flags are live: GhostArith contains [Add], which
    overwrites the flags, so it is banned while a produced flag value is
    still needed by a later Jcc/Setcc/Cmov/PushFlags. *)
let emit_ghost rng ctx stack_depth flags_live =
  let scratch () = Context_allocator.alloc_scratch ctx in
  let kinds =
    match (stack_depth >= 1, flags_live) with
    | true,  false -> [| GhostPushPop; GhostDupDrop; GhostArith; GhostKeyAdj; GhostFlags; GhostMemRead |]
    | false, false -> [| GhostPushPop; GhostArith; GhostKeyAdj; GhostFlags; GhostMemRead |]
    | true,  true  -> [| GhostPushPop; GhostDupDrop; GhostKeyAdj; GhostFlags; GhostMemRead |]
    | false, true  -> [| GhostPushPop; GhostKeyAdj; GhostFlags; GhostMemRead |]
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
    (* Use a non-zero random delta so the key stream is genuinely perturbed.
       Two consecutive KeyAdjust with the same delta cancel:
         key' = key XOR d XOR d = key  (XOR is self-inverse)
       The runtime decoder sees the same effective key at the next real op,
       but a static analyser tracing the key stream must symbolically evaluate
       both mutations instead of recognising a trivial XOR-0 no-op. *)
    let d = ref (next_int64 rng) in
    (* Guarantee non-zero: loop is extremely unlikely to iterate more than once *)
    while Int64.equal !d 0L do d := next_int64 rng done;
    [ KeyAdjust !d; KeyAdjust !d ]
  | GhostFlags ->
    [ PushFlags; PopFlags ]
  | GhostMemRead ->
    let sp_slot = Context_allocator.slot_of_reg ctx Register.rsp in
    [ PushReg sp_slot; ReadMem 8; PopReg (scratch ()) ]

(** [insert_ghosts_into_ops rng ctx ops ghost_rate] walks through [ops]
    and inserts ghost sequences at each non-terminator gap with probability
    [ghost_rate] (0–100 integer percent). Terminators are never padded.
    Flag-liveness aware: no flag-writing ghost (GhostArith) is inserted at
    a gap where produced flags are still live. *)
let insert_ghosts_into_ops rng ctx ops ghost_rate =
  let depth = ref 0 in
  (* We operate on a list-accumulator for efficiency *)
  let result = ref [] in
  let emit op = result := op :: !result in
  (* live.(i): flags entering instruction i are still needed *)
  let live = Stack_flag_liveness.analyze_list ops in
  let idx = ref 0 in
  let emit_ghost_here flags_live =
    let ghost_ops = emit_ghost rng ctx !depth flags_live in
    List.iter (fun gop ->
      emit gop;
      depth := !depth + stack_delta gop
    ) ghost_ops
  in
  List.iter (fun op ->
    let i = !idx in
    incr idx;
    if Stack_balance_pass.is_terminator op then begin
      (* Before the terminator, optionally insert a ghost. The terminator
         itself may consume the flags (Jcc), so use its entry liveness. *)
      if maybe rng ghost_rate then emit_ghost_here live.(i);
      emit op
      (* depth after terminator doesn't matter *)
    end else begin
      emit op;
      depth := !depth + stack_delta op;
      (* After the real op, maybe insert a ghost *)
      if maybe rng ghost_rate then emit_ghost_here live.(i + 1)
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
  (* Ghost PopReg slots may be freshly allocated — grow the context *)
  { prog with
    blocks = new_blocks;
    context_slots = max prog.context_slots (Context_allocator.total_slots ctx) }

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
