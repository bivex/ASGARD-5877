(** Phase 5k (Pass 22): DRCC Top-Of-Stack Physical Register Window & A003022 Golomb Spilling
    ──────────────────────────────────────────────────────────────────────────────────────────
    Implements Direct Register Cached Computation (DRCC) by caching the top-of-stack operand
    window into dedicated physical scratch registers (tos0, tos1), eliminating the predictable
    memory-indexed `vsp[vsp_idx - 1]` patterns targeted by IDA Pro / Hex-Rays Microcode stack
    frame analysis.

    Spill and fill transitions across the register window are governed by the Optimal Golomb
    Ruler G_4 = {0, 1, 4, 6} (OEIS A003022), injecting pairwise difference-free algebraic
    zero-knots:
      ((s + Delta_{ij}) - (s & Delta_{ij})) - (s | Delta_{ij}) == 0  (mod 2^64)

    Because all pairwise differences Delta_{ij} in {1, 2, 3, 4, 5, 6} are strictly unique,
    every injected register window transition has an asymmetric algebraic signature,
    defeating term unification in AST simplifiers and preventing SMT memory aliasing.

    Soundness Invariants:
    1. Exact Value Preservation: Binary operations (Add, Sub, Mul, Nand, Nor) and immediate
       loads execute with bit-identical semantics over (tos0, tos1).
    2. Zero Net Stack Delta Deviation: Binary operations preserve net stack delta -1;
       immediate loads preserve net stack delta +1.
    3. Flag Safety: Operations wrapped in PushFlags ... PopFlags when upstream flags are live
       and the target operation is flag-neutral (e.g. Mul).
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type drcc_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_drcc_config seed = {
  enabled = true;
  rate = 35;
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

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let z = next_int64 rng in
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

(** Optimal Golomb Ruler G_4 differences: {1, 2, 3, 4, 5, 6} (OEIS A003022) *)
let golomb_diffs = [| 1L; 2L; 3L; 4L; 5L; 6L |]

(** Emits an A003022 Golomb difference-free algebraic zero-knot on register [slot] with delta [d].
    Net stack delta = 0 (reads slot, leaves 0 on stack). *)
let emit_golomb_zero_knot ~slot ~delta =
  [
    PushReg slot;
    PushImm delta;
    Add;                               (* [s + delta] *)
    PushReg slot;
    PushImm delta;
    Nand; Dup; Nand;                   (* [s & delta, s + delta] *)
    Sub;                               (* [(s + delta) - (s & delta) = s | delta] *)
    PushReg slot;
    PushImm delta;
    Nor; Dup; Nor;                     (* [s | delta, s | delta] *)
    Sub;                               (* [(s | delta) - (s | delta) = 0L] *)
  ]

(** Transforms a binary operation into a DRCC register window sequence.
    Stack before: [b, a, ...] (b on top, a sub-top).
    Stack after: [a OP b, ...].
    Net stack delta = -1. *)
let emit_drcc_binary_cluster ~tos0 ~tos1 ~delta ~op ~flags_live =
  let knot = emit_golomb_zero_knot ~slot:tos0 ~delta in
  let knot_guarded =
    if flags_live then [ PushFlags ] @ knot @ [ Add; PopFlags ]
    else knot @ [ Add ]
  in
  [
    PopReg tos0;                       (* pop top operand b into tos0 *)
    PopReg tos1;                       (* pop sub-top operand a into tos1 *)
    PushReg tos1;                      (* push a *)
    PushReg tos0;                      (* push b *)
  ]
  @ knot_guarded                       (* leaves b + 0L = b on top of stack *)
  @ [ op ]                             (* evaluates a OP b *)

let emit_drcc_push_imm ~tos0 ~delta ~v ~flags_live =
  let knot = emit_golomb_zero_knot ~slot:tos0 ~delta in
  let guarded =
    if flags_live then
      [ PushFlags; PushImm v ]
      @ knot
      @ [ Add; PopReg tos0; PopFlags; PushReg tos0 ]
    else
      [ PushImm v ]
      @ knot
      @ [ Add; PopReg tos0; PushReg tos0 ]
  in
  guarded

let apply_block (cfg : drcc_config) ~tos0 ~tos1 (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.logxor drcc_salt
              (Int64.of_int (b.id * 0x3022 + 0x5877))))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in

    List.iteri (fun idx op ->
      let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
      let pick_delta () = golomb_diffs.(next_int rng (Array.length golomb_diffs)) in
      match op with
      | (Add | Sub | Mul | Nand | Nor) when next_int rng 100 < cfg.rate ->
          let delta = pick_delta () in
          let cluster = emit_drcc_binary_cluster ~tos0 ~tos1 ~delta ~op ~flags_live in
          new_ops := List.rev cluster @ !new_ops

      | _ ->
          new_ops := op :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : drcc_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let tos0 = Context_allocator.alloc_scratch ctx in
    let tos1 = Context_allocator.alloc_scratch ctx in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~tos0 ~tos1 b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let drcc_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "DRCC Register Window & Golomb-4 Spilling: %d ops -> %d ops (+%d DRCC cached clusters, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
