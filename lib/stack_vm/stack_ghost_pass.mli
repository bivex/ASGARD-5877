(** Ghost Stack Padding Pass — public interface *)

open Stack_ir

type ghost_config = {
  seed        : int64;
  ghost_rate  : int;
  max_ghosts  : int;
}

val default_ghost_config : int64 -> ghost_config

val apply_block   : ghost_config -> Context_allocator.t -> block   -> block
val apply_program : ghost_config -> Context_allocator.t -> program -> program

val ghost_stats : program -> program -> string
