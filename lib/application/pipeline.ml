open Random_visa_domain
open Random_visa_ports

type pipeline_result = {
  spec_name : string;
  instruction_count : int;
  sail_file_path : string;
  emitted_files : string list;
  compilation_success : bool;
  compiler_output : string;
  execution_output : string;
  hw_cost_report : Hw_cost.report;
  vlen : int;
  elen : int;
  seed : int option;
  profile : string;
}

let run
    ~sail_writer
    ~cpp_emitter
    ?compiler
    ~rng
    ~name
    ~num_instructions
    ~output_dir
    ?(vlen = 128)
    ?seed
    ?(compile_and_test = true)
    ?(profile_name = "rvv-like")
    () =
  match Isa_grammar.get_profile profile_name with
  | Error err -> Error err
  | Ok profile -> (
      match Vector_config.make ~vlen ~elen:64 () with
      | Error err -> Error err
      | Ok config -> (
          match
            Synthesize_isa.run ~rng ~name ~config ~profile ~num_instructions ()
          with
          | Error err -> Error err
          | Ok spec -> (
              let hw_report = Hw_cost.evaluate spec in
              let sail_path =
                Filename.concat output_dir (String.lowercase_ascii name ^ ".sail")
              in
              match Export_sail.run sail_writer spec ~target_file_path:sail_path with
              | Error err -> Error err
              | Ok _ -> (
                  match
                    Generate_emulator.run_cpp cpp_emitter spec ~output_dir
                  with
                  | Error err -> Error err
                  | Ok emitted_files ->
                      let comp_success, comp_out, exec_out =
                        match (compile_and_test, compiler) with
                        | true, Some (module C : Ports.Compiler) -> (
                            match C.compile ~project_dir:output_dir with
                            | Error (Errors.Compilation_error msg) ->
                                (false, msg, "")
                            | Error other ->
                                (false, Errors.to_string other, "")
                            | Ok () -> (
                                match C.run_tests ~project_dir:output_dir with
                                | Ok output -> (true, "Compilation succeeded", output)
                                | Error err -> (false, "Tests failed", Errors.to_string err)))
                        | _ -> (false, "Compilation skipped", "")
                      in
                      Ok {
                        spec_name = spec.name;
                        instruction_count = List.length spec.instructions;
                        sail_file_path = sail_path;
                        emitted_files;
                        compilation_success = comp_success;
                        compiler_output = comp_out;
                        execution_output = exec_out;
                        hw_cost_report = hw_report;
                        vlen = spec.config.vlen;
                        elen = spec.config.elen;
                        seed;
                        profile = profile.name;
                      }))))
