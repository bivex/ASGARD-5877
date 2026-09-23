let emit_probes b ~enable_timing_probes =
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
  end

let emit_alu_handlers b ~rng ~enable_egraph_expansion =
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

  let h_add_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_add_rr ~rng
    else pick_poly_add ()
  in
  let h_sub_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_sub_rr ~rng
    else pick_poly_sub ()
  in
  let h_xor_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_xor_rr ~rng
    else pick_poly_xor ()
  in
  let h_and_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_and_rr ~rng
    else "(ctx.get_reg(dst) & ctx.get_reg(src))"
  in
  let h_or_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_or_rr ~rng
    else "(ctx.get_reg(dst) | ctx.get_reg(src))"
  in

  Buffer.add_string b "    H_NOP: ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RR: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RI: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_HIGH: {\n";
  Buffer.add_string b "        uint64_t high_val = (uint64_t)(uint32_t)imm << 32;\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b (Printf.sprintf "    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_add_rr_expr ()));
  Buffer.add_string b "    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b (Printf.sprintf "    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_sub_rr_expr ()));
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
  Buffer.add_string b (Printf.sprintf "    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_xor_rr_expr ()));
  Buffer.add_string b "    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) ^ (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
  Buffer.add_string b (Printf.sprintf "    H_AND_RR: { ctx.set_reg(dst, %s); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_and_rr_expr ()));
  Buffer.add_string b "    H_AND_RI: ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b (Printf.sprintf "    H_OR_RR: { ctx.set_reg(dst, %s); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_or_rr_expr ()));
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
  Buffer.add_string b "    H_SAR_RI: {\n";
  Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
  Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  (* Division contract: divisor 0 yields quotient 0 (mirrors vm_eval), and
     INT64_MIN / -1 wraps to INT64_MIN instead of raising #DE / UB. *)
  Buffer.add_string b "    H_DIV_RR: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
  Buffer.add_string b "        ctx.set_reg(dst, (b == 0) ? 0ULL : (a / b));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IDIV_RR: {\n";
  Buffer.add_string b "        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);\n";
  Buffer.add_string b "        int64_t q = (b == 0) ? 0 : ((b == -1) ? (int64_t)(0 - (uint64_t)a) : (a / b));\n";
  Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)q);\n";
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
  Buffer.add_string b "    H_POP_R: ctx.set_reg(dst, ctx.pop()); ctx.executed_instructions++; FETCH_NEXT();\n"
