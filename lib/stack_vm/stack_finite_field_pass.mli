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

type finite_field_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_finite_field_config : int64 -> finite_field_config

(** Emits Mersenne-31 prime field multiplicative invertibility knot:
    s0 - fold31(fold31(s0 * a) * a^-1) == 0 (mod 2^64).
    Net stack delta = +1 (pushes 0L onto stack). *)
val emit_mersenne_invertibility_knot : scratch_slot:int -> stack_op list

(** Emits Galois Field GF(2^64) polynomial distributivity knot:
    xtime(s ^ C) ^ xtime(s) ^ xtime(C) == 0 (mod 2^64).
    Net stack delta = +1 (pushes 0L onto stack). *)
val emit_gf64_distributivity_knot : scratch_slot:int -> stack_op list

(** Emits Mersenne-31 quadratic Frobenius cross-term knot:
    fold31((s0 + c)^2) - fold31(s0^2 + 2cs0 + c^2) == 0.
    Net stack delta = +1 (pushes 0L onto stack). *)
val emit_mersenne_quadratic_knot : scratch_slot:int -> stack_op list

val apply_block :
  finite_field_config ->
  ?scratch_ring:int array ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  ?scratch_ring:int array ->
  finite_field_config ->
  Context_allocator.t ->
  program ->
  program


val finite_field_stats : program -> program -> string
