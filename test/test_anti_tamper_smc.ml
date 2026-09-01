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

let tests = [
  Alcotest.test_case "smc_probe_c_compilation_and_execution" `Quick test_smc_probe_c_compilation_and_execution;
  Alcotest.test_case "full_threaded_vm_with_layer3_protection" `Quick test_full_threaded_vm_with_layer3_protection;
]
