(** Phase 5h (Pass 17): Mixed-Characteristic Finite Field Arithmetic Pass
    ────────────────────────────────────────────────────────────────────
    Injects non-linear zero knots and polynomial field homomorphisms across
    three incompatible mathematical structures:
      1. Ring Z_{2^64} (host machine arithmetic, char 2)
      2. Mersenne Prime Field F_{M31} = Z/(2^31 - 1)Z (char 2147483647)
      3. Galois Field GF(2^64) with primitive poly x^64 + x^4 + x^3 + x + 1.

    Because gcd(2^64, 2^31 - 1) = 1, SMT solvers in QF_BV cannot apply
    bit-vector ring simplifications or linear coordinate projections,
    forcing exponential case-splitting and non-linear integer timeouts.

    Soundness Invariants:
    1. Zero Net Stack Delta: Knots evaluate to 0 and add 0 to live operands.
    2. Flag Preservation: Wrapped in PushFlags ... PopFlags when downstream
       condition codes are live.
    3. Complete 64-bit sound evaluation without arithmetic overflow.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type finite_field_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_finite_field_config seed = {
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

let next_int rng n =
  if n <= 1 then 0
  else
    let s, z = splitmix64 rng.state in
    rng.state <- s;
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

(** Helper emitting branchless binary XOR on top two stack elements [B, A]:
    Computes (A + B) - 2 * (A & B) == A ^ B.
    Stack transition: [B, A] -> [A ^ B]. Net delta = -1. *)
let emit_xor () =
  [
    Dup2;                  (* [B, A, B, A] *)
    Nand; Dup; Nand;       (* [A & B, B, A] *)
    PushImm 1L;
    Shl;                   (* [2 * (A & B), B, A] *)
    Swap;                  (* [B, 2*(A & B), A] *)
    Rot;                   (* [A, B, 2*(A & B)] *)
    Add;                   (* [A + B, 2*(A & B)] *)
    Swap;                  (* [2*(A & B), A + B] *)
    Sub;                   (* [(A + B) - 2*(A & B) = A ^ B] *)
  ]

(** Helper emitting xtime(u) in GF(2^64):
    xtime(u) = (u << 1) ^ (((u >> 63) * 0x1B)).
    Stack transition: [u] -> [xtime(u)]. Net delta = 0. *)
let emit_xtime () =
  [
    Dup;
    PushImm 1L;
    Shl;                                   (* [u << 1, u] *)
    Swap;
    PushImm 63L;
    Shr;
    PushImm finite_field_gf64_poly;        (* 0x1BL *)
    Mul;                                   (* [poly = (u >> 63) * 0x1B, u << 1] *)
  ] @ emit_xor ()

(** Pass 17 Knot 1: Mersenne-31 Multiplicative Invertibility Knot.
    In F_{M31} (M31 = 2^31 - 1):
      s0 = s & 0x7FFFFFFE (< 2^31 - 1)
      p1 = s0 * a (fits in 62 bits, zero 64-bit overflow)
      y = fold31(fold31(p1))
      p2 = y * a^-1 (fits in 62 bits)
      z = fold31(fold31(p2))
    Because F_{M31} is a field, z == s0 identically.
    s0 - z == 0.
    Net stack delta = +1 (pushes 0L onto stack). *)
let emit_mersenne_invertibility_knot ~scratch_slot =
  [
    (* 1. Compute s0 = s & finite_field_m31_mask (0x7FFFFFFEL, strictly < M31) *)
    PushReg scratch_slot;
    PushImm finite_field_m31_mask;
    Nand; Dup; Nand;                       (* [s0] *)

    (* 2. Save a copy of s0 *)
    Dup;                                   (* [s0, s0] *)

    (* 3. p1 = s0 * a *)
    PushImm finite_field_m31_mul;
    Mul;                                   (* [p1, s0] *)

    (* 4. Fold p1 into y = fold31(fold31(p1)) *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;                       (* [p1 & M31, p1, s0] *)
    Swap;
    PushImm 31L;
    Shr;                                   (* [p1 >> 31, p1 & M31, s0] *)
    Add;                                   (* [y1, s0] *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;                       (* [y1 & M31, y1, s0] *)
    Swap;
    PushImm 31L;
    Shr;                                   (* [y1 >> 31, y1 & M31, s0] *)
    Add;                                   (* [y, s0] *)

    (* 5. p2 = y * inv_a *)
    PushImm finite_field_m31_inv;
    Mul;                                   (* [p2, s0] *)

    (* 6. Fold p2 into z = fold31(fold31(p2)) *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;                       (* [p2 & M31, p2, s0] *)
    Swap;
    PushImm 31L;
    Shr;                                   (* [p2 >> 31, p2 & M31, s0] *)
    Add;                                   (* [z1, s0] *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;                       (* [z1 & M31, z1, s0] *)
    Swap;
    PushImm 31L;
    Shr;                                   (* [z1 >> 31, z1 & M31, s0] *)
    Add;                                   (* [z, s0] *)

    (* 7. Zero = s0 - z *)
    Sub;                                   (* [0L] *)
  ]

(** Pass 17 Knot 2: Galois Field GF(2^64) Polynomial Distributivity Knot.
    Evaluates:
      xtime(s ^ C) ^ xtime(s) ^ xtime(C) == 0.
    In GF(2^64), multiplication by x is linear: xtime(u ^ v) = xtime(u) ^ xtime(v).
    Net stack delta = +1 (pushes 0L onto stack). *)
let emit_gf64_distributivity_knot ~scratch_slot =
  let c = finite_field_gf64_const in
  let xtime_c =
    let open Int64 in
    let high = logand (shift_right_logical c 63) 1L in
    let poly = if high <> 0L then finite_field_gf64_poly else 0L in
    logxor (shift_left c 1) poly
  in
  [
    (* 1. Compute u = s ^ C *)
    PushReg scratch_slot;
    PushImm c;
  ] @ emit_xor () @
  (* 2. Compute xtime(u) *)
  emit_xtime () @
  (* 3. Compute xtime(s) *)
  [ PushReg scratch_slot ] @
  emit_xtime () @
  (* 4. XOR xu ^ xs *)
  emit_xor () @
  (* 5. XOR (xu ^ xs) ^ xtime(C) == 0 *)
  [ PushImm xtime_c ] @
  emit_xor ()

(** Pass 17 Knot 3: Mersenne-31 Quadratic Frobenius Cross-Term Knot.
    Evaluates in F_{M31}:
      fold31((s0 + c)^2) - fold31(s0^2 + 2*c*s0 + c^2) == 0.
    Where s0 = s & 0x3FFFFFFF (< 2^30) and c = 0x13375877L & 0x3FFFFFFF (< 2^30).
    (s0 + c)^2 < 2^62 < 2^64, zero 64-bit overflow.
    Net stack delta = +1 (pushes 0L onto stack). *)
let emit_mersenne_quadratic_knot ~scratch_slot =
  let c = Int64.logand 0x13375877L 0x3FFFFFFFL in
  let c_sq = Int64.mul c c in
  let two_c = Int64.mul 2L c in
  [
    (* 1. s0 = s & 0x3FFFFFFF *)
    PushReg scratch_slot;
    PushImm 0x3FFFFFFFL;
    Nand; Dup; Nand;                       (* [s0] *)

    (* 2. Save copies of s0 *)
    Dup; Dup;                              (* [s0, s0, s0] *)

    (* 3. LHS = (s0 + c)^2 *)
    PushImm c;
    Add;                                   (* [s0 + c, s0, s0] *)
    Dup;
    Mul;                                   (* [lhs = (s0 + c)^2, s0, s0] *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;                                   (* [lhs_fold, s0, s0] *)

    (* 4. RHS = s0^2 + 2*c*s0 + c^2 *)
    Rot;                                   (* [s0, lhs_fold, s0] *)
    Dup;
    Mul;                                   (* [s0^2, lhs_fold, s0] *)
    Rot;                                   (* [s0, s0^2, lhs_fold] *)
    PushImm two_c;
    Mul;                                   (* [2*c*s0, s0^2, lhs_fold] *)
    Add;                                   (* [s0^2 + 2*c*s0, lhs_fold] *)
    PushImm c_sq;
    Add;                                   (* [rhs, lhs_fold] *)
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;
    Dup;
    PushImm finite_field_m31;
    Nand; Dup; Nand;
    Swap;
    PushImm 31L;
    Shr;
    Add;                                   (* [rhs_fold, lhs_fold] *)

    (* 5. Zero = lhs_fold - rhs_fold *)
    Sub;                                   (* [0L] *)
  ]

let apply_block (cfg : finite_field_config) ?scratch_ring (ctx : Context_allocator.t) (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let scratch_ring =
      match scratch_ring with
      | Some r -> r
      | None -> Array.init 4 (fun _ -> Context_allocator.alloc_scratch ctx)
    in
    let n_ring = Array.length scratch_ring in
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x3141 + 0x5926)))
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
            match next_int rng 3 with
            | 0 -> emit_mersenne_invertibility_knot ~scratch_slot:s
            | 1 -> emit_gf64_distributivity_knot ~scratch_slot:s
            | _ -> emit_mersenne_quadratic_knot ~scratch_slot:s
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

let apply_program ?scratch_ring (cfg : finite_field_config) (ctx : Context_allocator.t) (prog : program) : program =
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

let finite_field_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Finite Field Arithmetic: %d ops -> %d ops (+%d mixed-characteristic knots, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
