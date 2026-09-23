open Ir

(** Reconciliation of 32-bit sub-register write semantics (zero-extension of
    the upper half of the backing 64-bit register) between the width-blind
    native VM and the exact reference evaluator.  See [Subreg_write] module
    comment in the implementation for the rationale. *)

val expand_instr : instr -> instr list
(** [expand_instr i] is [i] followed by a B64 `shl 32 / shr 32` zero-extension
    pair for every B32 GPR that [i] writes (nothing appended otherwise). *)

val expand_block : basic_block -> basic_block

val expand_cfg : cfg -> cfg

val expand_func : func -> func
