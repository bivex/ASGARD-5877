(** MBA Constant Synthesis Pass — public interface *)

open Stack_ir

type mba_config = {
  seed     : int64;
  mba_rate : int;
  egraph_rate           : int;
  egraph_node_limit     : int;
  egraph_time_budget_ms : int;
  egraph_iter_limit     : int;
}

val default_mba_config : int64 -> mba_config

val apply_block   : ?ctx:Context_allocator.t -> mba_config -> block   -> block
val apply_program : ?ctx:Context_allocator.t -> mba_config -> program -> program

val mba_stats : program -> program -> string
