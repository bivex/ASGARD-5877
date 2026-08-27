open Vm_ir

type multi_vm_package = {
  bridge : Bridge.affine_bridge;
  partition : Partitioner.partition_report;
  cpp_runtime_source : string;
  runner_source : string;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}

val compile_and_package :
  rng:Random.State.t ->
  ?enable_cff:bool ->
  ?enable_mba:bool ->
  ?mba_depth:int ->
  Ir.func ->
  multi_vm_package
