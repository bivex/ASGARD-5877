open Vm_ir

type metrics_report = {
  shannon_entropy : float;          (** Bits per byte (0.0 to 8.0) *)
  cyclomatic_complexity : int;       (** M = E - V + 2P *)
  flattening_depth : int;            (** Number of dispatcher stages *)
  decoy_density : float;             (** Percentage of decoy trap handlers *)
  mba_node_count : int;              (** Total AST nodes in arithmetic operations *)
  devirtualization_resistance_score : float; (** Composite score 0.0 - 100.0 *)
}

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
