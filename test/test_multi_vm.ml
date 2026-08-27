open Alcotest
open Multi_vm

let test_modular_inverse_64 () =
  let rng = Random.State.make [| 42 |] in
  for _ = 1 to 100 do
    let odd_val = Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L in
    let inv = Bridge.mod_inverse_64 odd_val in
    let prod = Int64.mul odd_val inv in
    check int64 "odd * inv == 1 (mod 2^64)" 1L prod
  done

let test_affine_bridge_roundtrip_1000 () =
  let rng = Random.State.make [| 1337 |] in
  let bridge = Bridge.generate_bridge ~dim:16 rng in
  for _ = 1 to 1000 do
    let orig_vec = Array.init 16 (fun _ -> Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) in
    let digest = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
    let morphed = Bridge.forward_morph bridge orig_vec digest in
    let recovered = Bridge.inverse_morph bridge morphed digest in
    for i = 0 to 15 do
      check int64 (Printf.sprintf "Recovered slot %d" i) orig_vec.(i) recovered.(i)
    done
  done

let test_trace_digest_coupling () =
  let d0 = 0x13375877AABBCCDDL in
  let d1 = Bridge.update_trace_digest d0 0x10L 0L in
  let d2 = Bridge.update_trace_digest d1 0x20L 1L in
  let d3 = Bridge.update_trace_digest d0 0x10L 0L in
  check bool "Deterministic digest update" true (d1 = d3);
  check bool "Evolving digest differs" true (d1 <> d2)

let test_ast_functional_partitioning () =
  let asm = {|
    mov x0, #42
    add x0, x0, #10
    cmp x0, #50
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    mul x0, x0, #2
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift: " ^ err)
  | Ok func ->
      let rep = Partitioner.partition_function func in
      check bool "Has math blocks" true (rep.math_blocks > 0);
      check bool "Has flow blocks" true (rep.flow_blocks > 0);
      check bool "Partitioned all blocks" true (rep.total_blocks = Hashtbl.length func.cfg.blocks)

let test_multi_vm_compilation_e2e () =
  let rng = Random.State.make [| 5877 |] in
  let asm = {|
    mov x0, #10
    add x0, x0, #5
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift: " ^ err)
  | Ok func ->
      let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
      let temp_dir = "/tmp/asgard_multi_vm_test" in
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" temp_dir) in
      let hdr_file = Filename.concat temp_dir "multi_vm_runtime.hpp" in
      let oc_h = open_out hdr_file in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;

      let runner_file = Filename.concat temp_dir "runner.cpp" in
      let oc_r = open_out runner_file in
      output_string oc_r pkg.runner_source;
      close_out oc_r;

      let bc_file = Filename.concat temp_dir "bc.cpp" in
      let oc_b = open_out bc_file in
      output_string oc_b "#include <stdint.h>\n#include <stddef.h>\n";
      output_string oc_b "extern \"C\" const uint64_t embedded_bytecode[] = {\n";
      List.iter (fun w -> output_string oc_b (Printf.sprintf "    0x%016LXULL,\n" w)) pkg.bytecode;
      output_string oc_b "};\n";
      output_string oc_b (Printf.sprintf "extern \"C\" const size_t embedded_bytecode_len = %d;\n" (List.length pkg.bytecode));
      close_out oc_b;

      let bin_file = Filename.concat temp_dir "multi_vm_app" in
      let cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s %s -o %s" temp_dir runner_file bc_file bin_file in
      let status = Sys.command cmd in
      check int "Compilation status == 0" 0 status;
      let run_st = Sys.command (Printf.sprintf "%s > /dev/null 2>&1" bin_file) in
      check int "Run status == 0" 0 run_st

let tests = [
  ("Modular Inverse Modulo 2^64", `Quick, test_modular_inverse_64);
  ("Affine Bridge Roundtrip (1000 vectors)", `Quick, test_affine_bridge_roundtrip_1000);
  ("Trace Digest Coupling", `Quick, test_trace_digest_coupling);
  ("AST Functional Partitioning", `Quick, test_ast_functional_partitioning);
  ("Multi-VM C++ E2E Compilation & Exec", `Quick, test_multi_vm_compilation_e2e);
]
