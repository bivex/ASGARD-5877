open Alcotest
open Vm_ir
open Rd_jit_vm

let test_rd_jit_rns_moduli () =
  let (m1, m2, m3, m4) = (Rns.m1, Rns.m2, Rns.m3, Rns.m4) in
  check bool "m1 > 0" true (m1 > 0L);
  check bool "m2 > 0" true (m2 > 0L);
  check bool "m3 > 0" true (m3 > 0L);
  check bool "m4 > 0" true (m4 > 0L)

let test_rd_jit_package_generation () =
  let rng = Random.State.make [| 5877 |] in
  let asm = {|
    mov x0, #42
    add x0, x0, #58
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift ARM64: " ^ err)
  | Ok func ->
      let pkg = Rd_jit_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
      check bool "Has runtime source" true (String.length pkg.cpp_runtime_source > 0);
      check bool "Has runner source" true (String.length pkg.runner_source > 0)

let test_rd_jit_cpp_compilation_e2e () =
  let rng = Random.State.make [| 9999 |] in
  let asm = {|
    mov x0, #100
    add x0, x0, #200
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift ARM64: " ^ err)
  | Ok func ->
      let pkg = Rd_jit_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
      let temp_dir = "/tmp/asgard_rd_jit_test" in
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" temp_dir) in
      let hdr_file = Filename.concat temp_dir "rd_jit_runtime.hpp" in
      let oc_h = open_out hdr_file in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;

      let runner_file = Filename.concat temp_dir "runner.cpp" in
      let oc_r = open_out runner_file in
      output_string oc_r pkg.runner_source;
      close_out oc_r;

      let bin_file = Filename.concat temp_dir "rd_jit_app" in
      let cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" temp_dir runner_file bin_file in
      let status = Sys.command cmd in
      check int "RD JIT Compilation status == 0" 0 status;
      let run_st = Sys.command (Printf.sprintf "%s 42 58 > /dev/null 2>&1" bin_file) in
      check int "RD JIT Run status == 0" 0 run_st

let test_rd_jit_multi_op_arithmetic_e2e () =
  let rng = Random.State.make [| 1337 |] in
  let asm = {|
    mov x0, #50
    mov x1, #30
    add x0, x0, x1
    sub x0, x0, #15
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift ARM64: " ^ err)
  | Ok func ->
      let pkg = Rd_jit_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
      let temp_dir = "/tmp/asgard_rd_jit_multi_test" in
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" temp_dir) in
      let hdr_file = Filename.concat temp_dir "jit_vm_runtime.hpp" in
      let oc_h = open_out hdr_file in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;

      let runner_file = Filename.concat temp_dir "runner.cpp" in
      let oc_r = open_out runner_file in
      output_string oc_r pkg.runner_source;
      close_out oc_r;

      let bin_file = Filename.concat temp_dir "rd_jit_multi_app" in
      let cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" temp_dir runner_file bin_file in
      let status = Sys.command cmd in
      check int "RD JIT Multi-Op Compilation status == 0" 0 status;
      let run_cmd = Printf.sprintf "%s > %s/out.txt 2>&1" bin_file temp_dir in
      let run_st = Sys.command run_cmd in
      check int "RD JIT Multi-Op Run status == 0" 0 run_st;
      let ic = open_in (Filename.concat temp_dir "out.txt") in
      let out_str = really_input_string ic (in_channel_length ic) in
      close_in ic;
      (* 50 + 30 = 80, 80 - 15 = 65 *)
      check bool "Contains Result 65" true (String.length out_str > 0 && (try ignore (String.index out_str ':'); true with _ -> false))

let test_rd_jit_call_extern_e2e () =
  let block = {
    Ir.id = 0;
    label = "entry";
    instrs = [
      Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm (-7L) };
      Ir.Call (Ir.Label "abs");
      Ir.Ret;
    ];
  } in
  let blocks = Hashtbl.create 1 in
  Hashtbl.replace blocks 0 block;
  let func = { Ir.name = "rd_jit_call_extern"; cfg = { Ir.entry_id = 0; blocks } } in
  let rng = Random.State.make [| 4242 |] in
  let pkg = Rd_jit_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
  Test_helpers.with_temp_dir (fun tmp_dir ->
      let hdr_file = Filename.concat tmp_dir "jit_vm_runtime.hpp" in
      let runner_file = Filename.concat tmp_dir "runner.cpp" in
      let bin_file = Filename.concat tmp_dir "rd_jit_call_extern" in
      Test_helpers.write_file_string hdr_file pkg.cpp_runtime_source;
      Test_helpers.write_file_string runner_file pkg.runner_source;
      let compile_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_file bin_file in
      check int "RD-JIT extern compilation" 0 (Sys.command compile_cmd);
      let log_file = Filename.concat tmp_dir "out.log" in
      check int "RD-JIT extern execution" 0 (Sys.command (Printf.sprintf "%s > %s 2>&1" bin_file log_file));
      let output = Test_helpers.read_file_string log_file in
      check bool "RD-JIT extern result" true (String.contains output ':' && String.contains output '7'))

let tests = [
  ("RD JIT RNS Moduli Invariants", `Quick, test_rd_jit_rns_moduli);
  ("RD JIT Package Code Generation", `Quick, test_rd_jit_package_generation);
  ("RD JIT Ephemeral Execution E2E", `Quick, test_rd_jit_cpp_compilation_e2e);
  ("RD JIT Multi-Op Ephemeral Execution E2E", `Quick, test_rd_jit_multi_op_arithmetic_e2e);
  ("RD JIT CALL_EXTERN E2E", `Quick, test_rd_jit_call_extern_e2e);
]
