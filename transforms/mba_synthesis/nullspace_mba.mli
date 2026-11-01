(** Nullspace MBA Engine — Minterm Basis Synthesis.
    Uses the 4 orthogonal disjoint minterms:
      e1 = x AND y
      e2 = x AND (NOT y)
      e3 = (NOT x) AND y
      e4 = NOT (x OR y)
    forming the identity matrix I_4 in the truth-table space.
    For any boolean function f_k with truth vector (v00, v01, v10, v11):
      f_k(x, y) - v11*e1 - v10*e2 - v01*e3 - v00*e4 == 0 (mod 2^64)
    identically over Z_{2^64} for all 64-bit inputs with 0% fallback rate. *)

open Vm_ir

type minterm_term = {
  bfunc_id : int;
  coeff    : int64;
}

val synth_minterm_zero : rng:Random.State.t -> terms_count:int -> minterm_term list

val eval_terms : terms:minterm_term list -> x:int64 -> y:int64 -> int64

val verify_minterm_zero : minterm_term list -> bool

val obfuscate_alu :
  rng:Random.State.t ->
  dst:Register.t ->
  src1:Ir.operand ->
  src2:Ir.operand ->
  Ir.alu_op ->
  Ir.instr list
