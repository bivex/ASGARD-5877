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

(* 6. VANGUARD COMMAND: Polymorphic Bytecode Protection and Native Emulation *)
let run_vanguard out_dir seed num_insts =
  let rng =
    match seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in
  match Isa_grammar.generate_isa ~rng ~name:"Vanguard_ISA" ~num_instructions:num_insts () with
  | Error err -> `Error (false, Errors.to_string err)
  | Ok spec ->
      let _ = Sys.command (Printf.sprintf "mkdir -p %s" out_dir) in
      (match Cpp_emitter_adapter.emit_emulator_project spec ~output_dir:out_dir with
      | Error err -> `Error (false, Errors.to_string err)
      | Ok _ -> (
          match Vanguard_9292.of_isa_spec ~rng spec with
          | Error err -> `Error (false, err)
          | Ok scheme ->
              let decoder_cpp = Vanguard_9292.emit_cpp_decoder scheme spec in
              let decoder_path = Filename.concat out_dir "vanguard_decoder.hpp" in
              let oc = open_out decoder_path in
              output_string oc decoder_cpp;
              close_out oc;

              let runner_cpp = {|#include "isa_state.hpp"
#include "vanguard_decoder.hpp"
#include <fstream>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <program.vanguard>\n";
        return 1;
    }
    std::ifstream file(argv[1], std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open bytecode: " << argv[1] << "\n";
        return 1;
    }
    std::vector<uint64_t> words;
    uint64_t w = 0;
    while (file.read(reinterpret_cast<char*>(&w), sizeof(w))) {
        words.push_back(w);
    }
    visa_emulator::EmulatorState state;
    vanguard_vm::VanguardDecoder decoder;
    std::cout << "[VANGUARD-VM] Initialized emulator runtime with rolling key.\n";
    std::cout << "[VANGUARD-VM] Executing " << words.size() << " polymorphic obfuscated words...\n";
    for (size_t i = 0; i < words.size(); ++i) {
        if (!decoder.decode_and_execute(state, words[i])) {
            std::cerr << "[VANGUARD-VM] Instruction " << i << " TRAPPED! Execution halted.\n";
            return 2;
        }
    }
    std::cout << "[VANGUARD-VM] Execution SUCCESS! Verified "
              << decoder.executed_instructions << " obfuscated instructions.\n";
    return 0;
}
|} in
              let runner_path = Filename.concat out_dir "vanguard_runner.cpp" in
              let oc_r = open_out runner_path in
              output_string oc_r runner_cpp;
              close_out oc_r;

              let bin_path = Filename.concat out_dir "vanguard_runner" in
              let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s %s/instructions.cpp -o %s"
                out_dir runner_path out_dir bin_path in
              let comp_status = Sys.command comp_cmd in
              if comp_status <> 0 then
                `Error (false, "Compilation of vanguard_runner failed")
              else (
                Printf.printf "\n=== VANGUARD-9292 POLYMORPHIC SCHEME GENERATED ===\n";
                Printf.printf "  Word width:           %d bits\n" scheme.layout.word_bits;
                Printf.printf "  Rolling key seed:     0x%08lX\n" scheme.key_seed;
                Printf.printf "  Junk decoy ratio:     %.1f%%\n" (scheme.junk_ratio *. 100.0);
                Printf.printf "  Bitfield layout:      ";
                List.iter (fun (f : Vanguard_9292.field_layout) ->
                  Printf.printf "[%s: offset %d, %db] " (Vanguard_9292.field_kind_to_string f.kind) f.bit_offset f.bit_width)
                  scheme.layout.fields;
                Printf.printf "\n===================================================\n";

                let insts = List.filter (fun (i : Vector_instruction.t) -> i.format = Types.Instruction_format.OP_VV || i.format = Types.Instruction_format.OP_VX || i.format = Types.Instruction_format.OP_VI) spec.instructions in
                let prog_lines =
                  match insts with
                  | i1 :: i2 :: _ ->
                      [ Printf.sprintf "%s v3, v2, v1" i1.mnemonic;
                        Printf.sprintf "%s v4, v2, v1" i2.mnemonic ]
                  | i1 :: _ ->
                      [ Printf.sprintf "%s v3, v2, v1" i1.mnemonic ]
                  | [] -> []
                in
                let prog_src = String.concat "\n" prog_lines in
                let prog_vanguard = Filename.concat out_dir "program.vanguard" in
                match Vanguard_9292.assemble_program scheme spec prog_src with
                | Error err -> `Error (false, err)
                | Ok words ->
                    let _ = Vanguard_9292.write_bytecode_file words prog_vanguard in
                    Printf.printf "Assembled %d protected instructions to %s\n" (List.length words) prog_vanguard;

                    Printf.printf "\n--- Launching Vanguard Protected Binary in Emulator ---\n";
                    let run_cmd = Printf.sprintf "%s %s" bin_path prog_vanguard in
                    let _ = Sys.command run_cmd in
                    Printf.printf "--------------------------------------------------------\n\n";
                    `Ok ())))

