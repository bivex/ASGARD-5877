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

let splitmix64 state =
  let s = Int64.add !state 0x9E3779B97F4A7C15L in
  state := s;
  let z0 = s in
  let z1 = Int64.mul (Int64.logxor z0 (Int64.shift_right_logical z0 30)) 0xBF58476D1CE4E5B9L in
  let z2 = Int64.mul (Int64.logxor z1 (Int64.shift_right_logical z1 27)) 0x94D049BB133111EBL in
  Int64.logxor z2 (Int64.shift_right_logical z2 31)

let encrypt_flag token flag_str =
  let state = ref token in
  let bytes = ref [] in
  String.iter (fun c ->
    let k = splitmix64 state in
    let enc = (Char.code c) lxor (Int64.to_int (Int64.logand k 0xFFL)) in
    bytes := enc :: !bytes
  ) flag_str;
  List.rev !bytes

let () =
  let preset_str = ref "default" in
  let config_file = ref "" in
  let num_rounds = ref 0 in
  let out_dir = ref "/Volumes/External/Code/ASGARD-5877/binaries/crackme_arm64" in

  let speclist = [
    ("-p", Arg.Set_string preset_str, " Protection preset: min, light, default, high, max, stealth");
    ("--preset", Arg.Set_string preset_str, " Protection preset: min, light, default, high, max, stealth");
    ("-c", Arg.Set_string config_file, " Custom JSON protection config path");
    ("--config", Arg.Set_string config_file, " Custom JSON protection config path");
    ("-r", Arg.Set_int num_rounds, " Number of ARX sponge rounds (default: from config)");
    ("--rounds", Arg.Set_int num_rounds, " Number of ARX sponge rounds (default: from config)");
    ("-o", Arg.Set_string out_dir, " Output directory for generated sources and binary");
    ("--output", Arg.Set_string out_dir, " Output directory for generated sources and binary");
  ] in
  Arg.parse speclist (fun _ -> ()) "ASGARD-5877 Cryptographic Hardened Crackme Generator\nUsage: gen_crypto_crackme [options]";

  let base_config =
    if !config_file <> "" then
      match Protection_config.from_file !config_file with
      | Ok c -> c
      | Error err -> failwith (Printf.sprintf "Failed to load config '%s': %s" !config_file err)
    else
      match Protection_config.from_preset !preset_str with
      | Ok c -> c
      | Error err -> failwith err
  in
  let actual_rounds = if !num_rounds > 0 then !num_rounds else base_config.crypto.rounds in
  let config = { base_config with
    crypto = { base_config.crypto with rounds = actual_rounds };
    cff = { base_config.cff with enabled = false; inject_opaque_predicates = false };
    mba = { base_config.mba with enabled = false };
  } in

  let rng = Random.State.make [| 0x5877_BEEF |] in
  let asm = generate_unrolled_arx_asm actual_rounds in
  match Lifter.lift_function asm with
  | Error err -> failwith err
  | Ok func ->
      let st = Vm_eval.make_state () in
      Vm_eval.set_reg st Register.rdi 0x9A4BC3D2E1F07856L;
      Vm_eval.set_reg st Register.rsi 0x5877BEEFC001CAFEL;
      let () = match Vm_eval.run_func st func with
        | Error e -> failwith e
        | Ok () -> ()
      in
      let token = Vm_eval.get_reg st Register.rax in
      Printf.printf "[Vm_eval] Golden Token: 0x%016LX (Rounds: %d)\n" token actual_rounds;
      let flag = "FLAG{128BIT_WIDE_ARX_SPONGE_UNBRUTEFORCEABLE_2026}" in
      let cipher_bytes = encrypt_flag token flag in
      let pkg = Vm_emitter.compile_and_package ~rng ~config func in
      let out_dir = !out_dir in
      let oc_h = open_out (Filename.concat out_dir "threaded_vm.hpp") in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;
      let oc_r = open_out (Filename.concat out_dir "runner.cpp") in
      output_string oc_r pkg.runner_source;
      close_out oc_r;
      let oc_eb = open_out (Filename.concat out_dir "embedded_bytecode.hpp") in
      Printf.fprintf oc_eb "#pragma once\n#include <stdint.h>\n#include <stddef.h>\n\nnamespace vanguard_threaded_vm {\nstatic const uint64_t embedded_bytecode[] = {\n";
      List.iter
        (fun w -> Printf.fprintf oc_eb "    0x%016LXULL,\n" w)
        pkg.bytecode;
      Printf.fprintf oc_eb "};\nstatic const size_t embedded_bytecode_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);\n}\n";
      close_out oc_eb;
      let oc_b = open_out_bin (Filename.concat out_dir "protected.vanguard") in
      List.iter
        (fun w ->
          for i = 0 to 7 do
            let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
            output_byte oc_b b
          done)
        pkg.bytecode;
      close_out oc_b;
      
      let oc_macro = open_out (Filename.concat out_dir "asgard_obf.h") in
      let macro_cfg = {
        C_macro_obf.default_config with
        seed = Random.State.bits rng;
        obfuscate_strings = config.c_macro.obfuscate_strings;
        obfuscate_constants = config.c_macro.obfuscate_constants;
        obfuscate_arithmetic = config.c_macro.obfuscate_arithmetic;
      } in
      output_string oc_macro (C_macro_obf.generate_header ~config:macro_cfg ());
      close_out oc_macro;

      (* Update samples/crackme_vault_128.cpp with fresh ciphertext and C macro hardening *)
      let oc_cpp = open_out "/Volumes/External/Code/ASGARD-5877/samples/crackme_vault_128.cpp" in
      Printf.fprintf oc_cpp "#include \"asgard_obf.h\"\n#include \"threaded_vm.hpp\"\n#include \"embedded_bytecode.hpp\"\n#include <stdio.h>\n#include <stdlib.h>\n#include <stdint.h>\n#include <string.h>\n\n#define FLAG_LEN %d\n\nstatic const uint8_t g_cipher_payload[FLAG_LEN] = {\n" (String.length flag);
      List.iteri (fun idx b ->
        Printf.fprintf oc_cpp "0x%02X%s" b (if idx = List.length cipher_bytes - 1 then "\n" else if idx mod 16 = 15 then ",\n    " else ", ")
      ) cipher_bytes;
      Printf.fprintf oc_cpp "};\n\nstatic inline uint64_t splitmix64(uint64_t* state) {\n    *state += 0x9E3779B97F4A7C15ULL;\n    uint64_t z = *state;\n    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;\n    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;\n    return z ^ (z >> 31);\n}\n\nstatic uint64_t* load_bytecode(const char* filepath, size_t* out_len) {\n    FILE* f = fopen(filepath, \"rb\");\n    if (!f) return nullptr;\n    fseek(f, 0, SEEK_END);\n    long sz = ftell(f);\n    fseek(f, 0, SEEK_SET);\n    if (sz <= 0 || sz %% 8 != 0) { fclose(f); return nullptr; }\n    size_t count = (size_t)sz / 8;\n    uint64_t* bc = (uint64_t*)malloc(sz);\n    if (!bc) { fclose(f); return nullptr; }\n    if (fread(bc, 8, count, f) != count) { free(bc); fclose(f); return nullptr; }\n    fclose(f);\n    *out_len = count;\n    return bc;\n}\n\nint main(int argc, char** argv) {\n    ASG_TIMING_GUARD_START(t_guard);\n    ASG_ANTI_DEBUG_GUARD({\n        printf(\"\\n[-] ACCESS DENIED: Security integrity violation detected!\\n\");\n        return 1;\n    });\n\n    if (argc < 2) {\n        printf(\"Usage: %%s <LICENSE_KEY_128> [optional_bytecode_path]\\n\", argv[0]);\n        printf(\"Key Format: ASGARD-xxxxxxxxxxxxxxxx-xxxxxxxxxxxxxxxx\\n\");\n        return 1;\n    }\n\n    const char* key = argv[1];\n    if (strncmp(key, \"ASGARD-\", 7) != 0) {\n        printf(\"\\n[-] ACCESS DENIED: Invalid Key Prefix (must start with ASGARD-)\\n\");\n        return 1;\n    }\n\n    uint64_t k_hi = 0, k_lo = 0;\n    int parsed = sscanf(key + 7, \"%%016llx-%%016llx\", (unsigned long long*)&k_hi, (unsigned long long*)&k_lo);\n    if (parsed != 2) {\n        unsigned int p[8] = {0};\n        int parsed8 = sscanf(key + 7, \"%%04x-%%04x-%%04x-%%04x-%%04x-%%04x-%%04x-%%04x\",\n                             &p[0], &p[1], &p[2], &p[3], &p[4], &p[5], &p[6], &p[7]);\n        if (parsed8 == 8) {\n            k_hi = ((uint64_t)p[0] << 48) | ((uint64_t)p[1] << 32) | ((uint64_t)p[2] << 16) | (uint64_t)p[3];\n            k_lo = ((uint64_t)p[4] << 48) | ((uint64_t)p[5] << 32) | ((uint64_t)p[6] << 16) | (uint64_t)p[7];\n        } else {\n            printf(\"\\n[-] ACCESS DENIED: Hex Parsing Error for 128-bit Key\\n\");\n            return 1;\n        }\n    }\n\n    const uint64_t* bc_ptr = vanguard_threaded_vm::embedded_bytecode;\n    size_t bc_len = vanguard_threaded_vm::embedded_bytecode_len;\n    uint64_t* heap_bc = nullptr;\n    if (argc >= 3) {\n        heap_bc = load_bytecode(argv[2], &bc_len);\n        if (heap_bc) bc_ptr = heap_bc;\n    }\n\n    vanguard_threaded_vm::VMContext ctx = {};\n    ctx.init();\n    ctx.set_rdi(k_hi);\n    ctx.set_rsi(k_lo);\n\n    ASGARD_BEGIN_VIRTUALIZE(\"vault_engine\");\n    bool vm_ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr, bc_len);\n    ASGARD_END();\n    if (heap_bc) free(heap_bc);\n\n    if (!vm_ok) {\n        printf(\"\\n[-] FATAL: Virtual Machine execution faulted (tampering detected)\\n\");\n        return 1;\n    }\n\n    uint64_t vm_token = ctx.get_rax();\n    uint64_t state = vm_token;\n    char flag_out[FLAG_LEN + 1];\n    for (int i = 0; i < FLAG_LEN; i++) {\n        uint64_t k = splitmix64(&state);\n        flag_out[i] = (char)(g_cipher_payload[i] ^ (k & 0xFF));\n    }\n    flag_out[FLAG_LEN] = '\\0';\n\n    ASG_TIMING_GUARD_CHECK(t_guard, 5000000000ULL, {\n        printf(\"\\n[-] ACCESS DENIED: Execution timeout / hardware debugger anomaly detected!\\n\");\n        return 1;\n    });\n\n    if (strncmp(flag_out, \"FLAG{\", 5) == 0 && flag_out[FLAG_LEN - 1] == '}') {\n        printf(\"=========================================================================\\n\");\n        printf(\"        ASGARD-5877 CRYPTOGRAPHIC HARDENED 128-BIT LICENSE VAULT         \\n\");\n        printf(\"=========================================================================\\n\\n\");\n        printf(\"[+] SUCCESS! 128-BIT KEY VALIDATED (Derived Token: 0x%%016llX)\\n\", (unsigned long long)vm_token);\n        printf(\"[+] PAYLOAD UNLOCKED: %%s\\n\", flag_out);\n        printf(\"=========================================================================\\n\");\n        return 0;\n    } else {\n        printf(\"=========================================================================\\n\");\n        printf(\"        ASGARD-5877 CRYPTOGRAPHIC HARDENED 128-BIT LICENSE VAULT         \\n\");\n        printf(\"=========================================================================\\n\\n\");\n        printf(\"[-] ACCESS DENIED: Invalid License Key! Decryption resulted in corrupt state.\\n\");\n        return 1;\n    }\n}\n";
      close_out oc_cpp;

      print_endline (Metrics.report_to_string pkg.metrics);
      Printf.printf "Successfully emitted Cryptographic Hardened VM (128-bit ARX Sponge) (%d bytes)\n"
        (List.length pkg.bytecode * 8)
