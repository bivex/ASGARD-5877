open Random_visa_ports
open Protect_ports

val compile_to_asm :
  arch:target_arch ->
  c_source:string ->
  out_asm:string ->
  include_dir:string ->
  (unit, error) result

val compile_native_binary :
  is_c:bool ->
  source_file:string ->
  out_binary:string ->
  include_dir:string ->
  (unit, error) result

val execute_binary :
  binary_path:string ->
  (int * string, error) result
