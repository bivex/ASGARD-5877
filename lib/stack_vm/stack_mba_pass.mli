(** MBA Constant Synthesis Pass — public interface *)

open Stack_ir

type mba_config = {
  seed     : int64;
  mba_rate : int;
}

val default_mba_config : int64 -> mba_config

val apply_block   : mba_config -> block   -> block
val apply_program : mba_config -> program -> program

val mba_stats : program -> program -> string
