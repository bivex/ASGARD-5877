(** Mutation_profile — Polymorphic opcode implementation families, MBA substitutions, and embedded silent poisoning. *)

type alu_variant =
  | LinearStandard
  | MbaZhouEyrolles of int
  | MaskedSemiLinear of { mask_even : int64; mask_odd : int64 }
  | PolynomialOpaqueZero

type timing_probe_mode =
  | ProbeDisabled
  | SilentPoisoning of { threshold_cycles : int64; poison_mask : int64 }

type handler_mutation = {
  alu_variant       : alu_variant;
  has_opaque_branch : bool;
  timing_probe      : timing_probe_mode;
}

type t = {
  op_mutations            : (int, handler_mutation) Hashtbl.t;
  global_timing_threshold : int64;
}

val generate :
  rng:Random.State.t ->
  total_opcodes:int ->
  ?enable_silent_poisoning:bool ->
  ?max_mba_depth:int ->
  unit ->
  t

val get_mutation : t -> int -> handler_mutation
