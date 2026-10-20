open Random_visa_ports

let write_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let asm_source = {|
func_demo_arm64:
    // 1. MOVN: Move with NOT
    movn x1, #0
    movn w2, #0x1f

    // 2. FCVT with Rounding Modes (Away, Floor, Nearest-Even, Ceil, Unsigned)
    fmov d0, #1.5
    fcvtas x3, d0
    fcvtms x4, d0
    fcvtns x5, d0
    fcvtps x6, d0
    fmov d1, #-1.5
    fcvtau x7, d1

    // 3. FCCMP: Floating Conditional Compare with NZCV Fallback
    mov x8, #1
    cmp x8, #1
    fmov d2, #1.0
    fmov d3, #2.0
    fccmp d2, d3, #4, eq
    cset w9, lt
    cmp x8, #2
    fccmp d2, d3, #4, eq
    cset w10, eq

    // 4. NEON Lane Transfers: INS, UMOV, SMOV
    mov w8, #100
    ins v0.s[0], w8
    ins v1.s[2], v0.s[0]
    umov w11, v1.s[2]
    mov w8, #0xFB
    ins v2.b[3], w8
    smov x12, v2.b[3]

    // 5. Saturating NEON Arithmetic: SQADD, SQSUB, SQRDMULH
    mov x8, #0x7FFFFFFF
    dup v3.2s, w8
    mov x13, #100
    dup v4.2s, w13
    sqadd v5.2s, v3.2s, v4.2s
    mov x8, #0x80000000
    dup v6.2s, w8
    sqsub v7.2s, v6.2s, v4.2s
    mov x8, #0x4000
    dup v8.4h, w8
    sqrdmulh v9.4h, v8.4h, v8.4h

    // 6. JavaScript ToInt32 Conversion: FJCVTZS
    fmov d10, #42.0
    fjcvtzs w13, d10
    cset w8, eq

    mov x0, #42
    ret
|}

