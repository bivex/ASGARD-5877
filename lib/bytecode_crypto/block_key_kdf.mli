(** Deterministic Topological Block Key Derivation Function (KDF).
    Guarantees CFG-path-independent key synchronization across CFF loops and join points. *)

val derive_block_key : master_key:bytes -> block_id:int -> block_offset:int -> int64
(** Derives a cryptographically strong 64-bit root key for a basic block.
    The key depends strictly on immutable topological properties (block identity and offset),
    eliminating execution-history path divergence and the need for mutable KeyAdjust compensations. *)

val derive_word_mask : block_key:int64 -> word_index_in_block:int -> int64
(** Position-dependent in-block mask for instruction word [word_index_in_block].
    Uses high-entropy permutation anchored to [block_key]. *)

val derive_module_aad :
  module_name:string ->
  version:int ->
  total_blocks:int ->
  code_size_bytes:int ->
  bytes
(** Constructs Associated Authenticated Data (AAD) binding module identity,
    block count, and total code size to prevent block swapping, reordering, and truncation. *)
