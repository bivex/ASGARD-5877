(** Phase 2c / Anti-Tracing: State-Feedback Rolling Key Pass
    ───────────────────────────────────────────────────────
    Couples bytecode rolling key decryption with dynamic VM execution state,
    defeating static and isolated-block dynamic tracing attacks.

    Attack vectors defeated:
      • Isolated block harvesting: tools (NoVmp, IDA VTIL) that decrypt blocks
        in isolation using static table keys fail because the rolling key stream
        now requires the dynamic state token computed by predecessor execution.
      • Path-forcing / NOP patching: forcing branches in a debugger or patching
        condition flags leaves the feedback registers desynchronized, causing
        all subsequent bytecode to decrypt into invalid opcodes and halt.

    Every injected KeyFeedback immediately follows the write of the coupled
    value into the coupled slot: the runtime hashes the live register while
    the encryptor can only hash a static constant, so the two must agree
    (see Stack_encoder.check_key_feedback_static).
 *)

open Stack_ir

type feedback_config = {
  seed                : int64;
  feedback_rate       : int;   (** Probability (0–100) of injecting feedback on known registers *)
}

val default_feedback_config : int64 -> feedback_config

type feedback_stats = {
  initial_ops       : int;
  final_ops         : int;
  feedback_injected : int;
}

(** [apply_program ?vpc_slot ?block_tokens cfg prog] injects the state
    feedback couplings.  When [vpc_slot] and [block_tokens] are given
    (the state of the CFF dispatcher), the rolling key is additionally
    coupled to the VPC at the entry of every CFF block: there the VPC
    provably holds the token of that block, so the coupled value is
    statically known and the encryptor can reproduce the key schedule. *)
val apply_program :
  ?vpc_slot:int ->
  ?block_tokens:(int, int64) Hashtbl.t ->
  feedback_config ->
  program ->
  program

val feedback_stats : program -> program -> feedback_stats
