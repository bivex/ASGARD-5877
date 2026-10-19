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

let entangle_with_accumulator ?(flags_live = false) ~(acc_slot : int) (delta : int64) : Stack_ir.stack_op list =
  if delta = 0L then []
  else if flags_live then [
    PushFlags;
    PushReg acc_slot;
    PushImm delta;
    Add;
    PopReg acc_slot;
    PopFlags;
  ] else [
    PushReg acc_slot;
    PushImm delta;
    Add;
    PopReg acc_slot;
  ]

(* ── Emitting a ghost sequence ────────────────────────────────────────── *)
(** [emit_ghost rng ctx stack_depth flags_live] returns a list of ops forming
    a stack-neutral ghost sequence. Choices depend on current stack depth and
    on whether architectural flags are live: GhostArith contains [Add], which
    overwrites the flags, so it is banned while a produced flag value is
    still needed by a later Jcc/Setcc/Cmov/PushFlags. *)
let emit_ghost ?(entangle = true) rng ~scratch_slot ctx entangle_slot stack_depth flags_live =
  let kinds =
    match (stack_depth >= 1, flags_live) with
    | true,  false -> [| GhostPushPop; GhostDupDrop; GhostArith; GhostKeyAdj; GhostFlags; GhostMemRead |]
    | false, false -> [| GhostPushPop; GhostArith; GhostKeyAdj; GhostFlags; GhostMemRead |]
    | true,  true  -> [| GhostPushPop; GhostDupDrop; GhostKeyAdj; GhostFlags; GhostMemRead |]
    | false, true  -> [| GhostPushPop; GhostKeyAdj; GhostFlags; GhostMemRead |]
  in
  let kind = kinds.(next_int rng (Array.length kinds)) in
  match kind with
  | GhostPushPop when entangle ->
    let imm = next_int64 rng in
    (entangle_with_accumulator ~flags_live ~acc_slot:entangle_slot imm, imm)
  | GhostPushPop ->
    let imm = next_int64 rng in
    ([ PushImm imm; PopReg scratch_slot ], 0L)
  | GhostDupDrop ->
    ([ Dup; PopReg scratch_slot ], 0L)
  | GhostArith when entangle ->
    let a = next_int64 rng in
    let b = next_int64 rng in
    let sum = Int64.add a b in
    let ghost_core =
      if flags_live then
        [ PushFlags; PushImm a; PushImm b; Add; PopReg scratch_slot; PopFlags ]
      else
        [ PushImm a; PushImm b; Add; PopReg scratch_slot ]
    in
    (ghost_core @ entangle_with_accumulator ~flags_live ~acc_slot:entangle_slot sum, sum)
  | GhostArith ->
    let a = next_int64 rng in
    let b = next_int64 rng in
    ([ PushImm a; PushImm b; Add; PopReg scratch_slot ], 0L)
  | GhostKeyAdj ->
    let d = ref (next_int64 rng) in
    while Int64.equal !d 0L do d := next_int64 rng done;
    ([ KeyAdjust !d; KeyAdjust !d ], 0L)
  | GhostFlags ->
    ([ PushFlags; PopFlags ], 0L)
  | GhostMemRead ->
    let sp_slot = Context_allocator.slot_of_reg ctx Register.rsp in
    ([ PushReg sp_slot; ReadMem 8; PopReg scratch_slot ], 0L)

(** [insert_ghosts_into_ops rng ctx ops ghost_rate] walks through [ops]
    and inserts ghost sequences at each non-terminator gap with probability
    [ghost_rate] (0–100 integer percent). Terminators are never padded.
    Flag-liveness aware: no flag-writing ghost (GhostArith) is inserted at
    a gap where produced flags are still live.
    Data-Flow Entanglement (P1-02): chains ghost computations into execution
    checksum Sigma_{exec} bound to effective memory addresses. *)
