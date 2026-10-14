(** Multi_vm_context_emitter — Typed C++ AST code generation for Multi-VM contexts and bridges. *)

open Cpp_codegen.Cpp_ast

val emit_math_vm_context : unit -> top_decl
val emit_flow_vm_context : unit -> top_decl
val emit_shared_vm_context : unit -> top_decl
val emit_bridge_switch_to_flow : unit -> top_decl
val emit_bridge_switch_to_math : unit -> top_decl

val emit_asgard_multi_vm_namespace : unit -> top_decl
val emit_asgard_multi_vm_source : unit -> string
