open Random_visa_domain
open Random_visa_ports

(** Use case: Compile emulator and run verification test harness. *)

val run :
  (module Ports.Compiler) ->
  project_dir:string ->
  (string, Errors.t) result
