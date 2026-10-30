(* Single-block asm; adjacent Bridge pair must be identity. Expect RAX=15. *)
open Multi_vm
let run ~label (cfg : Native_vm.Protection_config.t) =
  let asm = {|
    mov x0, #10
    add x0, x0, #5
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.printf "%s: lift fail %s\n" label e
  | Ok func ->
      let rng = Random.State.make [| 5877 |] in
      (try
        let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false
          ~enable_mba:cfg.mba.enabled ~mba_depth:cfg.mba.depth ~config:cfg func in
        let dir = "/tmp/asg_rt" in
        ignore (Sys.command ("rm -rf " ^ dir));
        Unix.mkdir dir 0o755;
        let oc = open_out (dir ^ "/multi_vm_runtime.hpp") in output_string oc pkg.cpp_runtime_source; close_out oc;
        let oc = open_out (dir ^ "/runner.cpp") in output_string oc pkg.runner_source; close_out oc;
        ignore (Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp -o %s/app 2>%s/e.txt" dir dir dir dir));
        if Sys.file_exists (dir ^ "/app") then begin
          let ic = Unix.open_process_in (dir ^ "/app") in
          let buf = Buffer.create 128 in
          (try while true do Buffer.add_string buf (input_line ic); Buffer.add_char buf '\n' done with End_of_file -> ());
          close_in ic;
          let s = Buffer.contents buf in
          let rax = try
            let re = Str.regexp "Result (RAX): \\([0-9]+\\)" in
            ignore (Str.search_forward re s 0); int_of_string (Str.matched_group 1 s)
          with _ -> (-1) in
          Printf.printf "%-28s RAX=%d %s\n" label rax (if rax = 15 then "OK" else "*** CORRUPT ***")
        end else Printf.printf "%-28s BUILD FAILED\n" label
      with e -> Printf.printf "%-28s EXN %s\n" label (Printexc.to_string e))

let () =
  let open Native_vm.Protection_config in
  let base = default in
  run ~label:"default" base;
  let b = ref { base with vm_runtime = { base.vm_runtime with enable_super_operators = false } } in
  run ~label:"no-superop" !b;
  b := { !b with vm_runtime = { !b.vm_runtime with enable_junk_instructions = false } };
  run ~label:"no-superop+junk" !b;
  b := { !b with anti_pushan = { !b.anti_pushan with running_key = false } };
  run ~label:"..+no-running-key" !b;
  b := { !b with vm_runtime = { !b.vm_runtime with ephemeral_jit = false } };
  run ~label:"..+no-ephemeral-jit" !b;
  b := { !b with vm_runtime = { !b.vm_runtime with chameleon_handlers = false; num_dispatch_domains = 1 } };
  run ~label:"..+no-chameleon" !b;
  b := { !b with vm_runtime = { !b.vm_runtime with egraph_expansion = false } };
  run ~label:"..+no-egraph" !b;
  b := { !b with mba = { !b.mba with enabled = false } };
  run ~label:"..+no-mba" !b;
  b := { !b with vm_runtime = { !b.vm_runtime with oblivious_memory = false; stack_scrambling = false; memory_sanitization = false } };
  run ~label:"..+bare-vm_runtime" !b;
  b := { !b with anti_pushan = { !b.anti_pushan with address_bound = false } };
  run ~label:"..+no-addr-bound" !b;
  b := { !b with bloat = { !b.bloat with junk_density = 0.0 } };
  run ~label:"..+no-bloat" !b
