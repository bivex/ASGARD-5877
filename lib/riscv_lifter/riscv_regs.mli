open Vm_ir

val map_riscv_reg : ?width:Register.width -> string -> (Register.t, string) result
val parse_imm : string -> (int64, string) result
val reg_to_vreg_index : Register.t -> int option
