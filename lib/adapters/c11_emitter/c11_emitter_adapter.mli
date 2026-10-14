open Random_visa_domain
open Random_visa_ports

(** C11 Bare-metal Emulator Code Emitter implementing [Ports.C11_code_emitter]. *)

include Ports.C11_code_emitter

val emit_c_project :
  ?allow_widening:bool ->
  Vector_isa_spec.t ->
  output_dir:string ->
  (string list, Errors.t) result

val emit_csr_state_c11_def : unit -> Cpp_codegen.Cpp_ast.top_decl list
val emit_emulator_state_c11_def : unit -> Cpp_codegen.Cpp_ast.top_decl list
val emit_decoded_inst_c11_def : unit -> Cpp_codegen.Cpp_ast.top_decl list
val emit_c11_prototypes : unit -> Cpp_codegen.Cpp_ast.top_decl list
