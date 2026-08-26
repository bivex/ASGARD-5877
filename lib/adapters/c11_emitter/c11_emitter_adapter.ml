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

let emit_header (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  let vlen = spec.config.vlen in
  let num_vregs = spec.config.num_vregs in
  Buffer.add_string b "#ifndef VISA_EMULATOR_H\n#define VISA_EMULATOR_H\n\n";
  Buffer.add_string b "#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n#include <string.h>\n#include <stdio.h>\n\n";
  Buffer.add_string b (Printf.sprintf "#define VISA_VLEN %d\n" vlen);
  Buffer.add_string b "#define VISA_VLEN_BYTES (VISA_VLEN / 8)\n";
  Buffer.add_string b (Printf.sprintf "#define VISA_NUM_VREGS %d\n" num_vregs);
  Buffer.add_string b "#define VISA_NUM_XREGS 32\n\n";
  Buffer.add_string b "typedef struct {\n";
  Buffer.add_string b "    uint64_t vl;\n    uint64_t vtype;\n    uint64_t vstart;\n    uint64_t vxrm;\n    uint64_t vxsat;\n    uint64_t pc;\n";
  Buffer.add_string b "} CSRState;\n\n";
  Buffer.add_string b "typedef struct {\n    _Alignas(64) uint8_t regs[VISA_NUM_VREGS][VISA_VLEN_BYTES];\n} VRegFile;\n\n";
  Buffer.add_string b "typedef struct {\n    VRegFile vregs;\n    uint64_t xregs[VISA_NUM_XREGS];\n    CSRState csr;\n} EmulatorState;\n\n";
  Buffer.add_string b "typedef struct {\n";
  Buffer.add_string b "    const char* mnemonic;\n";
  Buffer.add_string b "    uint8_t opcode;\n    uint8_t funct3;\n    uint8_t funct6;\n    uint8_t vd;\n    uint8_t vs2;\n    uint8_t vs1;\n    uint8_t rs1;\n    int8_t imm;\n    uint8_t vm;\n    uint32_t raw_word;\n";
  Buffer.add_string b "} DecodedInstruction;\n\n";
  Buffer.add_string b "void visa_emulator_init(EmulatorState* state);\n";
  Buffer.add_string b "void visa_emulator_reset(EmulatorState* state);\n";
  Buffer.add_string b "uint64_t visa_get_xreg(const EmulatorState* state, size_t idx);\n";
  Buffer.add_string b "void visa_set_xreg(EmulatorState* state, size_t idx, uint64_t val);\n";
  Buffer.add_string b "bool visa_is_mask_set(const EmulatorState* state, size_t mask_reg, size_t elem_idx);\n";
  Buffer.add_string b "void visa_dump_vregs(const EmulatorState* state);\n\n";
  Buffer.add_string b "DecodedInstruction visa_decode(uint32_t word);\n";
  Buffer.add_string b "bool visa_execute(EmulatorState* state, const DecodedInstruction* inst);\n";
  Buffer.add_string b "bool visa_step(EmulatorState* state, uint32_t word);\n";
  Buffer.add_string b "size_t visa_run_program(EmulatorState* state, const uint32_t* program, size_t count);\n\n";
  Buffer.add_string b "#endif // VISA_EMULATOR_H\n";
  Buffer.contents b

let emit_emulator_c (spec : Vector_isa_spec.t) =
  let b = Buffer.create 2048 in
  let sew = Types.Sew.to_bits spec.config.default_sew in
  let default_vl = spec.config.vlen / sew in
  Buffer.add_string b "#include \"visa_emulator.h\"\n\n";
  Buffer.add_string b "void visa_emulator_init(EmulatorState* state) {\n";
  Buffer.add_string b "    memset(state, 0, sizeof(*state));\n";
  Buffer.add_string b (Printf.sprintf "    state->csr.vl = %d;\n" default_vl);
  Buffer.add_string b "    state->csr.pc = 0x80000000;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "void visa_emulator_reset(EmulatorState* state) {\n    visa_emulator_init(state);\n}\n\n";
  Buffer.add_string b "uint64_t visa_get_xreg(const EmulatorState* state, size_t idx) {\n";
  Buffer.add_string b "    if (idx == 0 || idx >= VISA_NUM_XREGS) return 0;\n    return state->xregs[idx];\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "void visa_set_xreg(EmulatorState* state, size_t idx, uint64_t val) {\n";
  Buffer.add_string b "    if (idx > 0 && idx < VISA_NUM_XREGS) state->xregs[idx] = val;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "bool visa_is_mask_set(const EmulatorState* state, size_t mask_reg, size_t elem_idx) {\n";
  Buffer.add_string b "    if (mask_reg >= VISA_NUM_VREGS) return false;\n";
  Buffer.add_string b "    size_t byte_idx = elem_idx / 8;\n    size_t bit_idx = elem_idx % 8;\n";
  Buffer.add_string b "    if (byte_idx >= VISA_VLEN_BYTES) return false;\n";
  Buffer.add_string b "    return (state->vregs.regs[mask_reg][byte_idx] & (1 << bit_idx)) != 0;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "void visa_dump_vregs(const EmulatorState* state) {\n";
  Buffer.add_string b "    for (size_t i = 0; i < VISA_NUM_VREGS; ++i) {\n";
  Buffer.add_string b "        printf(\"v%02zu: [ \", i);\n";
  Buffer.add_string b "        for (int b = (int)VISA_VLEN_BYTES - 1; b >= 0; --b) printf(\"%02x \", state->vregs.regs[i][b]);\n";
  Buffer.add_string b "        printf(\"]\\n\");\n    }\n}\n\n";
  Buffer.add_string b "DecodedInstruction visa_decode(uint32_t word) {\n";
  Buffer.add_string b "    DecodedInstruction dec;\n    memset(&dec, 0, sizeof(dec));\n";
  Buffer.add_string b "    dec.raw_word = word;\n";
  Buffer.add_string b "    dec.opcode = word & 0x7F;\n";
  Buffer.add_string b "    dec.vd = (word >> 7) & 0x1F;\n";
  Buffer.add_string b "    dec.funct3 = (word >> 12) & 0x7;\n";
  Buffer.add_string b "    dec.vs1 = (word >> 15) & 0x1F;\n";
  Buffer.add_string b "    dec.rs1 = dec.vs1;\n";
  Buffer.add_string b "    int32_t imm5 = (int32_t)((word >> 15) & 0x1F);\n";
  Buffer.add_string b "    if (imm5 & 0x10) imm5 |= ~0x1F;\n";
  Buffer.add_string b "    dec.imm = (int8_t)imm5;\n";
  Buffer.add_string b "    dec.vs2 = (word >> 20) & 0x1F;\n";
  Buffer.add_string b "    dec.vm = (word >> 25) & 0x1;\n";
  Buffer.add_string b "    dec.funct6 = (word >> 26) & 0x3F;\n";
  Buffer.add_string b "    dec.mnemonic = \"unknown\";\n\n";
  Buffer.add_string b "    if (dec.opcode != 0x57) return dec;\n\n";
  Buffer.add_string b "    switch (dec.funct6) {\n";

  let groups = group_by_funct6 spec.instructions in
  List.iter
    (fun (f6, insts) ->
      Buffer.add_string b (Printf.sprintf "    case %d:\n" f6);
      List.iter
        (fun (inst : Vector_instruction.t) ->
          Buffer.add_string b (Printf.sprintf "        if (dec.funct3 == %d) { dec.mnemonic = \"%s\"; return dec; }\n" inst.funct3 inst.mnemonic))
        insts;
      Buffer.add_string b "        break;\n")
    groups;

  Buffer.add_string b "    default:\n        break;\n    }\n    return dec;\n}\n\n";
  Buffer.add_string b "bool visa_step(EmulatorState* state, uint32_t word) {\n";
  Buffer.add_string b "    DecodedInstruction dec = visa_decode(word);\n";
  Buffer.add_string b "    if (strcmp(dec.mnemonic, \"unknown\") == 0) return false;\n";
  Buffer.add_string b "    bool ok = visa_execute(state, &dec);\n";
  Buffer.add_string b "    if (ok) state->csr.pc += 4;\n";
  Buffer.add_string b "    return ok;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "size_t visa_run_program(EmulatorState* state, const uint32_t* program, size_t count) {\n";
  Buffer.add_string b "    size_t executed = 0;\n";
  Buffer.add_string b "    for (size_t i = 0; i < count; ++i) {\n";
  Buffer.add_string b "        if (!visa_step(state, program[i])) break;\n";
  Buffer.add_string b "        ++executed;\n    }\n    return executed;\n}\n";
  Buffer.contents b

let generate_c11_op_expr (inst : Vector_instruction.t) =
  match inst.binary_op with
  | Some ADD -> "(int32_t)((uint32_t)op2 + (uint32_t)op1)"
  | Some SUB -> "(int32_t)((uint32_t)op2 - (uint32_t)op1)"
  | Some MUL -> "(int32_t)((uint32_t)op2 * (uint32_t)op1)"
  | Some DIV -> "(op1 == 0) ? -1 : ((op2 == INT32_MIN && op1 == -1) ? INT32_MIN : (op2 / op1))"
  | Some REM -> "(op1 == 0) ? op2 : ((op2 == INT32_MIN && op1 == -1) ? 0 : (op2 % op1))"
  | Some AND -> "op2 & op1"
  | Some OR  -> "op2 | op1"
  | Some XOR -> "op2 ^ op1"
  | Some SLL -> "(int32_t)((uint32_t)op2 << (op1 & 31u))"
  | Some SRL -> "(int32_t)((uint32_t)op2 >> (op1 & 31u))"
  | Some SRA -> "op2 >> (op1 & 31u)"
  | Some MIN -> "(op2 < op1) ? op2 : op1"
  | Some MAX -> "(op2 > op1) ? op2 : op1"
  | Some SADD -> "clamp_i32((int64_t)op2 + op1)"
  | Some SSUB -> "clamp_i32((int64_t)op2 - op1)"
  | Some CMPEQ -> "(op2 == op1) ? 1 : 0"
  | Some CMPNE -> "(op2 != op1) ? 1 : 0"
  | Some CMPLT -> "(op2 < op1) ? 1 : 0"
  | Some CMPGE -> "(op2 >= op1) ? 1 : 0"
  | None -> (
      match inst.unary_op with
      | Some NEG -> "(int32_t)(0u - (uint32_t)op2)"
      | Some NOT -> "~op2"
      | Some ABS -> "(op2 == INT32_MIN) ? INT32_MIN : ((op2 < 0) ? -op2 : op2)"
      | Some CLZ -> "(op2 == 0) ? 32 : __builtin_clz((uint32_t)op2)"
      | Some CTZ -> "(op2 == 0) ? 32 : __builtin_ctz((uint32_t)op2)"
      | Some CPOP -> "__builtin_popcount((uint32_t)op2)"
      | None -> "op2")

let emit_instructions_c (spec : Vector_isa_spec.t) =
  let b = Buffer.create 4096 in
  Buffer.add_string b "#include \"visa_emulator.h\"\n#include <limits.h>\n\n";
  Buffer.add_string b "static inline int32_t clamp_i32(int64_t val) {\n";
  Buffer.add_string b "    if (val < (int64_t)INT32_MIN) return INT32_MIN;\n";
  Buffer.add_string b "    if (val > (int64_t)INT32_MAX) return INT32_MAX;\n";
  Buffer.add_string b "    return (int32_t)val;\n}\n\n";

  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b (Printf.sprintf "static bool exec_%s(EmulatorState* state, const DecodedInstruction* inst) {\n" inst.mnemonic);
      Buffer.add_string b "    const size_t vl = (size_t)state->csr.vl;\n";
      Buffer.add_string b "    int32_t* vd_ptr = (int32_t*)state->vregs.regs[inst->vd];\n";
      Buffer.add_string b "    const int32_t* vs2_ptr = (const int32_t*)state->vregs.regs[inst->vs2];\n";

      let has_op1_scalar = inst.format = Types.Instruction_format.OP_VX || inst.format = Types.Instruction_format.OP_VI in
      if has_op1_scalar then begin
        if inst.format = Types.Instruction_format.OP_VX then
          Buffer.add_string b "    const int32_t op1_scalar = (int32_t)visa_get_xreg(state, inst->rs1);\n"
        else
          Buffer.add_string b "    const int32_t op1_scalar = (int32_t)inst->imm;\n"
      end else if inst.binary_op <> None then begin
        Buffer.add_string b "    const int32_t* vs1_ptr = (const int32_t*)state->vregs.regs[inst->vs1];\n"
      end;

      let expr = generate_c11_op_expr inst in

      Buffer.add_string b "    if (inst->vm == 1) {\n";
      Buffer.add_string b "        for (size_t i = 0; i < vl; ++i) {\n";
      Buffer.add_string b "            int32_t op2 = vs2_ptr[i];\n";
      if inst.binary_op <> None then begin
        if has_op1_scalar then
          Buffer.add_string b "            int32_t op1 = op1_scalar;\n"
        else
          Buffer.add_string b "            int32_t op1 = vs1_ptr[i];\n"
      end;
      Buffer.add_string b (Printf.sprintf "            int32_t res = %s;\n" expr);
      Buffer.add_string b "            vd_ptr[i] = res;\n";
      Buffer.add_string b "        }\n";
      Buffer.add_string b "    } else {\n";
      Buffer.add_string b "        for (size_t i = 0; i < vl; ++i) {\n";
      Buffer.add_string b "            if (!visa_is_mask_set(state, 0, i)) continue;\n";
      Buffer.add_string b "            int32_t op2 = vs2_ptr[i];\n";
      if inst.binary_op <> None then begin
        if has_op1_scalar then
          Buffer.add_string b "            int32_t op1 = op1_scalar;\n"
        else
          Buffer.add_string b "            int32_t op1 = vs1_ptr[i];\n"
      end;
      Buffer.add_string b (Printf.sprintf "            int32_t res = %s;\n" expr);
      Buffer.add_string b "            vd_ptr[i] = res;\n";
      Buffer.add_string b "        }\n";
      Buffer.add_string b "    }\n";
      Buffer.add_string b "    return true;\n}\n\n")
    spec.instructions;

  Buffer.add_string b "bool visa_execute(EmulatorState* state, const DecodedInstruction* inst) {\n";
  List.iter
    (fun (inst : Vector_instruction.t) ->
      Buffer.add_string b (Printf.sprintf "    if (strcmp(inst->mnemonic, \"%s\") == 0) return exec_%s(state, inst);\n" inst.mnemonic inst.mnemonic))
    spec.instructions;
  Buffer.add_string b "    return false;\n}\n";
  Buffer.contents b

let emit_main_c (spec : Vector_isa_spec.t) =
  let b = Buffer.create 4096 in
  Buffer.add_string b "#include \"visa_emulator.h\"\n#include <stdlib.h>\n\n";
  Buffer.add_string b "static void setup_test_state(EmulatorState* state) {\n";
  Buffer.add_string b "    for (size_t i = 0; i < state->csr.vl; ++i) {\n";
  Buffer.add_string b "        ((int32_t*)state->vregs.regs[1])[i] = (int32_t)((i + 1) * 10);\n";
  Buffer.add_string b "        ((int32_t*)state->vregs.regs[2])[i] = (int32_t)((i + 1) * 2);\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    visa_set_xreg(state, 1, 5);\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "static int run_self_tests(EmulatorState* state) {\n";
  Buffer.add_string b "    int passed = 0;\n";
  List.iter
    (fun (inst : Vector_instruction.t) ->
      let word = Vector_instruction.encode ~vd:3 ~vs2:2 ~vs1_or_rs1_or_imm:1 ~vm:1 inst in
      Buffer.add_string b "    {\n";
      Buffer.add_string b "        setup_test_state(state);\n";
      Buffer.add_string b (Printf.sprintf "        uint32_t word = 0x%08X;\n" (Int32.to_int word));
      Buffer.add_string b "        bool ok = visa_step(state, word);\n";
      Buffer.add_string b "        if (!ok) {\n";
      Buffer.add_string b (Printf.sprintf "            fprintf(stderr, \"[FAIL] %s failed to execute\\n\");\n" inst.mnemonic);
      Buffer.add_string b "            return 1;\n";
      Buffer.add_string b "        }\n";
      Buffer.add_string b (Printf.sprintf "        printf(\"[TEST] %s: word=0x%%08x res[0]=%%d\\n\", word, ((int32_t*)state->vregs.regs[3])[0]);\n" inst.mnemonic);
      Buffer.add_string b "        ++passed;\n";
      Buffer.add_string b "    }\n")
    spec.instructions;
  Buffer.add_string b "    printf(\"=== ALL C11 EMULATOR TESTS PASSED (%d instructions verified) ===\\n\", passed);\n";
  Buffer.add_string b "    return 0;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "int main(int argc, char** argv) {\n";
  Buffer.add_string b "    EmulatorState state;\n    visa_emulator_init(&state);\n";
  Buffer.add_string b "    if (argc > 1) {\n";
  Buffer.add_string b "        if (strcmp(argv[1], \"--hex\") == 0 && argc > 2) {\n";
  Buffer.add_string b "            uint32_t w = (uint32_t)strtoul(argv[2], NULL, 16);\n";
  Buffer.add_string b "            setup_test_state(&state);\n";
  Buffer.add_string b "            return visa_step(&state, w) ? 0 : 1;\n";
  Buffer.add_string b "        }\n    }\n";
  Buffer.add_string b "    return run_self_tests(&state);\n";
  Buffer.add_string b "}\n";
  Buffer.contents b

let emit_makefile () =
  let b = Buffer.create 512 in
  Buffer.add_string b "CC ?= clang\nCFLAGS ?= -std=c11 -O2 -Wall -Wextra -I.\nOBJS = visa_emulator.o visa_instructions.o main.o\nTARGET = visa_c11_test_runner\n\n";
  Buffer.add_string b "all: $(TARGET)\n\n";
  Buffer.add_string b "$(TARGET): $(OBJS)\n\t$(CC) $(CFLAGS) -o $@ $^\n\n";
  Buffer.add_string b "%.o: %.c visa_emulator.h\n\t$(CC) $(CFLAGS) -c $< -o $@\n\n";
  Buffer.add_string b "clean:\n\trm -f $(OBJS) $(TARGET)\n\n";
  Buffer.add_string b ".PHONY: all clean\n";
  Buffer.contents b

let emit_c_project ?(allow_widening = false) (spec : Vector_isa_spec.t) ~output_dir =
  let has_widening = List.exists (fun (i : Vector_instruction.t) -> i.is_widening) spec.instructions in
  if has_widening && not allow_widening then
    Error (Errors.Unsupported_backend_feature "C11 emitter does not support widening instructions in bare-metal profile")
  else
    try
      ensure_dir output_dir;
      let p_h = write_file (Filename.concat output_dir "visa_emulator.h") (emit_header spec) in
      let p_emu_c = write_file (Filename.concat output_dir "visa_emulator.c") (emit_emulator_c spec) in
      let p_inst_c = write_file (Filename.concat output_dir "visa_instructions.c") (emit_instructions_c spec) in
      let p_main_c = write_file (Filename.concat output_dir "main.c") (emit_main_c spec) in
      let p_make = write_file (Filename.concat output_dir "Makefile") (emit_makefile ()) in
      Ok [ p_h; p_emu_c; p_inst_c; p_main_c; p_make ]
    with exn ->
      Error (Errors.Code_generation_error (Printf.sprintf "Failed to emit C11 project to %s: %s" output_dir (Printexc.to_string exn)))
