open Random_visa_domain
open Random_visa_ports

(** C11 Bare-metal Emulator Code Emitter implementing [Ports.C11_code_emitter]. *)

include Ports.C11_code_emitter

val emit_c_project :
  ?allow_widening:bool ->
  Vector_isa_spec.t ->
  output_dir:string ->
  (string list, Errors.t) result
