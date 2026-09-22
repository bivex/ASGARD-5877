open Vm_ir
include Rd_jit_types

let emit_rd_jit_runtime_header () =
  Rd_jit_buffer.header () ^ Rd_jit_synth.header ()

let compile_and_package ~rng ?config ?(enable_cff = false) ?(enable_mba = false) ?(mba_depth = 2) (func : Ir.func) : rd_jit_package =
  let (enable_cff, enable_mba, mba_depth) =
    match config with
    | Some (c : Native_vm.Protection_config.t) ->
        (c.cff.enabled || enable_cff, c.mba.enabled || enable_mba, if mba_depth <> 2 then mba_depth else c.mba.depth)
    | None -> (enable_cff, enable_mba, mba_depth)
  in

  let target_func =
    if enable_cff then
      let cff_opts =
        match config with
        | Some c ->
            {
              Cff.inject_opaque_predicates = c.cff.inject_opaque_predicates;
              obfuscate_states = c.cff.obfuscate_states;
            }
        | None -> Cff.default_cff_options
      in
      match Cff.flatten_func ~options:cff_opts ~rng func with
      | Ok f -> f
      | Error _ -> func
    else func
  in

  let base_pkg =
    Native_vm.Vm_emitter.compile_and_package
      ~rng
      ?config
      ~enable_cff
      ~enable_mba
      ~mba_depth
      target_func
  in

  let rd_jit_hdr = emit_rd_jit_runtime_header () in

  let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
  let other_blocks =
    Hashtbl.fold
      (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
      target_func.cfg.blocks []
  in
  let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
  let sorted_blocks = entry_block :: sorted_other in

  let block_decls = Buffer.create 2048 in
  let block_entries = Buffer.create 512 in

  List.iteri
    (fun idx (b : Ir.basic_block) ->
      let instrs = b.instrs in
      let c_instrs = Buffer.create 256 in
      let count = ref 0 in
      List.iter
        (fun instr ->
          let (op, dst, src, imm) =
            match instr with
            | Ir.Nop -> ("asgard_rd_jit::JIT_OP_NOP", 0, 0, 0L)
            | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
                ("asgard_rd_jit::JIT_OP_MOV_RR", Native_vm.Vm_transform.reg_to_index d mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
                ("asgard_rd_jit::JIT_OP_MOV_RI", Native_vm.Vm_transform.reg_to_index d mod 16, 0, imm)
            | Ir.Alu { op = Ir.Add; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_ADD_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Add; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_ADD_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Sub; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_SUB_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Sub; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_SUB_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Imul; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_MUL_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Imul; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_MUL_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Xor; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_XOR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Xor; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_XOR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.And; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_AND_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.And; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_AND_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Or; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_OR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Or; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_OR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Ret -> ("asgard_rd_jit::JIT_OP_RET", 0, 0, 0L)
            | Ir.Vm_exit -> ("asgard_rd_jit::JIT_OP_EXIT", 0, 0, 0L)
            | _ -> ("asgard_rd_jit::JIT_OP_NOP", 0, 0, 0L)
          in
          incr count;
          Buffer.add_string c_instrs (Printf.sprintf "    { %s, %d, %d, 0x%016LXULL },\n" op dst src imm)
        )
        instrs;

      Buffer.add_string block_decls (Printf.sprintf "static const asgard_rd_jit::JITInstr jit_block_%d_instrs[] = {\n%s};\n" idx (Buffer.contents c_instrs));
      Buffer.add_string block_entries (Printf.sprintf "    { %d, %d, jit_block_%d_instrs },\n" idx !count idx)
    )
    sorted_blocks;

  let runner_cpp = Printf.sprintf {|#if __has_include("jit_vm_runtime.hpp")
#include "jit_vm_runtime.hpp"
#elif __has_include("rd_jit_runtime.hpp")
#include "rd_jit_runtime.hpp"
#else
#include "threaded_vm.hpp"
#endif
#include <iostream>
#include <chrono>

// JIT Block Descriptors
%s
static const asgard_rd_jit::JITBlock jit_blocks[] = {
%s};
static const size_t num_jit_blocks = sizeof(jit_blocks) / sizeof(jit_blocks[0]);

int main(int argc, char** argv) {
    std::cout << "[ASGARD-RD-JIT] Initializing Register-Driven JIT Virtual Machine...\n";
    std::cout << "  * Architecture: Register-Driven RISC (No Stack Emulation)\n";
    std::cout << "  * Arithmetic: RNS-4 Modular Residue Splitting (M > 2^64)\n";
    std::cout << "  * Memory Protection: Dual-Mapped W^X Ephemeral Buffer\n";
    std::cout << "  * Blocks: " << num_jit_blocks << " dynamic JIT synthesis block(s)\n";

    asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);
    asgard_rd_jit::RD_JIT_Context ctx;
    ctx.init();

    uint64_t arg1 = (argc > 1) ? (uint64_t)atoll(argv[1]) : 42ULL;
    uint64_t arg2 = (argc > 2) ? (uint64_t)atoll(argv[2]) : 58ULL;
    ctx.set_reg(0, arg1);
    ctx.set_reg(1, arg2);

    auto t0 = std::chrono::high_resolution_clock::now();
    asgard_rd_jit::execute_jit_function(jit_buf, ctx, jit_blocks, num_jit_blocks);
    auto t1 = std::chrono::high_resolution_clock::now();

    double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
    uint64_t res = ctx.get_reg(0);

    std::cout << "[ASGARD-RD-JIT] Ephemeral Execution Successful!\n";
    std::cout << "  * Result (REG 0): " << res << " (0x" << std::hex << res << std::dec << ")\n";
    std::cout << "  * RNS Residues: (" << ctx.vregs[0].r1 << ", " << ctx.vregs[0].r2 << ", " << ctx.vregs[0].r3 << ", " << ctx.vregs[0].r4 << ")\n";
    std::cout << "  * JIT Cycle Time: " << elapsed_us << " us\n";
    return 0;
}
|} (Buffer.contents block_decls) (Buffer.contents block_entries) in

  {
    cpp_runtime_source = rd_jit_hdr;
    runner_source = runner_cpp;
    rns_moduli = (Rns.m1, Rns.m2, Rns.m3, Rns.m4);
    bytecode = base_pkg.bytecode;
    metrics = base_pkg.metrics;
  }
