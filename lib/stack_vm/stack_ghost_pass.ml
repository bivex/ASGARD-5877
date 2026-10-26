(** Phase 3: Metamorphic Ghost Stack Padding Pass
    ─────────────────────────────────────────────
    Inserts semantically neutral "ghost" operations between real instructions
    to break symbolic VSP tracking (VTIL, NoVmp) and neural sequence taggers
    (BiLSTM, Transformer, n-gram baselines).

    Metamorphic Invariants & Soundness Guarantees:
      1. Zero Stack Delta: Every ghost cluster maintains exact stack neutrality
         (net delta = 0 across the cluster).
      2. Flag-Preservation: Flag-modifying ALU operations are strictly restricted
         to points where architectural flags are dead, or wrapped in complete
         PushFlags ... PopFlags sandwiches.
      3. Def-Use Scratch Ring Entanglement: Ghost operations pass values through
         a multi-slot scratch ring (s_src -> s_dst), building interconnected
         dataflow dependency graphs.
      4. Dynamic Def-Use Webbing (Zero DCE Loss): When `entangle = true`, each
         block weaves its scratch ring operations into live stack execution via
         non-trivial zero knots:
           Nor(r, Nor(r, r)) ≡ 0  for all r ∈ Z/2^64Z
         This creates genuine reads of scratch ring slots on the live computation
         path, preventing dataflow DCE / liveness scanners from discarding ghost
         computations as isolated dead components.
      5. Memory & Terminator Hygiene: Memory pointers on the stack are never
         perturbed; terminator pairs (JccRel + JmpRel) remain unbroken.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type ghost_rng = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  let z = logxor z (shift_right_logical z 31) in
  (s, z)

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

(* ── Accumulator helper ────────────────────────────────────────────────── *)

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
  (* Class A: Pure Context Operations (Flag-neutral, Stack-neutral) *)
  | GhostSetRegImm
  | GhostScratchCopy
  | GhostRealRegShadow
  | GhostImmStore

  (* Class B: Arithmetic & Logic Def-Use Chains (Flags dead, Stack-neutral) *)
  | GhostArithShadow
  | GhostNorShadow
  | GhostAddRegImmChain

  (* Class C: Live-Stack Identity Transforms (Flags dead, Depth >= 1) *)
  | GhostLiveAddZero
  | GhostLiveAddSubPair

  (* Class D: Flag-Preserving Live-Stack Identity (Flags live, Depth >= 1) *)
  | GhostLiveFlagPreserved

  (* Class E: Entangled Def-Use Webbing (Flags dead, Depth >= 1)
     Uses Nor(r, Nor(r, r)) ≡ 0 to add 0 to the stack top while creating
     a genuine read of a scratch-ring register, tying ghost registers to live flow. *)
  | GhostEntangledWebbing

let emit_ghost_cluster rng ~scratch_ring ~ctx ~ring_idx stack_depth flags_live entangle =
  let n_scratch = Array.length scratch_ring in
  let s_src = scratch_ring.(!ring_idx mod n_scratch) in
  ring_idx := (!ring_idx + 1) mod n_scratch;
  let s_dst = scratch_ring.(!ring_idx mod n_scratch) in

  let n_slots = Context_allocator.total_slots ctx in
  let real_r = if n_slots > 0 then next_int rng n_slots else 0 in

  let candidates =
    if flags_live then
      if stack_depth >= 1 then
        [| GhostSetRegImm; GhostScratchCopy; GhostRealRegShadow; GhostImmStore; GhostLiveFlagPreserved |]
      else
        [| GhostSetRegImm; GhostScratchCopy; GhostRealRegShadow; GhostImmStore |]
    else
      if stack_depth >= 1 then
        if entangle then
          [| GhostSetRegImm; GhostScratchCopy; GhostRealRegShadow; GhostImmStore;
             GhostArithShadow; GhostNorShadow; GhostAddRegImmChain;
             GhostLiveAddZero; GhostLiveAddSubPair; GhostEntangledWebbing |]
        else
          [| GhostSetRegImm; GhostScratchCopy; GhostRealRegShadow; GhostImmStore;
             GhostArithShadow; GhostNorShadow; GhostAddRegImmChain;
             GhostLiveAddZero; GhostLiveAddSubPair |]
      else
        [| GhostSetRegImm; GhostScratchCopy; GhostRealRegShadow; GhostImmStore;
           GhostArithShadow; GhostNorShadow; GhostAddRegImmChain |]
  in

  let kind = candidates.(next_int rng (Array.length candidates)) in
  match kind with
  (* Class A: Pure Context Operations *)
  | GhostSetRegImm ->
      let imm = next_int64 rng in
      [ SetRegImm (s_dst, imm) ]

  | GhostScratchCopy ->
      [ PushReg s_src; PopReg s_dst ]

  | GhostRealRegShadow ->
      [ PushReg real_r; PopReg s_dst ]

  | GhostImmStore ->
      let imm = next_int64 rng in
      [ PushImm imm; PopReg s_dst ]

  (* Class B: ALU Chains through scratch ring (flags dead) *)
  | GhostArithShadow ->
      let imm = next_int64 rng in
      [ PushReg real_r; PushImm imm; Add; PushReg s_src; Add; PopReg s_dst ]

  | GhostNorShadow ->
      let imm = next_int64 rng in
      [ PushReg real_r; PushImm imm; Nor; PushReg s_src; Nor; PopReg s_dst ]

  | GhostAddRegImmChain ->
      let imm = next_int64 rng in
      [ AddRegImm (s_src, imm); PopReg s_dst ]

  (* Class C: Live-Stack Identities (flags dead, depth >= 1)
     Replaces trivial [PushImm 0; Add] and [AddImm k; SubImm k] with non-trivial
     algebraic zero knots that cannot be reduced by single-pass peephole scanners. *)
  | GhostLiveAddZero ->
      let imm = next_int64 rng in
      let k1 = next_int64 rng in
      let k2 = Int64.sub imm k1 in
      (* x + (imm - k1 - k2) == x + 0 == x *)
      [ PushImm imm; PushImm k1; Sub; PushImm k2; Sub; Add ]

  | GhostLiveAddSubPair ->
      let k1 = next_int64 rng in
      let k2 = next_int64 rng in
      (* Add (k1 + k2) then Sub k1 then Sub k2 *)
      let sum_k = Int64.add k1 k2 in
      [ AddImm sum_k; SubImm k1; SubImm k2 ]

  (* Class D: Flag-Preserving Live-Stack Identity (flags live, depth >= 1) *)
  | GhostLiveFlagPreserved ->
      let k1 = next_int64 rng in
      let k2 = next_int64 rng in
      let sum_k = Int64.add k1 k2 in
      [ PushFlags; AddImm sum_k; SubImm k1; SubImm k2; PopFlags ]

  (* Class E: Entangled Def-Use Webbing (flags dead, depth >= 1)
     Weaves polymorphic zero-knots using scratch ring registers:
     Variant 0: Nor(s_src, Nor(s_src, s_src)) == 0
     Variant 1: (s_src & ~s_dst) - (s_src & ~s_dst) == 0 via Nor
     Variant 2: Nor(s_dst, Nor(s_dst, s_dst)) == 0 *)
  | GhostEntangledWebbing ->
      match next_int rng 4 with
      | 0 ->
          [ PushReg s_src; PushReg s_src; Nor; PushReg s_src; Nor; Add ]
      | 1 ->
          [ PushReg s_src; PushReg s_src; Nor; PushReg s_src; Nor; Sub ]
      | 2 ->
          [ PushReg s_dst; PushReg s_dst; Sub; Add ]
      | _ ->
          [ PushReg s_src; Dup; Nor; PushReg s_src; Add; PushImm 1L; Add; Add ]

(* ── Insertion Pass ───────────────────────────────────────────────────── *)

let insert_ghosts_into_ops ?(entangle = true) ~scratch_ring rng ctx ops ghost_rate =
  let depth = ref 0 in
  let ring_idx = ref (next_int rng (Array.length scratch_ring)) in
  let result = ref [] in
  let emit op = result := op :: !result in
  let live = Stack_flag_liveness.analyze_list ops in
  let idx = ref 0 in

  let emit_ghost_here flags_live =
    let cluster = emit_ghost_cluster rng ~scratch_ring ~ctx ~ring_idx !depth flags_live entangle in
    List.iter (fun gop ->
      emit gop;
      depth := !depth + stack_delta gop
    ) cluster
  in

  let seen_terminator = ref false in
  List.iter (fun op ->
    let i = !idx in
    incr idx;

    if Stack_balance_pass.is_terminator op then begin
      if not !seen_terminator then begin
        seen_terminator := true;
        if not live.(i) && maybe rng ghost_rate then emit_ghost_here false
      end;
      emit op
    end else begin
      emit op;
      depth := !depth + stack_delta op;
      let next_flags = if !idx < Array.length live then live.(!idx) else false in
      if maybe rng ghost_rate then emit_ghost_here next_flags
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
  ignore entangle_slot;
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id * 0x6B7))) in
  let scratch_ring =
    match scratch_ring with
    | Some r -> r
    | None -> Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx)
  in
  let new_ops =
    insert_ghosts_into_ops ~entangle:cfg.entangle ~scratch_ring rng ctx
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
        insert_ghosts_into_ops ~entangle:cfg.entangle ~scratch_ring rng2 ctx
          block.ops capped_rate
      end
    end
  in
  { block with ops = new_ops }

let apply_program (cfg : ghost_config) ctx (prog : program) : program =
  let scratch_ring = Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx) in
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id block ->
    Hashtbl.add new_blocks id (apply_block ~scratch_ring cfg ctx block)
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
