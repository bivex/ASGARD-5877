(** Null-Space MBA Synthesis.
    Synthesizes zero-equivalent polynomial terms from the kernel of the
    4-row truth-table matrix A over randomized bitwise bases. *)

open Vm_ir

val synth_zero : rng:Random.State.t -> m:int -> (int * int64) list
val verify_zero : (int * int64) list -> bool

val obfuscate_alu :
  rng:Random.State.t ->
  dst:Register.t ->
  src1:Ir.operand ->
  src2:Ir.operand ->
  Ir.alu_op ->
  Ir.instr list
