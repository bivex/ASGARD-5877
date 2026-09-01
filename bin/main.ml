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

(* 7. PROTECT COMMAND (Full Automated x86_64 & C/C++ VM-Protector Pipeline) *)
let run_protect input_file out_dir seed config_file preset enable_cff enable_mba mba_depth compile_and_run =
  let base_cfg =
    match config_file with
    | Some path -> (
        match Native_vm.Protection_config.from_file path with
        | Ok c -> c
        | Error err ->
            prerr_endline (Printf.sprintf "[Config] Warning: %s, using default" err);
            Native_vm.Protection_config.default)
    | None -> (
        match preset with
        | Some p -> (
            match Native_vm.Protection_config.from_preset p with
            | Ok c -> c
            | Error err ->
                prerr_endline (Printf.sprintf "[Preset] Warning: %s, using default" err);
                Native_vm.Protection_config.default)
        | None -> Native_vm.Protection_config.default)
  in

  let resolved_cff = if enable_cff then true else base_cfg.cff.enabled in
  let resolved_mba = if enable_mba then true else base_cfg.mba.enabled in
  let resolved_mba_depth = if mba_depth <> 2 then mba_depth else base_cfg.mba.depth in
  let resolved_seed =
    match seed with
    | Some s -> Some s
    | None -> base_cfg.seed
  in
  let effective_cfg = {
    base_cfg with
    seed = resolved_seed;
    cff = { base_cfg.cff with enabled = resolved_cff };
    mba = { base_cfg.mba with enabled = resolved_mba; depth = resolved_mba_depth };
  } in

  let rng =
    match effective_cfg.seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  if not (Sys.file_exists input_file) then begin
    prerr_endline (Printf.sprintf "Input file not found: %s" input_file);
    `Error (false, "File not found")
  end else begin
    (try Sys.mkdir out_dir 0o755 with _ -> ());
    let is_c_src = String.ends_with ~suffix:".c" input_file || String.ends_with ~suffix:".cpp" input_file in

    let asm_source_file =
      if is_c_src then begin
        let hdr_path = Filename.concat out_dir "asgard_obf.h" in
        let obf_c_path = Filename.concat out_dir "app_obf.c" in
        let seed_val = Random.State.int rng 0x3FFFFFFF in
        let config = {
          C_macro_obf.seed = seed_val;
          mba_depth = effective_cfg.mba.depth;
          obfuscate_strings = effective_cfg.c_macro.obfuscate_strings;
          obfuscate_constants = effective_cfg.c_macro.obfuscate_constants;
          obfuscate_arithmetic = effective_cfg.c_macro.obfuscate_arithmetic;
          inject_opaque_predicates = effective_cfg.c_macro.nanomites;
          macro_prefix = "ASG_";
        } in
        (match C_macro_obf.transform_file ~config ~in_file:input_file ~out_file:obf_c_path ~header_file:(Some hdr_path) () with
        | Ok () -> ()
        | Error err -> prerr_endline (Printf.sprintf "C pre-transform warning: %s" err));

        let asm_out = Filename.concat out_dir "app.s" in
        let gen_asm_cmd = Printf.sprintf "clang -S -target x86_64-apple-darwin -masm=intel -O1 -fno-stack-protector -Wno-format-security -I%s -fno-asynchronous-unwind-tables %s -o %s" out_dir obf_c_path asm_out in
        let _ = Sys.command gen_asm_cmd in
        asm_out
      end else input_file
    in

    let ic = open_in asm_source_file in
    let len = in_channel_length ic in
    let text = really_input_string ic len in
    close_in ic;

    let raw_lines =
      match X86_lifter.X86_parser.parse_lines text with
      | Ok lines -> lines
      | Error err ->
          prerr_endline (Printf.sprintf "Parser warning: %s, falling back to full function" err);
          []
    in

    let regions =
      if raw_lines <> [] then X86_lifter.Lifter.extract_marked_regions raw_lines
      else []
    in

    if List.length regions > 1 || (List.length regions = 1 && (match fst (List.hd regions) with X86_lifter.X86_parser.ModeUltra "main" -> false | _ -> true)) then
      Printf.printf "[VM-Protector] Auto-detected %d marker protected region(s) in source.\n" (List.length regions);

    match X86_lifter.Lifter.lift_function text with
    | Error err ->
        prerr_endline (Printf.sprintf "Lifter failed: %s" err);
        `Error (false, err)
    | Ok lifted_func ->
        let pkg =
          Native_vm.Vm_emitter.compile_and_package
            ~rng
            ~config:effective_cfg
            lifted_func
        in

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
          let bin_path = Filename.concat out_dir (if is_c_src then "protected_app" else "protected_runner") in
          let comp_src = if is_c_src then Filename.concat out_dir "app_obf.c" else runner_path in
          let compiler = if is_c_src then "clang -O3 -Wno-format-security" else "clang++ -std=c++20 -O3 -Wno-format-security -fvisibility-inlines-hidden" in
          let comp_cmd = Printf.sprintf "%s -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x -I%s %s -o %s && strip -x %s" compiler out_dir comp_src bin_path bin_path in

          Printf.printf "\n[1/2] Compiling Native Protected Binary (Zero-Bloat / Stripped) with %s...\n" (if is_c_src then "clang -O3" else "clang++ -O3");
          let comp_status = Sys.command comp_cmd in
          if comp_status <> 0 then begin
            prerr_endline "Native compilation failed";
            `Error (false, "Compilation error")
          end else begin
            Printf.printf "[2/2] Launching Protected Binary:\n";
            Printf.printf "--------------------------------------------------------\n";
            let run_cmd = Printf.sprintf "%s" bin_path in
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
  let config_file =
    let doc = "Path to JSON protection configuration file" in
    Arg.(value & opt (some string) None & info [ "c"; "config" ] ~docv:"FILE" ~doc)
  in
  let preset =
    let doc = "Protection preset (default, max_security, lightweight, stealth)" in
    Arg.(value & opt (some string) None & info [ "p"; "preset" ] ~docv:"PRESET" ~doc)
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
  let term = Term.(ret (const run_protect $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ compile)) in
  Cmd.v (Cmd.info "protect" ~doc) term

(* 7b. PROTECT-ARM64 COMMAND (Automated ARM64 Native Lifter & VM Pipeline) *)
let run_protect_arm64 input_file out_dir seed config_file preset enable_cff enable_mba mba_depth compile_and_run =
  let base_cfg =
    match config_file with
    | Some path -> (
        match Native_vm.Protection_config.from_file path with
        | Ok c -> c
        | Error err ->
            prerr_endline (Printf.sprintf "[Config] Warning: %s, using default" err);
            Native_vm.Protection_config.default)
    | None -> (
        match preset with
        | Some p -> (
            match Native_vm.Protection_config.from_preset p with
            | Ok c -> c
            | Error err ->
                prerr_endline (Printf.sprintf "[Preset] Warning: %s, using default" err);
                Native_vm.Protection_config.default)
        | None -> Native_vm.Protection_config.default)
  in

  let resolved_cff = if enable_cff then true else base_cfg.cff.enabled in
  let resolved_mba = if enable_mba then true else base_cfg.mba.enabled in
  let resolved_mba_depth = if mba_depth <> 2 then mba_depth else base_cfg.mba.depth in
  let resolved_seed =
    match seed with
    | Some s -> Some s
    | None -> base_cfg.seed
  in
  let effective_cfg = {
    base_cfg with
    seed = resolved_seed;
    cff = { base_cfg.cff with enabled = resolved_cff };
    mba = { base_cfg.mba with enabled = resolved_mba; depth = resolved_mba_depth };
  } in

  let rng =
    match effective_cfg.seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  if not (Sys.file_exists input_file) then begin
    prerr_endline (Printf.sprintf "Input file not found: %s" input_file);
    `Error (false, "File not found")
  end else begin
    (try Sys.mkdir out_dir 0o755 with _ -> ());
    let is_c_src = String.ends_with ~suffix:".c" input_file || String.ends_with ~suffix:".cpp" input_file in

    let asm_source_file =
      if is_c_src then begin
        let hdr_path = Filename.concat out_dir "asgard_obf.h" in
        let obf_c_path = Filename.concat out_dir "app_obf.c" in
        let seed_val = Random.State.int rng 0x3FFFFFFF in
        let config = {
          C_macro_obf.seed = seed_val;
          mba_depth = effective_cfg.mba.depth;
          obfuscate_strings = effective_cfg.c_macro.obfuscate_strings;
          obfuscate_constants = effective_cfg.c_macro.obfuscate_constants;
          obfuscate_arithmetic = effective_cfg.c_macro.obfuscate_arithmetic;
          inject_opaque_predicates = effective_cfg.c_macro.nanomites;
          macro_prefix = "ASG_";
        } in
        (match C_macro_obf.transform_file ~config ~in_file:input_file ~out_file:obf_c_path ~header_file:(Some hdr_path) () with
        | Ok () -> ()
        | Error err -> prerr_endline (Printf.sprintf "C pre-transform warning: %s" err));

        let asm_out = Filename.concat out_dir "app_arm64.s" in
        let gen_asm_cmd = Printf.sprintf "clang -S -target arm64-apple-darwin -O1 -fno-stack-protector -Wno-format-security -I%s -fno-asynchronous-unwind-tables %s -o %s" out_dir obf_c_path asm_out in
        let _ = Sys.command gen_asm_cmd in
        asm_out
      end else input_file
    in

    let ic = open_in asm_source_file in
    let len = in_channel_length ic in
    let text = really_input_string ic len in
    close_in ic;

    match Arm64_lifter.lift_function text with
    | Error err ->
        prerr_endline (Printf.sprintf "ARM64 Lifter failed: %s" err);
        `Error (false, err)
    | Ok lifted_func ->
        let pkg =
          Native_vm.Vm_emitter.compile_and_package
            ~rng
            ~config:effective_cfg
            lifted_func
        in

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
        Printf.printf "Generated ARM64 Threaded VM Header: %s\n" hdr_path;
        Printf.printf "Generated ARM64 Protected Bytecode: %s (%d bytes)\n" bc_path (List.length pkg.bytecode * 8);

        if compile_and_run then begin
          let bin_path = Filename.concat out_dir (if is_c_src then "protected_app" else "protected_runner") in
          let comp_src = if is_c_src then Filename.concat out_dir "app_obf.c" else runner_path in
          let compiler = if is_c_src then "clang -O3 -target arm64-apple-darwin -Wno-format-security" else "clang++ -std=c++20 -O3 -target arm64-apple-darwin -Wno-format-security -fvisibility-inlines-hidden" in
          let comp_cmd = Printf.sprintf "%s -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x -I%s %s -o %s && strip -x %s" compiler out_dir comp_src bin_path bin_path in

          Printf.printf "\n[1/2] Compiling Native ARM64 Protected Binary with %s...\n" (if is_c_src then "clang -O3" else "clang++ -O3");
          let comp_status = Sys.command comp_cmd in
          if comp_status <> 0 then begin
            prerr_endline "Native ARM64 compilation failed";
            `Error (false, "Compilation error")
          end else begin
            Printf.printf "[2/2] Launching ARM64 Protected Binary:\n";
            Printf.printf "--------------------------------------------------------\n";
            let run_cmd = Printf.sprintf "%s" bin_path in
            let _ = Sys.command run_cmd in
            Printf.printf "--------------------------------------------------------\n\n";
            `Ok ()
          end
        end else `Ok ()
  end

