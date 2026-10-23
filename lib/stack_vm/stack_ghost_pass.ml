(** Phase 3: Metamorphic Ghost Stack Padding Pass
    ─────────────────────────────────────────────
    Inserts semantically neutral "ghost" operations between real instructions
    to break symbolic VSP tracking (VTIL, NoVmp) and neural sequence taggers
    (BiLSTM, Transformer, n-gram baselines).

    Metamorphic Invariants & Anti-Neural Protections:
      1. Homomorphic Grammar Pool: Ghost sequences use the full opcode repertoire
         of Stack-VM (AddRegImm, SetRegImm, AddImm, SubImm, Nor, Swap, Rot, ReadMem),
         eliminating the rigid template tells (PushFlags; PopFlags, KeyAdjust; KeyAdjust).
      2. Flag-Preserving Wrappers: Any flag-producing ghost operation executed
         while architectural flags are live is wrapped in PushFlags ... PopFlags
         containing real arithmetic in between, eliminating isolated pushf/popf pairs.
      3. Non-Adjacent Key Adjustments: Key perturbations are split across 3 non-identical
         deltas (d1 ^ d2 ^ (d1 ^ d2) = 0) interleaved with scratch stores.
      4. Scratch & Accumulator Ring: Reuses an 8-slot ring of scratch registers
         allocated once per block to prevent single-register write concentration.
      5. Soundness: Every ghost sequence preserves stack depth (delta = 0).
*)

open Stack_ir
open Vm_ir

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

type ghost_rng = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFFFFFFL) in
    v mod n

let maybe rng prob = next_int rng 100 < prob

(* ── Metamorphic Accumulator Entanglement ────────────────────────────── *)
let entangle_with_accumulator ?(flags_live = false) ~(acc_slot : int) (delta : int64) : Stack_ir.stack_op list =
  if delta = 0L then []
  else if flags_live then [
    PushFlags;
    AddRegImm (acc_slot, delta);
    PopReg acc_slot;
    PopFlags;
  ] else [
    AddRegImm (acc_slot, delta);
    PopReg acc_slot;
  ]

(* ── Metamorphic Ghost Repertoire ────────────────────────────────────── *)
type ghost_kind =
  | GhostSuperopAdd      (** AddRegImm on accumulator (superoperator) *)
  | GhostSuperopScratch  (** SetRegImm + AddRegImm zero-net chain *)
  | GhostSubImmChain     (** PushReg s; AddImm d; SubImm d; PopReg s *)
  | GhostNorInvert       (** PushReg s; PushReg s; Nor; Dup; Nor; PopReg s *)
  | GhostArithZero       (** PushImm a; PushImm b; Add; PushImm (a+b); Sub; PopReg s *)
  | GhostSandwichFlags   (** PushFlags; PushImm a; PushImm b; Add; PopReg s; PopFlags *)
  | GhostTriKeyAdjust    (** KeyAdjust d1; PushImm v; PopReg s; KeyAdjust d2; KeyAdjust (d1^d2) *)
  | GhostMemRead         (** PushReg sp; ReadMem 8; PopReg s *)
  | GhostDupDrop         (** Dup; AddImm d; SubImm d; PopReg s *)
  | GhostSwapSwap        (** Swap; Swap *)
  | GhostRotCycle        (** Rot; Rot; Rot *)

