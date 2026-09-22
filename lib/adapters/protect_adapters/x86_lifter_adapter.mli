open Random_visa_ports
open Protect_ports

val arch_name : string
val target_arch : target_arch
val lift_source : string -> (Vm_ir.Ir.func * (string * string) list, error) result
