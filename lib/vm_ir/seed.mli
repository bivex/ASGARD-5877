(** Hierarchical multi-stream seed management for deterministic build diversification. *)

type t = {
  master_seed : int64;
  opcode_seed : int64;
  register_seed : int64;
  cfg_seed : int64;
  constant_seed : int64;
  mba_seed : int64;
  superop_seed : int64;
}

val create : ?master_seed:int64 -> unit -> t
val derive_subseed : t -> string -> int64
val make_rng : int64 -> Random.State.t
val to_string : t -> string
