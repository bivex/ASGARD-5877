open Vm_ir
open Stack_ir

val lower_basic_block : Context_allocator.t -> Ir.basic_block -> block

val lower_cfg : Context_allocator.t -> Ir.cfg -> program

val lower_func : ?ctx:Context_allocator.t -> Ir.func -> Context_allocator.t * program
