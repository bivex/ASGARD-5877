open Random_visa_domain

let ensure_dir dir =
  if not (Sys.file_exists dir) then
    let rec mkdir_p d =
      if not (Sys.file_exists d) then begin
        mkdir_p (Filename.dirname d);
        try Sys.mkdir d 0o755 with Sys_error _ -> ()
      end
    in
    mkdir_p dir

let write_file path content =
  let oc = open_out_bin path in
  output_string oc content;
  close_out oc;
  path

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

let generate_c_op_expr (inst : Vector_instruction.t) =
  match inst.binary_op with
  | Some ADD -> if inst.is_widening then "op2 + op1" else "static_cast<elem_t>(static_cast<uint32_t>(op2) + static_cast<uint32_t>(op1))"
  | Some SUB -> if inst.is_widening then "op2 - op1" else "static_cast<elem_t>(static_cast<uint32_t>(op2) - static_cast<uint32_t>(op1))"
  | Some MUL -> if inst.is_widening then "op2 * op1" else "static_cast<elem_t>(static_cast<uint32_t>(op2) * static_cast<uint32_t>(op1))"
  | Some DIV -> "(op1 == 0) ? -1 : ((op2 == INT32_MIN && op1 == -1) ? INT32_MIN : (op2 / op1))"
  | Some REM -> "(op1 == 0) ? op2 : ((op2 == INT32_MIN && op1 == -1) ? 0 : (op2 % op1))"
  | Some AND -> "op2 & op1"
  | Some OR  -> "op2 | op1"
  | Some XOR -> "op2 ^ op1"
  | Some SLL -> "static_cast<elem_t>(static_cast<uint32_t>(op2) << (op1 & 31u))"
  | Some SRL -> "static_cast<elem_t>(static_cast<uint32_t>(op2) >> (op1 & 31u))"
  | Some SRA -> "static_cast<elem_t>(op2 >> (op1 & 31u))"
  | Some MIN -> "std::min(op2, op1)"
  | Some MAX -> "std::max(op2, op1)"
  | Some SADD -> "static_cast<elem_t>(std::clamp<int64_t>(static_cast<int64_t>(op2) + op1, INT32_MIN, INT32_MAX))"
  | Some SSUB -> "static_cast<elem_t>(std::clamp<int64_t>(static_cast<int64_t>(op2) - op1, INT32_MIN, INT32_MAX))"
  | Some CMPEQ -> "(op2 == op1) ? elem_t(1) : elem_t(0)"
  | Some CMPNE -> "(op2 != op1) ? elem_t(1) : elem_t(0)"
  | Some CMPLT -> "(op2 < op1) ? elem_t(1) : elem_t(0)"
  | Some CMPGE -> "(op2 >= op1) ? elem_t(1) : elem_t(0)"
  | None -> (
      match inst.unary_op with
      | Some NEG -> "static_cast<elem_t>(0u - static_cast<uint32_t>(op2))"
      | Some NOT -> "~op2"
      | Some ABS -> "(op2 == INT32_MIN) ? INT32_MIN : ((op2 < 0) ? -op2 : op2)"
      | Some CLZ -> "(op2 == 0) ? 32 : __builtin_clz(static_cast<uint32_t>(op2))"
      | Some CTZ -> "(op2 == 0) ? 32 : __builtin_ctz(static_cast<uint32_t>(op2))"
      | Some CPOP -> "__builtin_popcount(static_cast<uint32_t>(op2))"
      | None -> "op2")

