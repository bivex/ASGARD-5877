open Contracts
open Protect_ports

val arch_name : string
val target_arch : target_arch
val lift_source : string -> (ir_func * (string * string) list, error) result
