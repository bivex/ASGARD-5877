open Random_visa_ports
open Protect_ports

val run :
  lifter:(module Lifter) ->
  ?c_macro_obfuscator:(module C_macro_obfuscator) ->
  vm_packager:(module Vm_packager) ->
  ?trampoline_engine:(module Trampoline_engine) ->
  ?toolchain:(module Toolchain) ->
  rng:Random.State.t ->
  config:protection_config ->
  input_file:string ->
  out_dir:string ->
  ?compile_and_run:bool ->
  unit ->
  (protect_result, error) result
