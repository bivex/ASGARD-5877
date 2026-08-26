open Random_visa_domain
open Random_visa_cpp_emitter

let test_vanguard_emulator_integration () =
  let rng = Random.State.make [| 777 |] in
  match Isa_grammar.generate_isa ~rng ~name:"Vanguard_ISA" ~num_instructions:6 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let tmp_dir = Filename.temp_file "vanguard_emu_" "_dir" in
      (try Sys.remove tmp_dir with _ -> ());
      (try Sys.mkdir tmp_dir 0o755 with _ -> ());

      (* 1. Emit base C++ emulator files *)
      (match Cpp_emitter_adapter.emit_emulator_project spec ~output_dir:tmp_dir with
      | Error err -> Alcotest.fail (Errors.to_string err)
      | Ok _ -> ());

      (* 2. Generate Vanguard-9292 build-specific obfuscation scheme *)
      let vanguard_res = Vanguard_9292.of_isa_spec ~rng spec in
      (match vanguard_res with
      | Error err -> Alcotest.fail err
      | Ok vanguard_scheme ->
          (* 3. Emit vanguard_decoder.hpp *)
          let decoder_cpp = Vanguard_9292.emit_cpp_decoder vanguard_scheme spec in
          let decoder_path = Filename.concat tmp_dir "vanguard_decoder.hpp" in
          let oc = open_out decoder_path in
          output_string oc decoder_cpp;
          close_out oc;

          (* 4. Emit vanguard_runner.cpp *)
          let runner_cpp = {|
#include "isa_state.hpp"
#include "vanguard_decoder.hpp"
#include <fstream>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1], std::ios::binary);
    if (!file.is_open()) return 1;
    std::vector<uint64_t> words;
    uint64_t w = 0;
    while (file.read(reinterpret_cast<char*>(&w), sizeof(w))) {
        words.push_back(w);
    }
    visa_emulator::EmulatorState state;
    vanguard_vm::VanguardDecoder decoder;
    for (size_t i = 0; i < words.size(); ++i) {
        if (!decoder.decode_and_execute(state, words[i])) {
            return 2;
        }
    }
    std::cout << "Successfully executed " << decoder.executed_instructions << " obfuscated vanguard instructions!\n";
    return 0;
}
|} in
          let runner_path = Filename.concat tmp_dir "vanguard_runner.cpp" in
          let oc_r = open_out runner_path in
          output_string oc_r runner_cpp;
          close_out oc_r;

          (* 5. Compile vanguard_runner with clang++ *)
          let bin_path = Filename.concat tmp_dir "vanguard_runner" in
          let compile_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s %s/instructions.cpp -o %s"
            tmp_dir runner_path tmp_dir bin_path in
          let comp_status = Sys.command compile_cmd in
          Alcotest.(check int) "compilation succeeds" 0 comp_status;

          (* 6. Assemble program using Vanguard-9292 *)
          let inst1 = List.hd spec.instructions in
          let inst2 = List.nth spec.instructions 1 in
          let asm_src = Printf.sprintf "%s v3, v2, v1\n%s v4, v2, v1\n" inst1.mnemonic inst2.mnemonic in
          (match Vanguard_9292.assemble_program vanguard_scheme spec asm_src with
          | Error err -> Alcotest.fail err
          | Ok words ->
              let bytecode_path = Filename.concat tmp_dir "prog.vanguard" in
              let _ = Vanguard_9292.write_bytecode_file words bytecode_path in

              (* 7. Execute valid obfuscated bytecode in emulator *)
              let run_cmd = Printf.sprintf "%s %s" bin_path bytecode_path in
              let ic = Unix.open_process_in run_cmd in
              let out_buf = Buffer.create 256 in
              (try
                 while true do
                   Buffer.add_string out_buf (input_line ic);
                   Buffer.add_char out_buf '\n'
                 done
               with End_of_file -> ());
              let status = Unix.close_process_in ic in
              Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
              let out_str = Buffer.contents out_buf in
              Alcotest.(check bool) "executed 2 obfuscated instructions" true
                (String.contains out_str '2' && String.contains out_str 'o');

              (* 8. Test Decoy/Junk Trap: corrupt the bytecode word *)
              let bad_bytecode_path = Filename.concat tmp_dir "corrupt.vanguard" in
              let bad_words = [ 0xDEADBEEFCAFE0000L ] in
              let _ = Vanguard_9292.write_bytecode_file bad_words bad_bytecode_path in
              let bad_cmd = Printf.sprintf "%s %s 2>/dev/null" bin_path bad_bytecode_path in
              let bad_status = Sys.command bad_cmd in
              Alcotest.(check bool) "trap causes exit code 2" true (bad_status <> 0);

              let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
              ()))

let tests = [
  Alcotest.test_case "vanguard_emulator_integration" `Slow test_vanguard_emulator_integration;
]
