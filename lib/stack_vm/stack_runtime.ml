open Stack_ir

type target_arch = X86_64 | AArch64 | RV64

type runtime_config = {
  arch : target_arch;
  pcode_reg : string;   (* VIP *)
  stack_reg : string;   (* VSP *)
  crypt_reg : string;   (* VKEY *)
  disp_reg : string;    (* VDISP *)
  ctx_reg : string;     (* VCTX *)
}

let default_config = function
  | X86_64 -> {
      arch = X86_64;
      pcode_reg = "rsi";
      stack_reg = "rbp";
      crypt_reg = "r12";
      disp_reg = "r13";
      ctx_reg = "r14";
    }
  | AArch64 -> {
      arch = AArch64;
      pcode_reg = "x19";
      stack_reg = "x20";
      crypt_reg = "x21";
      disp_reg = "x22";
      ctx_reg = "x23";
    }
  | RV64 -> {
      arch = RV64;
      pcode_reg = "s1";
      stack_reg = "s2";
      crypt_reg = "s3";
      disp_reg = "s4";
      ctx_reg = "s5";
    }

let emit_entry_stub cfg total_slots =
  match cfg.arch with
  | X86_64 -> [
      "push    rbx";
      "push    rbp";
      "push    r12";
      "push    r13";
      "push    r14";
      "push    r15";
      Printf.sprintf "sub     rsp, %d" (total_slots * 8 + 4096);
      Printf.sprintf "lea     %s, [rsp]" cfg.ctx_reg;
      Printf.sprintf "lea     %s, [rsp + %d]" cfg.stack_reg (total_slots * 8 + 4000);
    ]
  | AArch64 -> [
      "stp     x19, x20, [sp, #-80]!";
      "stp     x21, x22, [sp, #16]";
      "stp     x23, x24, [sp, #32]";
      "stp     x29, x30, [sp, #48]";
      Printf.sprintf "sub     sp, sp, #%d" (total_slots * 8 + 4096);
      Printf.sprintf "mov     %s, sp" cfg.ctx_reg;
      Printf.sprintf "add     %s, sp, #%d" cfg.stack_reg (total_slots * 8 + 4000);
    ]
  | RV64 -> [
      "addi    sp, sp, -64";
      "sd      s1, 0(sp)";
      "sd      s2, 8(sp)";
      "sd      s3, 16(sp)";
      "sd      s4, 24(sp)";
      "sd      s5, 32(sp)";
      Printf.sprintf "addi    sp, sp, -%d" (total_slots * 8 + 4096);
      Printf.sprintf "mv      %s, sp" cfg.ctx_reg;
    ]

let emit_exit_stub cfg total_slots =
  match cfg.arch with
  | X86_64 -> [
      Printf.sprintf "add     rsp, %d" (total_slots * 8 + 4096);
      "pop     r15";
      "pop     r14";
      "pop     r13";
      "pop     r12";
      "pop     rbp";
      "pop     rbx";
      "ret";
    ]
  | AArch64 -> [
      Printf.sprintf "add     sp, sp, #%d" (total_slots * 8 + 4096);
      "ldp     x29, x30, [sp, #48]";
      "ldp     x23, x24, [sp, #32]";
      "ldp     x21, x22, [sp, #16]";
      "ldp     x19, x20, [sp], #80";
      "ret";
    ]
  | RV64 -> [
      Printf.sprintf "addi    sp, sp, %d" (total_slots * 8 + 4096);
      "ld      s1, 0(sp)";
      "ld      s2, 8(sp)";
      "ld      s3, 16(sp)";
      "ld      s4, 24(sp)";
      "ld      s5, 32(sp)";
      "addi    sp, sp, 64";
      "ret";
    ]

