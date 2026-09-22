open Random_visa_domain
open Vanguard_types

let emit_cpp_decoder (t : t) (spec : Vector_isa_spec.t) =
  let find_field kind =
    match List.find_opt (fun f -> f.kind = kind) t.layout.fields with
    | Some f -> (f.bit_offset, f.bit_width)
    | None -> (0, 0)
  in
  let op_off, op_w = find_field Opcode in
  let dst_off, dst_w = find_field Dst in
  let s1_off, s1_w = find_field Src1 in
  let s2_off, s2_w = find_field Src2 in
  let imm_off, imm_w = find_field Imm in
  let mask_off, _ = find_field Mask in

  let mask_expr width =
    if width >= 64 then "0xFFFFFFFFFFFFFFFFULL"
    else Printf.sprintf "0x%LXULL" (Int64.sub (Int64.shift_left 1L width) 1L)
  in

  let b = Buffer.create 4096 in
  Buffer.add_string b "#pragma once\n";
  Buffer.add_string b "#include \"isa_state.hpp\"\n";
  Buffer.add_string b "#include \"decoder.hpp\"\n";
  Buffer.add_string b "#include \"instructions.hpp\"\n";
  Buffer.add_string b "#include <cstdint>\n#include <iostream>\n#include <iomanip>\n\n";
  Buffer.add_string b "namespace vanguard_vm {\n\n";

  (* RollingKey class *)
  Buffer.add_string b "struct RollingKey {\n";
  Buffer.add_string b "    uint32_t state;\n";
  Buffer.add_string b "    uint32_t counter{0};\n";
  Buffer.add_string b "    inline explicit RollingKey(uint32_t seed) noexcept\n";
  Buffer.add_string b "        : state(seed == 0 ? 0x1337BEEFU : seed), counter(0) {}\n\n";
  Buffer.add_string b "    inline uint32_t next() noexcept {\n";
  Buffer.add_string b "        counter++;\n";
  Buffer.add_string b "        uint32_t x = state;\n";
  Buffer.add_string b "        x ^= x << 13;\n";
  Buffer.add_string b "        x ^= x >> 17;\n";
  Buffer.add_string b "        x ^= x << 5;\n";
  Buffer.add_string b "        uint32_t rot = (x << 7) | (x >> 25);\n";
  Buffer.add_string b "        uint32_t mixed = rot + (counter * 0x9E3779B9U);\n";
  Buffer.add_string b "        if (mixed == 0) mixed = 0x1337BEEFU;\n";
  Buffer.add_string b "        state = mixed;\n";
  Buffer.add_string b "        return mixed;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint64_t next64() noexcept {\n";
  Buffer.add_string b "        uint64_t w1 = (uint64_t)next();\n";
  Buffer.add_string b "        uint64_t w2 = (uint64_t)next();\n";
  Buffer.add_string b "        return (w1 << 32) | w2;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";

  (* VanguardDecoder class *)
  Buffer.add_string b "class VanguardDecoder {\npublic:\n";
  Buffer.add_string b "    RollingKey key;\n";
  Buffer.add_string b "    bool trapped{false};\n";
  Buffer.add_string b "    size_t executed_instructions{0};\n\n";
  Buffer.add_string b (Printf.sprintf "    explicit VanguardDecoder(uint32_t seed = 0x%08lXU) noexcept : key(seed) {}\n\n" t.key_seed);
  Buffer.add_string b "    bool decode_and_execute(visa_emulator::EmulatorState& state, uint64_t raw_word) {\n";
  Buffer.add_string b "        uint64_t word = raw_word ^ key.next64();\n\n";
  Buffer.add_string b (Printf.sprintf "        uint32_t opcode = (word >> %d) & %s;\n" op_off (mask_expr op_w));
  Buffer.add_string b (Printf.sprintf "        size_t dst = (word >> %d) & %s;\n" dst_off (mask_expr dst_w));
  Buffer.add_string b (Printf.sprintf "        size_t src1 = (word >> %d) & %s;\n" s1_off (mask_expr s1_w));
  Buffer.add_string b (Printf.sprintf "        size_t src2 = (word >> %d) & %s;\n" s2_off (mask_expr s2_w));
  Buffer.add_string b (Printf.sprintf "        int64_t imm = (word >> %d) & %s;\n" imm_off (mask_expr imm_w));
  Buffer.add_string b (Printf.sprintf "        bool mask = ((word >> %d) & 1) != 0;\n\n" mask_off);

  Buffer.add_string b "        visa_emulator::DecodedInstruction dec;\n";
  Buffer.add_string b "        dec.vd = static_cast<uint8_t>(dst);\n";
  Buffer.add_string b "        dec.vs2 = static_cast<uint8_t>(src2);\n";
  Buffer.add_string b "        dec.vs1 = static_cast<uint8_t>(src1);\n";
  Buffer.add_string b "        dec.rs1 = static_cast<uint8_t>(src1);\n";
  Buffer.add_string b "        dec.imm = static_cast<int8_t>(imm);\n";
  Buffer.add_string b "        dec.vm = mask ? 1 : 0;\n\n";

  Buffer.add_string b "        switch (opcode) {\n";

  (* Instruction cases *)
  List.iter
    (fun (inst : Vector_instruction.t) ->
      match Opcode_map.encode t.opcodes inst.mnemonic with
      | None -> ()
      | Some code ->
          Buffer.add_string b (Printf.sprintf "            case 0x%02X: // %s\n" code inst.mnemonic);
          Buffer.add_string b (Printf.sprintf "                dec.id = visa_emulator::InstId::%s;\n" (String.uppercase_ascii inst.mnemonic));
          Buffer.add_string b (Printf.sprintf "                dec.mnemonic = \"%s\";\n" inst.mnemonic);
          Buffer.add_string b "                if (!visa_emulator::InstructionExecutor::execute(state, dec)) return false;\n";
          Buffer.add_string b "                executed_instructions++;\n";
          Buffer.add_string b "                return true;\n")
    spec.instructions;

  (* Decoy junk opcode traps *)
  let junk_codes = ref [] in
  for c = 0 to (1 lsl (Opcode_map.opcode_bits t.opcodes)) - 1 do
    if Opcode_map.is_junk t.opcodes c then junk_codes := c :: !junk_codes
  done;

  if !junk_codes <> [] then begin
    Buffer.add_string b "\n            // Decoy Junk Trap Opcode Handlers\n";
    List.iter
      (fun c -> Buffer.add_string b (Printf.sprintf "            case 0x%02X:\n" c))
      (List.rev !junk_codes);
    Buffer.add_string b "                std::cerr << \"[VANGUARD-TRAP] Decoy junk opcode caught at runtime: 0x\" << std::hex << opcode << \"\\n\";\n";
    Buffer.add_string b "                trapped = true;\n";
    Buffer.add_string b "                return false;\n";
  end;

  Buffer.add_string b "            default:\n";
  Buffer.add_string b "                std::cerr << \"[VANGUARD-TRAP] Unmapped opcode caught: 0x\" << std::hex << opcode << \"\\n\";\n";
  Buffer.add_string b "                trapped = true;\n";
  Buffer.add_string b "                return false;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "} // namespace vanguard_vm\n";
  Buffer.contents b
