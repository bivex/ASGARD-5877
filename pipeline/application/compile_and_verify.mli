open Domain
open Contracts

(** Use case: Compile emulator and run verification test harness. *)

val run :
  (module Ports.Compiler) ->
  project_dir:string ->
  (string, Errors.t) result
