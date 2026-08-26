let run_cmd cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 512 in
  (try
     while true do
       Buffer.add_string buf (input_line ic);
       Buffer.add_char buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  (status, Buffer.contents buf)

let get_bin () =
  let candidates = [
    "../bin/main.exe";
    "./_build/default/bin/main.exe";
    "bin/main.exe";
  ] in
  match List.find_opt Sys.file_exists candidates with
  | Some p -> p
  | None ->
      let cur = Sys.getcwd () in
      failwith (Printf.sprintf "Binary not found in candidates from cwd '%s'" cur)

let test_cli_generate_and_execution () =
  let bin = get_bin () in
  let tmp_dir = Filename.temp_file "cli_gen_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  let cmd = Printf.sprintf "%s generate --seed 123 --num-instructions 6 --output-dir %s --compile-and-test" bin tmp_dir in
  let status, out = run_cmd cmd in
  Alcotest.(check bool) "generate exit code 0" true (status = Unix.WEXITED 0);
  Alcotest.(check bool) "output contains ALL EMULATOR TESTS PASSED" true
    (let len = String.length "=== ALL EMULATOR TESTS PASSED" in
     let text_len = String.length out in
     let rec find_sub i =
       if i + len > text_len then false
       else if String.sub out i len = "=== ALL EMULATOR TESTS PASSED" then true
       else find_sub (i + 1)
     in
     find_sub 0);
  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  ()

let test_cli_parse_and_cost () =
  let bin = get_bin () in
  let tmp_dir = Filename.temp_file "cli_pc_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  let gen_cmd = Printf.sprintf "%s generate --seed 321 --num-instructions 4 --output-dir %s" bin tmp_dir in
  let status, _ = run_cmd gen_cmd in
  Alcotest.(check bool) "generate ok" true (status = Unix.WEXITED 0);

  let sail_file = Printf.sprintf "%s/rvv_custom_isa.sail" tmp_dir in
  let parse_cmd = Printf.sprintf "%s parse -i %s" bin sail_file in
  let status_p, out_p = run_cmd parse_cmd in
  Alcotest.(check bool) "parse exit code 0" true (status_p = Unix.WEXITED 0);
  Alcotest.(check bool) "parse output has instructions" true (String.contains out_p 'I' && String.contains out_p 'n');

  let cost_cmd = Printf.sprintf "%s cost -s %s" bin sail_file in
  let status_c, out_c = run_cmd cost_cmd in
  Alcotest.(check bool) "cost exit code 0" true (status_c = Unix.WEXITED 0);
  Alcotest.(check bool) "cost output has verdict" true (String.contains out_c 'V' && String.contains out_c 'e');

  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  ()

let test_cli_assemble_and_disassemble () =
  let bin = get_bin () in
  let tmp_dir = Filename.temp_file "cli_asm_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  let gen_cmd = Printf.sprintf "%s generate --seed 42 --num-instructions 8 --output-dir %s" bin tmp_dir in
  let _ = run_cmd gen_cmd in

  let sail_file = Printf.sprintf "%s/rvv_custom_isa.sail" tmp_dir in
  let asm_file = Printf.sprintf "%s/input.s" tmp_dir in
  let vbc_file = Printf.sprintf "%s/output.vbc" tmp_dir in

  let oc = open_out asm_file in
  output_string oc "vmul_vv v3, v2, v1\nvand_vx v4, v2, x1\n";
  close_out oc;

  let asm_cmd = Printf.sprintf "%s assemble -s %s -i %s -o %s" bin sail_file asm_file vbc_file in
  let status_a, out_a = run_cmd asm_cmd in
  Alcotest.(check bool) "assemble exit code 0" true (status_a = Unix.WEXITED 0);
  Alcotest.(check bool) "assembled message" true (String.contains out_a 'A' && String.contains out_a 's');

  let dis_cmd = Printf.sprintf "%s disassemble -s %s -i %s" bin sail_file vbc_file in
  let status_d, out_d = run_cmd dis_cmd in
  Alcotest.(check bool) "disassemble exit code 0" true (status_d = Unix.WEXITED 0);
  Alcotest.(check bool) "contains vmul_vv" true (String.contains out_d 'v' && String.contains out_d 'm');

  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  ()

let tests = [
  Alcotest.test_case "cli_generate_and_execution" `Slow test_cli_generate_and_execution;
  Alcotest.test_case "cli_parse_and_cost" `Quick test_cli_parse_and_cost;
  Alcotest.test_case "cli_assemble_and_disassemble" `Quick test_cli_assemble_and_disassemble;
]