let emit_ghost ?(entangle = true) rng ~scratch_ring ~ctx ~entangle_slot stack_depth flags_live =
  let n_scratch = Array.length scratch_ring in
  let scratch = scratch_ring.(next_int rng n_scratch) in
  let kinds =
    match (stack_depth >= 3, stack_depth >= 2, stack_depth >= 1, flags_live) with
    | true,  _, _, false ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSubImmChain; GhostNorInvert;
           GhostArithZero; GhostSandwichFlags; GhostTriKeyAdjust; GhostMemRead;
           GhostDupDrop; GhostSwapSwap; GhostRotCycle |]
    | _, true, _, false ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSubImmChain; GhostNorInvert;
           GhostArithZero; GhostSandwichFlags; GhostTriKeyAdjust; GhostMemRead;
           GhostDupDrop; GhostSwapSwap |]
    | _, _, true, false ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSubImmChain; GhostNorInvert;
           GhostArithZero; GhostSandwichFlags; GhostTriKeyAdjust; GhostMemRead;
           GhostDupDrop |]
    | _, _, false, false ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSubImmChain; GhostNorInvert;
           GhostArithZero; GhostSandwichFlags; GhostTriKeyAdjust; GhostMemRead |]
    (* When flags are live: use flag-preserving superoperators and sandwiches *)
    | true,  _, _, true ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSandwichFlags;
           GhostTriKeyAdjust; GhostMemRead; GhostSwapSwap; GhostRotCycle |]
    | _, true, _, true ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSandwichFlags;
           GhostTriKeyAdjust; GhostMemRead; GhostSwapSwap |]
    | _, _, _, true ->
        [| GhostSuperopAdd; GhostSuperopScratch; GhostSandwichFlags;
           GhostTriKeyAdjust; GhostMemRead |]
  in
  let kind = kinds.(next_int rng (Array.length kinds)) in
  match kind with
  | GhostSuperopAdd when entangle ->
      let imm = next_int64 rng in
      (entangle_with_accumulator ~flags_live ~acc_slot:entangle_slot imm, imm)
  | GhostSuperopAdd ->
      let delta = next_int64 rng in
      if flags_live then
        ([ PushFlags; AddRegImm (scratch, delta); PopReg scratch; PopFlags ], 0L)
      else
        ([ AddRegImm (scratch, delta); PopReg scratch ], 0L)

  | GhostSuperopScratch ->
      let imm = next_int64 rng in
      let delta = next_int64 rng in
      if flags_live then
        ([ SetRegImm (scratch, imm);
           PushFlags;
           AddRegImm (scratch, delta);
           PopReg scratch;
           PopFlags ], 0L)
      else
        ([ SetRegImm (scratch, imm);
           AddRegImm (scratch, delta);
           PopReg scratch ], 0L)
  | GhostSubImmChain ->
      let delta = next_int64 rng in
      if flags_live then
        ([ PushFlags;
           PushReg scratch;
           AddImm delta;
           SubImm delta;
           PopReg scratch;
           PopFlags ], 0L)
      else
        ([ PushReg scratch;
           AddImm delta;
           SubImm delta;
           PopReg scratch ], 0L)

  | GhostNorInvert ->
      if flags_live then
        ([ PushFlags;
           PushReg scratch;
           PushReg scratch;
           Nor;
           Dup;
           Nor;
           PopReg scratch;
           PopFlags ], 0L)
      else
        ([ PushReg scratch;
           PushReg scratch;
           Nor;
           Dup;
           Nor;
           PopReg scratch ], 0L)

  | GhostArithZero when entangle ->
      let a = next_int64 rng in
      let b = next_int64 rng in
      let sum = Int64.add a b in
      let ghost_core =
        if flags_live then
          [ PushFlags; PushImm a; PushImm b; Add; PushImm sum; Sub; PopReg scratch; PopFlags ]
        else
          [ PushImm a; PushImm b; Add; PushImm sum; Sub; PopReg scratch ]
      in
      (ghost_core @ entangle_with_accumulator ~flags_live ~acc_slot:entangle_slot sum, sum)

  | GhostArithZero ->
      let a = next_int64 rng in
      let b = next_int64 rng in
      let sum = Int64.add a b in
      if flags_live then
        ([ PushFlags; PushImm a; PushImm b; Add; PushImm sum; Sub; PopReg scratch; PopFlags ], 0L)
      else
        ([ PushImm a; PushImm b; Add; PushImm sum; Sub; PopReg scratch ], 0L)

  | GhostSandwichFlags ->
      let a = next_int64 rng in
      let b = next_int64 rng in
      ([ PushFlags;
         PushImm a;
         PushImm b;
         Add;
         PopReg scratch;
         PopFlags ], 0L)

  | GhostTriKeyAdjust ->
      let d1 = ref (next_int64 rng) in
      while Int64.equal !d1 0L do d1 := next_int64 rng done;
      let d2 = ref (next_int64 rng) in
      while Int64.equal !d2 0L do d2 := next_int64 rng done;
      let d3 = Int64.logxor !d1 !d2 in
      let imm = next_int64 rng in
      ([ KeyAdjust !d1;
         PushImm imm;
         PopReg scratch;
         KeyAdjust !d2;
         KeyAdjust d3 ], 0L)

  | GhostMemRead ->
      let sp_slot = Context_allocator.slot_of_reg ctx Register.rsp in
      ([ PushReg sp_slot; ReadMem 8; PopReg scratch ], 0L)

  | GhostDupDrop ->
      let delta = next_int64 rng in
      if flags_live then
        ([ PushFlags; Dup; AddImm delta; SubImm delta; PopReg scratch; PopFlags ], 0L)
      else
        ([ Dup; AddImm delta; SubImm delta; PopReg scratch ], 0L)

  | GhostSwapSwap ->
      ([ Swap; Swap ], 0L)

  | GhostRotCycle ->
      ([ Rot; Rot; Rot ], 0L)

