open X86_lifter
open Native_vm

(** Tests for Anti-Pushan Protection: Execution-History Coupled Rolling Key.
    Pushan assumes static / constraint-free block emulation where opcodes are
    stateless. ASGARD couples every instruction dispatch to a dynamic running key
    mutated by prior execution history. *)

let compile_and_run ~tmp_prefix pkg =
  let tmp_dir = Filename.temp_file tmp_prefix "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  (try Sys.mkdir tmp_dir 0o755 with _ -> ());

  let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
  let oc_h = open_out hdr_path in
  output_string oc_h pkg.Vm_emitter.cpp_runtime_source;
  close_out oc_h;

  let runner_path = Filename.concat tmp_dir "runner.cpp" in
  let oc_r = open_out runner_path in
  output_string oc_r pkg.Vm_emitter.runner_source;
  close_out oc_r;

  let bin_path = Filename.concat tmp_dir "runner" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path in
  let comp_status = Sys.command comp_cmd in
  if comp_status <> 0 then Alcotest.fail "clang++ compilation failed";

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
  (status, Buffer.contents out_buf)

let test_running_key_advances_on_execution () =
  let rng = Random.State.make [| 0x1337 |] in
  let asm = {|
func_key_test:
    mov rax, 100
    add rax, 50
    sub rax, 10
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng func in
      let status, out_str = compile_and_run ~tmp_prefix:"anti_pushan_adv_" pkg in
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      (* 100 + 50 - 10 = 140 *)
      Alcotest.(check bool) "rax is 140" true (String.contains out_str '1' && String.contains out_str '4' && String.contains out_str '0')

let test_loop_history_soundness () =
  let rng = Random.State.make [| 0x5877 |] in
  let asm = {|
func_loop_fact:
    mov rax, 1
    mov rcx, 5
.Lloop:
    imul rax, rcx
    sub rcx, 1
    cmp rcx, 0
    jne .Lloop
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:false func in
      let status, out_str = compile_and_run ~tmp_prefix:"anti_pushan_loop_" pkg in
      Alcotest.(check bool) "loop execution succeeds" true (status = Unix.WEXITED 0);
      (* 5! = 120 *)
      Alcotest.(check bool) "rax is 120 (5!)" true (String.contains out_str '1' && String.contains out_str '2' && String.contains out_str '0')

let test_branch_path_history_diversity () =
  let rng = Random.State.make [| 0x9999 |] in
  let asm = {|
func_branch_div:
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
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:true func in
      let status, out_str = compile_and_run ~tmp_prefix:"anti_pushan_branch_" pkg in
      Alcotest.(check bool) "branch execution succeeds" true (status = Unix.WEXITED 0);
      (* 42 < 50 -> rax = 42 + 2000 = 2042 *)
      Alcotest.(check bool) "rax is 2042" true (String.contains out_str '2' && String.contains out_str '0' && String.contains out_str '4')

let tests = [
  Alcotest.test_case "running_key_advances_on_execution" `Quick test_running_key_advances_on_execution;
  Alcotest.test_case "loop_history_soundness" `Quick test_loop_history_soundness;
  Alcotest.test_case "branch_path_history_diversity" `Quick test_branch_path_history_diversity;
]
