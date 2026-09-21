open Cmdliner
open Random_visa_domain
open Random_visa_cpp_emitter

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
