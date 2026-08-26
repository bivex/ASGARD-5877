open Random_visa_domain
open Random_visa_c11_emitter

let test_c11_fail_fast_on_widening () =
  let inst =
    Vector_instruction.make
      ~mnemonic:"vwadd_vv"
      ~format:Types.Instruction_format.OP_WIDENING
      ~funct6:0
      ~funct3:0
      ~binary_op:Types.Binary_op.ADD
      ~is_widening:true
      ()
  in
  match Vector_config.make () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok config ->
      match Vector_isa_spec.of_instructions ~name:"WideSpec" ~config [ inst ] with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          let tmp_dir = Filename.temp_file "c11_fail_" "_dir" in
          (try Sys.remove tmp_dir with _ -> ());
          let res = C11_emitter_adapter.emit_c_project ~allow_widening:false spec ~output_dir:tmp_dir in
          Alcotest.(check bool) "fails fast on widening" true (Result.is_error res);
          match res with
          | Error (Errors.Unsupported_backend_feature msg) ->
              Alcotest.(check bool) "mentions widening" true (String.contains msg 'w')
          | _ -> Alcotest.fail "Expected Unsupported_backend_feature"

let test_c11_compilation_and_execution () =
  let rng = Random.State.make [| 77 |] in
  match
    Generation_profile.make
      ~name:"nowide"
      ~class_weights:[
        (Instruction_class.Arith, 60.0);
        (Instruction_class.Saturating, 20.0);
        (Instruction_class.Compare, 20.0);
      ]
  with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok profile ->
      match Isa_grammar.generate_isa ~rng ~name:"C11_ISA" ~profile ~num_instructions:6 () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          let tmp_dir = Filename.temp_file "c11_emu_" "_dir" in
          (try Sys.remove tmp_dir with _ -> ());
          (try Sys.mkdir tmp_dir 0o755 with _ -> ());

          (match C11_emitter_adapter.emit_c_project spec ~output_dir:tmp_dir with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok files ->
              Alcotest.(check bool) "emitted 5 files" true (List.length files = 5);
              List.iter
                (fun f -> Alcotest.(check bool) (Printf.sprintf "file exists: %s" f) true (Sys.file_exists f))
                files);

          (* Compile using clang or make *)
          let compile_cmd = Printf.sprintf "clang -std=c11 -O2 -Wall -Wextra -I%s %s/visa_emulator.c %s/visa_instructions.c %s/main.c -o %s/visa_c11_runner" tmp_dir tmp_dir tmp_dir tmp_dir tmp_dir in
          let compile_res = Sys.command compile_cmd in
          Alcotest.(check int) "clang compilation exit code" 0 compile_res;

          (* Execute runner *)
          let run_cmd = Printf.sprintf "%s/visa_c11_runner" tmp_dir in
          let ic = Unix.open_process_in run_cmd in
          let buf = Buffer.create 512 in
          (try
             while true do
               Buffer.add_string buf (input_line ic);
               Buffer.add_char buf '\n'
             done
           with End_of_file -> ());
          let status = Unix.close_process_in ic in
          Alcotest.(check bool) "runner exited cleanly" true (status = Unix.WEXITED 0);
          let output = Buffer.contents buf in
          Alcotest.(check bool) "contains ALL C11 EMULATOR TESTS PASSED" true
            (let len = String.length "=== ALL C11 EMULATOR TESTS PASSED" in
             let text_len = String.length output in
             let rec find_sub i =
               if i + len > text_len then false
               else if String.sub output i len = "=== ALL C11 EMULATOR TESTS PASSED" then true
               else find_sub (i + 1)
             in
             find_sub 0);

          let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
          ()

let tests = [
  Alcotest.test_case "c11_fail_fast_on_widening" `Quick test_c11_fail_fast_on_widening;
  Alcotest.test_case "c11_compilation_and_execution" `Slow test_c11_compilation_and_execution;
]
