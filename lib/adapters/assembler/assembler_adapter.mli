open Random_visa_domain
open Random_visa_ports

(** Vector Assembler and Bytecode (.vbc) Compiler Adapter implementing [Ports.Assembler]. *)

include Ports.Assembler

val parse_reg : string -> (int, Errors.t) result

val parse_imm : string -> (int, Errors.t) result

val disassemble_word : Vector_isa_spec.t -> int32 -> (string, Errors.t) result

val disassemble_program : Vector_isa_spec.t -> int32 list -> string

val write_vbc_file :
  ?vlen:int ->
  ?elen:int ->
  int32 list ->
  string ->
  (string, Errors.t) result

val read_vbc_file : string -> (int * int * int32 list, Errors.t) result
