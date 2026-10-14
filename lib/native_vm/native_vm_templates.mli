(** Native_vm_templates — Declarative Jingoo templates for Native Threaded VM C++ runtime. *)

open Jingoo

val env : Jg_types.environment

val render : string -> (string * Jg_types.tvalue) list -> string

val platform_compat_header : string

val crypto_primitives_header : string

val sanitization_header : string

val threaded_header_template : string

val runner_template : string
