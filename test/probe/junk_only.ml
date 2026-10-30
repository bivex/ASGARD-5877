open Multi_vm
let run ~label ?(seed=5) (cfg : Native_vm.Protection_config.t) =
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
  | Error e -> Printf.printf "%s: lift fail\n" label
  | Ok func ->
      let rng = Random.State.make [| seed |] in
      let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false
        ~enable_mba:cfg.Native_vm.Protection_config.mba.enabled
        ~mba_depth:cfg.Native_vm.Protection_config.mba.depth ~config:cfg func in
      let dir = "/tmp/asg_jo" in
      ignore (Sys.command ("rm -rf " ^ dir));
      Unix.mkdir dir 0o755;
      let oc = open_out (dir ^ "/multi_vm_runtime.hpp") in output_string oc pkg.cpp_runtime_source; close_out oc;
      let oc = open_out (dir ^ "/runner.cpp") in output_string oc pkg.runner_source; close_out oc;
      ignore (Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp -o %s/app 2>%s/e.txt" dir dir dir dir));
      let ic = Unix.open_process_in (dir ^ "/app") in
      let buf = Buffer.create 128 in
      (try while true do Buffer.add_string buf (input_line ic); Buffer.add_char buf '\n' done with End_of_file -> ());
      close_in ic;
      let s = Buffer.contents buf in
      let rax = try
        let re = Str.regexp "Result (RAX): \\([0-9]+\\)" in
        ignore (Str.search_forward re s 0); Str.matched_group 1 s
      with _ -> "?" in
      Printf.printf "%-34s RAX=%s %s\n" label rax (if rax = "50" then "OK" else "*** CORRUPT ***")

let () =
  let open Native_vm.Protection_config in
  let bare cfg = { cfg with
    vm_runtime = { cfg.vm_runtime with enable_super_operators = false; enable_junk_instructions = false;
                                       chameleon_handlers = false; num_dispatch_domains = 1;
                                       egraph_expansion = false; stack_scrambling = false;
                                       oblivious_memory = false; memory_sanitization = false; ephemeral_jit = false };
    anti_pushan = { cfg.anti_pushan with running_key = false; address_bound = false };
    mba = { cfg.mba with enabled = false };
    bloat = { cfg.bloat with junk_density = 0.5 } } in
  let b = bare default in
  run ~label:"bare (junk off)" b;
  run ~label:"bare + junk ON" { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed1" ~seed:1 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed2" ~seed:2 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed3" ~seed:3 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed4" ~seed:4 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed6" ~seed:6 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed7" ~seed:7 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  run ~label:"bare + junk ON seed8" ~seed:8 { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } };
  let j = { b with vm_runtime = { b.vm_runtime with enable_junk_instructions = true } } in
  run ~label:"mba-ONLY (junk off)" { b with mba = { b.mba with enabled = true } };
  run ~label:"mba-ONLY seed1" ~seed:1 { b with mba = { b.mba with enabled = true } };
  run ~label:"mba-ONLY seed2" ~seed:2 { b with mba = { b.mba with enabled = true } };
  run ~label:"mba-ONLY seed3" ~seed:3 { b with mba = { b.mba with enabled = true } };
  run ~label:"mba-ONLY seed6" ~seed:6 { b with mba = { b.mba with enabled = true } };
  run ~label:"mba+junk seed1" ~seed:1 j;
  run ~label:"mba+junk seed2" ~seed:2 j;
  run ~label:"mba+junk seed3" ~seed:3 j;
  run ~label:"mba+junk seed6" ~seed:6 j;
  run ~label:"mba+junk seed7" ~seed:7 j;
  run ~label:"mba+junk seed8" ~seed:8 j;
  run ~label:"junk+superop" { j with vm_runtime = { j.vm_runtime with enable_super_operators = true } };
  run ~label:"junk+chameleon4" { j with vm_runtime = { j.vm_runtime with chameleon_handlers = true; num_dispatch_domains = 4 } };
  run ~label:"junk+egraph-mba" { j with mba = { j.mba with enabled = true } };
  run ~label:"junk+running-key" { j with anti_pushan = { j.anti_pushan with running_key = true } };
  run ~label:"junk+addr-bound" { j with anti_pushan = { j.anti_pushan with address_bound = true } };
  run ~label:"junk+ephemeral" { j with vm_runtime = { j.vm_runtime with ephemeral_jit = true } };
  run ~label:"junk+oblivious" { j with vm_runtime = { j.vm_runtime with oblivious_memory = true } };
  run ~label:"junk+scramble" { j with vm_runtime = { j.vm_runtime with stack_scrambling = true } };
  run ~label:"junk+memsan" { j with vm_runtime = { j.vm_runtime with memory_sanitization = true } };
  (* native threaded engine, same asm, MBA+junk *)
  let asm2 = {|
    mov x0, #42
    cmp x0, #40
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    add x0, x0, #8
    ret
  |} in
  (match Arm64_lifter.lift_function asm2 with
   | Error _ -> print_endline "lift fail"
   | Ok func2 ->
     let cfg = j in
     let rng = Random.State.make [| 5 |] in
     let npkg = Native_vm.Vm_emitter.compile_and_package ~rng ~enable_cff:false
       ~enable_mba:true ~mba_depth:cfg.mba.depth ~config:cfg func2 in
     let dir = "/tmp/asg_nat" in
     ignore (Sys.command ("rm -rf " ^ dir));
     Unix.mkdir dir 0o755;
     let oc = open_out (dir ^ "/threaded_vm.hpp") in output_string oc npkg.cpp_runtime_source; close_out oc;
     let oc = open_out (dir ^ "/runner.cpp") in output_string oc npkg.runner_source; close_out oc;
     let bc = Buffer.create 512 in
     Buffer.add_string bc "#include <stdint.h>\n#include <stddef.h>\n";
     Buffer.add_string bc "extern \"C\" const uint64_t embedded_bytecode[] = {\n";
     List.iter (fun w -> Buffer.add_string bc (Printf.sprintf "  0x%016LXULL,\n" w)) npkg.bytecode;
     Buffer.add_string bc "};\n";
     Buffer.add_string bc (Printf.sprintf "extern \"C\" const size_t embedded_bytecode_len = %d;\n" (List.length npkg.bytecode));
     let oc = open_out (dir ^ "/bc.cpp") in output_string oc (Buffer.contents bc); close_out oc;
     ignore (Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp %s/bc.cpp -o %s/app 2>%s/e.txt" dir dir dir dir dir));
     let ic = Unix.open_process_in (dir ^ "/app") in
     let buf = Buffer.create 128 in
     (try while true do Buffer.add_string buf (input_line ic); Buffer.add_char buf '\n' done with End_of_file -> ());
     close_in ic;
     let s2 = Buffer.contents buf in
     (try
        let re = Str.regexp "RAX: \([0-9]+\)" in
        ignore (Str.search_forward re s2 0);
        let rax = Str.matched_group 1 s2 in
        Printf.printf "%-34s RAX=%s %s\n" "NATIVE junk+mba" rax (if rax = "50" then "OK" else "*** CORRUPT ***")
      with _ -> Printf.printf "NATIVE junk+mba: output=%s\n" s2))
