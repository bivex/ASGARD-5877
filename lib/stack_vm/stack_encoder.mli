open Stack_ir

type opcode_map = {
  op_push_imm : int;
  op_push_reg : int;
  op_pop_reg : int;
  op_read_mem : int;
  op_write_mem : int;
  op_add : int;
  op_sub : int;
  op_mul : int;
  op_nor : int;
  op_nand : int;
  op_shl : int;
  op_shr : int;
  op_dup : int;
  op_swap : int;
  op_push_flags : int;
  op_pop_flags : int;
  op_jmp_rel : int;
  op_jcc_rel : int;
  op_key_adjust : int;
  op_exit : int;
  op_call_extern : int;
  op_resolve_sym : int;
  op_setcc : int;
  op_cmov : int;
  op_cmp : int;
  op_test : int;
}

val default_opcode_map : opcode_map

val generate_opcode_map : int64 -> opcode_map

type encrypted_bytecode = {
  bytes : bytes;
  block_offsets : (int, int) Hashtbl.t;
  block_keys : (int, int64) Hashtbl.t;
  seed_key : int64;
  op_map : opcode_map;
}

val rotl64 : int64 -> int -> int64

val step_key : int64 -> int -> int64

val encode_op : ?op_map:opcode_map -> stack_op -> bytes

val encode_program :
  ?seed_key:int64 ->
  ?op_map:opcode_map ->
  ?polymorphic:bool ->
  program ->
  encrypted_bytecode

val decode_op :
  ?op_map:opcode_map ->
  bytes ->
  int ref ->
  int64 ref ->
  stack_op option

val decode_all :
  ?op_map:opcode_map ->
  bytes ->
  int64 ->
  stack_op list
