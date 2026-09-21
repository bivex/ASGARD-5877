open Vm_ir

type metrics_report

val shannon_entropy : metrics_report -> float
val cyclomatic_complexity : metrics_report -> int
val flattening_depth : metrics_report -> int
val decoy_density : metrics_report -> float
val mba_node_count : metrics_report -> int
val devirtualization_resistance_score : metrics_report -> float

val calculate_shannon_entropy : int64 list -> float
val calculate_cfg_complexity : Ir.func -> int
val calculate_metrics :
  bytecode:int64 list ->
  func:Ir.func ->
  decoy_count:int ->
  total_handlers:int ->
  mba_nodes:int ->
  metrics_report

val report_to_string : metrics_report -> string
