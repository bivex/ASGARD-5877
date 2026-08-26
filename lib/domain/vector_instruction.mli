(** Vector Instruction Aggregate and Encoding definitions. *)

type t = {
  mnemonic : string;
  format : Types.Instruction_format.t;
  funct6 : int;
  funct3 : int;
  opcode : int;
  binary_op : Types.Binary_op.t option;
  unary_op : Types.Unary_op.t option;
  element_kind : Types.Element_kind.t;
  is_widening : bool;
  is_reduction : bool;
  description : string;
  sail_function : Sail_ast.function_def;
}

val make :
  mnemonic:string ->
  format:Types.Instruction_format.t ->
  funct6:int ->
  funct3:int ->
  ?opcode:int ->
  ?binary_op:Types.Binary_op.t ->
  ?unary_op:Types.Unary_op.t ->
  ?element_kind:Types.Element_kind.t ->
  ?is_widening:bool ->
  ?is_reduction:bool ->
  ?description:string ->
  ?sail_function:Sail_ast.function_def ->
  unit ->
  t

(** [encode ?vm ?vd ?vs2 ?vs1_or_rs1_or_imm inst] encodes a 32-bit RISC-V V-ISA instruction word. *)
val encode :
  ?vm:int ->
  ?vd:int ->
  ?vs2:int ->
  ?vs1_or_rs1_or_imm:int ->
  t ->
  int32

val synthesize_sail_function :
  mnemonic:string ->
  format:Types.Instruction_format.t ->
  binary_op:Types.Binary_op.t option ->
  unary_op:Types.Unary_op.t option ->
  element_kind:Types.Element_kind.t ->
  is_widening:bool ->
  Sail_ast.function_def
