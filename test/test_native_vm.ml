open X86_lifter
open Native_vm
open Vm_ir
open Test_helpers

let compile_and_prepare_vm tmp_dir (pkg : Vm_emitter.vm_package) =
  let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
  write_file_string hdr_path pkg.cpp_runtime_source;
  let runner_path = Filename.concat tmp_dir "runner.cpp" in
  write_file_string runner_path pkg.runner_source;
  let bin_path = Filename.concat tmp_dir "runner" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path in
  let comp_status = Sys.command comp_cmd in
  Alcotest.(check int) "clang++ compilation succeeds" 0 comp_status;
  bin_path

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
      Alcotest.(check bool) "DRS score calculated" true (Metrics.devirtualization_resistance_score pkg.metrics > 20.0);
      with_temp_dir (fun tmp_dir ->
        let bin_path = compile_and_prepare_vm tmp_dir pkg in
        let bc_path = Filename.concat tmp_dir "code.vanguard" in
        write_bytecode_bin bc_path pkg.bytecode;

        let status, out_str = run_command_capture (Printf.sprintf "%s %s" bin_path bc_path) in
        Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
        Alcotest.(check bool) "rax is 55" true (String.contains out_str '5' && String.contains out_str 'R');

        let bad_bc_path = Filename.concat tmp_dir "corrupt.vanguard" in
        let oc_bad = open_out_bin bad_bc_path in
        for _ = 0 to 7 do output_byte oc_bad 0xFE done;
        close_out oc_bad;
        let bad_status = Sys.command (Printf.sprintf "%s %s 2>/dev/null" bin_path bad_bc_path) in
        Alcotest.(check bool) "decoy trap fails with exit code 2" true (bad_status <> 0))

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
      Alcotest.(check bool) "flattening depth >= 3" true (Metrics.flattening_depth pkg.metrics >= 3);
      with_temp_dir (fun tmp_dir ->
        let bin_path = compile_and_prepare_vm tmp_dir pkg in
        let bc_path = Filename.concat tmp_dir "code.vanguard" in
        write_bytecode_bin bc_path pkg.bytecode;
        let status, out_str = run_command_capture (Printf.sprintf "%s %s" bin_path bc_path) in
        Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
        Alcotest.(check bool) "rax is 215" true (String.contains out_str '2' && String.contains out_str '1'))

let test_super_operators_execution () =
  let rng = Random.State.make [| 9999 |] in
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
      Alcotest.(check bool) "bytecode is compacted by fusion" true (List.length pkg.bytecode < 6);
      with_temp_dir (fun tmp_dir ->
        let bin_path = compile_and_prepare_vm tmp_dir pkg in
        let status, out_str = run_command_capture bin_path in
        Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
        Alcotest.(check bool) "rax is 130" true (String.contains out_str '1' && String.contains out_str '3' && String.contains out_str '0'))

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
      Alcotest.(check bool) "junk increases bytecode size" true (List.length pkg_junk.bytecode >= List.length pkg_clean.bytecode);
      with_temp_dir (fun tmp_dir ->
        let bin_path = compile_and_prepare_vm tmp_dir pkg_junk in
        let status, out_str = run_command_capture bin_path in
        Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
        Alcotest.(check bool) "rax is 42" true (String.contains out_str '4' && String.contains out_str '2'))

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
      with_temp_dir (fun tmp_dir ->
        let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
        write_file_string hdr_path pkg.cpp_runtime_source;
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
    uint64_t before_words[64];
    for (size_t i = 0; i < count; ++i) before_words[i] = embedded_bytecode[i];

    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count, true);
    if (!ok) return 1;

    size_t wiped_count = 0;
    for (size_t i = 0; i < count; ++i) {
        if (embedded_bytecode[i] != before_words[i]) wiped_count++;
    }
    return (ctx.get_rax() == 600ULL && wiped_count == count) ? 0 : 2;
}
|} (String.concat "\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) pkg.bytecode)) in
        let runner_path = Filename.concat tmp_dir "runner.cpp" in
        write_file_string runner_path custom_runner;
        let bin_path = Filename.concat tmp_dir "runner" in
        let comp_status = Sys.command (Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path) in
        Alcotest.(check int) "clang++ compilation succeeds" 0 comp_status;
        let status, _ = run_command_capture bin_path in
        Alcotest.(check bool) "exit code 0 (rax 600 and all words wiped)" true (status = Unix.WEXITED 0))

