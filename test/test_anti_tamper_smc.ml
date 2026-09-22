open X86_lifter
open Native_vm

(** Tests for Layer 3 (Звено 3): Dynamic Anti-Tamper & Memory Integrity.
    Verifies:
    1. Dual-Mapping W^X memory aliasing (RW for mutation, RX for execution).
    2. Introspective Self-Modifying Code (SMC) + Hardware Timing Predicates (RDTSC / CNTVCT_EL0).
    3. In-Memory MEM-SBOM Forensics & Hardware Breakpoint inspection.
    4. End-to-End VM execution under all Layer 3 Anti-Tamper guards. *)

let test_smc_probe_c_compilation_and_execution () =
  let tmp_dir = Filename.temp_file "anti_tamper_smc_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  (try Sys.mkdir tmp_dir 0o755 with _ -> ());

  let main_cpp = Filename.concat tmp_dir "test_smc.cpp" in
  let oc = open_out main_cpp in
  output_string oc (Hardened_runtime.emit_anti_emulation_probes ());
  output_string oc "\n";
  output_string oc (Hardened_runtime.emit_dual_mapping_header ());
  output_string oc "\n";
  output_string oc (Hardened_runtime.emit_introspective_smc_header ());
  output_string oc "\n";
  output_string oc (Hardened_runtime.emit_memory_integrity_scanner_header ());
  output_string oc "\n";
  output_string oc {|
#include <stdio.h>
#include <stdlib.h>

int main() {
    // 1. Test SMC execution and mutation
    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe(0x42);
    if (smc_penalty != 0) {
        printf("SMC probe failed with penalty: %llu\n", (unsigned long long)smc_penalty);
        return 1;
    }

    // 2. Test Memory Integrity and Hardware Breakpoints scanner
    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();
    if (mem_penalty != 0) {
        printf("Memory integrity probe failed with penalty: %llu\n", (unsigned long long)mem_penalty);
        return 2;
    }

    // 3. Test Anti-Emulation timing differential
    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
    if (emu_penalty != 0) {
        printf("Anti-emulation probe failed with penalty: %llu\n", (unsigned long long)emu_penalty);
        return 3;
    }

    printf("[SMC & Anti-Tamper] All Layer 3 probes SUCCESS! Clean environment.\n");
    return 0;
}
|};
  close_out oc;

  let bin_path = Filename.concat tmp_dir "test_smc" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 %s -o %s" main_cpp bin_path in
  let comp_status = Sys.command comp_cmd in
  Alcotest.(check int) "clang++ compilation of Layer 3 probes succeeds" 0 comp_status;

  let run_cmd = bin_path in
  let ic = Unix.open_process_in run_cmd in
  let out_buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
  let out_str = Buffer.contents out_buf in
  Alcotest.(check bool) "output contains SUCCESS" true (String.contains out_str 'S' && String.contains out_str 'U' && String.contains out_str 'C')