let emit_dispatch_epilogue cfg =
  match cfg.arch with
  | X86_64 -> [
      Printf.sprintf "movzx   eax, byte ptr [%s]" cfg.pcode_reg;
      Printf.sprintf "add     %s, 1" cfg.pcode_reg;
      Printf.sprintf "xor     eax, %sd" cfg.crypt_reg;
      Printf.sprintf "add     %sd, eax" cfg.crypt_reg;
      Printf.sprintf "add     %s, rax" cfg.disp_reg;
      Printf.sprintf "jmp     %s" cfg.disp_reg;
    ]
  | AArch64 -> [
      Printf.sprintf "ldrb    w0, [%s], #1" cfg.pcode_reg;
      Printf.sprintf "eor     w0, w0, %s" cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, w0" cfg.crypt_reg cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, x0" cfg.disp_reg cfg.disp_reg;
      Printf.sprintf "br      %s" cfg.disp_reg;
    ]
  | RV64 -> [
      Printf.sprintf "lbu     t0, 0(%s)" cfg.pcode_reg;
      Printf.sprintf "addi    %s, %s, 1" cfg.pcode_reg cfg.pcode_reg;
      Printf.sprintf "xor     t0, t0, %s" cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, t0" cfg.crypt_reg cfg.crypt_reg;
      Printf.sprintf "add     %s, %s, t0" cfg.disp_reg cfg.disp_reg;
      Printf.sprintf "jr      %s" cfg.disp_reg;
    ]

let emit_handler cfg op =
  let body = match op with
    | Add -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "add     rax, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Sub -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "sub     rax, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Nor -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "or      rax, [%s + 8]" cfg.stack_reg;
        "not     rax";
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Nand -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "and     rax, [%s + 8]" cfg.stack_reg;
        "not     rax";
        Printf.sprintf "add     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Dup -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "sub     %s, 8" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rax" cfg.stack_reg;
      ]
    | Swap -> [
        Printf.sprintf "mov     rax, [%s]" cfg.stack_reg;
        Printf.sprintf "mov     rdx, [%s + 8]" cfg.stack_reg;
        Printf.sprintf "mov     [%s], rdx" cfg.stack_reg;
        Printf.sprintf "mov     [%s + 8], rax" cfg.stack_reg;
      ]
    | _ -> [
        Printf.sprintf "nop";
      ]
  in
  body @ emit_dispatch_epilogue cfg

