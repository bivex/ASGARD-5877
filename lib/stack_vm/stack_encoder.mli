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
  op_sar : int;
  op_div : int;
  op_idiv : int;
  op_push_imm32 : int;
  op_add_imm : int;
  op_sub_imm : int;
  op_add_ii : int;
  op_sub_ii : int;
  op_set_reg_imm : int;
  op_add_reg_imm : int;
}

val default_opcode_map : opcode_map

val generate_opcode_map : int64 -> opcode_map

type encrypted_bytecode = {
  bytes : bytes;
  block_offsets : (int, int) Hashtbl.t;
  block_keys : (int, int64) Hashtbl.t;
  seed_key : int64;
  op_map : opcode_map;
  (** Anti-VMPredator address binding: stored [seed_key]/[block_keys]
      literals are pre-XORed with this mask; the C++ runtime XORs it back
      out with the key derived from its handler addresses. Cipher bytes are
      unaffected. [0L] reproduces the legacy encoding byte-identically. *)
  addr_mask : int64;
  (** Keyed integrity tag over the padded cipher image, verified by the
      runtime before it decodes the first byte. Invariant under
      [apply_addr_mask]. *)
  payload_tag : int64;
  (** The two MAC key halves [payload_tag] is keyed with, under ids 0 and 1,
      masked with [addr_mask] exactly like the block keys. *)
  tag_keys : (int, int64) Hashtbl.t;
}

(** SipHash-1-2 PRF, 128-bit key split into [(k0, k1)], 64-bit message
    word. Shared by the block-key derivation, the payload tag and their
    C++ mirrors so the two sides cannot drift. *)
val siphash_block : k0:int64 -> k1:int64 -> int64 -> int64

(** The two payload-tag key halves for [seed_key], domain-separated from the
    per-block key halves. *)
val payload_tag_keys : int64 -> int64 * int64

(** Keyed integrity tag over [cipher]: SipHash-1-2 in CBC mode over the
    8-byte-padded image, binding its padded length and then every
    little-endian 64-bit word. A flipped byte, a truncation or an extension
    all change the result. *)
val derive_payload_tag : bytes -> int64 -> int64

(** [payload_tag_of_keys] with explicit key halves, so a caller holding a
    key that is not [seed_key]-derived can still produce a matching tag. *)
val payload_tag_of_keys : k0:int64 -> k1:int64 -> bytes -> int64

(** Effective (unmasked) rolling seed: [seed_key xor addr_mask]. The value
    decoders and evaluators must start from. *)
val effective_seed_key : encrypted_bytecode -> int64

(** Re-bind stored literals to a new address mask (delta-based, composes;
    mask [0L] un-marks). Cipher bytes are never touched. *)
val apply_addr_mask : encrypted_bytecode -> int64 -> encrypted_bytecode

(** Parse exactly 16 hex digits into a full-range unsigned 64-bit pattern
    (Int64.of_string rejects values above Int64.max_int). *)
val parse_u64_hex : string -> int64

val rotl64 : int64 -> int -> int64

val step_key : int64 -> int -> int64

val encode_op : ?op_map:opcode_map -> ?compact_imm:bool -> stack_op -> bytes

val encode_program :
  ?seed_key:int64 ->
  ?op_map:opcode_map ->
  ?polymorphic:bool ->
  ?addr_mask:int64 ->
  ?compact_imm:bool ->
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
  ?block_keys:(int, int64) Hashtbl.t ->
  ?block_offsets:(int, int) Hashtbl.t ->
  bytes ->
  int64 ->
  stack_op list

(** Block-aware decode: use when [encrypted_bytecode] has per-block SipHash keys. *)
val decode_enc : encrypted_bytecode -> stack_op list

