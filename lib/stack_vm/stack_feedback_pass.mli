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
*)

open Stack_ir

type feedback_config = {
  seed                : int64;
  feedback_rate       : int;   (** Probability (0–100) of injecting feedback on known registers *)
  enable_cff_feedback : bool;  (** Inject VPC token feedback at CFF block entries *)
}

val default_feedback_config : int64 -> feedback_config

type feedback_stats = {
  initial_ops       : int;
  final_ops         : int;
  feedback_injected : int;
}

val apply_program :
  ?vpc_slot:int ->
  ?block_tokens:(int, int64) Hashtbl.t ->
  feedback_config ->
  program ->
  program

val feedback_stats : program -> program -> feedback_stats
