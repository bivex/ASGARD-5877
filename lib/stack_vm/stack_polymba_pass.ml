(** Phase 5e: Non-Linear PolyMBA Pass (E-Graph & Equality Saturation Breaker)
    ──────────────────────────────────────────────────────────────────────
    Defeats Equality Saturation (E-graphs, SaMBA, Cobra, egg) and SMT QF_BV solvers
    by injecting degree-2 quadratic cross-term identities and dynamic variable-shift
    knots into the live stack stream.

    Mechanism & Theory:
      Linear MBA expressions (degree 1) are easily factorized by E-graphs because
      associativity, commutativity, and distributive rewrite rules can be applied
      simultaneously.

      This pass injects non-linear identities:
        1. Quadratic Cross-Term Knot (degree 2):
           Zero = ((s + 1)^2) - (s^2 + 2s + 1) == 0 (mod 2^64)
           Forces e-node explosion in E-graphs trying to distribute cross-terms.
        2. Dynamic Variable-Shift Knot:
           Zero = ((s * 5 + 3) << (s & 15)) - ((s * 5 + 3) << (s & 15)) == 0
           Forces 16-way case splitting in SMT/symbolic solvers because the shift
           amount is a dynamic runtime variable, having no static rewrite rule.

      Soundness Invariants:
      1. Zero Net Stack Delta: The knot evaluates to 0 on stack top and adds 0
         to the live stack operand (V + 0 == V). Net delta = 0.
      2. Flag Preservation: Wrapped in PushFlags ... PopFlags when architectural
         flags are live at the injection site.
      3. Value Invariance: In 64-bit modular arithmetic, both identities evaluate
         strictly to 0 for all 2^64 values of s.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type polymba_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_polymba_config seed = {
  enabled = true;
  rate = 40;
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

(** Evaluates degree >= 3 cubic Rivest permutation polynomial zero-knot onto the stack:
      Left:  (s + 1)^3
      Right: s^3 + 3s^2 + 3s + 1
      Zero:  Left - Right == 0 (mod 2^64)
    Forces 8 multinomial terms expansion in E-graphs (SAMBA/Cobra/egg), saturating
    the equivalence saturation budget and preventing polynomial canonicalization. *)
let emit_cubic_rivest_knot ~scratch_slot =
  [
    (* Left: (s + 1)^3 *)
    PushReg scratch_slot;
    PushImm 1L;
    Add;
    Dup;
    Dup;
    Mul;
    Mul;

    (* Right: s^3 + 3s^2 + 3s + 1 *)
    PushReg scratch_slot;
    Dup;
    Dup;
    Mul;
    Mul; (* s^3 *)

    PushReg scratch_slot;
    Dup;
    Mul;
    PushImm 3L;
    Mul; (* 3s^2 *)
    Add; (* s^3 + 3s^2 *)

    PushReg scratch_slot;
    PushImm 3L;
    Mul; (* 3s *)
    Add; (* s^3 + 3s^2 + 3s *)

    PushImm 1L;
    Add; (* s^3 + 3s^2 + 3s + 1 *)

    (* Left - Right == 0 (mod 2^64) *)
    Sub;
  ]

let emit_quadratic_knot = emit_cubic_rivest_knot

(** Evaluates asymmetric distributive shift knot onto the stack:
      Left:  (s * 5 + 3) << k
      Right: ((s << k) * 5) + (3 << k)
      Zero:  Left - Right == 0 (mod 2^64)
    Because the left and right subtrees have completely different AST topologies
    (single shift of sum vs sum of two independent shifts), GVN and Term Slicing
    cannot hash-cons them to identical e-nodes or slice them as F - F. *)
let emit_dyn_shift_knot ~scratch_slot =
  [
    (* 1. Compute Left = (s * 5 + 3) << (s & 15) *)
    PushReg scratch_slot;
    PushImm polymba_dyn_shift_mul; (* 5 *)
    Mul;
    PushImm polymba_dyn_shift_add; (* 3 *)
    Add;
    PushReg scratch_slot;
    PushImm polymba_dyn_shift_mask; (* 15 *)
    Nand; Dup; Nand;
    Shl;                           (* [Left] *)

    (* 2. Compute Right = ((s << k) * 5) + (3 << k) *)
    PushReg scratch_slot;
    PushReg scratch_slot;
    PushImm polymba_dyn_shift_mask; (* 15 *)
    Nand; Dup; Nand;
    Shl;                           (* s << k *)
    PushImm polymba_dyn_shift_mul; (* 5 *)
    Mul;                           (* (s << k) * 5 *)
    PushImm polymba_dyn_shift_add; (* 3 *)
    PushReg scratch_slot;
    PushImm polymba_dyn_shift_mask; (* 15 *)
    Nand; Dup; Nand;
    Shl;                           (* 3 << k *)
    Add;                           (* [Right = ((s<<k)*5) + (3<<k), Left] *)

    (* 3. Zero = Left - Right *)
    Sub;
  ]

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

let apply_block (cfg : polymba_config) ~scratch_ring _ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 || Array.length scratch_ring = 0 then b
  else
    let n_ring = Array.length scratch_ring in
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x2718 + 0x2818)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let count = ref 0 in
    let max_per_block = 2 in
    let ring_idx = ref (b.id mod n_ring) in
    let depth = ref 0 in
    List.iteri (fun idx op ->
      new_ops := op :: !new_ops;
      depth := !depth + stack_delta op;
      if not (is_terminator op) && !depth >= 1 && !count < max_per_block then begin
        if next_int rng 100 < cfg.rate then begin
          let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
          let s = scratch_ring.(!ring_idx) in
          ring_idx := (!ring_idx + 1) mod n_ring;
          let knot =
            if next_int rng 2 = 0 then emit_cubic_rivest_knot ~scratch_slot:s
            else emit_dyn_shift_knot ~scratch_slot:s
          in
          let cluster =
            if flags_live then [ PushFlags ] @ knot @ [ Add; PopFlags ]
            else knot @ [ Add ]
          in
          new_ops := List.rev cluster @ !new_ops;
          incr count
        end
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program ?scratch_ring (cfg : polymba_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let scratch_ring =
      match scratch_ring with
      | Some r -> r
      | None -> Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx)
    in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~scratch_ring ctx b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let polymba_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let b_before = count_ops prog_before in
  let b_after = count_ops prog_after in
  Printf.sprintf "PolyMBA Non-Linear Expansion: %d ops -> %d ops (+%d non-linear knots, +%.1f%%)"
    b_before b_after (b_after - b_before)
    (if b_before = 0 then 0.0 else float_of_int (b_after - b_before) /. float_of_int b_before *. 100.0)
