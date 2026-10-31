open Random_visa_domain
open Random_visa_ports

(** Use case: Generate C++ or C11 standalone emulator project from ISA spec. *)

val run_cpp :
  (module Ports.Cpp_code_emitter) ->
  Vector_isa_spec.t ->
  output_dir:string ->
  (string list, Errors.t) result

val run_c11 :
  (module Ports.C11_code_emitter) ->
  Vector_isa_spec.t ->
  output_dir:string ->
  (string list, Errors.t) result
