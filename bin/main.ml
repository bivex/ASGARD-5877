open Cmdliner
open Random_visa_domain
open Random_visa_ports
open Random_visa_application
open Random_visa_sail_export
open Random_visa_sail_parser
open Random_visa_cpp_emitter
open Random_visa_compiler_adapter
open Random_visa_assembler

let print_hw_report (report : Hw_cost.report) =
  Printf.printf "\n=== Hardware Cost Model Report ===\n";
  Printf.printf "  Verdict:               %s\n" (String.uppercase_ascii (Hw_cost.verdict_to_string report.verdict));
  Printf.printf "  Regfile Read Ports:    %d\n" report.regfile_read_ports;
  Printf.printf "  Regfile Write Ports:   %d\n" report.regfile_write_ports;
  Printf.printf "  Max Element/Group:     %d bytes\n" report.max_group_bytes;
  Printf.printf "  VLEN:                  %d bytes (%d bits)\n" report.vlen_bytes (report.vlen_bytes * 8);
  Printf.printf "  ELEN:                  %d bits\n" report.elen_bits;
  Printf.printf "  Widening Dst Width:    %d bits\n" report.widening_dst_bits;
  Printf.printf "  Decoder Entries:       %d\n" report.decoder_entries;
  Printf.printf "  Distinct funct6 codes: %d\n" report.distinct_funct6;
  if report.warnings <> [] then begin
    Printf.printf "  Warnings:\n";
    List.iter (fun w -> Printf.printf "    [!] %s\n" w) report.warnings
  end;
  Printf.printf "==================================\n\n"

(* 1. GENERATE COMMAND *)
let run_generate name n out_dir profile_name seed vlen compile_and_test =
  let rng =
    match seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in
  let sail_writer = (module Sail_export_adapter : Ports.Sail_spec_writer) in
  let cpp_emitter = (module Cpp_emitter_adapter : Ports.Cpp_code_emitter) in
  let compiler = (module Compiler_adapter : Ports.Compiler) in

  match
    Pipeline.run
      ~sail_writer
      ~cpp_emitter
      ~compiler
      ~rng
      ~name
      ~num_instructions:n
      ~output_dir:out_dir
      ~vlen
      ?seed
      ~compile_and_test
      ~profile_name
      ()
  with
  | Error err ->
      prerr_endline (Printf.sprintf "Error: %s" (Errors.to_string err));
      `Error (false, Errors.to_string err)
  | Ok res ->
      Printf.printf "Successfully synthesized V-ISA '%s' (%d instructions)\n" res.spec_name res.instruction_count;
      Printf.printf "Sail Specification: %s\n" res.sail_file_path;
      Printf.printf "Emitted C++ Files:  %d files in %s\n" (List.length res.emitted_files) out_dir;
      print_hw_report res.hw_cost_report;
      if compile_and_test then begin
        if res.compilation_success then begin
          Printf.printf "Compilation: SUCCESS\n";
          Printf.printf "Verification output:\n%s\n" res.execution_output
        end else begin
          prerr_endline (Printf.sprintf "Compilation / verification failed:\n%s" res.compiler_output)
        end
      end;
      `Ok ()