(* ── Insertion Pass with Data-Flow Entanglement ───────────────────────── *)
let insert_ghosts_into_ops ?(entangle = true) ~entangle_slot ~scratch_ring rng ctx ops ghost_rate =
  let checksum = ref 0L in
  let depth = ref 0 in
  let result = ref [] in
  let emit op = result := op :: !result in
  let live = Stack_flag_liveness.analyze_list ops in
  let idx = ref 0 in

  let emit_ghost_here flags_live =
    let ghost_ops, delta =
      emit_ghost ~entangle ~scratch_ring ~ctx ~entangle_slot rng !depth flags_live
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
          emit (AddImm (Int64.neg !checksum));
          emit (PushReg entangle_slot);
          emit Add;
          emit Swap;
          emit PopFlags;
          emit Swap
        end else begin
          emit Swap;
          emit (AddImm (Int64.neg !checksum));
          emit (PushReg entangle_slot);
          emit Add;
          emit Swap
        end
      end else begin
        if flags_live then begin
          emit PushFlags;
          emit Swap;
          emit (AddImm (Int64.neg !checksum));
          emit (PushReg entangle_slot);
          emit Add;
          emit Swap;
          emit PopFlags
        end else begin
          emit (AddImm (Int64.neg !checksum));
          emit (PushReg entangle_slot);
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
      if maybe rng ghost_rate then emit_ghost_here live.(i);
      emit op
    end else begin
      emit op;
      depth := !depth + stack_delta op;
      if maybe rng ghost_rate then emit_ghost_here live.(i + 1)
    end
  ) ops;

  List.rev !result

(* ── Public API ───────────────────────────────────────────────────────── *)
type ghost_config = {
  seed        : int64;
  ghost_rate  : int;
  max_ghosts  : int;
  entangle    : bool;
}

let default_ghost_config seed = {
  seed;
  ghost_rate = 40;
  max_ghosts = 0;
  entangle = true;
}

let apply_block ?scratch_ring ?entangle_slot cfg ctx block =
  let entangle_slot =
    match entangle_slot with
    | Some s -> s
    | None -> if cfg.entangle then Context_allocator.alloc_scratch ctx else 0
  in
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
  let scratch_ring =
    match scratch_ring with
    | Some r -> r
    | None -> Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx)
  in
  let new_ops =
    insert_ghosts_into_ops ~entangle:cfg.entangle ~entangle_slot ~scratch_ring rng ctx
      block.ops cfg.ghost_rate
  in
  let new_ops =
    if cfg.max_ghosts <= 0 then new_ops
    else begin
      let real_count = List.length block.ops in
      let total = List.length new_ops in
      let ghost_count = total - real_count in
      if ghost_count <= cfg.max_ghosts then new_ops
      else begin
        let rng2 = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
        let capped_rate = cfg.ghost_rate * cfg.max_ghosts / (max 1 ghost_count) in
        insert_ghosts_into_ops ~entangle:cfg.entangle ~entangle_slot ~scratch_ring rng2 ctx
          block.ops capped_rate
      end
    end
  in
  { block with ops = new_ops }

let apply_program (cfg : ghost_config) ctx (prog : program) : program =
  let entangle_slot = if cfg.entangle then Context_allocator.alloc_scratch ctx else 0 in
  let scratch_ring = Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx) in
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id block ->
    Hashtbl.add new_blocks id (apply_block ~scratch_ring ~entangle_slot cfg ctx block)
  ) prog.blocks;
  let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
  { prog with blocks = new_blocks; context_slots }

let ghost_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after  = count_ops prog_after in
  let ghost_count = after - before in
  Printf.sprintf "Ghost padding: %d real ops → %d total ops (%d ghost, +%.0f%%)"
    before after ghost_count
    (if before = 0 then 0.0 else float_of_int ghost_count /. float_of_int before *. 100.0)
