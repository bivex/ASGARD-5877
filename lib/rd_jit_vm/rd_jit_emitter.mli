open Vm_ir

type rd_jit_package = {
  cpp_runtime_source : string;
  runner_source : string;
  rns_moduli : int64 * int64 * int64 * int64;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}

val emit_rd_jit_runtime_header : external_symbols:string list -> string

val compile_and_package :
  rng:Random.State.t ->
  ?config:Native_vm.Protection_config.t ->
  ?enable_cff:bool ->
  ?enable_mba:bool ->
  ?mba_depth:int ->
  Ir.func ->
  rd_jit_package