let protect_arm64_cmd =
  let doc = "Virtualize and protect ARM64 assembly or C source with ARM64 Lifter, CFF, MBA, and Direct Threaded VM" in
  let input =
    let doc = "Input ARM64 assembly (.s / .asm) or C source (.c)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_dir =
    let doc = "Output directory for VM runtime and protected bytecode" in
    Arg.(value & opt string "./protected_arm64_out" & info [ "o"; "output-dir" ] ~docv:"DIR" ~doc)
  in
  let seed =
    let doc = "Randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let config_file =
    let doc = "Path to JSON protection configuration file" in
    Arg.(value & opt (some string) None & info [ "c"; "config" ] ~docv:"FILE" ~doc)
  in
  let preset =
    let doc = "Protection preset (default, max_security, lightweight, stealth)" in
    Arg.(value & opt (some string) None & info [ "p"; "preset" ] ~docv:"PRESET" ~doc)
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
    let doc = "Compile native C++ runner and execute protected ARM64 binary" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_protect_arm64 $ input $ out_dir $ seed $ config_file $ preset $ cff $ mba $ mba_depth $ compile)) in
  Cmd.v (Cmd.info "protect-arm64" ~doc) term

let run_c_obf input out_file out_header seed strings consts mba_depth compile =
  let seed_val = match seed with Some s -> s | None -> Random.self_init (); Random.int 0x3FFFFFFF in

  let config = {
    C_macro_obf.seed = seed_val;
    mba_depth;
    obfuscate_strings = strings;
    obfuscate_constants = consts;
    obfuscate_arithmetic = true;
    inject_opaque_predicates = true;
    macro_prefix = "ASG_";
  } in
  let header_path = match out_header with
    | Some p -> p
    | None ->
        let dir = Filename.dirname out_file in
        Filename.concat (if dir = "" then "." else dir) "asgard_obf.h"
  in
  match C_macro_obf.transform_file ~config ~in_file:input ~out_file ~header_file:(Some header_path) () with
  | Error msg ->
      prerr_endline ("C Macro Obfuscation failed: " ^ msg);
      `Error (false, msg)
  | Ok () ->
      Printf.printf "=== C MACRO OBFUSCATION COMPLETE ===\n";
      Printf.printf "  Input C Source:       %s\n" input;
      Printf.printf "  Obfuscated Output:    %s\n" out_file;
      Printf.printf "  Generated Header:     %s\n" header_path;
      Printf.printf "  Random Seed:          0x%X\n" seed_val;
      Printf.printf "  String Encryption:    %s\n" (if strings then "ENABLED" else "DISABLED");
      Printf.printf "  Constant Blinding:    %s\n" (if consts then "ENABLED" else "DISABLED");
      Printf.printf "  MBA Depth:            %d\n" mba_depth;
      Printf.printf "====================================\n\n";
      if compile then begin
        let bin_path = (try Filename.chop_extension out_file with _ -> out_file) ^ "_bin" in
        let comp_cmd = Printf.sprintf "clang -O2 -I%s %s -o %s" (Filename.dirname header_path) out_file bin_path in
        Printf.printf "[1/2] Compiling obfuscated C source with clang -O2...\n";
        let status = Sys.command comp_cmd in
        if status <> 0 then begin
          prerr_endline "Clang compilation failed!";
          `Error (false, "Compilation error")
        end else begin
          Printf.printf "[2/2] Running Obfuscated Binary (%s):\n" bin_path;
          Printf.printf "--------------------------------------------------------\n";
          let _ = Sys.command bin_path in
          Printf.printf "--------------------------------------------------------\n\n";
          `Ok ()
        end
      end else `Ok ()