let generate_c_runtime
    ?(external_symbols = [])
    ?(constants = [])
    ?enc
    _cfg
    prog =
  let enc = match enc with
    | Some e -> e
    | None -> Stack_encoder.encode_program prog
  in
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "#include <stdint.h>\n#include <stdlib.h>\n#include <string.h>\n#include <dlfcn.h>\n#include <stdio.h>\n\n";

  (* 1. Constants *)
  Buffer.add_string buf "struct AsgardConstantEntry {\n    const char* name;\n    const uint8_t* data;\n    size_t size;\n};\n\n";
  if constants = [] then begin
    Buffer.add_string buf "static const AsgardConstantEntry g_asgard_constants[] = { { \"\", nullptr, 0 } };\n\n";
  end else begin
    List.iteri (fun idx (_name, bytes) ->
      Buffer.add_string buf (Printf.sprintf "static const uint8_t cdata_%d[] = { " idx);
      for i = 0 to String.length bytes - 1 do
        Buffer.add_string buf (Printf.sprintf "0x%02X, " (Char.code bytes.[i]))
      done;
      Buffer.add_string buf "0x00 };\n"
    ) constants;
    Buffer.add_string buf "static const AsgardConstantEntry g_asgard_constants[] = {\n";
    List.iteri (fun idx (name, bytes) ->
      Buffer.add_string buf (Printf.sprintf "    { \"%s\", cdata_%d, %d },\n" (String.escaped name) idx (String.length bytes))
    ) constants;
    Buffer.add_string buf "};\n\n";
  end;

  Buffer.add_string buf "static inline void* asgard_resolve_constant(const char* name) {\n";
  Buffer.add_string buf "    if (!name || name[0] == '\\0') return nullptr;\n";
  Buffer.add_string buf "    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {\n";
  Buffer.add_string buf "        if (g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name) == 0) return (void*)g_asgard_constants[i].data;\n";
  Buffer.add_string buf "        if (name[0] == '_' && g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name + 1) == 0) return (void*)g_asgard_constants[i].data;\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "    return nullptr;\n";
  Buffer.add_string buf "}\n\n";

  (* 2. External symbols *)
  if external_symbols = [] then
    Buffer.add_string buf "static const char* g_external_symbols[] = { \"\" };\n\n"
  else begin
    Buffer.add_string buf "static const char* g_external_symbols[] = {\n";
    List.iter (fun sym ->
      Buffer.add_string buf (Printf.sprintf "    \"%s\",\n" (String.escaped sym))
    ) external_symbols;
    Buffer.add_string buf "};\n\n";
  end;

  (* 3. Block offsets and keys *)
  let max_bid = Hashtbl.fold (fun id _ acc -> max id acc) enc.block_offsets 0 in
  Buffer.add_string buf (Printf.sprintf "static const uint32_t g_stack_block_offsets[%d] = {\n" (max_bid + 1));
  for i = 0 to max_bid do
    let off = match Hashtbl.find_opt enc.block_offsets i with Some o -> o | None -> 0 in
    Buffer.add_string buf (Printf.sprintf "    %d,\n" off)
  done;
  Buffer.add_string buf "};\n\n";

  Buffer.add_string buf (Printf.sprintf "static const uint64_t g_stack_block_keys[%d] = {\n" (max_bid + 1));
  for i = 0 to max_bid do
    let k = match Hashtbl.find_opt enc.block_keys i with Some k -> k | None -> enc.seed_key in
    Buffer.add_string buf (Printf.sprintf "    0x%016LXULL,\n" k)
  done;
  Buffer.add_string buf "};\n\n";

  (* 4. VM state struct *)
  Buffer.add_string buf "namespace asgard_stack_vm {\n\n";
  Buffer.add_string buf "typedef struct {\n";
  Buffer.add_string buf "    uint64_t vsp[4096];\n";
  Buffer.add_string buf "    int vsp_idx;\n";
  Buffer.add_string buf (Printf.sprintf "    uint64_t ctx[%d];\n" (max 64 prog.context_slots));
  Buffer.add_string buf "    uint64_t vkey;\n";
  Buffer.add_string buf "    uint8_t zf;\n";
  Buffer.add_string buf "    uint8_t sf;\n";
  Buffer.add_string buf "    uint8_t cf;\n";
  Buffer.add_string buf "    uint8_t of;\n";
  Buffer.add_string buf "    int halted;\n";
  Buffer.add_string buf "} stack_vm_t;\n\n";

  (* 5. Decryption helpers *)
  Buffer.add_string buf "static inline uint64_t rotl64(uint64_t v, int k) {\n";
  Buffer.add_string buf "    return (v << (k & 63)) | (v >> ((64 - k) & 63));\n";
  Buffer.add_string buf "}\n\n";
  Buffer.add_string buf "static inline void step_key(uint64_t *key, uint8_t p) {\n";
  Buffer.add_string buf "    *key = rotl64(*key, 3) + (p ^ 0x5A);\n";
  Buffer.add_string buf "}\n\n";

  Buffer.add_string buf "static inline uint8_t fetch_byte(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {\n";
  Buffer.add_string buf "    uint8_t c = bc[(*vip)++];\n";
  Buffer.add_string buf "    uint8_t op = c ^ (uint8_t)(vm->vkey & 0xFF);\n";
  Buffer.add_string buf "    step_key(&vm->vkey, op);\n";
  Buffer.add_string buf "    return op;\n";
  Buffer.add_string buf "}\n\n";

  Buffer.add_string buf "static inline int16_t fetch_i16(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {\n";
  Buffer.add_string buf "    uint16_t b0 = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "    uint16_t b1 = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "    return (int16_t)(b0 | (b1 << 8));\n";
  Buffer.add_string buf "}\n\n";

  Buffer.add_string buf "static inline int32_t fetch_i32(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {\n";
  Buffer.add_string buf "    uint32_t b0 = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "    uint32_t b1 = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "    uint32_t b2 = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "    uint32_t b3 = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "    return (int32_t)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));\n";
  Buffer.add_string buf "}\n\n";

  Buffer.add_string buf "static inline int64_t fetch_i64(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {\n";
  Buffer.add_string buf "    uint64_t res = 0;\n";
  Buffer.add_string buf "    for (int i = 0; i < 8; ++i) {\n";
  Buffer.add_string buf "        uint64_t b = fetch_byte(vm, bc, vip);\n";
  Buffer.add_string buf "        res |= (b << (i * 8));\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "    return (int64_t)res;\n";
  Buffer.add_string buf "}\n\n";

  (* Phase 2: VSP Whitening macro — per-slot XOR mask: vkey + slot * 0x9E3779B97F4A7C15 *)
  Buffer.add_string buf "/* Phase-2 VSP Whitening: slot mask = vkey + slot * 0x9E3779B97F4A7C15ULL */\n";
  Buffer.add_string buf "#define VSP_MASK(vk, slot) ((vk) + (uint64_t)(slot) * UINT64_C(0x9E3779B97F4A7C15))\n";
  Buffer.add_string buf "#define VSP_ENCODE(vk, slot, v) ((v) ^ VSP_MASK(vk, slot))\n\n";

  Buffer.add_string buf "static inline int eval_cond(const stack_vm_t *vm, uint8_t cond) {\n";
  Buffer.add_string buf "    switch (cond) {\n";
  Buffer.add_string buf "        case 0: return vm->zf;\n";
  Buffer.add_string buf "        case 1: return !vm->zf;\n";
  Buffer.add_string buf "        case 2: return vm->cf;\n";
  Buffer.add_string buf "        case 3: return !vm->cf;\n";
  Buffer.add_string buf "        case 4: return vm->cf || vm->zf;\n";
  Buffer.add_string buf "        case 5: return !vm->cf && !vm->zf;\n";
  Buffer.add_string buf "        case 6: return vm->sf;\n";
  Buffer.add_string buf "        case 7: return !vm->sf;\n";
  Buffer.add_string buf "        case 8: return vm->sf != vm->of;\n";
  Buffer.add_string buf "        case 9: return vm->sf == vm->of;\n";
  Buffer.add_string buf "        case 10: return vm->zf || (vm->sf != vm->of);\n";
  Buffer.add_string buf "        case 11: return !vm->zf && (vm->sf == vm->of);\n";
  Buffer.add_string buf "        case 12: return vm->of;\n";
  Buffer.add_string buf "        case 13: return !vm->of;\n";
  Buffer.add_string buf "        case 14: return 1;\n";
  Buffer.add_string buf "        case 15: return 0;\n";
  Buffer.add_string buf "        case 16: return 1;\n";
  Buffer.add_string buf "        default: return 1;\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "}\n\n";

  (* 6. stack_vm_run *)
  Buffer.add_string buf "static inline void stack_vm_run(stack_vm_t *vm, const uint8_t *bytecode, size_t size) {\n";
  Buffer.add_string buf "    size_t vip = 0;\n";
  Buffer.add_string buf "    const int max_ctx = (int)(sizeof(vm->ctx) / sizeof(vm->ctx[0]));\n";
  Buffer.add_string buf "    while (!vm->halted && vip < size) {\n";
  Buffer.add_string buf "        uint8_t op = fetch_byte(vm, bytecode, &vip);\n";
  Buffer.add_string buf "        switch (op) {\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* PUSH_IMM */ {\n" enc.op_map.op_push_imm);
  Buffer.add_string buf "                uint64_t imm = (uint64_t)fetch_i64(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (vm->vsp_idx < 4096) {\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, imm);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* PUSH_REG */ {\n" enc.op_map.op_push_reg);
  Buffer.add_string buf "                int16_t idx = fetch_i16(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (vm->vsp_idx < 4096 && idx >= 0 && idx < max_ctx) {\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->ctx[idx]);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* POP_REG */ {\n" enc.op_map.op_pop_reg);
  Buffer.add_string buf "                int16_t idx = fetch_i16(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (vm->vsp_idx > 0 && idx >= 0 && idx < max_ctx) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    vm->ctx[idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* READ_MEM */ {\n" enc.op_map.op_read_mem);
  Buffer.add_string buf "                uint8_t w = fetch_byte(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                uint64_t addr = 0;\n";
  Buffer.add_string buf "                if (vm->vsp_idx > 0) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    addr = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                uint64_t val = 0;\n";
  Buffer.add_string buf "                if (addr != 0) {\n";
  Buffer.add_string buf "                    if (w == 1) val = *(const uint8_t*)addr;\n";
  Buffer.add_string buf "                    else if (w == 2) val = *(const uint16_t*)addr;\n";
  Buffer.add_string buf "                    else if (w == 4) val = *(const uint32_t*)addr;\n";
  Buffer.add_string buf "                    else val = *(const uint64_t*)addr;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                if (vm->vsp_idx < 4096) {\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, val);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* WRITE_MEM */ {\n" enc.op_map.op_write_mem);
  Buffer.add_string buf "                uint8_t w = fetch_byte(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t val = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t addr = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    if (addr != 0) {\n";
  Buffer.add_string buf "                        if (w == 1) *(uint8_t*)addr = (uint8_t)val;\n";
  Buffer.add_string buf "                        else if (w == 2) *(uint16_t*)addr = (uint16_t)val;\n";
  Buffer.add_string buf "                        else if (w == 4) *(uint32_t*)addr = (uint32_t)val;\n";
  Buffer.add_string buf "                        else *(uint64_t*)addr = val;\n";
  Buffer.add_string buf "                    }\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* ADD */ {\n" enc.op_map.op_add);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = a + b;\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->cf = (res < a);\n";
  Buffer.add_string buf "                    vm->of = ((~(a ^ b) & (a ^ res)) >> 63) & 1;\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* SUB */ {\n" enc.op_map.op_sub);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = a - b;\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->cf = (a < b);\n";
  Buffer.add_string buf "                    vm->of = (((a ^ b) & (a ^ res)) >> 63) & 1;\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* MUL */ {\n" enc.op_map.op_mul);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, a * b);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* NOR */ {\n" enc.op_map.op_nor);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = ~(a | b);\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->cf = 0;\n";
  Buffer.add_string buf "                    vm->of = 0;\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* NAND */ {\n" enc.op_map.op_nand);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = ~(a & b);\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->cf = 0;\n";
  Buffer.add_string buf "                    vm->of = 0;\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* SHL */ {\n" enc.op_map.op_shl);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t count = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t val = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = val << (count & 63);\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* SHR */ {\n" enc.op_map.op_shr);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t count = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t val = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = val >> (count & 63);\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* DUP */ {\n" enc.op_map.op_dup);
  Buffer.add_string buf "                /* Dup: decode value from src slot, re-encode at new slot */\n";
  Buffer.add_string buf "                if (vm->vsp_idx > 0 && vm->vsp_idx < 4096) {\n";
  Buffer.add_string buf "                    int src = vm->vsp_idx - 1;\n";
  Buffer.add_string buf "                    uint64_t decoded = VSP_ENCODE(vm->vkey, src, vm->vsp[src]);\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, decoded);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* SWAP */ {\n" enc.op_map.op_swap);
  Buffer.add_string buf "                /* Swap: decode both positions, re-encode at swapped positions */\n";
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    int ia = vm->vsp_idx - 1, ib = vm->vsp_idx - 2;\n";
  Buffer.add_string buf "                    uint64_t da = VSP_ENCODE(vm->vkey, ia, vm->vsp[ia]);\n";
  Buffer.add_string buf "                    uint64_t db = VSP_ENCODE(vm->vkey, ib, vm->vsp[ib]);\n";
  Buffer.add_string buf "                    vm->vsp[ia] = VSP_ENCODE(vm->vkey, ia, db);\n";
  Buffer.add_string buf "                    vm->vsp[ib] = VSP_ENCODE(vm->vkey, ib, da);\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* PUSH_FLAGS */ {\n" enc.op_map.op_push_flags);
  Buffer.add_string buf "                if (vm->vsp_idx < 4096) {\n";
  Buffer.add_string buf "                    uint64_t fl = (vm->zf ? 0x40ULL : 0ULL) |\n";
  Buffer.add_string buf "                                  (vm->sf ? 0x80ULL : 0ULL) |\n";
  Buffer.add_string buf "                                  (vm->cf ? 0x01ULL : 0ULL) |\n";
  Buffer.add_string buf "                                  (vm->of ? 0x800ULL : 0ULL) | 0x02ULL;\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, fl);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* POP_FLAGS */ {\n" enc.op_map.op_pop_flags);
  Buffer.add_string buf "                if (vm->vsp_idx > 0) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t fl = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    vm->cf = (fl & 0x01ULL) != 0;\n";
  Buffer.add_string buf "                    vm->zf = (fl & 0x40ULL) != 0;\n";
  Buffer.add_string buf "                    vm->sf = (fl & 0x80ULL) != 0;\n";
  Buffer.add_string buf "                    vm->of = (fl & 0x800ULL) != 0;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* JMP_REL */ {\n" enc.op_map.op_jmp_rel);
  Buffer.add_string buf "                int32_t target_bid = fetch_i32(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (target_bid >= 0 && (size_t)target_bid < sizeof(g_stack_block_offsets)/sizeof(g_stack_block_offsets[0])) {\n";
  Buffer.add_string buf "                    vip = g_stack_block_offsets[target_bid];\n";
  Buffer.add_string buf "                    vm->vkey = g_stack_block_keys[target_bid];\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* JCC_REL */ {\n" enc.op_map.op_jcc_rel);
  Buffer.add_string buf "                uint8_t cond = fetch_byte(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                int32_t target_bid = fetch_i32(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (eval_cond(vm, cond)) {\n";
  Buffer.add_string buf "                    if (target_bid >= 0 && (size_t)target_bid < sizeof(g_stack_block_offsets)/sizeof(g_stack_block_offsets[0])) {\n";
  Buffer.add_string buf "                        vip = g_stack_block_offsets[target_bid];\n";
  Buffer.add_string buf "                        vm->vkey = g_stack_block_keys[target_bid];\n";
  Buffer.add_string buf "                    }\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* KEY_ADJUST */ {\n" enc.op_map.op_key_adjust);
  Buffer.add_string buf "                int64_t delta = fetch_i64(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                vm->vkey ^= (uint64_t)delta;\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* EXIT */\n" enc.op_map.op_exit);
  Buffer.add_string buf "                vm->halted = 1;\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* CALL_EXTERN */ {\n" enc.op_map.op_call_extern);
  Buffer.add_string buf "                int32_t sym_idx = fetch_i32(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (sym_idx >= 0 && (size_t)sym_idx < sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {\n";
  Buffer.add_string buf "                    const char* sym_name = g_external_symbols[sym_idx];\n";
  Buffer.add_string buf "                    if (sym_name && sym_name[0] != '\\0') {\n";
  Buffer.add_string buf "                        void* sym_ptr = dlsym(RTLD_DEFAULT, sym_name);\n";
  Buffer.add_string buf "                        if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);\n";
  Buffer.add_string buf "                        if (!sym_ptr) {\n";
  Buffer.add_string buf "                            char alt[256];\n";
  Buffer.add_string buf "                            snprintf(alt, sizeof(alt), \"_%s\", sym_name);\n";
  Buffer.add_string buf "                            sym_ptr = dlsym(RTLD_DEFAULT, alt);\n";
  Buffer.add_string buf "                        }\n";
  Buffer.add_string buf "                        if (sym_ptr) {\n";
  Buffer.add_string buf "                            uint64_t a0 = vm->ctx[0];\n";
  Buffer.add_string buf "                            uint64_t a1 = vm->ctx[1];\n";
  Buffer.add_string buf "                            uint64_t a2 = vm->ctx[2];\n";
  Buffer.add_string buf "                            uint64_t a3 = vm->ctx[3];\n";
  Buffer.add_string buf "                            uint64_t a4 = (max_ctx > 6) ? vm->ctx[6] : 0;\n";
  Buffer.add_string buf "                            uint64_t a5 = (max_ctx > 7) ? vm->ctx[7] : 0;\n";
  Buffer.add_string buf "                            uint64_t a6 = (max_ctx > 8) ? vm->ctx[8] : 0;\n";
  Buffer.add_string buf "                            uint64_t a7 = (max_ctx > 9) ? vm->ctx[9] : 0;\n";
  Buffer.add_string buf "                            typedef uint64_t (*ext_fn_8)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);\n";
  Buffer.add_string buf "                            uint64_t ret = ((ext_fn_8)sym_ptr)(a0, a1, a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string buf "                            vm->ctx[0] = ret;\n";
  Buffer.add_string buf "                        }\n";
  Buffer.add_string buf "                    }\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* RESOLVE_SYM */ {\n" enc.op_map.op_resolve_sym);
  Buffer.add_string buf "                int32_t sym_idx = fetch_i32(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                void* sym_ptr = nullptr;\n";
  Buffer.add_string buf "                if (sym_idx >= 0 && (size_t)sym_idx < sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {\n";
  Buffer.add_string buf "                    const char* sym_name = g_external_symbols[sym_idx];\n";
  Buffer.add_string buf "                    if (sym_name && sym_name[0] != '\\0') {\n";
  Buffer.add_string buf "                        sym_ptr = dlsym(RTLD_DEFAULT, sym_name);\n";
  Buffer.add_string buf "                        if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);\n";
  Buffer.add_string buf "                        if (!sym_ptr) {\n";
  Buffer.add_string buf "                            char alt[256];\n";
  Buffer.add_string buf "                            snprintf(alt, sizeof(alt), \"_%s\", sym_name);\n";
  Buffer.add_string buf "                            sym_ptr = dlsym(RTLD_DEFAULT, alt);\n";
  Buffer.add_string buf "                        }\n";
  Buffer.add_string buf "                        if (!sym_ptr) {\n";
  Buffer.add_string buf "                            sym_ptr = asgard_resolve_constant(sym_name);\n";
  Buffer.add_string buf "                        }\n";
  Buffer.add_string buf "                    }\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                if (vm->vsp_idx < 4096) {\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, (uint64_t)sym_ptr);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* SETCC */ {\n" enc.op_map.op_setcc);
  Buffer.add_string buf "                uint8_t cond = fetch_byte(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                uint64_t res = eval_cond(vm, cond) ? 1ULL : 0ULL;\n";
  Buffer.add_string buf "                if (vm->vsp_idx < 4096) {\n";
  Buffer.add_string buf "                    vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vkey, vm->vsp_idx, res);\n";
  Buffer.add_string buf "                    ++vm->vsp_idx;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* CMOV */ {\n" enc.op_map.op_cmov);
  Buffer.add_string buf "                uint8_t cond = fetch_byte(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                int16_t idx = fetch_i16(vm, bytecode, &vip);\n";
  Buffer.add_string buf "                if (vm->vsp_idx > 0) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t v = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    if (eval_cond(vm, cond) && idx >= 0 && idx < max_ctx) {\n";
  Buffer.add_string buf "                        vm->ctx[idx] = v;\n";
  Buffer.add_string buf "                    }\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* CMP */ {\n" enc.op_map.op_cmp);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = a - b;\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->cf = (a < b);\n";
  Buffer.add_string buf "                    vm->of = (((a ^ b) & (a ^ res)) >> 63) & 1;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf (Printf.sprintf "            case 0x%02X: /* TEST */ {\n" enc.op_map.op_test);
  Buffer.add_string buf "                if (vm->vsp_idx >= 2) {\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t b = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    --vm->vsp_idx;\n";
  Buffer.add_string buf "                    uint64_t a = VSP_ENCODE(vm->vkey, vm->vsp_idx, vm->vsp[vm->vsp_idx]);\n";
  Buffer.add_string buf "                    uint64_t res = a & b;\n";
  Buffer.add_string buf "                    vm->zf = (res == 0);\n";
  Buffer.add_string buf "                    vm->sf = ((int64_t)res < 0);\n";
  Buffer.add_string buf "                    vm->cf = 0;\n";
  Buffer.add_string buf "                    vm->of = 0;\n";
  Buffer.add_string buf "                }\n";
  Buffer.add_string buf "                break;\n";
  Buffer.add_string buf "            }\n";
  Buffer.add_string buf "            default: vm->halted = 1; break;\n";
  Buffer.add_string buf "        }\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "}\n\n";

  (* 7. stack_vm_call *)
  Buffer.add_string buf "static inline uint64_t stack_vm_call(const uint64_t* bc_words, size_t len_words,\n";
  Buffer.add_string buf "                                      uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0,\n";
  Buffer.add_string buf "                                      uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {\n";
  Buffer.add_string buf "    stack_vm_t vm;\n";
  Buffer.add_string buf "    memset(&vm, 0, sizeof(vm));\n";
  Buffer.add_string buf (Printf.sprintf "    vm.vkey = 0x%016LXULL;\n" enc.seed_key);
  Buffer.add_string buf "    alignas(16) static thread_local uint8_t host_stack[1048576];\n";
  Buffer.add_string buf "    uint64_t sp_val = (uint64_t)(host_stack + sizeof(host_stack) - 8192);\n";
  Buffer.add_string buf "    vm.ctx[0] = a0;\n";
  Buffer.add_string buf "    vm.ctx[1] = a1;\n";
  Buffer.add_string buf "    vm.ctx[2] = a2;\n";
  Buffer.add_string buf "    vm.ctx[3] = a3;\n";
  Buffer.add_string buf "    vm.ctx[4] = sp_val;\n";
  Buffer.add_string buf "    vm.ctx[5] = sp_val;\n";
  Buffer.add_string buf "    vm.ctx[6] = a4;\n";
  Buffer.add_string buf "    vm.ctx[7] = a5;\n";
  Buffer.add_string buf "    vm.ctx[8] = a6;\n";
  Buffer.add_string buf "    vm.ctx[9] = a7;\n";
  Buffer.add_string buf "    const uint8_t* bc_bytes = (const uint8_t*)bc_words;\n";
  Buffer.add_string buf "    stack_vm_run(&vm, bc_bytes, len_words * 8);\n";
  Buffer.add_string buf "    return vm.ctx[0];\n";
  Buffer.add_string buf "}\n\n";

  Buffer.add_string buf "} // namespace asgard_stack_vm\n\n";

  Buffer.add_string buf "namespace vanguard_threaded_vm {\n";
  Buffer.add_string buf "    static inline uint64_t asgard_vm_call(const uint64_t* bc, size_t len,\n";
  Buffer.add_string buf "                                          uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0,\n";
  Buffer.add_string buf "                                          uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {\n";
  Buffer.add_string buf "        return asgard_stack_vm::stack_vm_call(bc, len, a0, a1, a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string buf "    }\n";
  Buffer.add_string buf "} // namespace vanguard_threaded_vm\n";

  Buffer.contents buf

