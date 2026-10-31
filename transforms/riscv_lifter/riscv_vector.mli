open Vm_ir
open Riscv_types

type vtype_state = {
  mutable sew : int;
  mutable lmul : int;
  mutable vl : int64 option;
}

val current_state : vtype_state
val reset_state : unit -> unit

val calculate_vlmax : sew:int -> lmul:int -> int

val lift_vector : string -> raw_op list -> (Ir.instr list, string) result option
