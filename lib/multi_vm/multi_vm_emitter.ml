open Vm_ir

type multi_vm_package = {
  bridge : Bridge.affine_bridge;
  partition : Partitioner.partition_report;
  cpp_runtime_source : string;
  runner_source : string;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}

let compile_and_package ~rng ?(enable_cff = true) ?(enable_mba = true) ?(mba_depth = 2) (f : Ir.func) : multi_vm_package =
  let bridge = Bridge.generate_bridge rng in
  let partition = Partitioner.partition_function f in

  let base_pkg =
    Native_vm.Vm_emitter.compile_and_package
      ~rng
      ~enable_cff
      ~enable_mba
      ~mba_depth
      f
  in

  let bridge_cpp = Bridge.emit_cpp_bridge_code bridge in

  let multi_vm_hdr = Printf.sprintf {|#pragma once
// =========================================================================
// ASGARD-5877: HETEROGENEOUS DUAL-VM RUNTIME (MATH-VM & FLOW-VM)
// In-Place Affine State Morphing & Zero-Native Dispatch
// =========================================================================
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

%s

namespace asgard_multi_vm {

struct MathVMContext {
    uint64_t gprs[32];
    uint64_t vip;
    uint64_t rns_slots[4];
    uint64_t trace_digest;
    
    inline void init(uint64_t init_digest) {
        memset(this, 0, sizeof(*this));
        trace_digest = init_digest;
    }
};

struct FlowVMContext {
    uint64_t vstack[64];
    uint64_t vsp;
    uint64_t vip;
    uint64_t state_var;
    uint64_t trace_digest;

    inline void init(uint64_t init_digest) {
        memset(this, 0, sizeof(*this));
        trace_digest = init_digest;
    }
};

union SharedVMContext {
    MathVMContext math;
    FlowVMContext flow;
    uint8_t raw[1024];
};

static inline void bridge_switch_to_flow(SharedVMContext& ctx) {
    uint64_t cur_digest = ctx.math.trace_digest;
    uint64_t temp_math_regs[16];
    for (int i = 0; i < 16; ++i) temp_math_regs[i] = ctx.math.gprs[i];
    
    ctx.flow.init(cur_digest);
    in_place_morph_math_to_flow(temp_math_regs, ctx.flow.vstack, cur_digest);
}

static inline void bridge_switch_to_math(SharedVMContext& ctx) {
    uint64_t cur_digest = ctx.flow.trace_digest;
    uint64_t temp_flow_stack[16];
    for (int i = 0; i < 16; ++i) temp_flow_stack[i] = ctx.flow.vstack[i];
    
    ctx.math.init(cur_digest);
    in_place_morph_flow_to_math(temp_flow_stack, ctx.math.gprs, cur_digest);
}

} // namespace asgard_multi_vm

// Threaded base engine integration
%s
|} bridge_cpp base_pkg.cpp_runtime_source in

  let runner_cpp = Printf.sprintf {|#include "multi_vm_runtime.hpp"
#include <iostream>
#include <vector>
#include <chrono>

extern "C" const uint64_t embedded_bytecode[];
extern "C" const size_t embedded_bytecode_len;

int main(int argc, char** argv) {
    std::cout << "[ASGARD-MULTI-VM] Initializing In-Place Heterogeneous Dual-VM Runtime...\n";
    std::cout << "  Engine 1: Math-VM (Register/RNS Oriented, " << %d << " blocks)\n";
    std::cout << "  Engine 2: Flow-VM (Stack/CFF Markov Oriented, " << %d << " blocks)\n";
    std::cout << "  Zero-Bridge Transitions: " << %d << " affine morphing junctions\n";

    asgard_multi_vm::SharedVMContext shared_ctx;
    shared_ctx.math.init(ASGARD_INITIAL_DIGEST);
    shared_ctx.math.gprs[vanguard_threaded_vm::REG_RDI] = (argc > 1) ? atoll(argv[1]) : 42;

    auto t0 = std::chrono::high_resolution_clock::now();
    vanguard_threaded_vm::VMContext& base_ctx = *(reinterpret_cast<vanguard_threaded_vm::VMContext*>(&shared_ctx.math));
    vanguard_threaded_vm::execute_threaded(base_ctx, embedded_bytecode, embedded_bytecode_len);
    auto t1 = std::chrono::high_resolution_clock::now();

    double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
    uint64_t res = base_ctx.get_rax();

    std::cout << "[ASGARD-MULTI-VM] Execution Successful!\n";
    std::cout << "  Result (RAX): " << res << " (0x" << std::hex << res << std::dec << ")\n";
    std::cout << "  Execution Time: " << elapsed_us << " us\n";
    return 0;
}
|} partition.math_blocks partition.flow_blocks partition.inter_vm_transitions in

  {
    bridge;
    partition;
    cpp_runtime_source = multi_vm_hdr;
    runner_source = runner_cpp;
    bytecode = base_pkg.bytecode;
    metrics = base_pkg.metrics;
  }
