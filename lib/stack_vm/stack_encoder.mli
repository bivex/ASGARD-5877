open Stack_ir

type encrypted_bytecode = {
  bytes : bytes;
  block_offsets : (int, int) Hashtbl.t;
  block_keys : (int, int64) Hashtbl.t;
  seed_key : int64;
}

val rotl64 : int64 -> int -> int64

val step_key : int64 -> int -> int64

val encode_op : stack_op -> bytes

val encode_program : ?seed_key:int64 -> program -> encrypted_bytecode

val decode_op : bytes -> int ref -> int64 ref -> stack_op option

val decode_all : bytes -> int64 -> stack_op list
