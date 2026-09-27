open Random_visa_domain
open Random_visa_cpp_emitter
open Random_visa_compiler_adapter

let test_cpp_emulator_compilation_and_execution () =
  let rng = Random.State.make [| 42 |] in
  match Isa_grammar.generate_isa ~rng ~name:"E2E_ISA" ~num_instructions:8 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      Test_helpers.with_temp_dir (fun tmp_dir ->
        (match Cpp_emitter_adapter.emit_emulator_project spec ~output_dir:tmp_dir with
        | Error err -> Alcotest.fail (Errors.to_string err)
        | Ok emitted_files ->
            Alcotest.(check bool) "emitted files >= 7" true (List.length emitted_files >= 7);
            List.iter
              (fun path -> Alcotest.(check bool) (Printf.sprintf "file exists %s" path) true (Sys.file_exists path))
              emitted_files);

        (match Compiler_adapter.compile ~project_dir:tmp_dir with
        | Error err -> Alcotest.fail (Errors.to_string err)
        | Ok () -> ());

        (match Compiler_adapter.run_tests ~project_dir:tmp_dir with
        | Error err -> Alcotest.fail (Errors.to_string err)
        | Ok output ->
            Alcotest.(check bool) "contains ALL EMULATOR TESTS PASSED" true
              (let len = String.length "=== ALL EMULATOR TESTS PASSED" in
               let text_len = String.length output in
               let rec find_sub i =
                 if i + len > text_len then false
                 else if String.sub output i len = "=== ALL EMULATOR TESTS PASSED" then true
                 else find_sub (i + 1)
               in
               find_sub 0)))

let tests = [
  Alcotest.test_case "cpp_emulator_compilation_and_execution" `Slow test_cpp_emulator_compilation_and_execution;
]
