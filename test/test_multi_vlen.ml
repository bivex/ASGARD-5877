open Random_visa_domain
open Random_visa_cpp_emitter
open Random_visa_compiler_adapter

let test_cpp_multi_vlen vlen =
  let rng = Random.State.make [| vlen |] in
  match Vector_config.make ~vlen ~elen:64 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok config ->
      match Isa_grammar.generate_isa ~rng ~name:(Printf.sprintf "VLEN_%d_ISA" vlen) ~config ~num_instructions:4 () with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok spec ->
          let tmp_dir = Filename.temp_file (Printf.sprintf "vlen_%d_" vlen) "_dir" in
          (try Sys.remove tmp_dir with _ -> ());
          (try Sys.mkdir tmp_dir 0o755 with _ -> ());

          (match Cpp_emitter_adapter.emit_emulator_project spec ~output_dir:tmp_dir with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok _ -> ());

          (match Compiler_adapter.compile ~project_dir:tmp_dir with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok () -> ());

          (match Compiler_adapter.run_tests ~project_dir:tmp_dir with
          | Error err -> Alcotest.fail (Errors.to_string err)
          | Ok out ->
              Alcotest.(check bool) "tests passed" true
                (String.contains out 'A' && String.contains out 'L' && String.contains out 'L'));

          let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
          ()

let tests = [
  Alcotest.test_case "vlen_64" `Slow (fun () -> test_cpp_multi_vlen 64);
  Alcotest.test_case "vlen_128" `Slow (fun () -> test_cpp_multi_vlen 128);
  Alcotest.test_case "vlen_256" `Slow (fun () -> test_cpp_multi_vlen 256);
  Alcotest.test_case "vlen_512" `Slow (fun () -> test_cpp_multi_vlen 512);
]
