(* Replicate the pipeline's Multi-VM packaging exactly, then run the emitted runner *)
open Multi_vm
let () =
  let asm_path = Sys.argv.(1) in
  let ic = open_in asm_path in
  let asm = really_input_string ic (in_channel_length ic) in
  close_in ic;
  match Protect_adapters.Arm64_lifter_adapter.lift_source asm with
  | Error e -> Printf.eprintf "lift failed: %s\n" e; exit 1
  | Ok (wrapped, _c) ->
    let func : Vm_ir.Ir.func =
      match Random_visa_ports.Protect_ports.unwrap_multi_ir wrapped with
      | [ (_, f) ] -> f
      | _ -> Printf.eprintf "expected single func\n"; exit 1 in
      let native_cfg = Native_vm.Protection_config.default in
      let rng = Random.State.make [| 1337 |] in
      let pkg = Multi_vm_emitter.compile_and_package
        ~rng ~enable_cff:false ~enable_mba:native_cfg.mba.enabled
        ~mba_depth:native_cfg.mba.depth
        ~config:native_cfg func in
      Printf.printf "transitions=%d math=%d flow=%d mem=%d bytecode=%d words\n%!"
        pkg.partition.inter_vm_transitions pkg.partition.math_blocks
        pkg.partition.flow_blocks pkg.partition.memory_blocks (List.length pkg.bytecode);
      let dir = "/tmp/asg_repl" in
      ignore (Sys.command ("rm -rf " ^ dir));
      Unix.mkdir dir 0o755;
      let oc = open_out (dir ^ "/multi_vm_runtime.hpp") in output_string oc pkg.cpp_runtime_source; close_out oc;
      let oc = open_out (dir ^ "/runner.cpp") in output_string oc pkg.runner_source; close_out oc;
      let oc = open_out (dir ^ "/bc.cpp") in
      output_string oc "#include <stdint.h>\n#include <stddef.h>\n";
      output_string oc "extern \"C\" const uint64_t embedded_bytecode[] = {\n";
      List.iter (fun w -> output_string oc (Printf.sprintf "  0x%016LXULL,\n" w)) pkg.bytecode;
      output_string oc "};\n";
      output_string oc (Printf.sprintf "extern \"C\" const size_t embedded_bytecode_len = %d;\n" (List.length pkg.bytecode));
      close_out oc;
      let st = Sys.command (Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp -o %s/app 2>%s/cc.err" dir dir dir dir) in
      if st <> 0 then begin
        let ic = open_in (dir ^ "/cc.err") in
        let e = really_input_string ic (in_channel_length ic) in close_in ic;
        Printf.eprintf "compile failed:\n%s\n" e; exit 1
      end;
      let ic = Unix.open_process_in (dir ^ "/app") in
      (try while true do print_endline (input_line ic) done with End_of_file -> ());
      close_in ic