let emit_runner_cpp ?(header_name = "stack_vm_runtime.hpp") bytecode =
  let b = Buffer.create 1024 in
  Buffer.add_string b (Printf.sprintf "#include \"%s\"\n#include <stdio.h>\n#include <stdlib.h>\n\n" header_name);
  Buffer.add_string b "static uint64_t embedded_bytecode[] = {\n";
  List.iter (fun w -> Buffer.add_string b (Printf.sprintf "    0x%016LXULL,\n" w)) bytecode;
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "int main(int argc, char** argv) {\n";
  Buffer.add_string b "    uint64_t* bc_ptr = embedded_bytecode;\n";
  Buffer.add_string b "    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);\n";
  Buffer.add_string b "    if (argc >= 2) {\n";
  Buffer.add_string b "        FILE* f = fopen(argv[1], \"rb\");\n";
  Buffer.add_string b "        if (f) {\n";
  Buffer.add_string b "            fseek(f, 0, SEEK_END);\n";
  Buffer.add_string b "            long sz = ftell(f);\n";
  Buffer.add_string b "            fseek(f, 0, SEEK_SET);\n";
  Buffer.add_string b "            if (sz > 0 && (sz % 8) == 0) {\n";
  Buffer.add_string b "                size_t count = (size_t)sz / 8;\n";
  Buffer.add_string b "                uint64_t* heap_bc = (uint64_t*)malloc((size_t)sz);\n";
  Buffer.add_string b "                if (heap_bc && fread(heap_bc, 8, count, f) == count) {\n";
  Buffer.add_string b "                    bc_ptr = heap_bc;\n";
  Buffer.add_string b "                    bc_len = count;\n";
  Buffer.add_string b "                }\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            fclose(f);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    uint64_t ret = vanguard_threaded_vm::asgard_vm_call(bc_ptr, bc_len);\n";
  Buffer.add_string b "    printf(\"[Stack-VM] Execution SUCCESS! Result: %llu\\n\", (unsigned long long)ret);\n";
  Buffer.add_string b "    return 0;\n";
  Buffer.add_string b "}\n";
  Buffer.contents b
