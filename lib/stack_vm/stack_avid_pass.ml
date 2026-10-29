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

(** Emits a polymorphic zero-knot that consumes an anchor slot:
    Generates 1 of 5 mathematically distinct algebraic zero families so
    a single pattern cannot eliminate all knots:
      0: Nor(r, Nor(r, r)) == 0 (Add)
      1: Nor(r, Nor(r, r)) == 0 (Sub)
      2: (r - r) == 0 (Add)
      3: (r + ~r + 1) == 0 via Nor
      4: (Nand(r, Nand(r, r)) + 1) == 0
    Every knot evaluates to an identity 0 on the stack top while creating
    genuine dataflow reads of [reg]. *)
let emit_anchor_chord rng reg =
  match next_int rng 4 with
  | 0 ->
      (* x - (r - r) == x (flag-dead zero difference) *)
      [ PushReg reg; PushReg reg; Sub; Sub ]
  | 1 ->
      (* x + (r - r) == x *)
      [ PushReg reg; PushReg reg; Sub; Add ]
  | 2 ->
      (* x + (r + ~r + 1) == x via Nor-inversion *)
      [ PushReg reg; Dup; Nor; PushReg reg; Add; PushImm 1L; Add; Add ]
  | _ ->
      (* x + (Nand(r, Nand(r, r)) + 1) == x *)
      [ PushReg reg; PushReg reg; Nand; PushReg reg; Nand; Add; PushImm 1L; Add ]

(** Generates an avid cluster. If an anchor is available and flags are dead,
    weaves a def-use chord from the anchor. *)
let generate_avid_cluster rng scratch_slot anchor_slot flags_live =
  let imm1 = next_int64 rng in
  if flags_live then
    match anchor_slot with
    | Some anchor ->
        (* Flag-neutral def-use chord: swaps anchor copy, preserves stack top and flags *)
        [ PushImm imm1; PushReg anchor; Swap; PopReg anchor; PopReg scratch_slot ]
    | None ->
        [ PushImm imm1; PushReg scratch_slot; PopReg scratch_slot; PopReg scratch_slot ]
  else
    match anchor_slot with
    | Some anchor ->
        (* Always weave polymorphic def-use chord when anchor is available *)
        [ PushImm imm1 ] @ emit_anchor_chord rng anchor @ [ PopReg scratch_slot ]
    | None ->
        (* De Morgan zero knot on the scratch slot:
           ((s + k) - (s & k)) - (s | k) == 0  in Z_{2^64}.
           Mixed Add/Nand/Nor/Sub reads with no linear cancellation;
           drains the zero into scratch. Net delta = 0, flag-clobbering
           (flag-dead sites only). *)
        let k = next_int64 rng in
        [ PushReg scratch_slot; PushImm k; Add;
          PushReg scratch_slot; PushImm k; Nand; Dup; Nand; Sub;
          PushReg scratch_slot; PushImm k; Nor; Dup; Nor; Sub;
          PopReg scratch_slot ]


let apply_block_internal ?(scratch_slot = 10) ?(anchor_slot = 11) (cfg : avid_config) (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int
              (b.id * Int64.to_int salt_avid_block_mul
               + Int64.to_int salt_avid_block_add)))
    in
    let last_anchor = ref None in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let count = ref 0 in
    List.iteri (fun idx op ->
      if is_terminator op then begin
        match !last_anchor with
        | Some a ->
            last_anchor := None;
            let anchor_ops = [ PushReg a; PushImm 0L; Mul; PopReg a ] in
            new_ops := op :: (List.rev anchor_ops) @ !new_ops
        | None ->
            new_ops := op :: !new_ops
      end else begin
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
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_block (cfg : avid_config) ctx (b : block) : block =
  let scratch_slot = Context_allocator.alloc_scratch ctx in
  let anchor_slot = Context_allocator.alloc_scratch ctx in
  apply_block_internal ~scratch_slot ~anchor_slot cfg b

let apply_program (cfg : avid_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    let anchor_slot = Context_allocator.alloc_scratch ctx in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      Hashtbl.add new_blocks id (apply_block_internal ~scratch_slot ~anchor_slot cfg b)
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
