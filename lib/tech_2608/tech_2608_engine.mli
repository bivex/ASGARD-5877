(** ASGARD-5877: Tech-2608 (arXiv:2608.20628)
    Anti-Trace-Synthesis & Memory Chaffing Engine.
    Implements shadow memory pool management, decoy memory event injection,
    guest register state entanglement, and BinMirror trace resilience metrics. *)

open Tech_2608_types

val compute_chaff_address :
  pool_base:int64 ->
  pool_size:int ->
  guest_reg:int64 ->
  salt:int64 ->
  int64

val compute_chaff_value :
  guest_reg_a:int64 ->
  guest_reg_b:int64 ->
  rolling_key:int64 ->
  salt:int64 ->
  int64

val synthesize_chaff_events :
  config:chaff_config ->
  pool_base:int64 ->
  guest_regs:int64 array ->
  rolling_key:int64 ->
  count:int ->
  memory_event list

val inject_chaff_into_trace :
  config:chaff_config ->
  pool_base:int64 ->
  real_trace:memory_event list ->
  guest_regs:int64 array ->
  rolling_key:int64 ->
  memory_event list

val evaluate_trace_metrics :
  memory_event list ->
  (tech_2608_metrics, tech_2608_error) result

val emit_tech_2608_cpp_header : unit -> string
(** Emits standalone C++20 header source (<asg_tech_2608.hpp>) for runtime integration. *)