let cpp_runner_body = {|
    std::printf("\n");
    std::printf("======================================================================\n");
    std::printf("   ASGARD-5877 ARM64 VM PROTECTOR: LIVE INSTRUCTION AUDIT            \n");
    std::printf("======================================================================\n\n");

    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    std::printf("[*] Entering ASGARD Hardened VM Engine...\n");
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count);
    if (!ok) {
        std::printf("[-] VM EXECUTION FAILED! (halted / trap triggered)\n");
        return 1;
    }
    std::printf("[+] VM EXECUTION SUCCESS! Total virtual ops dispatched: %zu\n\n", ctx.executed_instructions);

    bool all_ok = true;

    // STEP 1: MOVN
    uint64_t m1 = ctx.get_reg(vanguard_threaded_vm::REG_RCX); // x1
    uint32_t m2 = (uint32_t)ctx.get_reg(vanguard_threaded_vm::REG_RDX); // x2
    std::printf("[STEP 1] MOVN (Move with NOT):\n");
    std::printf("         x1 (movn x1, #0)       -> 0x%016llX (expected: 0xFFFFFFFFFFFFFFFF)\n", (unsigned long long)m1);
    std::printf("         x2 (movn w2, #0x1f)    -> 0x%08X         (expected: 0xFFFFFFE0)\n", m2);
    bool s1 = (m1 == 0xFFFFFFFFFFFFFFFFULL && m2 == 0xFFFFFFE0U);
    std::printf("         Status: %s\n\n", s1 ? "[PASS] Verified via ASGARD VM" : "[FAIL] Mismatch");
    all_ok &= s1;

    // STEP 2: FCVT with Rounding Modes
    int64_t as_val = (int64_t)ctx.get_reg(vanguard_threaded_vm::REG_RBX); // x3
    int64_t ms_val = (int64_t)ctx.get_reg(vanguard_threaded_vm::REG_RSI); // x4
    int64_t ns_val = (int64_t)ctx.get_reg(vanguard_threaded_vm::REG_RDI); // x5
    int64_t ps_val = (int64_t)ctx.get_reg(vanguard_threaded_vm::REG_R8);  // x6
    uint64_t au_val = ctx.get_reg(vanguard_threaded_vm::REG_R9);          // x7
    std::printf("[STEP 2] FCVT Float-to-Int with Rounding Modes (input = 1.5, -1.5):\n");
    std::printf("         x3 (fcvtas Away)       -> %lld (expected: 2)\n", (long long)as_val);
    std::printf("         x4 (fcvtms Floor)      -> %lld (expected: 1)\n", (long long)ms_val);
    std::printf("         x5 (fcvtns Nearest-Ev) -> %lld (expected: 2)\n", (long long)ns_val);
    std::printf("         x6 (fcvtps Ceil)       -> %lld (expected: 2)\n", (long long)ps_val);
    std::printf("         x7 (fcvtau Unsigned)   -> %llu (expected: 0, saturates on negative)\n", (unsigned long long)au_val);
    bool s2 = (as_val == 2 && ms_val == 1 && ns_val == 2 && ps_val == 2 && au_val == 0);
    std::printf("         Status: %s\n\n", s2 ? "[PASS] Verified via ASGARD VM" : "[FAIL] Mismatch");
    all_ok &= s2;

    // STEP 3: FCCMP
    uint32_t cond_lt = (uint32_t)ctx.get_reg(vanguard_threaded_vm::REG_R11); // x9
    uint32_t cond_eq = (uint32_t)ctx.get_reg(vanguard_threaded_vm::REG_R12); // x10
    std::printf("[STEP 3] FCCMP (Floating Conditional Compare with NZCV Fallback):\n");
    std::printf("         True condition path    -> LT flag evaluated: %u (expected: 1, 1.0 < 2.0)\n", cond_lt);
    std::printf("         False fallback path    -> EQ flag evaluated: %u (expected: 1, nzcv #4 fallback)\n", cond_eq);
    bool s3 = (cond_lt == 1 && cond_eq == 1);
    std::printf("         Status: %s\n\n", s3 ? "[PASS] Verified via ASGARD VM" : "[FAIL] Mismatch");
    all_ok &= s3;

    // STEP 4: INS, UMOV, SMOV
    uint32_t u_ext = (uint32_t)ctx.get_reg(vanguard_threaded_vm::REG_R13);  // x11
    int64_t s_ext = (int64_t)ctx.get_reg(vanguard_threaded_vm::REG_R14);   // x12
    std::printf("[STEP 4] NEON Scalar <-> Vector Lane Transfer (INS / UMOV / SMOV):\n");
    std::printf("         ins + umov (100)       -> %u   (expected: 100)\n", u_ext);
    std::printf("         ins + smov (-5 byte)   -> %lld    (expected: -5, sign-extended)\n", (long long)s_ext);
    bool s4 = (u_ext == 100 && s_ext == -5);
    std::printf("         Status: %s\n\n", s4 ? "[PASS] Verified via ASGARD VM" : "[FAIL] Mismatch");
    all_ok &= s4;

    // STEP 5: Saturating NEON
    uint32_t sat_add = (uint32_t)(ctx.vregs[5][0] & 0xFFFFFFFFULL);
    uint32_t sat_sub = (uint32_t)(ctx.vregs[7][0] & 0xFFFFFFFFULL);
    uint32_t sat_mul = (uint32_t)(ctx.vregs[9][0] & 0xFFFFULL);
    std::printf("[STEP 5] NEON Saturating Arithmetic (DSP / Audio / Video):\n");
    std::printf("         sqadd (0x7FFFFFFF+100) -> 0x%08X (expected: 0x7FFFFFFF, max int32)\n", sat_add);
    std::printf("         sqsub (0x80000000-100) -> 0x%08X (expected: 0x80000000, min int32)\n", sat_sub);
    std::printf("         sqrdmulh (0.5 * 0.5)   -> 0x%04X     (expected: 0x2000 = 0.25 in Q15)\n", sat_mul);
    bool s5 = (sat_add == 0x7FFFFFFFU && sat_sub == 0x80000000U && sat_mul == 0x2000U);
    std::printf("         Status: %s\n\n", s5 ? "[PASS] Verified via ASGARD VM" : "[FAIL] Mismatch");
    all_ok &= s5;

    // STEP 6: FJCVTZS
    uint32_t js_val = (uint32_t)ctx.get_reg(vanguard_threaded_vm::REG_R15); // x13
    uint32_t js_zf = (uint32_t)ctx.get_reg(vanguard_threaded_vm::REG_R10);  // x8
    std::printf("[STEP 6] FJCVTZS (JavaScript ToInt32 Conversion with Exactness Flag):\n");
    std::printf("         fjcvtzs 42.0           -> int32: %u, exact flag (ZF): %u (expected: 42, 1)\n", js_val, js_zf);
    bool s6 = (js_val == 42 && js_zf == 1);
    std::printf("         Status: %s\n\n", s6 ? "[PASS] Verified via ASGARD VM" : "[FAIL] Mismatch");
    all_ok &= s6;

    std::printf("======================================================================\n");
    if (all_ok) {
        std::printf("  [+] SUCCESS: ALL 6 INSTRUCTION FAMILIES VIRTUALIZED AND EXECUTED! \n");
        std::printf("      The new instructions successfully passed ASGARD VM Hardening! \n");
    } else {
        std::printf("  [-] FAILURE: Verification mismatch detected in ASGARD VM runtime! \n");
    }
    std::printf("======================================================================\n\n");

    return all_ok ? 0 : 1;
}
|}

