(** ASGARD-5877: Tech-2603 (arXiv:2603.18355)
    Anti-VPC-Tracking & Non-Linear Dispatch Specification.
    Formalizes non-linear bytecode layout permutations, affine generators,
    Split-VPC state representations, and entropy whitening to defeat
    heuristic VPC identification in symbolic emulation engines (PUSHAN, VM-Doctor). *)

type affine_generator = {
  a : int64;        (** Coprime multiplier: gcd(a, modulus) = 1 (a is odd) *)
  a_inv : int64;    (** Multiplicative inverse: (a * a_inv) mod modulus = 1 *)
  b : int64;        (** Additive offset *)
  modulus : int;    (** Capacity: power-of-two >= bytecode count *)
  shift : int;      (** log2(modulus) *)
}

type split_vpc = {
  key : int64;
  masked : int64;
  epoch : int32;
}

type vpc_scramble_plan = {
  logical_to_physical : int array;
  physical_to_logical : int array;
  successor_table : int array;
  padding_slots : int list;
  real_count : int;
  total_capacity : int;
  affine_gen : affine_generator;
}

type tech_2603_metrics = {
  monotonicity_score : float;
  (** Fraction of transitions with |delta| in {0, 1}. Standard code: 1.0. Target: < 0.05. *)
  entropy_variance : float;
  (** Variance of Shannon entropy across blocks; low variance prevents chunk detection. *)
  average_jump_distance : float;
  (** Mean physical jump distance between sequential logical steps. *)
}

type tech_2603_error =
  | ModulusNotPowerOfTwo of int
  | MultiplierNotCoprime of int64
  | CapacityTooSmall of { needed: int; capacity: int }
  | InvalidPermutation of string

val error_to_string : tech_2603_error -> string
