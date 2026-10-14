(** ASGARD-5877: Tech-2608 (arXiv:2608.20628)
    Anti-Trace-Synthesis & Memory Chaffing Specification.
    Formalizes shadow memory chaff pools, decoy memory read/write events,
    guest register entanglement, and trace distortion metrics to defeat
    behavior-specification-guided program synthesizers (BinMirror). *)

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
  chaff_ratio : float; (** Chaff events per genuine memory event (e.g., 2.0 = 2 chaff per 1 real) *)
  strategy : chaff_strategy;
  seed : int64;
}

type tech_2608_metrics = {
  chaff_density : float;
  (** Ratio of chaff operations to total memory operations in the trace *)
  address_entropy : float;
  (** Shannon entropy of accessed memory addresses *)
  register_entanglement_score : float;
  (** Fraction of chaff events whose address and value functionally depend on guest registers *)
}

type tech_2608_error =
  | InvalidPoolSize of int
  | InvalidChaffRatio of float
  | EmptyMemoryTrace

val error_to_string : tech_2608_error -> string
