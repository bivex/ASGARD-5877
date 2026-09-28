(** Phase 2b: Spaghetti Control-Flow Splitting Pass
    ───────────────────────────────────────────────
    Splits straight-line basic blocks into chained fragments linked by JmpRel,
    increasing block count and dispersing control-flow before CFF dispatcher
    synthesis.

    Soundness invariants:
      • Cut is made ONLY at points where stack depth = 0 (block stack balance preserved).
      • Cut is made ONLY where architectural flags are dead (not live across cut),
        preventing subsequent CFF dispatcher comparisons from clobbering live flags.
      • Global block ceiling limits total block proliferation to preserve CFF performance.
*)

open Stack_ir

type spaghetti_config = {
  seed       : int64; (** Random seed for reproducible splitting *)
  split_rate : int;   (** Probability (0–100) of splitting an eligible block *)
  max_blocks : int;   (** Upper bound on total blocks in program *)
  min_chunk  : int;   (** Minimum ops before and after split point (default: 2) *)
}

val default_spaghetti_config : int64 -> spaghetti_config

val apply_program : spaghetti_config -> program -> program

val spaghetti_stats : program -> program -> string
