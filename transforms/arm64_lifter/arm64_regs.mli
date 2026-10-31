open Vm_ir

val map_arm64_reg : string -> (Register.t, string) result
val parse_imm : string -> (int64, string) result
