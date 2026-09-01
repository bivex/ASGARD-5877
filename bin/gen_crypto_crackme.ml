open Vm_ir
open X86_lifter
open Native_vm

let generate_unrolled_arx_asm num_rounds =
  let b = Buffer.create 4096 in
  Buffer.add_string b "func_arx_kdf:\n";
  Buffer.add_string b "    mov r8, rdi\n";
  Buffer.add_string b "    mov r9, rsi\n";
  Buffer.add_string b "    mov r10, 0xD6E8D422F0D4F439\n";
  Buffer.add_string b "    mov r11, 0x9E3779B97F4A7C15\n";
  for _ = 1 to num_rounds do
    Buffer.add_string b "    add r8, r9\n";
    Buffer.add_string b "    add r8, r10\n";
    Buffer.add_string b "    xor r9, r8\n";
    Buffer.add_string b "    mov rdx, r9\n";
    Buffer.add_string b "    shl r9, 13\n";
    Buffer.add_string b "    shr rdx, 51\n";
    Buffer.add_string b "    or r9, rdx\n";
    Buffer.add_string b "    mov rdx, r9\n";
    Buffer.add_string b "    imul rdx, r11\n";
    Buffer.add_string b "    xor r8, rdx\n";
    Buffer.add_string b "    add r9, r8\n";
    Buffer.add_string b "    mov rdx, r9\n";
    Buffer.add_string b "    shl r9, 29\n";
    Buffer.add_string b "    shr rdx, 35\n";
    Buffer.add_string b "    or r9, rdx\n";
    Buffer.add_string b "    add r10, r11\n";
  done;
  Buffer.add_string b "    mov rax, r8\n";
  Buffer.add_string b "    xor rax, r9\n";
  Buffer.add_string b "    ret\n";
  Buffer.contents b

let () =
  let rng = Random.State.make [| 0x5877_BEEF |] in
  let asm = generate_unrolled_arx_asm 16 in
  match Lifter.lift_function asm with
  | Error err -> failwith err
  | Ok func ->
      let st = Vm_eval.make_state () in
      Vm_eval.set_reg st Register.rdi 0x9A4BC3D2E1F07856L;
      Vm_eval.set_reg st Register.rsi 0x5877BEEFC001CAFEL;
      (match Vm_eval.run_func st func with
      | Error e -> Printf.printf "[Vm_eval] Error: %s\n" e
      | Ok () -> Printf.printf "[Vm_eval] Reference Evaluation RAX: 0x%016LX\n" (Vm_eval.get_reg st Register.rax));
      let config = Protection_config.max_security in
      let pkg = Vm_emitter.compile_and_package ~rng ~config func in
      let out_dir = "/Volumes/External/Code/ASGARD-5877/binaries/crackme_arm64" in
      let oc_h = open_out (Filename.concat out_dir "threaded_vm.hpp") in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;
      let oc_r = open_out (Filename.concat out_dir "runner.cpp") in
      output_string oc_r pkg.runner_source;
      close_out oc_r;
      let oc_b = open_out_bin (Filename.concat out_dir "protected.vanguard") in
      List.iter
        (fun w ->
          for i = 0 to 7 do
            let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
            output_byte oc_b b
          done)
        pkg.bytecode;
      close_out oc_b;
      print_endline (Metrics.report_to_string pkg.metrics);
      Printf.printf "Successfully emitted Cryptographic Hardened VM (128-bit ARX Sponge) (%d bytes)\n"
        (List.length pkg.bytecode * 8)
