open Random_visa_ports
open Protect_ports

val embed_vm_trampoline : c_src:string -> bytecode:int64 list -> out_path:string -> unit

module C_trampoline_engine : Trampoline_engine