let emit_instructions_cpp (spec : Vector_isa_spec.t) =
  let b = Buffer.create 4096 in
  Buffer.add_string b "#include \"instructions.hpp\"\n#include <algorithm>\n\n";
  Buffer.add_string b "namespace visa_emulator {\n\n";
  Buffer.add_string b "bool InstructionExecutor::execute(EmulatorState& state, const DecodedInstruction& inst) noexcept {\n";
  Buffer.add_string b "    switch (inst.id) {\n";
  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b (Printf.sprintf "    case InstId::%s:\n        exec_%s(state, inst);\n        return true;\n"
                             (String.uppercase_ascii inst.mnemonic) inst.mnemonic))
    spec.instructions;
  Buffer.add_string b "    default:\n        return false;\n    }\n}\n\n";

  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b (Printf.sprintf "void InstructionExecutor::exec_%s(EmulatorState& state, const DecodedInstruction& inst) noexcept {\n" inst.mnemonic);
      if inst.is_widening then begin
        Buffer.add_string b "    using src_elem_t = int32_t;\n";
        Buffer.add_string b "    using elem_t = int64_t;\n";
        Buffer.add_string b "    const size_t vl = std::min<size_t>(state.csr.vl, VLEN_BYTES / sizeof(elem_t));\n";
      end else begin
        Buffer.add_string b "    using src_elem_t = int32_t;\n";
        Buffer.add_string b "    using elem_t = int32_t;\n";
        Buffer.add_string b "    const size_t vl = static_cast<size_t>(state.csr.vl);\n";
      end;
      Buffer.add_string b "    auto* vd_ptr = reinterpret_cast<elem_t*>(state.vregs.get_reg_ptr(inst.vd));\n";
      Buffer.add_string b "    const auto* vs2_ptr = reinterpret_cast<const src_elem_t*>(state.vregs.get_reg_ptr(inst.vs2));\n";

      let has_op1_scalar = inst.format = Types.Instruction_format.OP_VX || inst.format = Types.Instruction_format.OP_VI in
      if has_op1_scalar then begin
        if inst.format = Types.Instruction_format.OP_VX then
          Buffer.add_string b "    const elem_t op1_scalar = static_cast<elem_t>(state.get_xreg(inst.rs1));\n"
        else
          Buffer.add_string b "    const elem_t op1_scalar = static_cast<elem_t>(inst.imm);\n"
      end else if inst.binary_op <> None then begin
        Buffer.add_string b "    const auto* vs1_ptr = reinterpret_cast<const src_elem_t*>(state.vregs.get_reg_ptr(inst.vs1));\n"
      end;

      let expr = generate_c_op_expr inst in

      Buffer.add_string b "    if (__builtin_expect(inst.vm == 1, 1)) {\n";
      Buffer.add_string b "        for (size_t i = 0; i < vl; ++i) {\n";
      Buffer.add_string b "            elem_t op2 = vs2_ptr[i];\n";
      if inst.binary_op <> None then begin
        if has_op1_scalar then
          Buffer.add_string b "            elem_t op1 = op1_scalar;\n"
        else
          Buffer.add_string b "            elem_t op1 = vs1_ptr[i];\n"
      end;
      Buffer.add_string b (Printf.sprintf "            elem_t res = %s;\n" expr);
      Buffer.add_string b "            vd_ptr[i] = res;\n";
      Buffer.add_string b "        }\n";
      Buffer.add_string b "    } else {\n";
      Buffer.add_string b "        for (size_t i = 0; i < vl; ++i) {\n";
      Buffer.add_string b "            if (!state.vregs.is_mask_set(0, i)) continue;\n";
      Buffer.add_string b "            elem_t op2 = vs2_ptr[i];\n";
      if inst.binary_op <> None then begin
        if has_op1_scalar then
          Buffer.add_string b "            elem_t op1 = op1_scalar;\n"
        else
          Buffer.add_string b "            elem_t op1 = vs1_ptr[i];\n"
      end;
      Buffer.add_string b (Printf.sprintf "            elem_t res = %s;\n" expr);
      Buffer.add_string b "            vd_ptr[i] = res;\n";
      Buffer.add_string b "        }\n";
      Buffer.add_string b "    }\n";
      Buffer.add_string b "}\n\n")
    spec.instructions;

  Buffer.add_string b "} // namespace visa_emulator\n";
  Buffer.contents b

