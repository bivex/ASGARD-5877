(** Virtual CFG Flattening Pass — public interface *)

open Stack_ir

type cff_config = {
  seed : int64;
}

val default_cff_config : int64 -> cff_config

val apply_program : cff_config -> Context_allocator.t -> program -> program

val cff_stats      : program -> program -> string
val direct_jmp_count : program -> int
