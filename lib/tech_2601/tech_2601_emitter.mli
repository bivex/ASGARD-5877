(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    C++20/C11 Typed EDSL AST Emitter for Cryptographic Shadow Unwind & Exception FSM Runtime. *)

open Cpp_codegen.Cpp_ast

val constant_time_memcmp_decl : unit -> top_decl
val secure_zeroize_decl : unit -> top_decl
val secure_zero_decl : unit -> top_decl
val sha256_class_def : unit -> top_decl
val hmac_sha256_class_def : unit -> top_decl
val try_scope_struct_def : unit -> top_decl
val destructor_struct_def : unit -> top_decl
val shadow_record_struct_def : unit -> top_decl
val original_metadata_struct_def : unit -> top_decl
val shadow_frame_struct_def : unit -> top_decl
val thread_shadow_stack_class_def : unit -> top_decl
val get_tls_shadow_stack_decl : unit -> top_decl
val protected_container_struct_def : unit -> top_decl
val rollback_stack_decl : unit -> top_decl
val scrub_stack_decl : unit -> top_decl
val xor_keystream_decl : unit -> top_decl
val compute_container_mac_decl : unit -> top_decl
val unseal_decl : unit -> top_decl
val resolve_exception_decl : unit -> top_decl

val tech_2601_namespace_decls : unit -> top_decl list
val runtime_header_decls : unit -> top_decl list
val emit_runtime_header : unit -> string
