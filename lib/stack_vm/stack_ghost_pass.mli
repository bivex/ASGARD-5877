(** Ghost Stack Padding Pass — public interface *)

open Stack_ir

type ghost_config = {
  seed        : int64;
  ghost_rate  : int;
  max_ghosts  : int;
  entangle    : bool;
}

val default_ghost_config : int64 -> ghost_config

val apply_block   : ?entangle_slot:int -> ghost_config -> Context_allocator.t -> block   -> block
val apply_program : ghost_config -> Context_allocator.t -> program -> program

val entangle_with_accumulator : ?flags_live:bool -> acc_slot:int -> int64 -> stack_op list

val ghost_stats : program -> program -> string
