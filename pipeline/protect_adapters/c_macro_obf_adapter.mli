open Random_visa_ports
open Protect_ports

val transform_source :
  config:protection_config ->
  in_file:string ->
  out_c_file:string ->
  out_header_file:string ->
  rng:Random.State.t ->
  (unit, error) result

val run_c_obfuscation :
  input:string ->
  out_file:string ->
  out_header:string option ->
  seed:int option ->
  strings:bool ->
  consts:bool ->
  mba_depth:int ->
  compile:bool ->
  (unit, error) result
