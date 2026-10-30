(** Phase 2a: Stack-VM Handler Multiplicity & Metamorphic Synthesis Pass *)

open Stack_ir

type multiplicity_config = {
  enabled : bool;
  rate    : int;
  seed    : int64;
}
type rng_state
val make_rng : int64 -> rng_state

val default_multiplicity_config : int64 -> multiplicity_config
val expand_add_mba : unit -> stack_op list

val expand_sub_mba : ?rng:rng_state -> unit -> stack_op list
val apply_block : multiplicity_config -> Context_allocator.t -> block -> block

val apply_program : multiplicity_config -> Context_allocator.t -> program -> program

val multiplicity_stats : program -> program -> string