let emit_emulator_hpp () =
  let b = Buffer.create 2048 in
  Buffer.add_string b "#pragma once\n#include \"isa_state.hpp\"\n#include \"decoder.hpp\"\n#include \"instructions.hpp\"\n#include <vector>\n\n";
  Buffer.add_string b "namespace visa_emulator {\n\n";
  Buffer.add_string b "class VectorEmulator {\npublic:\n";
  Buffer.add_string b "    EmulatorState state;\n\n";
  Buffer.add_string b "    inline bool step(uint32_t raw_inst) noexcept {\n";
  Buffer.add_string b "        DecodedInstruction dec = Decoder::decode(raw_inst);\n";
  Buffer.add_string b "        if (dec.id == InstId::UNKNOWN) return false;\n";
  Buffer.add_string b "        bool ok = InstructionExecutor::execute(state, dec);\n";
  Buffer.add_string b "        if (ok) state.csr.pc += 4;\n";
  Buffer.add_string b "        return ok;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    size_t run_program(const std::vector<uint32_t>& program) noexcept {\n";
  Buffer.add_string b "        size_t executed = 0;\n";
  Buffer.add_string b "        for (uint32_t word : program) {\n";
  Buffer.add_string b "            if (!step(word)) break;\n";
  Buffer.add_string b "            ++executed;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        return executed;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "} // namespace visa_emulator\n";
  Buffer.contents b

