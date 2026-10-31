(** ASGARD-5877: Tech-2603 (arXiv:2603.18355)
    Anti-VPC-Tracking & Non-Linear Dispatch Specification. *)

type affine_generator = {
  a : int64;
  a_inv : int64;
  b : int64;
  modulus : int;
  shift : int;
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
  entropy_variance : float;
  average_jump_distance : float;
}

type tech_2603_error =
  | ModulusNotPowerOfTwo of int
  | MultiplierNotCoprime of int64
  | CapacityTooSmall of { needed: int; capacity: int }
  | InvalidPermutation of string

let error_to_string = function
  | ModulusNotPowerOfTwo m ->
      Printf.sprintf "Tech-2603: Modulus %d is not a power of two" m
  | MultiplierNotCoprime a ->
      Printf.sprintf "Tech-2603: Multiplier 0x%LX is not coprime to modulus (must be odd)" a
  | CapacityTooSmall { needed; capacity } ->
      Printf.sprintf "Tech-2603: Capacity %d is too small for %d bytecode words" capacity needed
  | InvalidPermutation msg ->
      Printf.sprintf "Tech-2603: Invalid permutation: %s" msg
