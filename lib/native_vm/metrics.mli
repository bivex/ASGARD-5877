open Vm_ir

type cfg_recovery_metrics = {
  dispatcher_fanout : int;
  indirect_transitions_ratio : float;
  symbolic_unflatten_cost : float;
}

type decoding_ambiguity_metrics = {
  dynamic_context_dependency_ratio : float;
  key_recovery_depth : int;
  static_decodability_rate : float;
}

type runtime_overhead_metrics = {
  expansion_ratio : float;
  code_bloat_factor : float;
  estimated_cycle_overhead : float;
}

type code_size_metrics = {
  bytecode_bytes : int;
  handler_table_footprint_bytes : int;
}

type reproducibility_metrics = {
  seed_entropy_bits : int;
  differential_pass_rate : float;
}

type drs_v2_metrics = {
  r_ssa : float;
  d_nl : float;
  e_cfg : float;
  composite_score : float;
}

type metrics_report = {
  shannon_entropy : float;
  cyclomatic_complexity : int;
  flattening_depth : int;
  decoy_density : float;
  mba_node_count : int;
  devirtualization_resistance_score : float;
  cfg_recovery : cfg_recovery_metrics;
  decoding_ambiguity : decoding_ambiguity_metrics;
  runtime_overhead : runtime_overhead_metrics;
  code_size : code_size_metrics;
  reproducibility : reproducibility_metrics;
  drs_v2 : drs_v2_metrics;
}

val shannon_entropy : metrics_report -> float
val cyclomatic_complexity : metrics_report -> int
val flattening_depth : metrics_report -> int
val decoy_density : metrics_report -> float
val mba_node_count : metrics_report -> int
val devirtualization_resistance_score : metrics_report -> float

val cfg_recovery : metrics_report -> cfg_recovery_metrics
val decoding_ambiguity : metrics_report -> decoding_ambiguity_metrics
val runtime_overhead : metrics_report -> runtime_overhead_metrics
val code_size : metrics_report -> code_size_metrics
val reproducibility : metrics_report -> reproducibility_metrics
val drs_v2 : metrics_report -> drs_v2_metrics

val calculate_shannon_entropy : int64 list -> float
val calculate_cfg_complexity : Ir.func -> int

val calculate_metrics :
  bytecode:int64 list ->
  func:Ir.func ->
  decoy_count:int ->
  total_handlers:int ->
  mba_nodes:int ->
  metrics_report

val calculate_resilience_metrics :
  ?dynamic_key_active:bool ->
  ?native_ir_ops:int ->
  ?differential_verified:bool ->
  ?data_flow_entangled:bool ->
  ?non_linear_degree:float ->
  ?taint_transitions_active:bool ->
  bytecode:int64 list ->
  func:Ir.func ->
  decoy_count:int ->
  total_handlers:int ->
  mba_nodes:int ->
  unit ->
  metrics_report

val report_to_string : metrics_report -> string

