(** Port signatures (interfaces) for hexagonal Ports & Adapters architecture. *)

open Random_visa_domain

module type Sail_spec_writer = sig
  val write_spec : Vector_isa_spec.t -> target_file_path:string -> (string, Errors.t) result
end

module type Sail_parser = sig
  val parse : ?spec_name:string -> string -> (Vector_isa_spec.t, Errors.t) result
  val parse_file : ?spec_name:string -> string -> (Vector_isa_spec.t, Errors.t) result
end

module type Cpp_code_emitter = sig
  val emit_emulator_project : Vector_isa_spec.t -> output_dir:string -> (string list, Errors.t) result
end

module type C11_code_emitter = sig
  val emit_c_project : Vector_isa_spec.t -> output_dir:string -> (string list, Errors.t) result
end

module type Compiler = sig
  val compile : project_dir:string -> (unit, Errors.t) result
  val run_tests : project_dir:string -> (string, Errors.t) result
end

module type Assembler = sig
  val assemble_line : Vector_isa_spec.t -> string -> (int32 option, Errors.t) result
  val assemble_program : Vector_isa_spec.t -> string -> (int32 list, Errors.t) result
  val write_binary_bytecode : int32 list -> string -> (string, Errors.t) result
  val read_binary_bytecode : string -> (int32 list, Errors.t) result
end
