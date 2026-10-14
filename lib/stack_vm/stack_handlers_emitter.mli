(** Stack_handlers_emitter — Typed C++ AST code generation for Stack-VM manipulation handlers. *)

open Cpp_codegen.Cpp_ast

val vm_handler_params : (ctype * string) list

val emit_h_push_imm : unit -> top_decl
val emit_h_push_imm32 : unit -> top_decl
val emit_h_push_reg : unit -> top_decl
val emit_h_pop_reg : unit -> top_decl
val emit_h_dup : unit -> top_decl
val emit_h_dup2 : unit -> top_decl
val emit_h_rot : unit -> top_decl
val emit_h_swap : unit -> top_decl

val emit_push_pop_handlers : unit -> top_decl list
val emit_dup_swap_handlers : unit -> top_decl list
val emit_all_stack_manipulation_handlers : unit -> top_decl list

val emit_push_pop_handlers_string : unit -> string
val emit_dup_swap_handlers_string : unit -> string
val emit_all_handlers_string : unit -> string

val emit_handlers_source : Buffer.t -> unit
