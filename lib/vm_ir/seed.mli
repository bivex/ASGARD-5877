(** Hierarchical multi-stream seed management for deterministic build diversification. *)

type t

val create : ?master_seed:int64 -> unit -> t
val derive_subseed : t -> string -> int64
val make_rng : int64 -> Random.State.t
val to_string : t -> string

val master_seed : t -> int64
val opcode_seed : t -> int64
val register_seed : t -> int64
val cfg_seed : t -> int64
val constant_seed : t -> int64
val mba_seed : t -> int64
val superop_seed : t -> int64
