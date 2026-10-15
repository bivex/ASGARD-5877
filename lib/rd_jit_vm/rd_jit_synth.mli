open Cpp_codegen.Cpp_ast

val external_symbols_header : string list -> string
val jit_op_kind_decl : unit -> top_decl
val jit_instr_decl : unit -> top_decl
val jit_block_decl : unit -> top_decl
val header_decls : ?external_symbols:string list -> unit -> top_decl list
val header : ?external_symbols:string list -> unit -> string
