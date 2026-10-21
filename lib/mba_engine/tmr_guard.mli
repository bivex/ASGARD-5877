(* ASGARD-5877: Triple Modular Redundancy (TMR) Majority Voting & Anti-Patching *)

open Vm_ir
open Mba

val evaluate_tmr_majority : int64 -> int64 -> int64 -> int64
(** Pure bitwise majority vote: (r1 & r2) | (r2 & r3) | (r1 & r3). *)

val emit_tmr_majority :
  r1:Register.t ->
  r2:Register.t ->
  r3:Register.t ->
  dst:Register.t ->
  scratch1:Register.t ->
  scratch2:Register.t ->
  Ir.instr list
(** Emits branchless bitwise majority voting instructions:
    dst = (r1 & r2) | (r2 & r3) | (r1 & r3). *)

val emit_tmr_evaluation :
  e1:expr ->
  e2:expr ->
  e3:expr ->
  env:(string * Ir.operand) list ->
  dst:Register.t ->
  r1:Register.t ->
  r2:Register.t ->
  r3:Register.t ->
  scratch1:Register.t ->
  scratch2:Register.t ->
  Ir.instr list
(** Lowers three divergent MBA expressions (r1, r2, r3) and fuses them with
    branchless bitwise majority voting into [dst]. *)
