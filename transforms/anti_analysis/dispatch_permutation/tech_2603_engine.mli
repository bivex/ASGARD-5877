(** ASGARD-5877: Tech-2603 (arXiv:2603.18355)
    Anti-VPC-Tracking & Non-Linear Dispatch Engine.
    Implements bijective affine layout permutations, split-VPC encoding/decoding,
    entropy-whitened decoy synthesis, and anti-PUSHAN resilience metrics. *)

open Tech_2603_types

val is_power_of_two : int -> bool

val next_power_of_two : int -> int

val compute_modular_inverse_64 : int64 -> int -> int64
(** [compute_modular_inverse_64 a shift] computes x such that (a * x) mod 2^shift = 1.
    Requires that [a] is odd (coprime to 2^shift). *)

val generate_affine_plan :
  ?min_capacity:int ->
  seed:int64 ->
  real_count:int ->
  unit ->
  (vpc_scramble_plan, tech_2603_error) result
(** Generates a bijective affine permutation plan: pi(i) = (a * i + b) mod M,
    where M is the smallest power-of-two >= max(min_capacity, real_count),
    a is guaranteed odd and non-trivial, and b is a pseudorandom offset. *)

val scramble_bytecode :
  seed:int64 ->
  bytecode:int64 array ->
  plan:vpc_scramble_plan ->
  int64 array
(** Scrambles logical bytecode into physical slots according to [plan].
    Unused padding slots are populated with entropy-whitened decoy instructions. *)

val encode_split_vpc : seed:int64 -> physical_slot:int -> split_vpc
(** Encodes physical VPC slot into a dual-variable (key, masked) Split-VPC representation. *)

val resolve_split_vpc : split_vpc -> int
(** Reconstructs physical VPC slot from Split-VPC components. *)

val advance_split_vpc :
  split_vpc ->
  plan:vpc_scramble_plan ->
  dynamic_key:int64 ->
  split_vpc
(** Advances Split-VPC to the next logical instruction's physical slot via the successor table. *)

val evaluate_trace_metrics : int array -> tech_2603_metrics
(** Computes anti-PUSHAN metrics (monotonicity score, jump distance, entropy variance)
    over a physical execution slot trace. *)

val synthesize_decoy_word : seed:int64 -> slot:int -> int64
(** Synthesizes an entropy-whitened decoy instruction word for padding slots. *)

val emit_split_vpc_def : unit -> Cpp_codegen.Cpp_ast.top_decl
(** Emits typed AST for the SplitVPC struct definition. *)

val emit_nonlinear_vpc_dispatcher_def : unit -> Cpp_codegen.Cpp_ast.top_decl
(** Emits typed AST for NonLinearVPCDispatcher template struct definition. *)

val emit_tech_2603_cpp_header : unit -> string
(** Emits standalone C++20 header source (<asg_tech_2603.hpp>) for runtime integration. *)
