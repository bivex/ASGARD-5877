(* Same asm, same packaging, but WITHOUT any bridge ops in the IR *)
open Multi_vm
let () =
  let asm = {|
    mov x0, #42
    cmp x0, #40
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    add x0, x0, #8
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.eprintf "lift failed: %s\n" e; exit 1
  | Ok func ->
      let cfg = Native_vm.Protection_config.default in
      let rng = Random.State.make [| 9292 |] in
      let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false
        ~enable_mba:false ~mba_depth:2 ~config:cfg func in
      (* strip every Bridge op from bytecode-ir by repackaging a func with zero bridges:
         simulate by re-lifting and blanking partition transitions *)
      let rep = Partitioner.partition_function func in
      let zero_rep = { rep with Partitioner.inter_vm_transitions = 0 } in
      (* manually: bridge-free func = original; but compile_and_package always injects.
         Instead call the native emitter directly on the ORIGINAL func. *)
      let native_pkg = Native_vm.Vm_emitter.compile_and_package ~rng
        ~enable_cff:false ~enable_mba:false ~mba_depth:2 ~config:cfg func in
      let dir = "/tmp/asg_iso" in
      ignore (Sys.command ("rm -rf " ^ dir));
      Unix.mkdir dir 0o755;
      let oc = open_out (dir ^ "/threaded_vm.hpp") in
      output_string oc native_pkg.cpp_runtime_source; close_out oc;
      let oc = open_out (dir ^ "/runner.cpp") in
      output_string oc native_pkg.runner_source; close_out oc;
      (match native_pkg.bytecode with
      | _ -> ());
      (* native pkg runner embeds bytecode itself? check runner source *)
      let bc = Buffer.create 1024 in
      Buffer.add_string bc "#include <stdint.h>\n#include <stddef.h>\n";
      Buffer.add_string bc "extern \"C\" const uint64_t embedded_bytecode[] = {\n";
      List.iter (fun w -> Buffer.add_string bc (Printf.sprintf "  0x%016LXULL,\n" w)) native_pkg.bytecode;
      Buffer.add_string bc "};\n";
      Buffer.add_string bc (Printf.sprintf "extern \"C\" const size_t embedded_bytecode_len = %d;\n" (List.length native_pkg.bytecode));
      let oc = open_out (dir ^ "/bc.cpp") in output_string oc (Buffer.contents bc); close_out oc;
      let st = Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp %s/bc.cpp -o %s/app 2>%s/e.txt" dir dir dir dir dir) in
      if st <> 0 then begin
        let ic = open_in (dir ^ "/e.txt") in
        let e = really_input_string ic (in_channel_length ic) in close_in ic;
        Printf.eprintf "compile failed:\n%s\n" e; exit 1
      end;
      let ic = Unix.open_process_in (dir ^ "/app") in
      (try while true do print_endline (input_line ic) done with End_of_file -> ());
      close_in ic
