open Random_visa_domain
open Random_visa_ports

(** C++20 Emulator Code Emitter implementing [Ports.Cpp_code_emitter]. *)

include Ports.Cpp_code_emitter

val emit_to_files : Vector_isa_spec.t -> output_dir:string -> (string list, Errors.t) result
