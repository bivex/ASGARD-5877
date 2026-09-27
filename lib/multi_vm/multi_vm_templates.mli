(** Multi_vm_templates — Declarative Jingoo templates for Heterogeneous Multi-VM C++ runtime. *)

open Jingoo

val env : Jg_types.environment

val render : string -> (string * Jg_types.tvalue) list -> string

val multi_vm_header_template : string

val runner_template : string