let test_ephemeral_scrubbing_loop_and_stack () =
  let rng = Random.State.make [| 20260922 |] in
  let asm = {|
func_scrub_loop:
    mov rax, 1
    mov rcx, 4
.Lscrub_loop:
    imul rax, rcx
    push rax
    pop rbx
    sub rcx, 1
    cmp rcx, 0
    jne .Lscrub_loop
    mov rax, rbx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:false func in
      with_temp_dir (fun tmp_dir ->
        let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
        write_file_string hdr_path pkg.cpp_runtime_source;
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
    uint64_t before_words[64];
    for (size_t i = 0; i < count; ++i) before_words[i] = embedded_bytecode[i];

    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, count, true);
    if (!ok) return 1;
    if (ctx.get_rax() != 24ULL) return 2;

    size_t wiped_count = 0;
    for (size_t i = 0; i < count; ++i) {
        if (embedded_bytecode[i] != before_words[i]) wiped_count++;
    }
    return (wiped_count == count) ? 0 : 3;
}
|} (String.concat "\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) pkg.bytecode)) in
        let runner_path = Filename.concat tmp_dir "runner.cpp" in
        write_file_string runner_path custom_runner;
        let bin_path = Filename.concat tmp_dir "runner" in
        let comp_status = Sys.command (Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path) in
        Alcotest.(check int) "clang++ compilation succeeds" 0 comp_status;
        let status, _ = run_command_capture bin_path in
        Alcotest.(check bool) "exit code 0 (rax 24 and loop words wiped)" true (status = Unix.WEXITED 0))

let test_integrity_checksumming_and_stack_scrambling () =
  let rng = Random.State.make [| 2026 |] in
  let asm = {|
func_integrity_stack:
    mov rax, 100
    push rax
    mov rax, 200
    pop rbx
    add rax, rbx
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng func in
      with_temp_dir (fun tmp_dir ->
        let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
        write_file_string hdr_path pkg.cpp_runtime_source;
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
    vanguard_threaded_vm::VMContext ctx1 = {};
    ctx1.init();
    bool ok1 = vanguard_threaded_vm::execute_threaded(ctx1, embedded_bytecode, count);
    if (!ok1 || ctx1.get_rax() != 300ULL) return 1;

    uint64_t tampered_bytecode[64];
    memcpy(tampered_bytecode, embedded_bytecode, sizeof(embedded_bytecode));
    tampered_bytecode[0] ^= 0x90ULL;

    vanguard_threaded_vm::VMContext ctx2 = {};
    ctx2.init();
    bool ok2 = vanguard_threaded_vm::execute_threaded(ctx2, tampered_bytecode, count);
    if (ok2 || !ctx2.trapped) return 2;
    return 0;
}
|} (String.concat "\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) pkg.bytecode)) in
        let runner_path = Filename.concat tmp_dir "runner.cpp" in
        write_file_string runner_path custom_runner;
        let bin_path = Filename.concat tmp_dir "runner" in
        let comp_status = Sys.command (Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path) in
        Alcotest.(check int) "clang++ compilation succeeds" 0 comp_status;
        let status, _ = run_command_capture bin_path in
        Alcotest.(check bool) "exit code 0 (integrity test passed)" true (status = Unix.WEXITED 0))

let test_external_libc_call_trampoline () =
  let rng = Random.State.make [| 20260923 |] in
  let entry_block = {
    Ir.id = 0;
    label = "entry";
    instrs = [
      Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm (-42L) };
      Ir.Call (Ir.Label "abs");
      Ir.Ret;
    ];
  } in
  let blocks = Hashtbl.create 1 in
  Hashtbl.replace blocks 0 entry_block;
  let func = {
    Ir.name = "test_extern_call";
    cfg = { Ir.entry_id = 0; blocks };
  } in
  let pkg = Vm_emitter.compile_and_package ~rng func in
  with_temp_dir (fun tmp_dir ->
    let bin_path = compile_and_prepare_vm tmp_dir pkg in
    let status, out_str = run_command_capture bin_path in
    Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
    Alcotest.(check bool) "returned abs(-42) = 42" true (String.contains out_str '4' && String.contains out_str '2'))

let tests = [
  Alcotest.test_case "threaded_vm_compilation_and_execution" `Slow test_threaded_vm_compilation_and_execution;
  Alcotest.test_case "threaded_vm_with_cff" `Slow test_threaded_vm_with_cff;
  Alcotest.test_case "super_operators_execution" `Slow test_super_operators_execution;
  Alcotest.test_case "ephemeral_self_consuming_scrubbing" `Slow test_ephemeral_self_consuming_scrubbing;
  Alcotest.test_case "ephemeral_scrubbing_loop_and_stack" `Slow test_ephemeral_scrubbing_loop_and_stack;
  Alcotest.test_case "dynamic_junk_bytecode" `Slow test_dynamic_junk_bytecode;
  Alcotest.test_case "integrity_checksumming_and_stack_scrambling" `Slow test_integrity_checksumming_and_stack_scrambling;
  Alcotest.test_case "external_libc_call_trampoline" `Slow test_external_libc_call_trampoline;
]
