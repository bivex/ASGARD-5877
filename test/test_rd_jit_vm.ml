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

let tests = [
  ("RD JIT RNS Moduli Invariants", `Quick, test_rd_jit_rns_moduli);
  ("RD JIT Package Code Generation", `Quick, test_rd_jit_package_generation);
  ("RD JIT Ephemeral Execution E2E", `Quick, test_rd_jit_cpp_compilation_e2e);
]
