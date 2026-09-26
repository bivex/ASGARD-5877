open Vm_ir
open Stack_ir

val lower_basic_block :
  ?label_to_block:(string, int) Hashtbl.t ->
  ?ext_syms:(string, int) Hashtbl.t ->
  Context_allocator.t ->
  Ir.basic_block ->
  block

val lower_cfg :
  ?ext_syms:(string, int) Hashtbl.t ->
  Context_allocator.t ->
  Ir.cfg ->
  program

val lower_func :
  ?ctx:Context_allocator.t ->
  ?ext_syms:(string, int) Hashtbl.t ->
  Ir.func ->
  Context_allocator.t * program

val get_symbols_list : (string, int) Hashtbl.t -> string list
