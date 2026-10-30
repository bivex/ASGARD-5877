open Cpp_codegen.Cpp_ast

(* Runtime register-file layout constants (single source of truth shared
   by the EDSL struct definition and the raw JIT assembly offsets). *)
val rd_jit_gprs_count : int
val rd_jit_flags_off : int


val rns_moduli_decls : unit -> top_decl list
val rns_register_def : unit -> top_decl
val rd_jit_context_def : unit -> top_decl
val dual_mapped_jit_buffer_def : unit -> top_decl
val header_decls : unit -> top_decl list
val header : unit -> string