let vanguard_cmd =
  let doc = "Generate polymorphic Vanguard-9292 protected bytecode and execute on C++ emulator" in
  let out_dir =
    let doc = "Output directory for Vanguard emulator and protected binary" in
    Arg.(value & opt string "./vanguard_demo" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
  in
  let seed =
    let doc = "Random seed integer" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let n =
    let doc = "Number of instructions in underlying ISA" in
    Arg.(value & opt int 8 & info [ "n"; "num-instructions" ] ~docv:"NUM" ~doc)
  in
  let term = Term.(ret (const run_vanguard $ out_dir $ seed $ n)) in
  Cmd.v (Cmd.info "vanguard" ~doc) term

(* 7. PROTECT COMMAND (Full x86_64 VM-Protector Pipeline) *)
let run_protect input_file out_dir seed enable_cff enable_mba mba_depth compile_and_run =
  let rng =
    match seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  if not (Sys.file_exists input_file) then begin
    prerr_endline (Printf.sprintf "Input assembly file not found: %s" input_file);
    `Error (false, "File not found")
  end else begin
    let ic = open_in input_file in
    let len = in_channel_length ic in
    let text = really_input_string ic len in
    close_in ic;

    match X86_lifter.Lifter.lift_function text with
    | Error err ->
        prerr_endline (Printf.sprintf "Lifter failed: %s" err);
        `Error (false, err)
    | Ok lifted_func ->
        let pkg =
          Native_vm.Vm_emitter.compile_and_package
            ~rng
            ~enable_cff
            ~enable_mba
            ~mba_depth
            lifted_func
        in

        (try Sys.mkdir out_dir 0o755 with _ -> ());

        let hdr_path = Filename.concat out_dir "threaded_vm.hpp" in
        let oc_h = open_out hdr_path in
        output_string oc_h pkg.cpp_runtime_source;
        close_out oc_h;

        let runner_path = Filename.concat out_dir "runner.cpp" in
        let oc_r = open_out runner_path in
        output_string oc_r pkg.runner_source;
        close_out oc_r;

        let bc_path = Filename.concat out_dir "protected.vanguard" in
        let oc_b = open_out_bin bc_path in
        List.iter
          (fun w ->
            for i = 0 to 7 do
              let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
              output_byte oc_b b
            done)
          pkg.bytecode;
        close_out oc_b;

        print_endline (Native_vm.Metrics.report_to_string pkg.metrics);
        Printf.printf "Generated Threaded VM Header: %s\n" hdr_path;
        Printf.printf "Generated Protected Bytecode: %s (%d bytes)\n" bc_path (List.length pkg.bytecode * 8);

        if compile_and_run then begin
          let bin_path = Filename.concat out_dir "protected_runner" in
          let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" out_dir runner_path bin_path in
          Printf.printf "\n[1/2] Compiling Native Direct Threaded VM with clang++ -O2...\n";
          let comp_status = Sys.command comp_cmd in
          if comp_status <> 0 then begin
            prerr_endline "Native compilation failed";
            `Error (false, "Compilation error")
          end else begin
            Printf.printf "[2/2] Launching Protected Binary in Threaded VM:\n";
            Printf.printf "--------------------------------------------------------\n";
            let run_cmd = Printf.sprintf "%s %s" bin_path bc_path in
            let _ = Sys.command run_cmd in
            Printf.printf "--------------------------------------------------------\n\n";
            `Ok ()
          end
        end else `Ok ()
  end

let protect_cmd =
  let doc = "Virtualize and protect x86_64 assembly function with CFF, MBA, rolling key, and Direct Threaded VM" in
  let input =
    let doc = "Input x86_64 assembly file (.s / .asm)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_dir =
    let doc = "Output directory for VM runtime and protected bytecode" in
    Arg.(value & opt string "./protected_out" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
  in
  let seed =
    let doc = "Randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let cff =
    let doc = "Enable Control-Flow Flattening (CFF) with state dispatcher" in
    Arg.(value & flag & info [ "cff"; "flatten" ] ~doc)
  in
  let mba =
    let doc = "Enable Mixed Boolean-Arithmetic (MBA) rewriting" in
    Arg.(value & flag & info [ "mba" ] ~doc)
  in
  let mba_depth =
    let doc = "Mixed Boolean-Arithmetic recursion depth (1..4)" in
    Arg.(value & opt int 2 & info [ "mba-depth" ] ~docv:"DEPTH" ~doc)
  in
  let compile =
    let doc = "Compile native C++ runner and execute protected binary" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_protect $ input $ out_dir $ seed $ cff $ mba $ mba_depth $ compile)) in
  Cmd.v (Cmd.info "protect" ~doc) term

(* ROOT CLI GROUP *)
let main_cmd =
  let doc = "Random Vector ISA Synthesizer, Formal Sail Exporter, and VM-Protector in OCaml" in
  let info = Cmd.info "random_visa" ~version:"0.2.0" ~doc in
  Cmd.group info [
    generate_cmd;
    parse_cmd;
    assemble_cmd;
    disassemble_cmd;
    cost_cmd;
    vanguard_cmd;
    protect_cmd;
  ]

let () = exit (Cmd.eval main_cmd)
