type rd_jit_package = {
  cpp_runtime_source : string;
  runner_source : string;
  rns_moduli : int64 * int64 * int64 * int64;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}
