open Random_visa_domain
open Random_visa_ports

(** Use case: Export Vector ISA spec to formal Sail specification. *)

val to_string : Vector_isa_spec.t -> string

val run :
  (module Ports.Sail_spec_writer) ->
  Vector_isa_spec.t ->
  target_file_path:string ->
  (string, Errors.t) result
