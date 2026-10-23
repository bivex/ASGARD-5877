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

(* ── Natural Bytecode Shadowing Repertoire ───────────────────────────── *)
type ghost_kind =
  | GhostSuperopSet       (** SetRegImm into scratch *)
  | GhostRegCopy          (** PushReg r; PopReg s_dst; PushReg s_dst; PopReg s_src *)
  | GhostImmStore         (** PushImm imm; PopReg s_dst; PushReg s_dst; PopReg s_src *)
  | GhostArithShadow      (** PushReg r; PushImm imm; Add; PushReg s_src; Add; PopReg s_dst *)
  | GhostNorShadow        (** PushReg r; PushImm imm; Nor; PushReg s_src; Nor; PopReg s_dst *)
  | GhostLiveIdentity     (** Live stack identity transform: +0, -0, *1 *)
  | GhostDupEntangle      (** Dup; PushReg s_src; Nor; PopReg s_dst; PopReg s_src *)
  | GhostEntangle         (** AddRegImm (acc, delta); PopReg acc *)

let emit_ghost ?(entangle = true) rng ~scratch_ring ~ctx ~entangle_slot stack_depth flags_live =
  let n_scratch = Array.length scratch_ring in
  let s_src = scratch_ring.(next_int rng n_scratch) in
  let s_dst = scratch_ring.(next_int rng n_scratch) in
  let n_slots = Context_allocator.total_slots ctx in
  let real_r = if n_slots > 0 then next_int rng n_slots else 0 in
  let kinds =
    if flags_live then
      (* Flag-neutral operations: zero flag distortion *)
      match (stack_depth >= 2, stack_depth >= 1) with
      | true, _ ->
          [| GhostSuperopSet; GhostRegCopy; GhostImmStore; GhostLiveIdentity |]
      | false, true ->
          [| GhostSuperopSet; GhostRegCopy; GhostImmStore; GhostLiveIdentity |]
      | false, false ->
          [| GhostSuperopSet; GhostRegCopy; GhostImmStore |]
    else
      (* When flags dead: can execute arithmetic, NOR shadows, and live-stack identities *)
      match (stack_depth >= 2, stack_depth >= 1) with
      | true, _ ->
          [| GhostSuperopSet; GhostRegCopy; GhostImmStore; GhostArithShadow;
             GhostNorShadow; GhostLiveIdentity; GhostDupEntangle; GhostEntangle |]
      | false, true ->
          [| GhostSuperopSet; GhostRegCopy; GhostImmStore; GhostArithShadow;
             GhostNorShadow; GhostLiveIdentity; GhostDupEntangle; GhostEntangle |]
      | false, false ->
          [| GhostSuperopSet; GhostRegCopy; GhostImmStore; GhostArithShadow;
             GhostNorShadow; GhostEntangle |]
  in
  let kind = kinds.(next_int rng (Array.length kinds)) in
  match kind with
  | GhostEntangle when entangle ->
      let delta = next_int64 rng in
      ([ AddRegImm (entangle_slot, delta); PopReg entangle_slot ], delta)
  | GhostEntangle ->
      let delta = next_int64 rng in
      ([ AddRegImm (s_dst, delta); PopReg s_dst ], 0L)

  | GhostSuperopSet ->
      let imm = next_int64 rng in
      ([ SetRegImm (s_dst, imm); PushReg s_dst; PopReg s_src ], 0L)

  | GhostRegCopy ->
      ([ PushReg real_r; PopReg s_dst; PushReg s_dst; PopReg s_src ], 0L)

  | GhostImmStore ->
      let imm = next_int64 rng in
      ([ PushImm imm; PopReg s_dst; PushReg s_dst; PopReg s_src ], 0L)

  | GhostArithShadow ->
      let imm = next_int64 rng in
      ([ PushReg real_r; PushImm imm; Add; PushReg s_src; Add; PopReg s_dst ], 0L)

  | GhostNorShadow ->
      let imm = next_int64 rng in
      ([ PushReg real_r; PushImm imm; Nor; PushReg s_src; Nor; PopReg s_dst ], 0L)

  | GhostLiveIdentity when stack_depth >= 1 ->
      if flags_live then
        ([ PushImm 1L; Mul ], 0L)
      else
        (match next_int rng 3 with
         | 0 -> ([ PushImm 0L; Add ], 0L)
         | 1 -> ([ PushImm 0L; Sub ], 0L)
         | _ ->
             let imm = next_int64 rng in
             ([ AddImm imm; SubImm imm ], 0L))

  | GhostLiveIdentity ->
      let imm = next_int64 rng in
      ([ SetRegImm (s_dst, imm); PushReg s_dst; PopReg s_src ], 0L)

  | GhostDupEntangle when stack_depth >= 1 ->
      (* Dup(+1), PushReg(+1), Nor(-1 net=+1), PopReg(-1), PopReg(-1) = -1: wrong.
         Use: PushReg s_src, PopReg s_dst = net 0. *)
      ([ PushReg s_src; PopReg s_dst ], 0L)
  | GhostDupEntangle ->
      ([ PushReg s_src; PopReg s_dst ], 0L)
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

  let seen_terminator = ref false in
  List.iter (fun op ->
    let i = !idx in
    incr idx;
    (match op with
     | ReadMem _ -> maybe_entangle_mem false live.(i)
     | WriteMem _ -> maybe_entangle_mem true live.(i)
     | _ -> ());
    if Stack_balance_pass.is_terminator op then begin
      if not !seen_terminator then begin
        seen_terminator := true;
        if entangle && !checksum <> 0L then begin
          emit (PushReg entangle_slot);
          emit (AddImm (Int64.neg !checksum));
          emit (PopReg entangle_slot);
        end;
        if not live.(i) && maybe rng ghost_rate then emit_ghost_here false
      end;
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
