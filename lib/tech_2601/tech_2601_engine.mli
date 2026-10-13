(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    Core Transformation & Dynamic Runtime Coordination Engine. *)

open Tech_2601_types

val generate_shadow_record :
  ?alloc_size:int ->
  interceptor_symbol:string ->
  original_metadata ->
  (shadow_unwind_record, tech_2601_error) result
(** Synthesizes ABI-compliant shadow unwind records.
    Restricted to safe stack adjustments that preserve non-volatile frame registers. *)

val compute_stack_rollback_delta : shadow_unwind_record -> int
(** Computes the stack pointer rollback delta to cancel the temporary stack effects
    introduced by the OS during shadow unwinding. *)

val serialize_metadata : original_metadata -> bytes
(** Serializes original metadata and LSData into a canonical binary byte buffer. *)

val deserialize_metadata : bytes -> (original_metadata, tech_2601_error) result
(** Deserializes a canonical binary byte buffer into original metadata and LSData. *)

val seal_metadata :
  master_key:bytes ->
  ?alloc_size:int ->
  ?interceptor_symbol:string ->
  original_metadata ->
  protected_container
(** Encapsulates and encrypts original unwind tables and LSData,
    binding the container to the shadow record with an HMAC-SHA256 authentication tag. *)

val unseal_metadata :
  master_key:bytes ->
  protected_container ->
  (original_metadata, tech_2601_error) result
(** Verifies HMAC-SHA256 authentication tag in constant-time and decrypts metadata.
    Fails closed immediately upon bit-flips, corruption, or key mismatches. *)

val resolve_exception :
  original_metadata ->
  throwing_pc:int64 ->
  exception_type:int32 ->
  (int64 * int64 list, tech_2601_error) result
(** Evaluates the exception-handling FSM:
    Finds the target landing pad PC and computes the list of active destructor PCs
    that must be invoked in LIFO (reverse construction) order. *)

val runtime_header_source : string