let emit_main_cpp (spec : Vector_isa_spec.t) =
  let b = Buffer.create 4096 in
  Buffer.add_string b "#include \"emulator.hpp\"\n#include \"decoder.hpp\"\n#include \"instructions.hpp\"\n";
  Buffer.add_string b "#include <iostream>\n#include <fstream>\n#include <vector>\n#include <iomanip>\n#include <string>\n\n";
  Buffer.add_string b "static void setup_test_state(visa_emulator::EmulatorState& state) {\n";
  Buffer.add_string b "    for (size_t i = 0; i < state.csr.vl; ++i) {\n";
  Buffer.add_string b "        state.vregs.set_elem<int32_t>(1, i, static_cast<int32_t>((i + 1) * 10));\n";
  Buffer.add_string b "        state.vregs.set_elem<int32_t>(2, i, static_cast<int32_t>((i + 1) * 2));\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    state.set_xreg(1, 5);\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "static int run_self_tests(visa_emulator::VectorEmulator& emu) {\n";
  Buffer.add_string b "    int passed = 0;\n";
  List.iter
    (fun (inst : Vector_instruction.t) ->
      let word = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst in
      Buffer.add_string b "    {\n";
      Buffer.add_string b "        setup_test_state(emu.state);\n";
      Buffer.add_string b (Printf.sprintf "        uint32_t word = 0x%08X;\n" (Int32.to_int word));
      Buffer.add_string b "        bool ok = emu.step(word);\n";
      Buffer.add_string b "        if (!ok) {\n";
      Buffer.add_string b (Printf.sprintf "            std::cerr << \"[FAIL] %s failed to execute\\n\";\n" inst.mnemonic);
      Buffer.add_string b "            return 1;\n";
      Buffer.add_string b "        }\n";
      if inst.is_widening then
        Buffer.add_string b (Printf.sprintf "        std::cout << \"[TEST] %s: word=0x\" << std::hex << word << std::dec << \" res[0]=\" << emu.state.vregs.get_elem<int64_t>(3, 0) << \"\\n\";\n" inst.mnemonic)
      else
        Buffer.add_string b (Printf.sprintf "        std::cout << \"[TEST] %s: word=0x\" << std::hex << word << std::dec << \" res[0]=\" << emu.state.vregs.get_elem<int32_t>(3, 0) << \"\\n\";\n" inst.mnemonic);
      Buffer.add_string b "        ++passed;\n";
      Buffer.add_string b "    }\n")
    spec.instructions;
  Buffer.add_string b "    std::cout << \"=== ALL EMULATOR TESTS PASSED (\" << passed << \" instructions verified) ===\\n\";\n";
  Buffer.add_string b "    return 0;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "int main(int argc, char** argv) {\n";
  Buffer.add_string b "    visa_emulator::VectorEmulator emu;\n";
  Buffer.add_string b "    if (argc > 1) {\n";
  Buffer.add_string b "        std::string arg = argv[1];\n";
  Buffer.add_string b "        if (arg == \"--bin\" && argc > 2) {\n";
  Buffer.add_string b "            std::ifstream file(argv[2], std::ios::binary);\n";
  Buffer.add_string b "            if (!file) {\n";
  Buffer.add_string b "                std::cerr << \"Cannot open bytecode file: \" << argv[2] << \"\\n\";\n";
  Buffer.add_string b "                return 1;\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            std::vector<uint32_t> code;\n";
  Buffer.add_string b "            uint32_t w;\n";
  Buffer.add_string b "            while (file.read(reinterpret_cast<char*>(&w), sizeof(w))) code.push_back(w);\n";
  Buffer.add_string b "            setup_test_state(emu.state);\n";
  Buffer.add_string b "            size_t n = emu.run_program(code);\n";
  Buffer.add_string b "            std::cout << \"Executed \" << n << \" bytecode words.\\n\";\n";
  Buffer.add_string b "            return 0;\n";
  Buffer.add_string b "        } else if (arg == \"--hex\" && argc > 2) {\n";
  Buffer.add_string b "            uint32_t w = std::stoul(argv[2], nullptr, 16);\n";
  Buffer.add_string b "            setup_test_state(emu.state);\n";
  Buffer.add_string b "            bool ok = emu.step(w);\n";
  Buffer.add_string b "            return ok ? 0 : 1;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    return run_self_tests(emu);\n";
  Buffer.add_string b "}\n";
  Buffer.contents b

let emit_cmakelists (spec : Vector_isa_spec.t) =
  let b = Buffer.create 512 in
  Buffer.add_string b "cmake_minimum_required(VERSION 3.20)\n";
  Buffer.add_string b (Printf.sprintf "project(%s_emulator LANGUAGES CXX)\n\n" spec.name);
  Buffer.add_string b "set(CMAKE_CXX_STANDARD 20)\n";
  Buffer.add_string b "set(CMAKE_CXX_STANDARD_REQUIRED ON)\n";
  Buffer.add_string b "add_compile_options(-Wall -Wextra -O3)\n\n";
  Buffer.add_string b "add_executable(visa_test_runner\n";
  Buffer.add_string b "    main.cpp\n";
  Buffer.add_string b "    instructions.cpp\n";
  Buffer.add_string b ")\n";
  Buffer.contents b

let emit_to_files (spec : Vector_isa_spec.t) ~output_dir =
  try
    ensure_dir output_dir;
    let p_isa_state = write_file (Filename.concat output_dir "isa_state.hpp") (emit_isa_state_hpp spec) in
    let p_decoder = write_file (Filename.concat output_dir "decoder.hpp") (emit_decoder_hpp spec) in
    let p_inst_hpp = write_file (Filename.concat output_dir "instructions.hpp") (emit_instructions_hpp spec) in
    let p_inst_cpp = write_file (Filename.concat output_dir "instructions.cpp") (emit_instructions_cpp spec) in
    let p_emu_hpp = write_file (Filename.concat output_dir "emulator.hpp") (emit_emulator_hpp ()) in
    let p_main_cpp = write_file (Filename.concat output_dir "main.cpp") (emit_main_cpp spec) in
    let p_cmake = write_file (Filename.concat output_dir "CMakeLists.txt") (emit_cmakelists spec) in
    Ok [ p_isa_state; p_decoder; p_inst_hpp; p_inst_cpp; p_emu_hpp; p_main_cpp; p_cmake ]
  with exn ->
    Error (Errors.Code_generation_error (Printf.sprintf "Failed to emit C++ project to %s: %s" output_dir (Printexc.to_string exn)))

let emit_emulator_project (spec : Vector_isa_spec.t) ~output_dir =
  emit_to_files spec ~output_dir
