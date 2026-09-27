open Jingoo

let env = { Jg_types.std_env with autoescape = false }

let render template models =
  Jg_template.from_string ~env ~models template

let multi_vm_header_template = {|#pragma once
#define ASGARD_MULTI_VM_ENABLED 1
// =========================================================================
// ASGARD-5877: HETEROGENEOUS DUAL-VM RUNTIME (MATH-VM & FLOW-VM)
// In-Place Affine State Morphing & Zero-Native Dispatch
// =========================================================================
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

{{ bridge_cpp }}

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
{{ base_runtime_source }}
|}

let runner_template = {|#include "multi_vm_runtime.hpp"
#include <iostream>
#include <vector>
#include <chrono>

extern "C" __attribute__((weak)) const uint64_t embedded_bytecode[] = {
{%- for w in bytecode_words %}
{{ w }},
{%- endfor %}
};
extern "C" __attribute__((weak)) const size_t embedded_bytecode_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);

int main(int argc, char** argv) {
    std::cout << "[ASGARD-MULTI-VM] Initializing In-Place Heterogeneous Dual-VM Runtime...\n";
    std::cout << "  Engine 1: Math-VM (Register/RNS Oriented, " << {{ math_blocks }} << " blocks)\n";
    std::cout << "  Engine 2: Flow-VM (Stack/CFF Markov Oriented, " << {{ flow_blocks }} << " blocks)\n";
    std::cout << "  Zero-Bridge Transitions: " << {{ inter_vm_transitions }} << " affine morphing junctions\n";

    asgard_multi_vm::SharedVMContext shared_ctx = {};
    shared_ctx.math.init(ASGARD_INITIAL_DIGEST);

    vanguard_threaded_vm::VMContext base_ctx = {};
    base_ctx.init();
    base_ctx.set_rdi((argc > 1) ? (uint64_t)atoll(argv[1]) : 42ULL);

    auto t0 = std::chrono::high_resolution_clock::now();
    vanguard_threaded_vm::execute_threaded(base_ctx, embedded_bytecode, embedded_bytecode_len);
    auto t1 = std::chrono::high_resolution_clock::now();

    double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
    uint64_t res = base_ctx.get_rax();

    std::cout << "[ASGARD-MULTI-VM] Execution Successful!\n";
    std::cout << "  Result (RAX): " << res << " (0x" << std::hex << res << std::dec << ")\n";
    std::cout << "  Execution Time: " << elapsed_us << " us\n";
    return 0;
}
|}
