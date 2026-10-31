open Vm_ir
open Arm64_types

val lift : string -> raw_op list -> Ir.instr list option
