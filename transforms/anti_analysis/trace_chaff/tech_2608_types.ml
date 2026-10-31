(** ASGARD-5877: Tech-2608 (arXiv:2608.20628)
    Anti-Trace-Synthesis & Memory Chaffing Specification. *)

type access_op =
  | MemRead
  | MemWrite

type memory_event = {
  timestamp : int;
  access_type : access_op;
  addr : int64;
  size_bytes : int;
  value : int64;
  is_chaff : bool;
}

type chaff_strategy =
  | UniformRandom
  | RegisterEntangled
  | OpaqueGuarded
  | RollingKeyDependent

type chaff_config = {
  pool_size : int;
  chaff_ratio : float;
  strategy : chaff_strategy;
  seed : int64;
}

type tech_2608_metrics = {
  chaff_density : float;
  address_entropy : float;
  register_entanglement_score : float;
}

type tech_2608_error =
  | InvalidPoolSize of int
  | InvalidChaffRatio of float
  | EmptyMemoryTrace

let error_to_string = function
  | InvalidPoolSize sz ->
      Printf.sprintf "Tech-2608: Pool size %d must be a positive multiple of 64 bytes" sz
  | InvalidChaffRatio r ->
      Printf.sprintf "Tech-2608: Chaff ratio %.2f must be non-negative" r
  | EmptyMemoryTrace ->
      "Tech-2608: Memory trace is empty"
