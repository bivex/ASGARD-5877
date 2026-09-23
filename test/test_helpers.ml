(** Test_helpers — Shared test utilities for ASGARD-5877 verification suite. *)

let with_temp_dir f =
  let tmp_dir = Filename.temp_file "asgard_test_" "" in
  (try Sys.remove tmp_dir with Sys_error _ -> ());
  Sys.mkdir tmp_dir 0o755;
  let res =
    try f tmp_dir
    with exn ->
      (try ignore (Sys.command (Printf.sprintf "rm -rf %s" tmp_dir)) with Sys_error _ -> ());
      raise exn
  in
  (try ignore (Sys.command (Printf.sprintf "rm -rf %s" tmp_dir)) with Sys_error _ -> ());
  res

let read_file_string path =
  let ic = open_in path in
  let len = in_channel_length ic in
  let content = really_input_string ic len in
  close_in ic;
  content

let write_file_string path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let write_bytecode_bin path (words : int64 list) =
  let oc = open_out_bin path in
  List.iter
    (fun w ->
      for i = 0 to 7 do
        let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
        output_byte oc b
      done)
    words;
  close_out oc

let run_command_capture cmd =
  let ic = Unix.open_process_in cmd in
  let out_buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (status, Buffer.contents out_buf)

(* Compile a threaded-VM package's generated runtime + runner into an executable. *)
let compile_and_prepare_vm tmp_dir (pkg : Native_vm.Vm_emitter.vm_package) =
  let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
  write_file_string hdr_path pkg.cpp_runtime_source;
  let runner_path = Filename.concat tmp_dir "runner.cpp" in
  write_file_string runner_path pkg.runner_source;
  let bin_path = Filename.concat tmp_dir "runner" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path in
  let comp_status = Sys.command comp_cmd in
  Alcotest.(check int) "clang++ compilation succeeds" 0 comp_status;
  bin_path

(* Custom-runner helper for several packages inside one temp dir: each package
   gets its own header/runner/binary named after [name], so independent VM
   images (different key material) coexist without clobbering each other. *)
let run_custom_vm ~(name : string) tmp_dir (pkg : Native_vm.Vm_emitter.vm_package) (checks_body : string) =
  let hdr_path = Filename.concat tmp_dir (name ^ "_vm.hpp") in
  write_file_string hdr_path pkg.cpp_runtime_source;
  let custom_runner =
    Printf.sprintf {|
#include "%s_vm.hpp"
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static uint64_t embedded_bytecode[] = {
%s
};

int main() {
    size_t count = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
%s
    return 0;
}
|}
      name
      (String.concat "\n" (List.map (fun w -> Printf.sprintf "    0x%016LXULL," w) pkg.bytecode))
      checks_body
  in
  let runner_path = Filename.concat tmp_dir (name ^ "_runner.cpp") in
  write_file_string runner_path custom_runner;
  let bin_path = Filename.concat tmp_dir name in
  let comp_status =
    Sys.command (Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path)
  in
  Alcotest.(check int) (name ^ ": clang++ compilation succeeds") 0 comp_status;
  let status, _ = run_command_capture bin_path in
  Alcotest.(check bool) (name ^ ": runner exits 0") true (status = Unix.WEXITED 0)