let generate_cmd =
  let doc = "Synthesize randomized V-ISA, export Sail, and generate C++ emulator" in
  let name =
    let doc = "ISA specification name" in
    Arg.(value & opt string "RVV_Custom_ISA" & info [ "name" ] ~docv:"NAME" ~doc)
  in
  let n =
    let doc = "Number of instructions to synthesize" in
    Arg.(value & opt int 16 & info [ "n"; "num-instructions" ] ~docv:"NUM" ~doc)
  in
  let out_dir =
    let doc = "Output directory for emitted specification and emulator" in
    Arg.(value & opt string "./output" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
  in
  let profile =
    let doc = "Generation profile ('rvv-like' or 'uniform')" in
    Arg.(value & opt string "rvv-like" & info [ "p"; "profile" ] ~docv:"PROFILE" ~doc)
  in
  let seed =
    let doc = "Random seed integer" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let vlen =
    let doc = "Vector register length VLEN in bits" in
    Arg.(value & opt int 128 & info [ "vlen" ] ~docv:"VLEN" ~doc)
  in
  let compile_and_test =
    let doc = "Compile emulator and execute verification self-tests" in
    Arg.(value & flag & info [ "compile-and-test" ] ~doc)
  in
  let term = Term.(ret (const run_generate $ name $ n $ out_dir $ profile $ seed $ vlen $ compile_and_test)) in
  Cmd.v (Cmd.info "generate" ~doc) term

(* 2. PARSE COMMAND *)
let run_parse input_file =
  if not (Sys.file_exists input_file) then
    `Error (false, Printf.sprintf "Input file not found: %s" input_file)
  else
    match Sail_parser_adapter.parse_file input_file with
    | Error err -> `Error (false, Errors.to_string err)
    | Ok spec ->
        Printf.printf "Parsed ISA Specification: %s (version: %s)\n" spec.name spec.version;
        Printf.printf "Hardware config: VLEN=%d, ELEN=%d, NUM_VREGS=%d\n"
          spec.config.vlen spec.config.elen spec.config.num_vregs;
        Printf.printf "Instructions (%d total):\n" (List.length spec.instructions);
        List.iter
          (fun (inst : Vector_instruction.t) ->
            Printf.printf "  %-16s format=%-12s funct6=0x%02X (%2d) funct3=%d opcode=0x%02X\n"
              inst.mnemonic
              (Types.Instruction_format.to_string inst.format)
              inst.funct6 inst.funct6 inst.funct3 inst.opcode)
          spec.instructions;
        let report = Hw_cost.evaluate spec in
        print_hw_report report;
        `Ok ()

let parse_cmd =
  let doc = "Parse formal Sail vector specification file and inspect instructions" in
  let input =
    let doc = "Path to Sail (.sail) input specification file" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let term = Term.(ret (const run_parse $ input)) in
  Cmd.v (Cmd.info "parse" ~doc) term

(* 3. ASSEMBLE COMMAND *)
let run_assemble spec_file input_asm output_vbc =
  match Sail_parser_adapter.parse_file spec_file with
  | Error err -> `Error (false, Errors.to_string err)
  | Ok spec ->
      try
        let ic = open_in input_asm in
        let len = in_channel_length ic in
        let src = really_input_string ic len in
        close_in ic;
        match Assembler_adapter.assemble_program spec src with
        | Error err -> `Error (false, Errors.to_string err)
        | Ok words -> (
            match Assembler_adapter.write_vbc_file ~vlen:spec.config.vlen ~elen:spec.config.elen words output_vbc with
            | Error err -> `Error (false, Errors.to_string err)
            | Ok path ->
                Printf.printf "Assembled %d instructions from %s -> %s\n" (List.length words) input_asm path;
                `Ok ())
      with exn ->
        `Error (false, Printf.sprintf "File I/O error: %s" (Printexc.to_string exn))

let assemble_cmd =
  let doc = "Assemble vector assembly text file into .vbc binary bytecode" in
  let spec =
    let doc = "Path to Sail specification (.sail) file" in
    Arg.(required & opt (some string) None & info [ "s"; "spec" ] ~docv:"SPEC" ~doc)
  in
  let input =
    let doc = "Path to assembly text (.s / .asm) file" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"INPUT" ~doc)
  in
  let output =
    let doc = "Path to output binary bytecode (.vbc / .bin) file" in
    Arg.(required & opt (some string) None & info [ "o"; "output" ] ~docv:"OUTPUT" ~doc)
  in
  let term = Term.(ret (const run_assemble $ spec $ input $ output)) in
  Cmd.v (Cmd.info "assemble" ~doc) term

(* 4. DISASSEMBLE COMMAND *)
let run_disassemble spec_file input_vbc =
  match Sail_parser_adapter.parse_file spec_file with
  | Error err -> `Error (false, Errors.to_string err)
  | Ok spec -> (
      let words_res =
        match Assembler_adapter.read_vbc_file input_vbc with
        | Ok (_, _, ws) -> Ok ws
        | Error _ -> Assembler_adapter.read_binary_bytecode input_vbc
      in
      match words_res with
      | Error err -> `Error (false, Errors.to_string err)
      | Ok words ->
          let text = Assembler_adapter.disassemble_program spec words in
          print_endline text;
          `Ok ())

let disassemble_cmd =
  let doc = "Disassemble binary bytecode (.vbc / .bin) into vector assembly" in
  let spec =
    let doc = "Path to Sail specification (.sail) file" in
    Arg.(required & opt (some string) None & info [ "s"; "spec" ] ~docv:"SPEC" ~doc)
  in
  let input =
    let doc = "Path to binary bytecode (.vbc / .bin) file" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"INPUT" ~doc)
  in
  let term = Term.(ret (const run_disassemble $ spec $ input)) in
  Cmd.v (Cmd.info "disassemble" ~doc) term

(* 5. COST COMMAND *)
let run_cost spec_file =
  match Sail_parser_adapter.parse_file spec_file with
  | Error err -> `Error (false, Errors.to_string err)
  | Ok spec ->
      let report = Hw_cost.evaluate spec in
      Printf.printf "Specification: %s (VLEN=%d, ELEN=%d, %d instructions)\n"
        spec.name spec.config.vlen spec.config.elen (List.length spec.instructions);
      print_hw_report report;
      `Ok ()

let cost_cmd =
  let doc = "Evaluate hardware feasibility and silicon cost of an ISA specification" in
  let spec =
    let doc = "Path to Sail specification (.sail) file" in
    Arg.(required & opt (some string) None & info [ "s"; "spec" ] ~docv:"SPEC" ~doc)
  in
  let term = Term.(ret (const run_cost $ spec)) in
  Cmd.v (Cmd.info "cost" ~doc) term

(* ROOT CLI GROUP *)
let main_cmd =
  let doc = "Random Vector ISA Synthesizer, Formal Sail Exporter, and Emulator Generator in OCaml" in
  let info = Cmd.info "random_visa" ~version:"0.1.0" ~doc in
  Cmd.group info [
    generate_cmd;
    parse_cmd;
    assemble_cmd;
    disassemble_cmd;
    cost_cmd;
  ]

let () = exit (Cmd.eval main_cmd)
