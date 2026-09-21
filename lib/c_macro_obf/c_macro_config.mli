(** Configuration types and PRNG utilities for C macro obfuscation. *)

type config = {
  seed : int;
  mba_depth : int;
  obfuscate_strings : bool;
  obfuscate_constants : bool;
  obfuscate_arithmetic : bool;
  inject_opaque_predicates : bool;
  api_hashing : bool;
  anti_debug : bool;
  signal_dispatch : bool;
  timing_guard : bool;
  timing_threshold_ticks : int64;
  macro_prefix : string;
}

val default_config : config

val xorshift32 : int -> int

val rand_u64 : Random.State.t -> int64
