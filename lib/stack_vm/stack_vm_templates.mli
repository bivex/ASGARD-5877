open Jingoo

(** Jingoo environment configured with autoescape disabled for C++ source emission. *)
val env : Jg_types.environment

(** Render a template string with the provided models using [env]. *)
val render : string -> (string * Jg_types.tvalue) list -> string

(** Jingoo template for [stack_vm_runtime.hpp]. *)
val runtime_hpp_template : string

(** Jingoo template for [stack_vm_runner.cpp]. *)
val runner_cpp_template : string

(** Jingoo template for [stack_vm_probe.cpp]. *)
val probe_cpp_template : string