let () =
  let module Arm64_adapter = Protect_adapters.Arm64_lifter_adapter in
  Printf.printf "[1/4] Lifting ARM64 assembly with new instructions into ASGARD Micro-IR...\n%!";
  match Arm64_adapter.lift_source asm_source with
  | Error err ->
      Printf.eprintf "[-] Lifter failed: %s\n%!" err;
      exit 1
  | Ok (func, _) ->
      Printf.printf "[2/4] Successfully lifted! Applying ASGARD Protection Pipeline...\n%!";
      let unwrapped : Vm_ir.Ir.func = Protect_ports.unwrap_ir func in
      let rng = Random.State.make [| 20261105 |] in
      let pkg = Native_vm.Vm_emitter.compile_and_package ~rng unwrapped in
      let tmp_dir = Filename.concat (Filename.get_temp_dir_name ()) "asgard_arm64_demo" in
      (try Unix.mkdir tmp_dir 0o755 with _ -> ());
      let vm_hdr_path = Filename.concat tmp_dir "demo_vm.hpp" in
      let runner_cpp_path = Filename.concat tmp_dir "runner.cpp" in
      let runner_bin_path = Filename.concat tmp_dir "runner" in
      write_file vm_hdr_path pkg.cpp_runtime_source;
      let bc_lines = String.concat "\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) pkg.bytecode) in
      let runner_cpp_source = Printf.sprintf {|
#include "demo_vm.hpp"
#include <cstdio>
#include <cstdint>

static uint64_t embedded_bytecode[] = {
%s
};

int main() {
    size_t count = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
%s
|} bc_lines cpp_runner_body in
      write_file runner_cpp_path runner_cpp_source;
      Printf.printf "[3/4] Compiling hardened Direct-Threaded C++ VM runtime with clang++...\n%!";
      let cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_cpp_path runner_bin_path in
      let st = Sys.command cmd in
      if st <> 0 then begin
        Printf.eprintf "[-] Clang++ compilation failed with code %d\n%!" st;
        exit 1
      end;
      Printf.printf "[4/4] Launching ASGARD Virtual Machine Execution...\n%!";
      let exit_code = Sys.command runner_bin_path in
      exit exit_code
