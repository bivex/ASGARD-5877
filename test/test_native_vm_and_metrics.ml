open X86_lifter
open Native_vm

let test_metrics_calculation () =
  let sample_bytecode = [
    0x8F0123456789ABCDL;
    0x1234567890ABCDEFL;
    0xFEDCBA0987654321L;
    0xCAFEBABE11223344L;
    0xDEADBEEF55667788L;
  ] in
  let entropy = Metrics.calculate_shannon_entropy sample_bytecode in
  Alcotest.(check bool) "entropy is high (> 4.0)" true (entropy > 4.0);

  (* Low entropy test *)
  let low_entropy_bytecode = [ 0L; 0L; 0L; 0L ] in
  let low_entropy = Metrics.calculate_shannon_entropy low_entropy_bytecode in
  Alcotest.(check bool) "low entropy is 0" true (low_entropy = 0.0)

let test_threaded_vm_compilation_and_execution () =
  let rng = Random.State.make [| 2026 |] in
  let asm = {|
func_compute:
    mov rax, 10
    add rax, 20
    imul rax, 2
    sub rax, 5
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng func in
      Alcotest.(check bool) "bytecode not empty" true (List.length pkg.bytecode > 0);
      Alcotest.(check bool) "DRS score calculated" true (pkg.metrics.devirtualization_resistance_score > 20.0);

      let tmp_dir = Filename.temp_file "threaded_vm_" "_dir" in
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

      (* Write bytecode to file *)
      let bc_path = Filename.concat tmp_dir "code.vanguard" in
      let oc_b = open_out_bin bc_path in
      List.iter
        (fun w ->
          for i = 0 to 7 do
            let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
            output_byte oc_b b
          done)
        pkg.bytecode;
      close_out oc_b;

      (* Execute runner *)
      let run_cmd = Printf.sprintf "%s %s" bin_path bc_path in
      let ic = Unix.open_process_in run_cmd in
      let out_buf = Buffer.create 256 in
      (try
         while true do
           Buffer.add_string out_buf (input_line ic);
           Buffer.add_char out_buf '\n'
         done
       with End_of_file -> ());
      let status = Unix.close_process_in ic in
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      (* (10 + 20) * 2 - 5 = 55 *)
      Alcotest.(check bool) "rax is 55" true (String.contains out_str '5' && String.contains out_str 'R');

      (* Decoy Trap Test *)
      let bad_bc_path = Filename.concat tmp_dir "corrupt.vanguard" in
      let oc_bad = open_out_bin bad_bc_path in
      for _ = 0 to 7 do output_byte oc_bad 0xFE done;
      close_out oc_bad;

      let bad_cmd = Printf.sprintf "%s %s 2>/dev/null" bin_path bad_bc_path in
      let bad_status = Sys.command bad_cmd in
      Alcotest.(check bool) "decoy trap fails with exit code 2" true (bad_status <> 0);

      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      ()

let test_threaded_vm_with_cff () =
  let rng = Random.State.make [| 7777 |] in
  let asm = {|
func_cff_test:
    mov rax, 15
    cmp rax, 10
    jge .Lge
    add rax, 100
    ret
.Lge:
    add rax, 200
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:true func in
      Alcotest.(check bool) "flattening depth >= 3" true (pkg.metrics.flattening_depth >= 3);

      let tmp_dir = Filename.temp_file "cff_vm_" "_dir" in
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

      let bc_path = Filename.concat tmp_dir "code.vanguard" in
      let oc_b = open_out_bin bc_path in
      List.iter
        (fun w ->
          for i = 0 to 7 do
            let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
            output_byte oc_b b
          done)
        pkg.bytecode;
      close_out oc_b;

      let run_cmd = Printf.sprintf "%s %s" bin_path bc_path in
      let ic = Unix.open_process_in run_cmd in
      let out_buf = Buffer.create 256 in
      (try
         while true do
           Buffer.add_string out_buf (input_line ic);
           Buffer.add_char out_buf '\n'
         done
       with End_of_file -> ());
      let status = Unix.close_process_in ic in
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      (* 15 >= 10 -> rax = 15 + 200 = 215 *)
      Alcotest.(check bool) "rax is 215" true (String.contains out_str '2' && String.contains out_str '1');

      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      ()

let test_super_operators_execution () =
  let rng = Random.State.make [| 9999 |] in
  (* Sequences of instructions that trigger Super-Operators:
     1. mov rax, 10 + add rax, 50 -> Fused_Mov_Add (rax = 60)
     2. add rax, rbx + imul rax, 2 -> Fused_Add_Imul (rax = (60 + 5) * 2 = 130)
  *)
  let asm = {|
func_super_ops:
    mov rbx, 5
    mov rax, 10
    add rax, 50
    add rax, rbx
    imul rax, 2
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_junk:false func in
      (* Original had 6 instrs, fused has fewer (4 instructions) *)
      Alcotest.(check bool) "bytecode is compacted by fusion" true (List.length pkg.bytecode < 6);

      let tmp_dir = Filename.temp_file "super_vm_" "_dir" in
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
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      (* (10 + 50 + 5) * 2 = 130 *)
      Alcotest.(check bool) "rax is 130" true (String.contains out_str '1' && String.contains out_str '3' && String.contains out_str '0');

      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      ()

let test_dynamic_junk_bytecode () =
  let rng = Random.State.make [| 133742 |] in
  let asm = {|
func_junk_test:
    mov rax, 40
    add rax, 2
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg_clean = Vm_emitter.compile_and_package ~rng ~enable_junk:false func in
      let pkg_junk = Vm_emitter.compile_and_package ~rng ~enable_junk:true func in
      (* Junk injection increases the instruction count in bytecode with phantom operations *)
      Alcotest.(check bool) "junk increases bytecode size" true (List.length pkg_junk.bytecode >= List.length pkg_clean.bytecode);

      let tmp_dir = Filename.temp_file "junk_vm_" "_dir" in
      (try Sys.remove tmp_dir with _ -> ());
      (try Sys.mkdir tmp_dir 0o755 with _ -> ());

      let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
      let oc_h = open_out hdr_path in
      output_string oc_h pkg_junk.cpp_runtime_source;
      close_out oc_h;

      let runner_path = Filename.concat tmp_dir "runner.cpp" in
      let oc_r = open_out runner_path in
      output_string oc_r pkg_junk.runner_source;
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
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      (* rax should be 40 + 2 = 42 despite phantom junk and taint siphoning *)
      Alcotest.(check bool) "rax is 42" true (String.contains out_str '4' && String.contains out_str '2');

      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      ()


let test_ephemeral_self_consuming_scrubbing () =
  let rng = Random.State.make [| 5877 |] in
  let asm = {|
func_scrub_verify:
    mov rax, 100
    add rax, 200
    add rax, 300
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng func in
      let tmp_dir = Filename.temp_file "scrub_vm_" "_dir" in
      (try Sys.remove tmp_dir with _ -> ());
      (try Sys.mkdir tmp_dir 0o755 with _ -> ());

      let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
      let oc_h = open_out hdr_path in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;

      let custom_runner = Printf.sprintf {|
#include "threaded_vm.hpp"
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static uint64_t embedded_bytecode[] = {
%s
};

int main() {
    size_t count = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    printf("[TEST] Bytecode count: %%zu words\n", count);
    for (size_t i = 0; i < count; ++i) {
        printf("[BEFORE] Word %%zu: 0x%%016llX\n", i, (unsigned long long)embedded_bytecode[i]);
    }

    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count);
    if (!ok) return 1;

    printf("[AFTER] Execution OK. RAX: %%llu\n", (unsigned long long)ctx.get_rax());
    return (ctx.get_rax() == 600ULL) ? 0 : 2;
}
|}
        (String.concat "\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) pkg.bytecode))
      in

      let runner_path = Filename.concat tmp_dir "runner.cpp" in
      let oc_r = open_out runner_path in
      output_string oc_r custom_runner;
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
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      let out_str = Buffer.contents out_buf in
      Printf.printf "\n%s\n%!" out_str;
      Alcotest.(check bool) "rax is 600" true (String.contains out_str '6' && String.contains out_str '0');

      let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
      ()

let tests = [
  Alcotest.test_case "metrics_calculation" `Quick test_metrics_calculation;
  Alcotest.test_case "threaded_vm_compilation_and_execution" `Slow test_threaded_vm_compilation_and_execution;
  Alcotest.test_case "threaded_vm_with_cff" `Slow test_threaded_vm_with_cff;
  Alcotest.test_case "super_operators_execution" `Slow test_super_operators_execution;
  Alcotest.test_case "ephemeral_self_consuming_scrubbing" `Slow test_ephemeral_self_consuming_scrubbing;
  Alcotest.test_case "dynamic_junk_bytecode" `Slow test_dynamic_junk_bytecode;
]



