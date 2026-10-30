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
  | Error e -> Printf.eprintf "lift: %s\n" e; exit 1
  | Ok func ->
      let cfg = Native_vm.Protection_config.default in
      let rng = Random.State.make [| 5 |] in
      let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false
        ~enable_mba:cfg.mba.enabled ~mba_depth:cfg.mba.depth ~config:cfg func in
      let dir = "/tmp/asg_s5" in
      ignore (Sys.command ("rm -rf " ^ dir));
      Unix.mkdir dir 0o755;
      let oc = open_out (dir ^ "/multi_vm_runtime.hpp") in output_string oc pkg.cpp_runtime_source; close_out oc;
      let oc = open_out (dir ^ "/runner.cpp") in output_string oc pkg.runner_source; close_out oc;
      let oc = open_out (dir ^ "/bytecode.txt") in
      List.iter (fun w -> output_string oc (Printf.sprintf "%016LX\n" w)) pkg.bytecode;
      close_out oc;
      ignore (Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp -o %s/app 2>%s/e.txt" dir dir dir dir));
      let ic = Unix.open_process_in (dir ^ "/app") in
      (try while true do print_endline (input_line ic) done with End_of_file -> ());
      close_in ic
