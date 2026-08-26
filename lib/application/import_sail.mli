open Random_visa_domain
open Random_visa_ports

(** Use case: Import Sail specification file or text into domain Vector ISA spec. *)

val run :
  (module Ports.Sail_parser) ->
  ?spec_name:string ->
  string ->
  (Vector_isa_spec.t, Errors.t) result

val run_file :
  (module Ports.Sail_parser) ->
  ?spec_name:string ->
  string ->
  (Vector_isa_spec.t, Errors.t) result
