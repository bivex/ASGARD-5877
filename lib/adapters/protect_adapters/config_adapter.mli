open Random_visa_ports
open Protect_ports

val wrap : Native_vm.Protection_config.t -> protection_config

val unwrap : protection_config -> Native_vm.Protection_config.t

val default : protection_config

val from_preset : string -> (protection_config, error) result

val from_file : string -> (protection_config, error) result

val save_to_file : string -> protection_config -> unit

val init_config : out_file:string -> preset:string option -> (unit, error) result

val resolve :
  config_file:string option ->
  preset:string option ->
  enable_cff:bool ->
  enable_mba:bool ->
  mba_depth:int ->
  seed:int option ->
  protection_config
