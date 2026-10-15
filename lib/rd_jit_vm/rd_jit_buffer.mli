open Cpp_codegen.Cpp_ast

val rns_moduli_decls : unit -> top_decl list
val rns_register_def : unit -> top_decl
val rd_jit_context_def : unit -> top_decl
val dual_mapped_jit_buffer_def : unit -> top_decl
val header_decls : unit -> top_decl list
val header : unit -> string
