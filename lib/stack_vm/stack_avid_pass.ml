(** Phase 5b: Stack-VM Avid Junk Operands Pass
    ───────────────────────────────────────────
    Inserts randomized variable-size avid junk operands directly into
    program basic blocks.

    Def-Use Entanglement & Anti-Deobfuscation Architecture:
      In legacy implementations, junk clusters wrote only to isolated dead
      scratch slots, making them 100% reversible by linear dead-code
      elimination (D810/peephole_eval).

      This overhauled implementation couples avid junk to the live execution
      graph using Nor-based def-use webbing:
        1. Anchor Recording: Pops to scratch slots are recorded into a small
           ring buffer of anchor slots.
        2. Def-Use Chords: Subsequent avid clusters weave the value stored
           in a previously written anchor slot into the computation:
             Nor(r, Nor(r, r)) ≡ 0 for all r ∈ Z_2^64
           Adding this knot to the stack top preserves the exact value
           while introducing genuine dataflow reads from the anchor slot.
        3. Global Liveness: Because the anchor slot is subsequently READ by
           future expander chords, the slot is NOT dead, defeating DCE and
           peephole scanners that rely on write-without-read liveness.

    Soundness Invariants:
      1. Zero Net Stack Delta: Every injected cluster preserves the net
         stack delta of the insertion point.
      2. Strict Flag Preservation: When condition flags are live, only
         flag-neutral instructions (PushImm, PopReg, PushReg, Swap) are
         used.
      3. Context Isolation: All scratch and anchor slots are allocated via
         [Context_allocator] to prevent collision with program state.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type avid_config = {
  enabled  : bool;
  rate     : int;   (** Insertion probability (0..100) per eligible instruction *)
  max_avid : int;   (** Maximum avid clusters per block (0 = unlimited) *)
  seed     : int64;
}

let default_avid_config seed = {
  enabled  = true;
  rate     = 40;
  max_avid = 0;
  seed;
}

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  let z = logxor z (shift_right_logical z 31) in
  (s, z)

type avid_rng = { mutable state : int64 }

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

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

(** Emits an expander knot that consumes an anchor slot:
    Identity: Nor(reg, Nor(reg, reg)) ≡ 0.
    Adding 0 to the stack top preserves the value while creating a read
    of [reg]. Net stack delta: 0 (Add consumes the knot). *)
let emit_anchor_chord reg =
  [
    PushReg reg;
    PushReg reg;
    Nor;
    PushReg reg;
    Nor;
    Add;
  ]

(** Generates an avid cluster. If an anchor is available and flags are dead,
    weaves a def-use chord from the anchor. *)
let generate_avid_cluster rng scratch_slot anchor_slot flags_live =
  let imm1 = next_int64 rng in
  let imm2 = next_int64 rng in
  if flags_live then
    match anchor_slot with
    | Some anchor ->
        (* Flag-neutral def-use chord: swaps anchor copy, preserves stack top and flags *)
        [ PushImm imm1; PushReg anchor; Swap; PopReg anchor; PopReg scratch_slot ]
    | None ->
        [ PushImm imm1; PushReg scratch_slot; PopReg scratch_slot; PopReg scratch_slot ]
  else
    match anchor_slot with
    | Some anchor when next_int rng 2 = 0 ->
        (* Def-use entangled cluster: pushes imm1, adds identity zero from anchor, pops to scratch *)
        [ PushImm imm1 ] @ emit_anchor_chord anchor @ [ PopReg scratch_slot ]
    | _ ->
        match next_int rng 2 with
        | 0 ->
            (* Non-trivial zero pair via two distinct randoms: (k1 + k2) - k1 - k2 == 0 *)
            let k1 = next_int64 rng in
            let k2 = next_int64 rng in
            let sum_k = Int64.add k1 k2 in
            [ PushImm sum_k; PushImm k1; Sub; PushImm k2; Sub; PopReg scratch_slot ]
        | _ ->
            [ SetRegImm (scratch_slot, imm1); AddRegImm (scratch_slot, imm2); PopReg scratch_slot ]

let apply_block (cfg : avid_config) ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int
              (b.id * Int64.to_int salt_avid_block_mul
               + Int64.to_int salt_avid_block_add)))
    in
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    let anchor_slot = Context_allocator.alloc_scratch ctx in
    let last_anchor = ref None in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let count = ref 0 in
    List.iteri (fun idx op ->
      new_ops := op :: !new_ops;
      if not (is_terminator op) && (cfg.max_avid <= 0 || !count < cfg.max_avid) then begin
        if next_int rng 100 < cfg.rate then begin
          let flags_live = live.(idx + 1) in
          let target_slot = if !last_anchor = None then anchor_slot else scratch_slot in
          let cluster = generate_avid_cluster rng target_slot !last_anchor flags_live in
          last_anchor := Some target_slot;
          new_ops := List.rev cluster @ !new_ops;
          incr count
        end
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : avid_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      Hashtbl.add new_blocks id (apply_block cfg ctx b)
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let avid_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after  = count_ops prog_after in
  let added = after - before in
  Printf.sprintf "Avid operands: %d ops → %d ops (+%d avid junk ops, +%.1f%%)"
    before after added
    (if before = 0 then 0.0 else float_of_int added /. float_of_int before *. 100.0)