let insert_ghosts_into_ops ?(entangle = true) ~entangle_slot ~scratch_slot rng ctx ops ghost_rate =
  let checksum = ref 0L in
  let depth = ref 0 in
  let result = ref [] in
  let emit op = result := op :: !result in
  let live = Stack_flag_liveness.analyze_list ops in
  let idx = ref 0 in
  let emit_ghost_here flags_live =
    let ghost_ops, delta =
      emit_ghost ~entangle ~scratch_slot rng ctx entangle_slot !depth flags_live
    in
    checksum := Int64.add !checksum delta;
    List.iter (fun gop ->
      emit gop;
      depth := !depth + stack_delta gop
    ) ghost_ops
  in
  let maybe_entangle_mem is_write flags_live =
    if entangle && !checksum <> 0L then begin
      if is_write then begin
        if flags_live then begin
          emit Swap;
          emit PushFlags;
          emit Swap;
          emit (PushReg entangle_slot);
          emit (PushImm !checksum);
          emit Sub;
          emit Add;
          emit Swap;
          emit PopFlags;
          emit Swap
        end else begin
          emit Swap;
          emit (PushReg entangle_slot);
          emit (PushImm !checksum);
          emit Sub;
          emit Add;
          emit Swap
        end
      end else begin
        if flags_live then begin
          emit PushFlags;
          emit Swap;
          emit (PushReg entangle_slot);
          emit (PushImm !checksum);
          emit Sub;
          emit Add;
          emit Swap;
          emit PopFlags
        end else begin
          emit (PushReg entangle_slot);
          emit (PushImm !checksum);
          emit Sub;
          emit Add
        end
      end
    end
  in
  (* Zero accumulator at the entry of the block *)
  if entangle then begin
    emit (PushImm 0L);
    emit (PopReg entangle_slot)
  end;
  List.iter (fun op ->
    let i = !idx in
    incr idx;
    (match op with
     | ReadMem _ -> maybe_entangle_mem false live.(i)
     | WriteMem _ -> maybe_entangle_mem true live.(i)
     | _ -> ());
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
  entangle    : bool;    (** Enable data-flow entanglement with memory operations (P1-02) *)
}

let default_ghost_config seed = {
  seed;
  ghost_rate = 40;    (* ~40% chance after each real instruction *)
  max_ghosts = 0;
  entangle = true;
}

(** [apply_block ?entangle_slot cfg ctx block] applies ghost padding to a
    single block.  The scratch slot the ghost sequences pop into is
    allocated once per block and reused by every ghost of that block. *)
let apply_block ?entangle_slot cfg ctx block =
  let entangle_slot =
    match entangle_slot with
    | Some s -> s
    | None -> if cfg.entangle then Context_allocator.alloc_scratch ctx else 0
  in
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
  (* One scratch slot per block, reused by every ghost of that block: a
     ghost sequence is self-contained (it pushes and pops within the
     sequence), so the value is dead when the sequence ends.  Allocating
     a fresh slot per ghost grew the declared context by an order of
     magnitude - the same order as the number of ghost sequences. *)
  let scratch_slot = Context_allocator.alloc_scratch ctx in
  let new_ops =
    insert_ghosts_into_ops ~entangle:cfg.entangle ~entangle_slot ~scratch_slot rng ctx
      block.ops cfg.ghost_rate
  in
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
        let rng2 = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
        let capped_rate = cfg.ghost_rate * cfg.max_ghosts / (max 1 ghost_count) in
        insert_ghosts_into_ops ~entangle:cfg.entangle ~entangle_slot ~scratch_slot rng2 ctx
          block.ops capped_rate
      end
    end
  in
  { block with ops = new_ops }

(** [apply_program cfg ctx prog] applies ghost padding to every block in
    [prog]. The stack balance of each block is preserved exactly by
    construction (each ghost sequence has delta = 0). *)
let apply_program cfg ctx prog =
  let block_ids =
    Hashtbl.fold (fun id _ acc -> id :: acc) prog.blocks []
    |> List.sort Int.compare
  in
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  List.iter (fun id ->
    match Hashtbl.find_opt prog.blocks id with
    | Some b ->
        let entangle_slot =
          if cfg.entangle then Context_allocator.alloc_scratch ctx else 0
        in
        Hashtbl.replace new_blocks id (apply_block ~entangle_slot cfg ctx b)
    | None -> ()
  ) block_ids;
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
