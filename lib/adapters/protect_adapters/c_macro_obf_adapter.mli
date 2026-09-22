open Random_visa_ports
open Protect_ports
open Native_vm

val transform_source :
  config:Protection_config.t ->
  in_file:string ->
  out_c_file:string ->
  out_header_file:string ->
  rng:Random.State.t ->
  (unit, error) result
