open Random_visa_ports
open Protect_ports
open Native_vm

module Threaded_vm_packager : Vm_packager = struct
  let engine_kind = Threaded

  let package ~rng ~(config : Protection_config.t) ?constants (func : Vm_ir.Ir.func) : package_result =
    let pkg = Native_vm.Vm_emitter.compile_and_package ~rng ~config ?constants func in
    {
      cpp_runtime_source = pkg.cpp_runtime_source;
      runner_source = pkg.runner_source;
      bytecode = pkg.bytecode;
      metrics = pkg.metrics;
      header_name = "threaded_vm.hpp";
    }
end

module Jit_vm_packager : Vm_packager = struct
  let engine_kind = Jit

  let package ~rng ~(config : Protection_config.t) ?constants:_ (func : Vm_ir.Ir.func) : package_result =
    let jit_pkg =
      Rd_jit_vm.Rd_jit_emitter.compile_and_package
        ~rng
        ?config:(Some config)
        ~enable_cff:config.cff.enabled
        ~enable_mba:config.mba.enabled
        ~mba_depth:config.mba.depth
        func
    in
    {
      cpp_runtime_source = jit_pkg.cpp_runtime_source;
      runner_source = jit_pkg.runner_source;
      bytecode = jit_pkg.bytecode;
      metrics = jit_pkg.metrics;
      header_name = "jit_vm_runtime.hpp";
    }
end

module Multi_vm_packager : Vm_packager = struct
  let engine_kind = MultiVm

  let package ~rng ~(config : Protection_config.t) ?constants:_ (func : Vm_ir.Ir.func) : package_result =
    let mv_pkg =
      Multi_vm.Multi_vm_emitter.compile_and_package
        ~rng
        ~enable_cff:config.cff.enabled
        ~enable_mba:config.mba.enabled
        ~mba_depth:config.mba.depth
        ~config
        func
    in
    {
      cpp_runtime_source = mv_pkg.cpp_runtime_source;
      runner_source = mv_pkg.runner_source;
      bytecode = mv_pkg.bytecode;
      metrics = mv_pkg.metrics;
      header_name = "multi_vm_runtime.hpp";
    }
end
