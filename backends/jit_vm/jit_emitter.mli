open Vm_ir

type jit_package = {
  cpp_runtime_source : string;
  runner_source : string;
  rns_moduli : int64 * int64 * int64 * int64;
  bytecode : int64 list;
  metrics : Protection_metrics.Metrics.metrics_report;
}

val emit_rd_jit_runtime_decls : external_symbols:string list -> Cpp_codegen.Cpp_ast.top_decl list
val emit_rd_jit_runtime_header : external_symbols:string list -> string
val emit_rd_jit_main_def : unit -> Cpp_codegen.Cpp_ast.top_decl

val compile_and_package :
  rng:Random.State.t ->
  ?config:Protection_config.t ->
  ?enable_cff:bool ->
  ?enable_mba:bool ->
  ?mba_depth:int ->
  ?external_symbols:string list ->
  Ir.func ->
  jit_package

val compile_and_package_chunked :
  rng:Random.State.t ->
  ?config:Protection_config.t ->
  ?enable_cff:bool ->
  ?enable_mba:bool ->
  ?mba_depth:int ->
  ?external_symbols:string list ->
  chunks:(string * int * int * int64) list list ->
  Ir.func ->
  jit_package
