open Vm_ir

type vm_package = {
  bytecode : int64 list;
  bytecodes : (string * int64 list) list;
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
  ?constants:(string * string) list ->
  Ir.func ->
  vm_package

val compile_and_package_multi :
  rng:Random.State.t ->
  ?runtime_profile:Random_visa_domain.Vm_runtime_profile.t ->
  ?config:Protection_config.t ->
  ?enable_cff:bool ->
  ?enable_mba:bool ->
  ?enable_junk:bool ->
  ?mba_depth:int ->
  ?constants:(string * string) list ->
  (string * Ir.func) list ->
  vm_package

val poly_multiplier_of_seed : int32 -> int64
val poly_init_of_seed : int32 -> int64