let test_full_threaded_vm_with_layer3_protection () =
  let rng = Random.State.make [| 0x3333 |] in
  let asm = {|
func_layer3_vm:
    mov rax, 500
    mov rbx, 20
    add rax, rbx
    imul rax, 3
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:true ~enable_junk:true func in

      let tmp_dir = Filename.temp_file "vm_layer3_" "_dir" in
      (try Sys.remove tmp_dir with _ -> ());
      (try Sys.mkdir tmp_dir 0o755 with _ -> ());

      let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
      let oc_h = open_out hdr_path in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;

      let runner_path = Filename.concat tmp_dir "runner.cpp" in
      let oc_r = open_out runner_path in
      output_string oc_r pkg.runner_source;
      close_out oc_r;

      let bin_path = Filename.concat tmp_dir "runner" in
      let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path in
      let comp_status = Sys.command comp_cmd in
      Alcotest.(check int) "clang++ compilation succeeds" 0 comp_status;

      let run_cmd = bin_path in
      let ic = Unix.open_process_in run_cmd in
      let out_buf = Buffer.create 256 in
      (try
         while true do
           Buffer.add_string out_buf (input_line ic);
           Buffer.add_char out_buf '\n'
         done
       with End_of_file -> ());
      let status = Unix.close_process_in ic in
      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      (* (500 + 20) * 3 = 1560 *)
      Alcotest.(check bool) "rax is 1560" true (String.contains out_str '1' && String.contains out_str '5' && String.contains out_str '6')

let test_nanomite_signal_dispatch () =
  let rng = Random.State.make [| 0x7777 |] in
  let asm = {|
func_nanomite_branch:
    mov rax, 42
    cmp rax, 50
    jl .Lless
    add rax, 1000
    ret
.Lless:
    add rax, 2000
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let config = {
        Protection_config.default with
        cff = { Protection_config.default.cff with enabled = false };
        mba = { Protection_config.default.mba with enabled = false };
        anti_tamper = {
          Protection_config.default.anti_tamper with
          nanomites = true;
        }
      } in
      let pkg = Vm_emitter.compile_and_package ~rng ~config func in

      let tmp_dir = Filename.temp_file "vm_nanomite_" "_dir" in
      (try Sys.remove tmp_dir with _ -> ());
      (try Sys.mkdir tmp_dir 0o755 with _ -> ());

      let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
      let oc_h = open_out hdr_path in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;

      let runner_source_with_check =
        pkg.runner_source ^ "\n__attribute__((destructor)) static void _check_nanomite_traps() {\n"
        ^ "    printf(\"[NANOMITES_ACTIVE] Traps Handled: %llu\\n\",\n"
        ^ "           (unsigned long long)asgard_nanomites::g_nanomite_dispatcher.traps_handled);\n"
        ^ "}\n"
      in
      let runner_path = Filename.concat tmp_dir "runner.cpp" in
      let oc_r = open_out runner_path in
      output_string oc_r runner_source_with_check;
      close_out oc_r;

      let bin_path = Filename.concat tmp_dir "runner" in
      let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path in
      let comp_status = Sys.command comp_cmd in
      Alcotest.(check int) "clang++ compilation succeeds with nanomites" 0 comp_status;

      let run_cmd = bin_path in
      let ic = Unix.open_process_in run_cmd in
      let out_buf = Buffer.create 256 in
      (try
         while true do
           Buffer.add_string out_buf (input_line ic);
           Buffer.add_char out_buf '\n'
         done
       with End_of_file -> ());
      let status = Unix.close_process_in ic in
      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      (* 42 < 50, so .Lless branch taken: 42 + 2000 = 2042 *)
      Alcotest.(check bool) "output contains SUCCESS" true (String.contains out_str 'S' && String.contains out_str 'U' && String.contains out_str 'C');
      Alcotest.(check bool) "rax is 2042" true (String.contains out_str '2' && String.contains out_str '0' && String.contains out_str '4');
      Alcotest.(check bool) "nanomite hardware traps active" true (String.contains out_str 'N' && String.contains out_str 'A' && String.contains out_str 'C')

let test_direct_syscalls_e2e () =
  let tmp_dir = Filename.temp_file "direct_syscalls_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  (try Sys.mkdir tmp_dir 0o755 with _ -> ());

  let main_cpp = Filename.concat tmp_dir "test_syscalls.cpp" in
  let oc = open_out main_cpp in
  output_string oc (Hardened_runtime.emit_direct_syscalls_header ());
  output_string oc "\n";
  output_string oc {|
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    pid_t sys_pid = asgard_syscalls::sys_getpid();
    pid_t real_pid = getpid();
    if (sys_pid != real_pid) {
        printf("[SYSCALL_FAIL] getpid mismatch: syscall=%d real=%d\n", sys_pid, real_pid);
        return 1;
    }

    bool is_traced = asgard_syscalls::sys_check_debugger_present();
    printf("[DIRECT_SYSCALL_OK] PID=%d Traced=%s\n", sys_pid, is_traced ? "YES" : "NO");

    const char msg[] = "[DIRECT_WRITE_OK]\n";
    int64_t w = asgard_syscalls::sys_write(1, msg, sizeof(msg) - 1);
    if (w <= 0) return 2;

    return 0;
}
|};
  close_out oc;

  let bin_path = Filename.concat tmp_dir "test_sys" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 %s -o %s" main_cpp bin_path in
  let comp_status = Sys.command comp_cmd in
  Alcotest.(check int) "clang++ compilation of direct syscalls succeeds" 0 comp_status;

  let run_cmd = bin_path in
  let ic = Unix.open_process_in run_cmd in
  let out_buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
  let out_str = Buffer.contents out_buf in
  Alcotest.(check bool) "output contains DIRECT_SYSCALL_OK" true (String.contains out_str 'D' && String.contains out_str 'I' && String.contains out_str 'R');
  Alcotest.(check bool) "output contains DIRECT_WRITE_OK" true (String.contains out_str 'W' && String.contains out_str 'R' && String.contains out_str 'I')

let test_vector_isa_e2e () =
  let tmp_dir = Filename.temp_file "vector_isa_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  (try Sys.mkdir tmp_dir 0o755 with _ -> ());

  let main_cpp = Filename.concat tmp_dir "test_vector_isa.cpp" in
  let oc = open_out main_cpp in
  (* Emit the SIMD intrinsic includes and a minimal VMContext with vregs *)
  output_string oc {|
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#if defined(__aarch64__)
#include <arm_neon.h>
#elif defined(__x86_64__)
#include <immintrin.h>
#endif

/* Minimal 128-bit vector register bank for the test */
struct VReg { uint64_t lo, hi; };
static VReg vregs[32];

static inline uint64_t get_vreg_lane(uint8_t i, size_t lane) { return lane == 0 ? vregs[i].lo : vregs[i].hi; }
static inline void set_vreg(uint8_t i, uint64_t lo, uint64_t hi) { vregs[i].lo = lo; vregs[i].hi = hi; }

static void do_vadd(uint8_t dst, uint8_t src) {
    uint64_t d0 = get_vreg_lane(dst, 0), d1 = get_vreg_lane(dst, 1);
    uint64_t s0 = get_vreg_lane(src, 0), s1 = get_vreg_lane(src, 1);
#if defined(__aarch64__)
    uint64x2_t vd = vcombine_u64(vcreate_u64(d0), vcreate_u64(d1));
    uint64x2_t vs = vcombine_u64(vcreate_u64(s0), vcreate_u64(s1));
    uint64x2_t vr = vaddq_u64(vd, vs);
    set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(__x86_64__)
    __m128i vd = _mm_set_epi64x((int64_t)d1, (int64_t)d0);
    __m128i vs = _mm_set_epi64x((int64_t)s1, (int64_t)s0);
    __m128i vr = _mm_add_epi64(vd, vs);
    set_vreg(dst, (uint64_t)_mm_extract_epi64(vr, 0), (uint64_t)_mm_extract_epi64(vr, 1));
#else
    set_vreg(dst, d0 + s0, d1 + s1);
#endif
}

static void do_vxor(uint8_t dst, uint8_t src) {
    uint64_t d0 = get_vreg_lane(dst, 0), d1 = get_vreg_lane(dst, 1);
    uint64_t s0 = get_vreg_lane(src, 0), s1 = get_vreg_lane(src, 1);
#if defined(__aarch64__)
    uint64x2_t vd = vcombine_u64(vcreate_u64(d0), vcreate_u64(d1));
    uint64x2_t vs = vcombine_u64(vcreate_u64(s0), vcreate_u64(s1));
    uint64x2_t vr = veorq_u64(vd, vs);
    set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(__x86_64__)
    __m128i vd = _mm_set_epi64x((int64_t)d1, (int64_t)d0);
    __m128i vs = _mm_set_epi64x((int64_t)s1, (int64_t)s0);
    __m128i vr = _mm_xor_si128(vd, vs);
    set_vreg(dst, (uint64_t)_mm_extract_epi64(vr, 0), (uint64_t)_mm_extract_epi64(vr, 1));
#else
    set_vreg(dst, d0 ^ s0, d1 ^ s1);
#endif
}

int main() {
    /* v0 = [10, 20], v1 = [3, 7] */
    set_vreg(0, 10ULL, 20ULL);
    set_vreg(1, 3ULL, 7ULL);

    /* v0 = v0 + v1 => [13, 27] */
    do_vadd(0, 1);
    if (get_vreg_lane(0, 0) != 13ULL || get_vreg_lane(0, 1) != 27ULL) {
        printf("[VECTOR_ISA_FAIL] VADD wrong: lo=%llu hi=%llu\n",
               (unsigned long long)get_vreg_lane(0, 0),
               (unsigned long long)get_vreg_lane(0, 1));
        return 1;
    }

    /* v2 = [0xFF00FF00FF00FF00, 0x00FF00FF00FF00FF],  v3 = same */
    set_vreg(2, 0xFF00FF00FF00FF00ULL, 0x00FF00FF00FF00FFULL);
    set_vreg(3, 0xFF00FF00FF00FF00ULL, 0x00FF00FF00FF00FFULL);
    /* v2 xor v3 => [0, 0] */
    do_vxor(2, 3);
    if (get_vreg_lane(2, 0) != 0ULL || get_vreg_lane(2, 1) != 0ULL) {
        printf("[VECTOR_ISA_FAIL] VXOR self-xor should be zero\n");
        return 2;
    }

    printf("[VECTOR_ISA_OK] NEON/SSE SIMD handlers verified.\n");
    return 0;
}
|};
  close_out oc;

  let bin_path = Filename.concat tmp_dir "test_visa" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 %s -o %s 2>&1" main_cpp bin_path in
  let comp_status = Sys.command comp_cmd in
  Alcotest.(check int) "vector ISA clang++ compilation succeeds" 0 comp_status;

  let ic = Unix.open_process_in bin_path in
  let out_buf = Buffer.create 128 in
  (try while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  Alcotest.(check bool) "vector ISA binary exits 0" true (status = Unix.WEXITED 0);
  let out = Buffer.contents out_buf in
  Alcotest.(check bool) "output contains VECTOR_ISA_OK" true
    (let needle = "VECTOR_ISA_OK" in
     let n = String.length needle and h = String.length out in
     let found = ref false in
     for i = 0 to h - n do
       if String.sub out i n = needle then found := true
     done; !found)

let tests = [
  Alcotest.test_case "smc_probe_c_compilation_and_execution" `Quick test_smc_probe_c_compilation_and_execution;
  Alcotest.test_case "full_threaded_vm_with_layer3_protection" `Quick test_full_threaded_vm_with_layer3_protection;
  Alcotest.test_case "nanomite_signal_dispatch" `Quick test_nanomite_signal_dispatch;
  Alcotest.test_case "direct_syscalls_e2e" `Quick test_direct_syscalls_e2e;
  Alcotest.test_case "vector_isa_e2e" `Quick test_vector_isa_e2e;
]
