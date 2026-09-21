open Vm_ir

type multi_vm_package = {
  bridge : Bridge.affine_bridge;
  partition : Partitioner.partition_report;
  cpp_runtime_source : string;
  runner_source : string;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}

let inject_bridge_transitions (bridge : Bridge.affine_bridge) (partition : Partitioner.partition_report) (f : Ir.func) : Ir.func * int =
  let digest = bridge.initial_digest in
  if partition.inter_vm_transitions = 0 then
    (* Homogeneous engine or single block: inject a zero-bridge roundtrip (Math -> Flow -> Math) *)
    let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
    Hashtbl.iter (fun id (b : Ir.basic_block) ->
      let instrs =
        match List.rev b.instrs with
        | (Ir.Ret as ret) :: rest ->
            List.rev (ret :: Ir.Bridge_to_math digest :: Ir.Bridge_to_flow digest :: rest)
        | (Ir.Vm_exit as ex) :: rest ->
            List.rev (ex :: Ir.Bridge_to_math digest :: Ir.Bridge_to_flow digest :: rest)
        | other ->
            other @ [ Ir.Bridge_to_flow digest; Ir.Bridge_to_math digest ]
      in
      Hashtbl.replace new_blocks id { b with instrs }
    ) f.cfg.blocks;
    ({ f with cfg = { f.cfg with blocks = new_blocks } }, 2)
  else
    (* Multi-block with cross-engine transitions *)
    let block_engine = Hashtbl.create 16 in
    List.iter (fun (pb : Partitioner.partitioned_block) ->
      Hashtbl.replace block_engine pb.block.id pb.engine
    ) partition.blocks;

    let trans_count = ref 0 in
    let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
    Hashtbl.iter (fun id (b : Ir.basic_block) ->
      let cur_eng = Hashtbl.find_opt block_engine id in
      let is_math = cur_eng = Some Partitioner.Engine_Math in
      let rev_acc = ref [] in
      List.iter (fun (instr : Ir.instr) ->
        match instr with
        | Ir.Jmp (BlockId target_id) ->
            let target_eng = Hashtbl.find_opt block_engine target_id in
            if target_eng <> cur_eng && cur_eng <> None && target_eng <> None then begin
              incr trans_count;
              if is_math then
                rev_acc := Ir.Bridge_to_flow digest :: !rev_acc
              else
                rev_acc := Ir.Bridge_to_math digest :: !rev_acc
            end;
            rev_acc := instr :: !rev_acc
        | Ir.Jcc { cond = _; target_true = BlockId tid; target_false = BlockId fid } ->
            let t_eng = Hashtbl.find_opt block_engine tid in
            let f_eng = Hashtbl.find_opt block_engine fid in
            if (t_eng <> cur_eng || f_eng <> cur_eng) && cur_eng <> None then begin
              incr trans_count;
              if is_math then
                rev_acc := Ir.Bridge_to_flow digest :: !rev_acc
              else
                rev_acc := Ir.Bridge_to_math digest :: !rev_acc
            end;
            rev_acc := instr :: !rev_acc
        | _ -> rev_acc := instr :: !rev_acc
      ) b.instrs;
      Hashtbl.replace new_blocks id { b with instrs = List.rev !rev_acc }
    ) f.cfg.blocks;
    ({ f with cfg = { f.cfg with blocks = new_blocks } }, !trans_count)

let compile_and_package ~rng ?(enable_cff = true) ?(enable_mba = true) ?(mba_depth = 2) (f : Ir.func) : multi_vm_package =
  let bridge = Bridge.generate_bridge rng in
  let partition = Partitioner.partition_function f in
  let (bridged_func, actual_transitions) = inject_bridge_transitions bridge partition f in
  let updated_partition = { partition with inter_vm_transitions = actual_transitions } in

  let base_pkg =
    Native_vm.Vm_emitter.compile_and_package
      ~rng
      ~enable_cff
      ~enable_mba
      ~mba_depth
      bridged_func
  in

  let bridge_cpp = Bridge.emit_cpp_bridge_code bridge in

  let multi_vm_hdr = Printf.sprintf {|#pragma once
#define ASGARD_MULTI_VM_ENABLED 1
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

  let bc_lines = String.concat ",\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL" w) base_pkg.bytecode) in
  let runner_cpp = Printf.sprintf {|#include "multi_vm_runtime.hpp"
#include <iostream>
#include <vector>
#include <chrono>

extern "C" __attribute__((weak)) const uint64_t embedded_bytecode[] = {
%s
};
extern "C" __attribute__((weak)) const size_t embedded_bytecode_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);

int main(int argc, char** argv) {
    std::cout << "[ASGARD-MULTI-VM] Initializing In-Place Heterogeneous Dual-VM Runtime...\n";
    std::cout << "  Engine 1: Math-VM (Register/RNS Oriented, " << %d << " blocks)\n";
    std::cout << "  Engine 2: Flow-VM (Stack/CFF Markov Oriented, " << %d << " blocks)\n";
    std::cout << "  Zero-Bridge Transitions: " << %d << " affine morphing junctions\n";

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
|} bc_lines updated_partition.math_blocks updated_partition.flow_blocks updated_partition.inter_vm_transitions in

  {
    bridge;
    partition = updated_partition;
    cpp_runtime_source = multi_vm_hdr;
    runner_source = runner_cpp;
    bytecode = base_pkg.bytecode;
    metrics = base_pkg.metrics;
  }
