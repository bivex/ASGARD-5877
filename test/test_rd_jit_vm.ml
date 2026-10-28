open Alcotest
open Vm_ir
open Rd_jit_vm

let contains_sub (s : string) (sub : string) : bool =
  let n = String.length s and m = String.length sub in
  if m = 0 then true
  else
    let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
    go 0

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
      Test_helpers.with_temp_dir (fun temp_dir ->
        let hdr_file = Filename.concat temp_dir "rd_jit_runtime.hpp" in
        Test_helpers.write_file_string hdr_file pkg.cpp_runtime_source;
        let runner_file = Filename.concat temp_dir "runner.cpp" in
        Test_helpers.write_file_string runner_file pkg.runner_source;
        let bin_file = Filename.concat temp_dir "rd_jit_app" in
        let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" temp_dir runner_file bin_file in
        let status = Sys.command cmd in
        check int "RD JIT Compilation status == 0" 0 status;
        let run_st, _ = Test_helpers.run_command_capture (Printf.sprintf "%s 42 58" bin_file) in
        check bool "RD JIT Run status == 0" true (run_st = Unix.WEXITED 0))

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
      Test_helpers.with_temp_dir (fun temp_dir ->
        let hdr_file = Filename.concat temp_dir "jit_vm_runtime.hpp" in
        Test_helpers.write_file_string hdr_file pkg.cpp_runtime_source;
        let runner_file = Filename.concat temp_dir "runner.cpp" in
        Test_helpers.write_file_string runner_file pkg.runner_source;
        let bin_file = Filename.concat temp_dir "rd_jit_multi_app" in
        let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" temp_dir runner_file bin_file in
        let status = Sys.command cmd in
        check int "RD JIT Multi-Op Compilation status == 0" 0 status;
        let run_st, out_str = Test_helpers.run_command_capture bin_file in
        check bool "RD JIT Multi-Op Run status == 0" true (run_st = Unix.WEXITED 0);
        (* 50 + 30 = 80, 80 - 15 = 65: the sealed pipeline must reproduce
           the exact value of REG 0, not merely produce output. *)
        let expected = "Result (REG 0): 65 (0x41)" in
        check bool "Exact REG 0 result 65" true (contains_sub out_str expected))

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
      let compile_cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s -o %s" tmp_dir runner_file bin_file in
      check int "RD-JIT extern compilation" 0 (Sys.command compile_cmd);
      let log_file = Filename.concat tmp_dir "out.log" in
      check int "RD-JIT extern execution" 0 (Sys.command (Printf.sprintf "%s > %s 2>&1" bin_file log_file));
      let output = Test_helpers.read_file_string log_file in
      check bool "RD-JIT extern result" true (contains_sub output "Result (REG 0): 7 (0x7)"))

let test_nano_oeis_invariants () =
  let module N = Rd_jit_vm.Nano_jit_slot in
  (* A000002: Kolakoski word *)
  check bool "Kolakoski prefix" true
    (N.kolakoski 20 = [| 1; 2; 2; 1; 1; 2; 1; 2; 2; 1; 2; 2; 1; 1; 2; 1; 1; 2; 2; 1 |]);
  (* A010060: Thue-Morse parity *)
  check bool "Thue-Morse prefix" true
    ([| false; true; true; false; true |] = Array.init 5 N.thue_morse);
  (* A000695: Moser-de Bruijn roundtrip is exact *)
  let rng = Random.State.make [| 58775 |] in
  let roundtrip_ok = ref true in
  for _ = 1 to 1000 do
    let v = Random.State.int64 rng Int64.max_int in
    if not (Int64.equal (N.moser_unpack (N.moser_pack v)) v) then roundtrip_ok := false
  done;
  check bool "Moser-de Bruijn roundtrip" true !roundtrip_ok;
  (* A000201/A001950: Beatty classification of arena units 0..11 *)
  let real = List.filter N.beatty_is_real (List.init 12 Fun.id) in
  check bool "Beatty real units" true (real = [ 1; 3; 4; 6; 8; 9; 11 ]);
  (* A000166: every derangement is fix-free *)
  let fix_free = ref true in
  Array.iter
    (fun packed ->
      Array.iter
        (fun i -> if N.perm_apply packed i = i then fix_free := false)
        (Array.init 16 Fun.id))
    N.derangement_tables;
  check bool "Derangements fix-free" true !fix_free;
  (* A002487: Stern alphas are odd units of Z_2^64 *)
  let all_odd = Array.for_all (fun a -> Int64.logand a 1L = 1L) N.stern_alphas in
  check bool "Stern alphas odd" true all_odd;
  (* A003022: Golomb marks give pairwise distinct slot distances *)
  let marks = List.map Int64.to_int (Array.to_list N.golomb5_marks) in
  let diffs =
    List.concat_map
      (fun i -> List.filter_map
          (fun j -> if j > i then Some (j - i) else None)
          marks)
      marks
  in
  check bool "Golomb distances distinct" true
    (List.length diffs = List.length (List.sort_uniq compare diffs))

let test_nano_sealed_package_shape () =
  let rng = Random.State.make [| 2601 |] in
  let asm = {|
    mov x0, #11
    mov x1, #22
    add x0, x0, x1
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift ARM64: " ^ err)
  | Ok func ->
      let pkg = Rd_jit_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
      (* The runner carries sealed artifacts only: no plaintext JIT block
         descriptors may leak the opcode stream into the binary. *)
      check bool "Runner has sealed tickets" true
        (contains_sub pkg.runner_source "g_nano_tickets");
      check bool "Runner has blob table" true
        (contains_sub pkg.runner_source "g_nano_blobs");
      check bool "No plaintext jit_blocks" true
        (not (contains_sub pkg.runner_source "jit_blocks"));
      (* The runtime header embeds the nano-arena controller. *)
      check bool "Header has nano arena" true
        (contains_sub pkg.cpp_runtime_source "asgard::nano_jit");
      check bool "Header has Padovan regions" true
        (contains_sub pkg.cpp_runtime_source "PADOVAN_CODE_FRAC")



let tests = [
  ("RD JIT RNS Moduli Invariants", `Quick, test_rd_jit_rns_moduli);
  ("RD JIT Package Code Generation", `Quick, test_rd_jit_package_generation);
  ("RD JIT Ephemeral Execution E2E", `Quick, test_rd_jit_cpp_compilation_e2e);
  ("RD JIT Multi-Op Ephemeral Execution E2E", `Quick, test_rd_jit_multi_op_arithmetic_e2e);
  ("RD JIT CALL_EXTERN E2E", `Quick, test_rd_jit_call_extern_e2e);
  ("RD JIT Nano-OEIS Invariants", `Quick, test_nano_oeis_invariants);
  ("RD JIT Sealed Package Shape", `Quick, test_nano_sealed_package_shape);
]
