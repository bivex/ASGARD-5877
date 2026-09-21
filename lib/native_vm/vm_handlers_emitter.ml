let emit_handlers_hpp b ~rng ~enable_timing_probes =
  let pick_poly_add () =
    match Random.State.int rng 4 with
    | 0 -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)) + 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | 1 -> "((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | 2 -> "(2 * (ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))"
    | _ -> "ctx.rns_add(ctx.get_reg(dst), ctx.get_reg(src))"
  in
  let pick_poly_sub () =
    match Random.State.int rng 3 with
    | 0 -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)) - 2 * ((~ctx.get_reg(dst)) & ctx.get_reg(src)))"
    | 1 -> "(2 * (ctx.get_reg(dst) & (~ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))"
    | _ -> "ctx.rns_sub(ctx.get_reg(dst), ctx.get_reg(src))"
  in
  let pick_poly_xor () =
    match Random.State.int rng 2 with
    | 0 -> "((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | _ -> "((ctx.get_reg(dst) + ctx.get_reg(src)) - 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))"
  in

  if enable_timing_probes then begin
    Buffer.add_string b "    #if defined(__x86_64__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #elif defined(__aarch64__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t0))\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #else\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0 = 0\n";
    Buffer.add_string b "    #define PROBE_CHECK() do {} while(0)\n";
    Buffer.add_string b "    #endif\n\n";
  end else begin
    Buffer.add_string b "    #define PROBE_START() do {} while(0)\n";
    Buffer.add_string b "    #define PROBE_CHECK() do {} while(0)\n\n";
  end;

  Buffer.add_string b "    H_NOP: ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RR: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RI: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_HIGH: {\n";
  Buffer.add_string b "        uint64_t high_val = (uint64_t)(uint32_t)imm << 32;\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b (Printf.sprintf "    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (pick_poly_add ()));
  Buffer.add_string b "    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b (Printf.sprintf "    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (pick_poly_sub ()));
  Buffer.add_string b "    H_SUB_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) - 2 * ((~ctx.get_reg(dst)) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_IMUL_RR: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
  Buffer.add_string b "        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));\n";
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IMUL_RI: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
  Buffer.add_string b "        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));\n";
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b (Printf.sprintf "    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (pick_poly_xor ()));
  Buffer.add_string b "    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) ^ (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_AND_RR: ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) | ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_AND_RI: ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_OR_RR: ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_OR_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";

  Buffer.add_string b "    H_ROL_RI: {\n";
  Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
  Buffer.add_string b "        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ROR_RI: {\n";
  Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
  Buffer.add_string b "        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SHL_RI: {\n";
  Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
  Buffer.add_string b "        ctx.set_reg(dst, val << shift);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SHR_RI: {\n";
  Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
  Buffer.add_string b "        ctx.set_reg(dst, val >> shift);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_CMP_RI: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMP_RR: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_PUSH_R: ctx.push(ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_POP_R: ctx.set_reg(dst, ctx.pop()); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_JMP: {\n";
  Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_JCC: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        uint64_t t_true = (uint64_t)((word >> 22) & 0x1FFFFFULL);\n";
  Buffer.add_string b "        uint64_t t_false = (uint64_t)((word >> 43) & 0x1FFFFFULL);\n";
  Buffer.add_string b "        uint64_t c = eval_condition(ctx, cond) ? 1ULL : 0ULL;\n";
  Buffer.add_string b "        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMOV: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SETCC: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        uint64_t val = eval_condition(ctx, cond) ? 1ULL : 0ULL;\n";
  Buffer.add_string b "        ctx.set_reg(dst, val);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CALL: {\n";
  Buffer.add_string b "        ctx.push((uint64_t)vIP_idx);\n";
  Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;\n";
  Buffer.add_string b "    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;\n\n";

  (* Super-Operators *)
  Buffer.add_string b "    H_FUSED_MOV_ADD_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, ctx.get_reg(src) + (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_ADD_IMUL_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) * (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_ADD_XOR_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) ^ (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_SUB_XOR_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) - ctx.get_reg(src)) ^ (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_XOR_ADD_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_CMP_CMOV: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);\n";
  Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n\n";

  Buffer.add_string b "    H_BRIDGE_TO_FLOW: {\n";
  Buffer.add_string b "        ctx.morph_math_to_flow((uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions++;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_BRIDGE_TO_MATH: {\n";
  Buffer.add_string b "        ctx.morph_flow_to_math((uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions++;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_DECOY_0: { ctx.set_reg(dst, ctx.get_reg(dst) ^ 0x5877ULL); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_1: { ctx.set_reg(dst, ctx.get_reg(dst) + (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_2: { ctx.set_reg(dst, ctx.get_reg(dst) * 0x9E37ULL); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_3: { ctx.set_reg(dst, (ctx.get_reg(dst) << 3) | (ctx.get_reg(dst) >> 61)); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_4: { ctx.set_reg(dst, ctx.get_reg(src) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_5: { ctx.set_reg(dst, ctx.get_reg(dst) & ~ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_6: { ctx.set_reg(dst, ctx.get_reg(dst) | 0xCAFEBABEULL); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_7: { ctx.set_reg(dst, (ctx.get_reg(dst) >> 5) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_8: { ctx.set_reg(dst, ctx.get_reg(dst) - 0x1337ULL); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_9: { ctx.set_reg(dst, ctx.get_reg(dst) ^ (ctx.get_reg(src) + 1)); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_10: { ctx.set_reg(dst, (ctx.get_reg(dst) * 6364136223846793005ULL) + 1); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_11: { ctx.set_reg(dst, (ctx.get_reg(dst) << 7) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_12: { ctx.set_reg(dst, ctx.get_reg(dst) ^ 0xDEADBEEFULL); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_13: { ctx.set_reg(dst, ctx.get_reg(dst) + ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_14: { ctx.set_reg(dst, ctx.get_reg(dst) ^ (uint64_t)(imm * 3)); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY_15: { ctx.set_reg(dst, ~ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b "    H_DECOY:\n";
  Buffer.add_string b "        ctx.trapped = true;\n";
  Buffer.add_string b "        goto EXIT_VM;\n\n"
