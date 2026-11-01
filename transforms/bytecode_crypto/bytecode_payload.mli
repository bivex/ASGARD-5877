(** Authenticated Bytecode Payload Packaging & Verification Engine.
    Implements fail-closed verification before instruction decoding. *)

type payload_error =
  | BadMagic of int32
  | UnsupportedVersion of int32
  | TruncatedPayload of { expected : int; actual : int }
  | AuthenticationFailed
  | CorruptedBlockTable of string

val error_to_string : payload_error -> string

type block_desc = {
  block_id : int;
  word_offset : int;
  word_count : int;
}

type sealed_payload = {
  header_bytes : bytes;
  block_table_bytes : bytes;
  code_bytes : bytes;
  auth_tag : bytes;
  serialized_blob : bytes;
}

type authenticated_payload = {
  module_name : string;
  version : int;
  total_blocks : int;
  blocks : block_desc list;
  code_words : int64 list;
}

val seal_program :
  master_key:bytes ->
  module_name:string ->
  blocks:(int * int64 list) list ->
  sealed_payload
(** Encrypts blocks with topological Block_key_kdf and seals the entire payload
    with an HMAC-SHA256 authentication tag binding code, topology, and metadata. *)

val verify_and_unpack :
  master_key:bytes ->
  module_name:string ->
  payload_bytes:bytes ->
  (authenticated_payload, payload_error) result
(** Authenticates payload in constant time BEFORE decoding or dispatching.
    Fails closed immediately upon bit-flips, tampering, truncation, or block reordering. *)
