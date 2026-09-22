open Random_visa_ports
open Protect_ports
open Native_vm

let convert_metrics (m : Native_vm.Metrics.metrics_report) : Protect_ports.metrics_report =
  {
    cyclomatic_complexity = Native_vm.Metrics.cyclomatic_complexity m;
    shannon_entropy = Native_vm.Metrics.shannon_entropy m;
    uniform_entropy = Native_vm.Metrics.shannon_entropy m /. 8.0;
    drs_score = Native_vm.Metrics.devirtualization_resistance_score m;
    formatted_summary = Native_vm.Metrics.report_to_string m;
  }

module Threaded_vm_packager : Vm_packager = struct
  let engine_kind = Threaded

  let package ~rng ~config ?constants (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let pkg = Native_vm.Vm_emitter.compile_and_package ~rng ~config:native_cfg ?constants ir in
    {
      cpp_runtime_source = pkg.cpp_runtime_source;
      runner_source = pkg.runner_source;
      bytecode = pkg.bytecode;
      metrics = convert_metrics pkg.metrics;
      header_name = "threaded_vm.hpp";
    }
end

module Jit_vm_packager : Vm_packager = struct
  let engine_kind = Jit

  let package ~rng ~config ?constants:_ (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let jit_pkg =
      Rd_jit_vm.Rd_jit_emitter.compile_and_package
        ~rng
        ?config:(Some native_cfg)
        ~enable_cff:native_cfg.cff.enabled
        ~enable_mba:native_cfg.mba.enabled
        ~mba_depth:native_cfg.mba.depth
        ir
    in
    {
      cpp_runtime_source = jit_pkg.cpp_runtime_source;
      runner_source = jit_pkg.runner_source;
      bytecode = jit_pkg.bytecode;
      metrics = convert_metrics jit_pkg.metrics;
      header_name = "jit_vm_runtime.hpp";
    }
end

module Multi_vm_packager : Vm_packager = struct
  let engine_kind = MultiVm

  let package ~rng ~config ?constants:_ (func : ir_func) : package_result =
    let ir : Vm_ir.Ir.func = unwrap_ir func in
    let native_cfg : Protection_config.t = unwrap_config config in
    let mv_pkg =
      Multi_vm.Multi_vm_emitter.compile_and_package
        ~rng
        ~enable_cff:native_cfg.cff.enabled
        ~enable_mba:native_cfg.mba.enabled
        ~mba_depth:native_cfg.mba.depth
        ~config:native_cfg
        ir
    in
    {
      cpp_runtime_source = mv_pkg.cpp_runtime_source;
      runner_source = mv_pkg.runner_source;
      bytecode = mv_pkg.bytecode;
      metrics = convert_metrics mv_pkg.metrics;
      header_name = "multi_vm_runtime.hpp";
    }
end
