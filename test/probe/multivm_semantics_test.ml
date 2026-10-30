(* Probe: does multi-block cross-engine bridging preserve semantics? *)
open Multi_vm

let compile_and_run ~seed ~name (asm : string) : string * int =
  let rng = Random.State.make [| seed |] in
  match Arm64_lifter.lift_function asm with
  | Error err -> failwith ("lift failed: " ^ err)
  | Ok func ->
      let pkg = Multi_vm_emitter.compile_and_package ~rng ~enable_cff:false ~enable_mba:false func in
      Printf.eprintf "%s: transitions=%d math=%d flow=%d mem=%d\n%!" name
        pkg.partition.inter_vm_transitions pkg.partition.math_blocks
        pkg.partition.flow_blocks pkg.partition.memory_blocks;
      let dir = Filename.get_temp_dir_name () ^ "/asg_mv_" ^ name in
      (try Sys.rmdir dir with _ -> ());
      (try Unix.mkdir dir 0o755 with _ -> ());
      let oc_h = open_out (dir ^ "/multi_vm_runtime.hpp") in
      output_string oc_h pkg.cpp_runtime_source; close_out oc_h;
      let oc_r = open_out (dir ^ "/runner.cpp") in
      output_string oc_r pkg.runner_source; close_out oc_r;
      let oc_b = open_out (dir ^ "/bc.cpp") in
      output_string oc_b "#include <stdint.h>\n#include <stddef.h>\n";
      output_string oc_b "extern \"C\" const uint64_t embedded_bytecode[] = {\n";
      List.iter (fun w -> output_string oc_b (Printf.sprintf "  0x%016LXULL,\n" w)) pkg.bytecode;
      output_string oc_b "};\n";
      output_string oc_b (Printf.sprintf "extern \"C\" const size_t embedded_bytecode_len = %d;\n" (List.length pkg.bytecode));
      close_out oc_b;
      let cmd = Printf.sprintf "clang++ -std=c++20 -O0 -I%s %s/runner.cpp -o %s/app 2>%s/err.txt" dir dir dir dir in
      let st = Sys.command cmd in
      if st <> 0 then (let ic = open_in (dir^"/err.txt") in let e = really_input_string ic (in_channel_length ic) in close_in ic; failwith ("compile failed: " ^ e));
      let ic = Unix.open_process_in (dir ^ "/app") in
      let out = Buffer.create 256 in
      (try while true do Buffer.add_string out (input_line ic); Buffer.add_char out '\n' done with End_of_file -> ());
      close_in ic;
      let s = Buffer.contents out in
      let rax = try
        let (>>=) = Option.bind in
        let re = Str.regexp "Result (RAX): \\([0-9]+\\)" in
        (match Str.search_forward re s 0 with
         | i -> int_of_string (Str.matched_group 1 s)
         | exception Not_found -> -1)
      with _ -> -1 in
      (s, rax)

let () =
  (* Case 1: single block — expected roundtrip identity *)
  let (out1, rax1) = compile_and_run ~seed:5877 ~name:"single" {|
    mov x0, #10
    add x0, x0, #5
    ret
  |} in
  Printf.printf "Case1 single-block: RAX=%d (expect 15)\n" rax1;

  (* Case 2: multi-block branch — cross-engine transitions *)
  let (out2, rax2) = compile_and_run ~seed:9292 ~name:"branch" {|
    mov x0, #42
    cmp x0, #40
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    add x0, x0, #8
    ret
  |} in
  Printf.printf "Case2 branch: RAX=%d (expect 50)\n" rax2;
  print_string out2