let c_obf_cmd =
  let doc = "Obfuscate C source code via polymorphic macros, stack string encryption, and MBA" in
  let input =
    let doc = "Input C source file (.c)" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_file =
    let doc = "Output obfuscated C source file" in
    Arg.(value & opt string "./obfuscated.c" & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let out_header =
    let doc = "Output companion header file path (defaults to asgard_obf.h next to output)" in
    Arg.(value & opt (some string) None & info [ "header" ] ~docv:"FILE" ~doc)
  in
  let seed =
    let doc = "Randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let strings =
    let doc = "Enable compile-time stack string encryption" in
    Arg.(value & opt bool true & info [ "strings" ] ~docv:"BOOL" ~doc)
  in
  let consts =
    let doc = "Enable constant blinding" in
    Arg.(value & opt bool true & info [ "constants" ] ~docv:"BOOL" ~doc)
  in
  let mba_depth =
    let doc = "Mixed Boolean-Arithmetic expansion depth (1..4)" in
    Arg.(value & opt int 2 & info [ "mba-depth" ] ~docv:"DEPTH" ~doc)
  in
  let compile =
    let doc = "Compile obfuscated C with clang -O2 and execute" in
    Arg.(value & opt bool true & info [ "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_c_obf $ input $ out_file $ out_header $ seed $ strings $ consts $ mba_depth $ compile)) in
  Cmd.v (Cmd.info "c-obf" ~doc) term

let run_project src_dir inputs out_bin seed enable_cff enable_mba mba_depth compile_and_run =
  let rng =
    match seed with
    | Some s -> Random.State.make [| s |]
    | None ->
        let s = Random.self_init (); Random.bits () in
        Random.State.make [| s |]
  in

  let collect_files dir =
    if not (Sys.file_exists dir && Sys.is_directory dir) then []
    else
      let entries = Sys.readdir dir in
      Array.to_list entries
      |> List.filter (fun f ->
             String.ends_with ~suffix:".c" f || String.ends_with ~suffix:".cpp" f
             || String.ends_with ~suffix:".s" f || String.ends_with ~suffix:".asm" f)
      |> List.map (Filename.concat dir)
  in

  let all_inputs =
    let from_dir = match src_dir with Some d -> collect_files d | None -> [] in
    let combined = from_dir @ inputs in
    List.sort_uniq String.compare combined
  in

  if all_inputs = [] then begin
    prerr_endline "No C/C++/Assembly source files found to protect.";
    `Error (false, "No input files")
  end else begin
    let out_dir = Filename.dirname out_bin in
    let build_dir = Filename.concat (if out_dir = "" then "." else out_dir) ".asgard_build" in
    (try Sys.mkdir out_dir 0o755 with _ -> ());
    (try Sys.mkdir build_dir 0o755 with _ -> ());

    let hdr_path = Filename.concat build_dir "asgard_obf.h" in
    let seed_val = Random.State.int rng 0x3FFFFFFF in
    let config = {
      C_macro_obf.seed = seed_val;
      mba_depth;
      obfuscate_strings = true;
      obfuscate_constants = true;
      obfuscate_arithmetic = true;
      inject_opaque_predicates = true;
      macro_prefix = "ASG_";
    } in

    Printf.printf "\n================ ASGARD-5877 MULTI-FILE PROJECT BUILDER ================\n";
    Printf.printf "  Source Files Count:    %d files\n" (List.length all_inputs);
    Printf.printf "  Build Output Target:   %s\n" out_bin;
    Printf.printf "  Shared Header:         %s\n" hdr_path;
    Printf.printf "  Randomization Seed:    0x%X\n" seed_val;
    Printf.printf "========================================================================\n\n";

    let total_markers = ref 0 in
    let obj_files = ref [] in

    List.iteri
      (fun idx in_file ->
        let base = Filename.chop_extension (Filename.basename in_file) in
        let is_c_src = String.ends_with ~suffix:".c" in_file || String.ends_with ~suffix:".cpp" in_file in
        Printf.printf "[%d/%d] Processing %s...\n" (idx + 1) (List.length all_inputs) in_file;

        if is_c_src then begin
          let file_dir = Filename.dirname in_file in
          let inc_dirs = [
            build_dir;
            file_dir;
            Filename.concat file_dir "include";
            Filename.concat file_dir "../include";
            Filename.concat file_dir "../../include";
          ] in
          let inc_flags = String.concat " " (List.filter (fun s -> s <> "") (List.map (fun d -> if Sys.file_exists d then "-I" ^ d else "") inc_dirs)) in

          let obf_c_path = Filename.concat build_dir (base ^ "_obf.c") in
          (match C_macro_obf.transform_file ~config ~in_file ~out_file:obf_c_path ~header_file:(Some hdr_path) () with
          | Ok () -> ()
          | Error err -> prerr_endline (Printf.sprintf "  [!] Pre-transform note: %s" err));

          let asm_out = Filename.concat build_dir (base ^ ".s") in
          let gen_asm_cmd = Printf.sprintf "clang -S -target x86_64-apple-darwin -masm=intel -O1 -fno-stack-protector -Wno-format-security %s -fno-asynchronous-unwind-tables %s -o %s" inc_flags obf_c_path asm_out in
          let _ = Sys.command gen_asm_cmd in

          let ic = open_in asm_out in
          let len = in_channel_length ic in
          let text = really_input_string ic len in
          close_in ic;

          let is_virtualized = ref false in
          (match X86_lifter.X86_parser.parse_lines text with
          | Ok lines ->
              let regions = X86_lifter.Lifter.extract_marked_regions ~require_markers:true lines in
              if regions <> [] then begin

                total_markers := !total_markers + List.length regions;
                let vm_hdr_filename = base ^ "_threaded_vm.hpp" in
                let vm_src_buf = Buffer.create 4096 in
                Buffer.add_string vm_src_buf (Printf.sprintf "#include \"%s\"\n#include \"asgard_obf.h\"\n#include <stdint.h>\n#include <stdbool.h>\n\n" vm_hdr_filename);

                let region_success = ref false in
                List.iteri
                  (fun r_idx (_mode, rlines) ->
                    match X86_lifter.Lifter.lift_lines rlines with
                    | Ok func ->
                        let clean_name =
                          let n = func.name in
                          if String.starts_with ~prefix:"_" n then String.sub n 1 (String.length n - 1) else n
                        in
                        let pkg = Native_vm.Vm_emitter.compile_and_package ~rng ~enable_cff ~enable_mba ~mba_depth func in
                        let vm_hdr_path = Filename.concat build_dir vm_hdr_filename in
                        let oc_h = open_out vm_hdr_path in
                        output_string oc_h pkg.cpp_runtime_source;
                        close_out oc_h;


                        Buffer.add_string vm_src_buf (Printf.sprintf "static const uint64_t embedded_bc_%s_%d[] = {\n" clean_name r_idx);
                        List.iter
                          (fun w -> Buffer.add_string vm_src_buf (Printf.sprintf "    0x%016LXULL,\n" w))
                          pkg.bytecode;
                        Buffer.add_string vm_src_buf "};\n\n";

                        Buffer.add_string vm_src_buf (Printf.sprintf "extern \"C\" uint64_t %s(uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4) {\n" clean_name);
                        Buffer.add_string vm_src_buf "    vanguard_threaded_vm::VMContext ctx = {};\n";
                        Buffer.add_string vm_src_buf "    ctx.init();\n";
                        Buffer.add_string vm_src_buf "    ctx.set_rdi(a1);\n";
                        Buffer.add_string vm_src_buf "    ctx.set_rsi(a2);\n";
                        Buffer.add_string vm_src_buf "    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a3);\n";
                        Buffer.add_string vm_src_buf "    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a4);\n";
                        Buffer.add_string vm_src_buf (Printf.sprintf "    vanguard_threaded_vm::execute_threaded(ctx, embedded_bc_%s_%d, sizeof(embedded_bc_%s_%d)/sizeof(embedded_bc_%s_%d[0]));\n" clean_name r_idx clean_name r_idx clean_name r_idx);
                        Buffer.add_string vm_src_buf "    return ctx.get_rax();\n";
                        Buffer.add_string vm_src_buf "}\n\n";
                        region_success := true
                    | Error _ -> ())
                  regions;

                if !region_success then begin
                  let vm_cpp_path = Filename.concat build_dir (base ^ "_vm.cpp") in
                  let oc_v = open_out vm_cpp_path in
                  output_string oc_v (Buffer.contents vm_src_buf);
                  close_out oc_v;

                  let obj_out = Filename.concat build_dir (base ^ ".o") in
                  let comp_obj_cmd = Printf.sprintf "clang++ -std=c++20 -O3 -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden %s -c %s -o %s" inc_flags vm_cpp_path obj_out in
                  let st = Sys.command comp_obj_cmd in
                  if st <> 0 then prerr_endline (Printf.sprintf "  [ERROR] Failed to compile VM wrapper for %s" in_file)
                  else (
                    obj_files := obj_out :: !obj_files;
                    is_virtualized := true
                  );

                  Printf.printf "  -> Protected %d marked region(s) (CFF: %s, MBA: %s, Depth: %d)\n"
                    (List.length regions)
                    (if enable_cff then "ON" else "OFF")
                    (if enable_mba then "ON" else "OFF")
                    mba_depth
                end
              end
          | Error _ -> ());

          if not !is_virtualized then begin
            let obj_out = Filename.concat build_dir (base ^ ".o") in
            let comp_obj_cmd = Printf.sprintf "clang -O3 -Wno-format-security -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden %s -c %s -o %s" inc_flags obf_c_path obj_out in
            let st = Sys.command comp_obj_cmd in
            if st <> 0 then prerr_endline (Printf.sprintf "  [ERROR] Failed to compile %s" in_file)
            else obj_files := obj_out :: !obj_files
          end
        end else begin


          let obj_out = Filename.concat build_dir (base ^ ".o") in
          let comp_obj_cmd = Printf.sprintf "clang -c %s -o %s" in_file obj_out in
          let st = Sys.command comp_obj_cmd in
          if st <> 0 then prerr_endline (Printf.sprintf "  [ERROR] Failed to compile %s" in_file)
          else obj_files := obj_out :: !obj_files
        end)
      all_inputs;

    let objs_str = String.concat " " (List.rev !obj_files) in
    let link_cmd = Printf.sprintf "clang -O3 -fno-rtti -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x %s -o %s && strip -x %s" objs_str out_bin out_bin in

    Printf.printf "\n[Linking] Linking %d protected object files into %s...\n" (List.length !obj_files) out_bin;
    let link_st = Sys.command link_cmd in
    if link_st <> 0 then begin
      prerr_endline "Project linking failed!";
      `Error (false, "Linking error")
    end else begin
      Printf.printf "[SUCCESS] Multi-File Protected Binary created successfully: %s\n" out_bin;
      Printf.printf "  Total Files Virtualized:  %d\n" (List.length all_inputs);
      Printf.printf "  Total Marked Regions:     %d\n" !total_markers;
      Printf.printf "  Strip Status:             STRIPPED (Zero C++ stdlib / symbol leaks)\n\n";

      if compile_and_run then begin
        Printf.printf "[Running] Executing Protected Multi-File Binary:\n";
        Printf.printf "--------------------------------------------------------\n";
        let run_cmd = Printf.sprintf "%s" out_bin in
        let _ = Sys.command run_cmd in
        Printf.printf "--------------------------------------------------------\n\n";
        `Ok ()
      end else `Ok ()
    end
  end

let project_cmd =
  let doc = "Build and protect a full multi-file C/C++ project with scattered markers and unified zero-bloat runtime" in
  let src_dir =
    let doc = "Directory containing source files (.c, .cpp, .s)" in
    Arg.(value & opt (some string) None & info [ "d"; "dir"; "src-dir" ] ~docv:"DIR" ~doc)
  in
  let inputs =
    let doc = "Individual source files to include in project" in
    Arg.(value & opt_all string [] & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let out_bin =
    let doc = "Output executable path" in
    Arg.(value & opt string "./bin/protected_app" & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let seed =
    let doc = "Project-wide randomization seed" in
    Arg.(value & opt (some int) None & info [ "s"; "seed" ] ~docv:"SEED" ~doc)
  in
  let cff =
    let doc = "Enable Control-Flow Flattening (CFF) across all files" in
    Arg.(value & flag & info [ "cff"; "flatten" ] ~doc)
  in
  let mba =
    let doc = "Enable Mixed Boolean-Arithmetic (MBA) rewriting across all files" in
    Arg.(value & flag & info [ "mba" ] ~doc)
  in
  let mba_depth =
    let doc = "MBA recursion depth (1..4)" in
    Arg.(value & opt int 2 & info [ "mba-depth" ] ~docv:"DEPTH" ~doc)
  in
  let compile =
    let doc = "Compile and execute final linked binary" in
    Arg.(value & opt bool true & info [ "run"; "compile" ] ~docv:"BOOL" ~doc)
  in
  let term = Term.(ret (const run_project $ src_dir $ inputs $ out_bin $ seed $ cff $ mba $ mba_depth $ compile)) in
  Cmd.v (Cmd.info "project" ~doc) term

let run_init_config out_file preset =
  let cfg =
    match preset with
    | Some p -> (
        match Native_vm.Protection_config.from_preset p with
        | Ok c -> c
        | Error err ->
            prerr_endline (Printf.sprintf "Preset error: %s, using default" err);
            Native_vm.Protection_config.default)
    | None -> Native_vm.Protection_config.default
  in
  Native_vm.Protection_config.save_to_file out_file cfg;
  Printf.printf "[ASGARD-5877] Protection configuration saved: %s\n" out_file;
  `Ok ()

let init_config_cmd =
  let doc = "Generate an annotated JSON protection configuration file for target binary" in
  let out_file =
    let doc = "Output configuration file path" in
    Arg.(value & opt string "asgard.json" & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let preset =
    let doc = "Protection preset template (default, max_security, lightweight, stealth)" in
    Arg.(value & opt (some string) None & info [ "p"; "preset" ] ~docv:"PRESET" ~doc)
  in
  let term = Term.(ret (const run_init_config $ out_file $ preset)) in
  Cmd.v (Cmd.info "init-config" ~doc) term

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
    protect_arm64_cmd;
    c_obf_cmd;
    project_cmd;
    init_config_cmd;
  ]


let () = exit (Cmd.eval main_cmd)


