(** Phase 2a: Stack-VM Handler Multiplicity & Metamorphic Synthesis Pass *)

open Stack_ir

type multiplicity_config = {
  enabled : bool;
  rate    : int;
  seed    : int64;
}

val default_multiplicity_config : int64 -> multiplicity_config

val apply_block : multiplicity_config -> Context_allocator.t -> block -> block

val apply_program : multiplicity_config -> Context_allocator.t -> program -> program

val multiplicity_stats : program -> program -> string
