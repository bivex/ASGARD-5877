open Random_visa_domain

let group_by_funct6 (instructions : Vector_instruction.t list) =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (inst : Vector_instruction.t) ->
      let cur = Option.value ~default:[] (Hashtbl.find_opt tbl inst.funct6) in
      Hashtbl.replace tbl inst.funct6 (inst :: cur))
    instructions;
  let groups =
    Hashtbl.fold
      (fun f6 insts acc ->
        let sorted =
          List.sort
            (fun (a : Vector_instruction.t) (b : Vector_instruction.t) ->
              Int.compare a.funct3 b.funct3)
            insts
        in
        (f6, sorted) :: acc)
      tbl []
  in
  List.sort (fun (a, _) (b, _) -> Int.compare a b) groups

let emit_isa_state_hpp (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  let vlen = spec.config.vlen in
  let num_vregs = spec.config.num_vregs in
  let sew = Types.Sew.to_bits spec.config.default_sew in
  let default_vl = vlen / sew in
  Buffer.add_string b "#pragma once\n";
  Buffer.add_string b "#include <cstdint>\n#include <cstddef>\n#include <array>\n#include <vector>\n#include <cstring>\n#include <iostream>\n#include <iomanip>\n#include <algorithm>\n\n";
  Buffer.add_string b "namespace visa_emulator {\n\n";
  Buffer.add_string b (Printf.sprintf "constexpr size_t VLEN = %d;\n" vlen);
  Buffer.add_string b "constexpr size_t VLEN_BYTES = VLEN / 8;\n";
  Buffer.add_string b (Printf.sprintf "constexpr size_t NUM_VREGS = %d;\n" num_vregs);
  Buffer.add_string b "constexpr size_t NUM_XREGS = 32;\n\n";
  Buffer.add_string b "struct CSRState {\n";
  Buffer.add_string b (Printf.sprintf "    uint64_t vl{%d};\n" default_vl);
  Buffer.add_string b "    uint64_t vtype{0};\n";
  Buffer.add_string b "    uint64_t vstart{0};\n";
  Buffer.add_string b "    uint64_t vxrm{0};\n";
  Buffer.add_string b "    uint64_t vxsat{0};\n";
  Buffer.add_string b "    uint64_t pc{0x80000000};\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "class VRegFile {\npublic:\n";
  Buffer.add_string b "    alignas(64) std::array<std::array<uint8_t, VLEN_BYTES>, NUM_VREGS> regs{};\n\n";
  Buffer.add_string b "    void reset() noexcept {\n";
  Buffer.add_string b "        for (auto& r : regs) r.fill(0);\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint8_t* get_reg_ptr(size_t reg_idx) noexcept { return regs[reg_idx].data(); }\n";
  Buffer.add_string b "    inline const uint8_t* get_reg_ptr(size_t reg_idx) const noexcept { return regs[reg_idx].data(); }\n\n";
  Buffer.add_string b "    template <typename T>\n";
  Buffer.add_string b "    inline T get_elem(size_t reg_idx, size_t elem_idx) const noexcept {\n";
  Buffer.add_string b "        if (reg_idx >= NUM_VREGS) return 0;\n";
  Buffer.add_string b "        size_t offset = elem_idx * sizeof(T);\n";
  Buffer.add_string b "        if (offset + sizeof(T) > VLEN_BYTES) return 0;\n";
  Buffer.add_string b "        T val;\n";
  Buffer.add_string b "        std::memcpy(&val, &regs[reg_idx][offset], sizeof(T));\n";
  Buffer.add_string b "        return val;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    template <typename T>\n";
  Buffer.add_string b "    inline void set_elem(size_t reg_idx, size_t elem_idx, T val) noexcept {\n";
  Buffer.add_string b "        if (reg_idx >= NUM_VREGS) return;\n";
  Buffer.add_string b "        size_t offset = elem_idx * sizeof(T);\n";
  Buffer.add_string b "        if (offset + sizeof(T) > VLEN_BYTES) return;\n";
  Buffer.add_string b "        std::memcpy(&regs[reg_idx][offset], &val, sizeof(T));\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline bool is_mask_set(size_t mask_reg, size_t elem_idx) const noexcept {\n";
  Buffer.add_string b "        if (mask_reg >= NUM_VREGS) return false;\n";
  Buffer.add_string b "        size_t byte_idx = elem_idx / 8;\n";
  Buffer.add_string b "        size_t bit_idx = elem_idx % 8;\n";
  Buffer.add_string b "        if (byte_idx >= VLEN_BYTES) return false;\n";
  Buffer.add_string b "        return (regs[mask_reg][byte_idx] & (1 << bit_idx)) != 0;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "struct EmulatorState {\n";
  Buffer.add_string b "    VRegFile vregs;\n";
  Buffer.add_string b "    std::array<uint64_t, NUM_XREGS> xregs{};\n";
  Buffer.add_string b "    CSRState csr;\n\n";
  Buffer.add_string b "    void reset() noexcept {\n";
  Buffer.add_string b "        vregs.reset();\n";
  Buffer.add_string b "        xregs.fill(0);\n";
  Buffer.add_string b "        csr = CSRState{};\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint64_t get_xreg(size_t idx) const noexcept {\n";
  Buffer.add_string b "        if (idx == 0 || idx >= NUM_XREGS) return 0;\n";
  Buffer.add_string b "        return xregs[idx];\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline void set_xreg(size_t idx, uint64_t val) noexcept {\n";
  Buffer.add_string b "        if (idx > 0 && idx < NUM_XREGS) xregs[idx] = val;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "} // namespace visa_emulator\n";
  Buffer.contents b

let emit_decoder_hpp (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  Buffer.add_string b "#pragma once\n#include <cstdint>\n#include <string_view>\n#include <optional>\n\n";
  Buffer.add_string b "namespace visa_emulator {\n\n";
  Buffer.add_string b "enum class InstId {\n    UNKNOWN = 0,\n";
  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b (Printf.sprintf "    %s,\n" (String.uppercase_ascii inst.mnemonic)))
    spec.instructions;
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "struct DecodedInstruction {\n";
  Buffer.add_string b "    InstId id{InstId::UNKNOWN};\n";
  Buffer.add_string b "    std::string_view mnemonic{\"unknown\"};\n";
  Buffer.add_string b "    uint8_t opcode{0};\n";
  Buffer.add_string b "    uint8_t funct3{0};\n";
  Buffer.add_string b "    uint8_t funct6{0};\n";
  Buffer.add_string b "    uint8_t vd{0};\n";
  Buffer.add_string b "    uint8_t vs2{0};\n";
  Buffer.add_string b "    uint8_t vs1{0};\n";
  Buffer.add_string b "    uint8_t rs1{0};\n";
  Buffer.add_string b "    int8_t imm{0};\n";
  Buffer.add_string b "    uint8_t vm{1};\n";
  Buffer.add_string b "    uint32_t raw_word{0};\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "class Decoder {\npublic:\n";
  Buffer.add_string b "    static inline DecodedInstruction decode(uint32_t word) noexcept {\n";
  Buffer.add_string b "        DecodedInstruction dec;\n";
  Buffer.add_string b "        dec.raw_word = word;\n";
  Buffer.add_string b "        dec.opcode = word & 0x7F;\n";
  Buffer.add_string b "        dec.vd = (word >> 7) & 0x1F;\n";
  Buffer.add_string b "        dec.funct3 = (word >> 12) & 0x7;\n";
  Buffer.add_string b "        dec.vs1 = (word >> 15) & 0x1F;\n";
  Buffer.add_string b "        dec.rs1 = dec.vs1;\n";
  Buffer.add_string b "        int32_t imm5 = static_cast<int32_t>((word >> 15) & 0x1F);\n";
  Buffer.add_string b "        if (imm5 & 0x10) imm5 |= ~0x1F;\n";
  Buffer.add_string b "        dec.imm = static_cast<int8_t>(imm5);\n";
  Buffer.add_string b "        dec.vs2 = (word >> 20) & 0x1F;\n";
  Buffer.add_string b "        dec.vm = (word >> 25) & 0x1;\n";
  Buffer.add_string b "        dec.funct6 = (word >> 26) & 0x3F;\n\n";
  Buffer.add_string b "        if (dec.opcode != 0x57) return dec;\n\n";
  Buffer.add_string b "        switch (dec.funct6) {\n";

  let groups = group_by_funct6 spec.instructions in
  List.iter
    (fun (f6, insts) ->
      Buffer.add_string b (Printf.sprintf "        case %d:\n" f6);
      List.iter
        (fun (inst : Vector_instruction.t) ->
          Buffer.add_string b (Printf.sprintf "            if (dec.funct3 == %d) {\n" inst.funct3);
          Buffer.add_string b (Printf.sprintf "                dec.id = InstId::%s;\n" (String.uppercase_ascii inst.mnemonic));
          Buffer.add_string b (Printf.sprintf "                dec.mnemonic = \"%s\";\n" inst.mnemonic);
          Buffer.add_string b "                return dec;\n            }\n")
        insts;
      Buffer.add_string b "            break;\n")
    groups;

  Buffer.add_string b "        default:\n            break;\n        }\n";
  Buffer.add_string b "        return dec;\n    }\n};\n\n";
  Buffer.add_string b "} // namespace visa_emulator\n";
  Buffer.contents b

let emit_instructions_hpp (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  Buffer.add_string b "#pragma once\n#include \"isa_state.hpp\"\n#include \"decoder.hpp\"\n\n";
  Buffer.add_string b "namespace visa_emulator {\n\n";
  Buffer.add_string b "class InstructionExecutor {\npublic:\n";
  Buffer.add_string b "    static bool execute(EmulatorState& state, const DecodedInstruction& inst) noexcept;\n\n";
  Buffer.add_string b "private:\n";
  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b (Printf.sprintf "    static void exec_%s(EmulatorState& state, const DecodedInstruction& inst) noexcept;\n" inst.mnemonic))
    spec.instructions;
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "} // namespace visa_emulator\n";
  Buffer.contents b
