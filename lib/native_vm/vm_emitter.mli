open Vm_ir

type vm_package = {
  bytecode : int64 list;
  cpp_runtime_source : string;
  runner_source : string;
  metrics : Metrics.metrics_report;
}

val compile_and_package :
  rng:Random.State.t ->
  ?runtime_profile:Random_visa_domain.Vm_runtime_profile.t ->
  ?config:Protection_config.t ->
  ?enable_cff:bool ->
  ?enable_mba:bool ->
  ?enable_junk:bool ->
  ?mba_depth:int ->
  Ir.func ->
  vm_package



