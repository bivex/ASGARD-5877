let emit_probes b ~enable_timing_probes =
  if enable_timing_probes then begin
    Buffer.add_string b "    #if defined(__x86_64__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #elif defined(__aarch64__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t0))\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #elif defined(__riscv) || defined(__riscv__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0; __asm__ volatile(\"rdtime %0\" : \"=r\"(_t0))\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile(\"rdtime %0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 150000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #else\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0 = 0\n";
    Buffer.add_string b "    #define PROBE_CHECK() do {} while(0)\n";
    Buffer.add_string b "    #endif\n\n";
  end else begin
    Buffer.add_string b "    #define PROBE_START() do {} while(0)\n";
    Buffer.add_string b "    #define PROBE_CHECK() do {} while(0)\n\n";
  end

let emit_alu_handlers b ~rng ~enable_egraph_expansion ?(enable_ephemeral_jit = false) () =
  let pick_variant n = Random.State.int rng n in
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
    match Random.State.int rng 3 with
    | 0 -> "((ctx.get_reg(dst) + ctx.get_reg(src)) - 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | 1 -> "((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | _ -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)))"
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
  let pick_poly_and () =
    match Random.State.int rng 3 with
    | 0 -> "(ctx.get_reg(dst) & ctx.get_reg(src))"
    | 1 -> "((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) | ctx.get_reg(src)))"
    | _ -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (ctx.get_reg(dst) | ctx.get_reg(src)))"
  in
  let pick_poly_or () =
    match Random.State.int rng 3 with
    | 0 -> "(ctx.get_reg(dst) | ctx.get_reg(src))"
    | 1 -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | _ -> "((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))"
  in

  let h_and_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_and_rr ~rng
    else pick_poly_and ()
  in
  let h_or_rr_expr () =
    if enable_egraph_expansion then Egraph_cpp_emitter.egraph_or_rr ~rng
    else pick_poly_or ()
  in

  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_NOP: ctx.executed_instructions++; FETCH_NEXT();\n"
   | 1 -> Buffer.add_string b "    H_NOP: { ctx.executed_instructions += 1; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_NOP: { (void)dst; ctx.executed_instructions++; FETCH_NEXT(); }\n");
  (match Random.State.int rng 3 with
   | 0 -> Buffer.add_string b "    H_MOV_RR: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();\n"
   | 1 -> Buffer.add_string b "    H_MOV_RR: { uint64_t _v = ctx.get_reg(src); ctx.set_reg(dst, _v); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_MOV_RR: { if (dst != src) ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  (match Random.State.int rng 3 with
   | 0 -> Buffer.add_string b "    H_MOV_RI: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();\n"
   | 1 -> Buffer.add_string b "    H_MOV_RI: { uint64_t _imm_u64 = static_cast<uint64_t>(static_cast<uint32_t>(imm)); ctx.set_reg(dst, _imm_u64); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_MOV_RI: { uint32_t _u32 = (uint32_t)imm; ctx.set_reg(dst, (uint64_t)_u32); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  Buffer.add_string b "    H_MOV_HIGH: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t high_val = (uint64_t)(uint32_t)imm << 32;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _d = ctx.get_reg(dst);\n";
       Buffer.add_string b "        uint64_t _hi = static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_d & 0xFFFFFFFFULL) ^ _hi);\n"
   | _ ->
       Buffer.add_string b "        uint32_t _low32 = static_cast<uint32_t>(ctx.get_reg(dst));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32) | static_cast<uint64_t>(_low32));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_NEG_RR: { PROBE_START(); ctx.set_reg(dst, 0ULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_NEG_RR: { PROBE_START(); uint64_t _v = ctx.get_reg(dst); ctx.set_reg(dst, (~_v) + 1ULL); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_NEG_RR: { PROBE_START(); ctx.set_reg(dst, static_cast<uint64_t>(-static_cast<int64_t>(ctx.get_reg(dst)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_NOT_RR: { PROBE_START(); ctx.set_reg(dst, ~ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_NOT_RR: { PROBE_START(); uint64_t _v = ctx.get_reg(dst); ctx.set_reg(dst, _v ^ ~0ULL); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_NOT_RR: { PROBE_START(); ctx.set_reg(dst, 0xFFFFFFFFFFFFFFFFULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  Buffer.add_string b "    H_BSWAP_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t res;\n";
       Buffer.add_string b "        if (bits == 16) { res = (uint64_t)__builtin_bswap16((uint16_t)val); }\n";
       Buffer.add_string b "        else if (bits == 32) { res = (uint64_t)__builtin_bswap32((uint32_t)val); }\n";
       Buffer.add_string b "        else { res = __builtin_bswap64(val); }\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _val = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t _b = static_cast<uint32_t>(imm);\n";
       Buffer.add_string b "        uint64_t _r = (_b == 16) ? static_cast<uint64_t>(__builtin_bswap16(static_cast<uint16_t>(_val)))\n";
       Buffer.add_string b "                     : ((_b == 32) ? static_cast<uint64_t>(__builtin_bswap32(static_cast<uint32_t>(_val)))\n";
       Buffer.add_string b "                                   : __builtin_bswap64(_val));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _r);\n"
   | _ ->
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        if (bits == 16) ctx.set_reg(dst, (uint64_t)__builtin_bswap16((uint16_t)ctx.get_reg(src)));\n";
       Buffer.add_string b "        else if (bits == 32) ctx.set_reg(dst, (uint64_t)__builtin_bswap32((uint32_t)ctx.get_reg(src)));\n";
       Buffer.add_string b "        else ctx.set_reg(dst, __builtin_bswap64(ctx.get_reg(src)));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CLZ_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t mval = val & mask;\n";
       Buffer.add_string b "        uint64_t res;\n";
       Buffer.add_string b "        if (bits <= 32) {\n";
       Buffer.add_string b "            uint32_t v32 = (uint32_t)mval;\n";
       Buffer.add_string b "            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz(v32) - (32 - bits));\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval);\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _s = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t _bits = static_cast<uint32_t>(imm);\n";
       Buffer.add_string b "        uint64_t _mask = (_bits >= 64) ? ~0ULL : ((1ULL << _bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t _ms = _s & _mask;\n";
       Buffer.add_string b "        if (_bits <= 32) {\n";
       Buffer.add_string b "            uint32_t _v32 = static_cast<uint32_t>(_ms);\n";
       Buffer.add_string b "            ctx.set_reg(dst, (_v32 == 0) ? static_cast<uint64_t>(_bits) : static_cast<uint64_t>(__builtin_clz(_v32) - (32 - _bits)));\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.set_reg(dst, (_ms == 0) ? 64ULL : static_cast<uint64_t>(__builtin_clzll(_ms)));\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src); uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t mval = val & mask;\n";
       Buffer.add_string b "        uint64_t _clz = (bits <= 32) ? (((uint32_t)mval == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz((uint32_t)mval) - (32 - bits)))\n";
       Buffer.add_string b "                                     : ((mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _clz);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CTZ_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t mval = val & mask;\n";
       Buffer.add_string b "        uint64_t res;\n";
       Buffer.add_string b "        if (bits <= 32) {\n";
       Buffer.add_string b "            uint32_t v32 = (uint32_t)mval;\n";
       Buffer.add_string b "            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)__builtin_ctz(v32);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_ctzll(mval);\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _s = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t _bits = static_cast<uint32_t>(imm);\n";
       Buffer.add_string b "        uint64_t _mask = (_bits >= 64) ? ~0ULL : ((1ULL << _bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t _ms = _s & _mask;\n";
       Buffer.add_string b "        if (_bits <= 32) {\n";
       Buffer.add_string b "            uint32_t _v32 = static_cast<uint32_t>(_ms);\n";
       Buffer.add_string b "            ctx.set_reg(dst, (_v32 == 0) ? static_cast<uint64_t>(_bits) : static_cast<uint64_t>(__builtin_ctz(_v32)));\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.set_reg(dst, (_ms == 0) ? 64ULL : static_cast<uint64_t>(__builtin_ctzll(_ms)));\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src); uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t mval = val & mask;\n";
       Buffer.add_string b "        uint64_t _ctz = (bits <= 32) ? (((uint32_t)mval == 0) ? (uint64_t)bits : (uint64_t)__builtin_ctz((uint32_t)mval))\n";
       Buffer.add_string b "                                     : ((mval == 0) ? 64ULL : (uint64_t)__builtin_ctzll(mval));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _ctz);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_POPCNT_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t mval = val & mask;\n";
       Buffer.add_string b "        uint64_t res = (bits <= 32) ? (uint64_t)__builtin_popcount((uint32_t)mval) : (uint64_t)__builtin_popcountll(mval);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _s = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t _b = static_cast<uint32_t>(imm);\n";
       Buffer.add_string b "        uint64_t _mask = (_b >= 64) ? ~0ULL : ((1ULL << _b) - 1ULL);\n";
       Buffer.add_string b "        uint64_t _ms = _s & _mask;\n";
       Buffer.add_string b "        uint64_t _res = (_b <= 32) ? static_cast<uint64_t>(__builtin_popcount(static_cast<uint32_t>(_ms))) : static_cast<uint64_t>(__builtin_popcountll(_ms));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n"
   | _ ->
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);\n";
       Buffer.add_string b "        uint64_t mval = ctx.get_reg(src) & mask;\n";
       Buffer.add_string b "        if (bits <= 32) {\n";
       Buffer.add_string b "            ctx.set_reg(dst, (uint64_t)__builtin_popcount((uint32_t)mval));\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.set_reg(dst, (uint64_t)__builtin_popcountll(mval));\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_RBIT_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t res = 0;\n";
       Buffer.add_string b "        for (uint32_t i = 0; i < bits; ++i) {\n";
       Buffer.add_string b "            if ((val >> i) & 1ULL) { res |= (1ULL << (bits - 1 - i)); }\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _val = ctx.get_reg(src); uint32_t _bits = static_cast<uint32_t>(imm);\n";
       Buffer.add_string b "        uint64_t _res = 0; uint32_t _i = 0;\n";
       Buffer.add_string b "        while (_i < _bits) {\n";
       Buffer.add_string b "            if ((_val >> _i) & 1ULL) _res |= (1ULL << (_bits - 1 - _i));\n";
       Buffer.add_string b "            _i++;\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(src); uint32_t bits = (uint32_t)imm;\n";
       Buffer.add_string b "        uint64_t res = 0;\n";
       Buffer.add_string b "        for (uint32_t i = 0; i < bits; ++i) {\n";
       Buffer.add_string b "            uint64_t _b = (val >> i) & 1ULL;\n";
       Buffer.add_string b "            res ^= (_b << (bits - 1 - i));\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  if enable_ephemeral_jit then begin
    Buffer.add_string b "#if defined(ASGARD_EPHEMERAL_JIT)\n";
    Buffer.add_string b "    H_ADD_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ADD_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_ADD_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ADD_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SUB_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SUB_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SUB_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SUB_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_IMUL_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_MUL_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_IMUL_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_MUL_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_XOR_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_XOR_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_XOR_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_XOR_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_AND_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_AND_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_AND_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_AND_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_OR_RR:  { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_OR_RR,  dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_OR_RI:  { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_OR_RI,  dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "#else\n"
  end;
    Buffer.add_string b (Printf.sprintf "    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_add_rr_expr ()));
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_ADD_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, _d + static_cast<uint64_t>(imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_ADD_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst), _i = (uint64_t)imm; ctx.set_reg(dst, (_d | _i) + (_d & _i)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  Buffer.add_string b (Printf.sprintf "    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_sub_rr_expr ()));
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_SUB_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) - 2 * ((~ctx.get_reg(dst)) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_SUB_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, _d - static_cast<uint64_t>(imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_SUB_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst), _i = (uint64_t)imm; ctx.set_reg(dst, _d + (~_i + 1ULL)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  Buffer.add_string b "    H_IMUL_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        PROBE_START();\n";
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));\n";
       Buffer.add_string b "        PROBE_CHECK();\n"
   | 1 ->
       Buffer.add_string b "        PROBE_START();\n";
       Buffer.add_string b "        uint64_t _a = ctx.get_reg(dst), _b = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _a * _b);\n";
       Buffer.add_string b "        PROBE_CHECK();\n"
   | _ ->
       Buffer.add_string b "        PROBE_START();\n";
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * static_cast<int64_t>(ctx.get_reg(src))));\n";
       Buffer.add_string b "        PROBE_CHECK();\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IMUL_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        PROBE_START();\n";
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));\n";
       Buffer.add_string b "        PROBE_CHECK();\n"
   | 1 ->
       Buffer.add_string b "        PROBE_START();\n";
       Buffer.add_string b "        uint64_t _d = ctx.get_reg(dst);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _d * static_cast<uint64_t>(imm));\n";
       Buffer.add_string b "        PROBE_CHECK();\n"
   | _ ->
       Buffer.add_string b "        PROBE_START();\n";
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * imm));\n";
       Buffer.add_string b "        PROBE_CHECK();\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b (Printf.sprintf "    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_xor_rr_expr ()));
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) - (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_XOR_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, _d ^ static_cast<uint64_t>(imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_XOR_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst), _i = (uint64_t)imm; ctx.set_reg(dst, (_d + _i) - 2 * (_d & _i)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  Buffer.add_string b (Printf.sprintf "    H_AND_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_and_rr_expr ()));
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_AND_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_AND_RI: { PROBE_START(); ctx.set_reg(dst, ctx.get_reg(dst) & static_cast<uint64_t>(imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_AND_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst), _i = (uint64_t)imm; ctx.set_reg(dst, (_d | _i) - (_d ^ _i)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  Buffer.add_string b (Printf.sprintf "    H_OR_RR: { PROBE_START(); ctx.set_reg(dst, %s); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n" (h_or_rr_expr ()));
  (match pick_variant 3 with
   | 0 -> Buffer.add_string b "    H_OR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | 1 -> Buffer.add_string b "    H_OR_RI: { PROBE_START(); ctx.set_reg(dst, ctx.get_reg(dst) | static_cast<uint64_t>(imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n"
   | _ -> Buffer.add_string b "    H_OR_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst), _i = (uint64_t)imm; ctx.set_reg(dst, (_d + _i) - (_d & _i)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }\n");
  if enable_ephemeral_jit then
    Buffer.add_string b "#endif\n";

  Buffer.add_string b "    H_ROL_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        uint64_t _res = (val << shift) | (val >> ((64 - shift) & 63));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ROR_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (v >> s) | (v << ((64 - s) & 63)));\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SHL_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, val << shift);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _res = ctx.get_reg(dst) << (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, v << s);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SHR_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, val >> shift);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, v >> s);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SAR_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));\n"
   | 1 ->
       Buffer.add_string b "        int64_t sval = (int64_t)ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(sval >> shift));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(imm & 63));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ROL_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        uint64_t _res = (val << shift) | (val >> ((64 - shift) & 63));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ROR_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (v >> s) | (v << ((64 - s) & 63)));\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SHL_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, val << shift);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _res = ctx.get_reg(dst) << (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, v << s);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SHR_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, val >> shift);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, v >> s);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SAR_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));\n"
   | 1 ->
       Buffer.add_string b "        int64_t sval = (int64_t)ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(sval >> shift));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_DIV_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        if (b == 0) { ctx.trapped = true; goto EXIT_VM; }\n";
       Buffer.add_string b "        ctx.set_reg(dst, a / b);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        if (__builtin_expect(!b, 0)) { ctx.trapped = true; goto EXIT_VM; }\n";
       Buffer.add_string b "        ctx.set_reg(dst, ctx.get_reg(dst) / b);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _divisor = ctx.get_reg(src);\n";
       Buffer.add_string b "        if (_divisor == 0ULL) { ctx.trapped = true; goto EXIT_VM; }\n";
       Buffer.add_string b "        uint64_t _dividend = ctx.get_reg(dst);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _dividend / _divisor);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IDIV_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        if (b == 0 || (b == -1 && a == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }\n";
       Buffer.add_string b "        int64_t q = (b == -1) ? (int64_t)(0 - (uint64_t)a) : (a / b);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)q);\n"
   | 1 ->
       Buffer.add_string b "        int64_t b = (int64_t)ctx.get_reg(src); int64_t a = (int64_t)ctx.get_reg(dst);\n";
       Buffer.add_string b "        if (__builtin_expect(b == 0 || (b == -1 && a == INT64_MIN), 0)) { ctx.trapped = true; goto EXIT_VM; }\n";
       Buffer.add_string b "        int64_t q = (b == -1) ? (int64_t)(0ULL - (uint64_t)a) : (a / b);\n";
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(q));\n"
   | _ ->
       Buffer.add_string b "        int64_t _d = static_cast<int64_t>(ctx.get_reg(dst)), _s = static_cast<int64_t>(ctx.get_reg(src));\n";
       Buffer.add_string b "        if (_s == 0 || (_s == -1 && _d == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }\n";
       Buffer.add_string b "        int64_t _quot = (_s == -1) ? (-_d) : (_d / _s);\n";
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(_quot));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_MULH_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        #if defined(__SIZEOF_INT128__)\n";
       Buffer.add_string b "        uint64_t res = (uint64_t)(((unsigned __int128)a * (unsigned __int128)b) >> 64);\n";
       Buffer.add_string b "        #else\n";
       Buffer.add_string b "        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;\n";
       Buffer.add_string b "        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;\n";
       Buffer.add_string b "        uint64_t p0 = a_lo * b_lo;\n";
       Buffer.add_string b "        uint64_t p1 = a_lo * b_hi;\n";
       Buffer.add_string b "        uint64_t p2 = a_hi * b_lo;\n";
       Buffer.add_string b "        uint64_t p3 = a_hi * b_hi;\n";
       Buffer.add_string b "        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;\n";
       Buffer.add_string b "        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;\n";
       Buffer.add_string b "        #endif\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        #if defined(__SIZEOF_INT128__)\n";
       Buffer.add_string b "        unsigned __int128 _prod = (unsigned __int128)a * (unsigned __int128)b;\n";
       Buffer.add_string b "        uint64_t res = static_cast<uint64_t>(_prod >> 64);\n";
       Buffer.add_string b "        #else\n";
       Buffer.add_string b "        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;\n";
       Buffer.add_string b "        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;\n";
       Buffer.add_string b "        uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;\n";
       Buffer.add_string b "        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;\n";
       Buffer.add_string b "        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;\n";
       Buffer.add_string b "        #endif\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | _ ->
       Buffer.add_string b "        #if defined(__SIZEOF_INT128__)\n";
       Buffer.add_string b "        uint64_t res = (uint64_t)(((unsigned __int128)ctx.get_reg(dst) * (unsigned __int128)ctx.get_reg(src)) >> 64);\n";
       Buffer.add_string b "        #else\n";
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;\n";
       Buffer.add_string b "        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;\n";
       Buffer.add_string b "        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;\n";
       Buffer.add_string b "        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;\n";
       Buffer.add_string b "        #endif\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IMULH_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        #if defined(__SIZEOF_INT128__)\n";
       Buffer.add_string b "        uint64_t res = (uint64_t)(((signed __int128)a * (signed __int128)b) >> 64);\n";
       Buffer.add_string b "        #else\n";
       Buffer.add_string b "        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;\n";
       Buffer.add_string b "        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;\n";
       Buffer.add_string b "        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;\n";
       Buffer.add_string b "        uint64_t p0 = a_lo * b_lo;\n";
       Buffer.add_string b "        uint64_t p1 = a_lo * b_hi;\n";
       Buffer.add_string b "        uint64_t p2 = a_hi * b_lo;\n";
       Buffer.add_string b "        uint64_t p3 = a_hi * b_hi;\n";
       Buffer.add_string b "        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;\n";
       Buffer.add_string b "        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;\n";
       Buffer.add_string b "        if (a < 0) res -= ub;\n";
       Buffer.add_string b "        if (b < 0) res -= ua;\n";
       Buffer.add_string b "        #endif\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        #if defined(__SIZEOF_INT128__)\n";
       Buffer.add_string b "        signed __int128 _prod = (signed __int128)a * (signed __int128)b;\n";
       Buffer.add_string b "        uint64_t res = static_cast<uint64_t>(_prod >> 64);\n";
       Buffer.add_string b "        #else\n";
       Buffer.add_string b "        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;\n";
       Buffer.add_string b "        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;\n";
       Buffer.add_string b "        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;\n";
       Buffer.add_string b "        uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;\n";
       Buffer.add_string b "        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;\n";
       Buffer.add_string b "        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;\n";
       Buffer.add_string b "        if (a < 0) res -= ub;\n";
       Buffer.add_string b "        if (b < 0) res -= ua;\n";
       Buffer.add_string b "        #endif\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | _ ->
       Buffer.add_string b "        #if defined(__SIZEOF_INT128__)\n";
       Buffer.add_string b "        uint64_t res = (uint64_t)(((signed __int128)(int64_t)ctx.get_reg(dst) * (signed __int128)(int64_t)ctx.get_reg(src)) >> 64);\n";
       Buffer.add_string b "        #else\n";
       Buffer.add_string b "        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;\n";
       Buffer.add_string b "        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;\n";
       Buffer.add_string b "        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;\n";
       Buffer.add_string b "        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;\n";
       Buffer.add_string b "        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;\n";
       Buffer.add_string b "        if (a < 0) res -= ub;\n";
       Buffer.add_string b "        if (b < 0) res -= ua;\n";
       Buffer.add_string b "        #endif\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMP_RI: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, a, b, bits);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _d = ctx.get_reg(dst);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, _d, static_cast<uint64_t>(imm), static_cast<uint32_t>((word >> 50) & 0x7F));\n"
   | _ ->
       Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);\n";
       Buffer.add_string b "        uint64_t _imm = (uint64_t)imm;\n";
       Buffer.add_string b "        compute_sub_flags(ctx, ctx.get_reg(dst), _imm, bits);\n");
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMP_RR: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, a, b, bits);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _a = ctx.get_reg(dst), _b = ctx.get_reg(src);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, _a, _b, static_cast<uint32_t>((word >> 50) & 0x7F));\n"
   | _ ->
       Buffer.add_string b "        uint32_t bits = static_cast<uint32_t>((word >> 50) & 0x7F);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, ctx.get_reg(dst), ctx.get_reg(src), bits);\n");
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_PUSH_R: {\n";
  (match Random.State.int rng 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst);\n";
       Buffer.add_string b "        ctx.push(val);\n";
       Buffer.add_string b "        uint64_t cur_sp = ctx.get_reg(REG_RSP);\n";
       Buffer.add_string b "        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {\n";
       Buffer.add_string b "            uint64_t sp_val = cur_sp - 8ULL;\n";
       Buffer.add_string b "            ctx.set_reg(REG_RSP, sp_val);\n";
       Buffer.add_string b "            *reinterpret_cast<uint64_t*>(sp_val) = val;\n";
       Buffer.add_string b "        }\n"
   | 1 ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst);\n";
       Buffer.add_string b "        ctx.push(val);\n";
       Buffer.add_string b "        uint64_t cur_sp = ctx.get_reg(REG_RSP);\n";
       Buffer.add_string b "        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {\n";
       Buffer.add_string b "            uint64_t* sp_ptr = reinterpret_cast<uint64_t*>(cur_sp - 8ULL);\n";
       Buffer.add_string b "            ctx.set_reg(REG_RSP, reinterpret_cast<uint64_t>(sp_ptr));\n";
       Buffer.add_string b "            *sp_ptr = val;\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        uint64_t val = ctx.get_reg(dst);\n";
       Buffer.add_string b "        ctx.push(val);\n";
       Buffer.add_string b "        uint64_t cur_sp = ctx.get_reg(REG_RSP);\n";
       Buffer.add_string b "        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {\n";
       Buffer.add_string b "            uint64_t sp_val = cur_sp - 8ULL;\n";
       Buffer.add_string b "            ctx.set_reg(REG_RSP, sp_val);\n";
       Buffer.add_string b "            std::memcpy(reinterpret_cast<void*>(sp_val), &val, sizeof(uint64_t));\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_POP_R: {\n";
  (match Random.State.int rng 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t cur_sp = ctx.get_reg(REG_RSP);\n";
       Buffer.add_string b "        uint64_t val = 0;\n";
       Buffer.add_string b "        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {\n";
       Buffer.add_string b "            val = *reinterpret_cast<const uint64_t*>(cur_sp);\n";
       Buffer.add_string b "            ctx.set_reg(REG_RSP, cur_sp + 8ULL);\n";
       Buffer.add_string b "            ctx.pop();\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            val = ctx.pop();\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, val);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t cur_sp = ctx.get_reg(REG_RSP);\n";
       Buffer.add_string b "        uint64_t val = 0;\n";
       Buffer.add_string b "        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {\n";
       Buffer.add_string b "            std::memcpy(&val, reinterpret_cast<const void*>(cur_sp), sizeof(uint64_t));\n";
       Buffer.add_string b "            ctx.set_reg(REG_RSP, cur_sp + 8ULL);\n";
       Buffer.add_string b "            ctx.pop();\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            val = ctx.pop();\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, val);\n"
   | _ ->
       Buffer.add_string b "        uint64_t cur_sp = ctx.get_reg(REG_RSP);\n";
       Buffer.add_string b "        uint64_t val = 0;\n";
       Buffer.add_string b "        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {\n";
       Buffer.add_string b "            const uint64_t* sp_ptr = reinterpret_cast<const uint64_t*>(cur_sp);\n";
       Buffer.add_string b "            val = *sp_ptr;\n";
       Buffer.add_string b "            ctx.set_reg(REG_RSP, cur_sp + sizeof(uint64_t));\n";
       Buffer.add_string b "            ctx.pop();\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            val = ctx.pop();\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(dst, val);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ADC_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t c = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t res = a + b + c;\n";
       Buffer.add_string b "        ctx.cf = (res < a) || (c && res == a);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t c = static_cast<uint64_t>(ctx.cf);\n";
       Buffer.add_string b "        uint64_t res = (a + b) + c;\n";
       Buffer.add_string b "        ctx.cf = (res < a) || (c && res == a);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = (res >> 63) != 0;\n";
       Buffer.add_string b "        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t c = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t ab = a + b;\n";
       Buffer.add_string b "        uint64_t res = ab + c;\n";
       Buffer.add_string b "        ctx.cf = (ab < a) || (res < ab);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ADC_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t c = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t res = a + b + c;\n";
       Buffer.add_string b "        ctx.cf = (res < a) || (c && res == a);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t c = static_cast<uint64_t>(ctx.cf);\n";
       Buffer.add_string b "        uint64_t res = (a + b) + c;\n";
       Buffer.add_string b "        ctx.cf = (res < a) || (c && res == a);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = (res >> 63) != 0;\n";
       Buffer.add_string b "        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t c = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t ab = a + b;\n";
       Buffer.add_string b "        uint64_t res = ab + c;\n";
       Buffer.add_string b "        ctx.cf = (ab < a) || (res < ab);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SBB_RR: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t res = a - b - borrow;\n";
       Buffer.add_string b "        ctx.cf = (a < b) || (borrow && a == b);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t borrow = static_cast<uint64_t>(ctx.cf);\n";
       Buffer.add_string b "        uint64_t res = (a - b) - borrow;\n";
       Buffer.add_string b "        ctx.cf = (a < b) || (borrow && a == b);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = (res >> 63) != 0;\n";
       Buffer.add_string b "        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t res = a - (b + borrow);\n";
       Buffer.add_string b "        ctx.cf = (a < b) || (borrow && a == b);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SBB_RI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t res = a - b - borrow;\n";
       Buffer.add_string b "        ctx.cf = (a < b) || (borrow && a == b);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t borrow = static_cast<uint64_t>(ctx.cf);\n";
       Buffer.add_string b "        uint64_t res = (a - b) - borrow;\n";
       Buffer.add_string b "        ctx.cf = (a < b) || (borrow && a == b);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = (res >> 63) != 0;\n";
       Buffer.add_string b "        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n"
   | _ ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        uint64_t res = a - (b + borrow);\n";
       Buffer.add_string b "        ctx.cf = (a < b) || (borrow && a == b);\n";
       Buffer.add_string b "        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);\n";
       Buffer.add_string b "        ctx.zf = (res == 0);\n";
       Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
       Buffer.add_string b "        ctx.set_reg(dst, res);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CCMP_RR: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  Buffer.add_string b "        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));\n";
  (match pick_variant 2 with
   | 0 ->
       Buffer.add_string b "        if (eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "            compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        if (!eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "            compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CCMP_RI: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  Buffer.add_string b "        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));\n";
  Buffer.add_string b "        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));\n";
  (match pick_variant 2 with
   | 0 ->
       Buffer.add_string b "        if (eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst);\n";
       Buffer.add_string b "            compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        if (!eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst);\n";
       Buffer.add_string b "            compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CCMN_RR: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  Buffer.add_string b "        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));\n";
  (match pick_variant 2 with
   | 0 ->
       Buffer.add_string b "        if (eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "            compute_add_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        if (!eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
       Buffer.add_string b "            compute_add_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CCMN_RI: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  Buffer.add_string b "        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));\n";
  Buffer.add_string b "        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));\n";
  (match pick_variant 2 with
   | 0 ->
       Buffer.add_string b "        if (eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst);\n";
       Buffer.add_string b "            compute_add_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        if (!eval_condition(ctx, cond)) {\n";
       Buffer.add_string b "            ctx.sf = (nzcv & 8) != 0;\n";
       Buffer.add_string b "            ctx.zf = (nzcv & 4) != 0;\n";
       Buffer.add_string b "            ctx.cf = (nzcv & 2) != 0;\n";
       Buffer.add_string b "            ctx.of = (nzcv & 1) != 0;\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            uint64_t a = ctx.get_reg(dst);\n";
       Buffer.add_string b "            compute_add_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_GET_FLAGS_R: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t f = 2ULL;\n";
       Buffer.add_string b "        if (ctx.cf) f |= 1ULL;\n";
       Buffer.add_string b "        if (ctx.zf) f |= 0x40ULL;\n";
       Buffer.add_string b "        if (ctx.sf) f |= 0x80ULL;\n";
       Buffer.add_string b "        if (ctx.of) f |= 0x800ULL;\n";
       Buffer.add_string b "        ctx.set_reg(dst, f);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t f = 2ULL | (ctx.cf ? 1ULL : 0ULL) | (ctx.zf ? 0x40ULL : 0ULL) | (ctx.sf ? 0x80ULL : 0ULL) | (ctx.of ? 0x800ULL : 0ULL);\n";
       Buffer.add_string b "        ctx.set_reg(dst, f);\n"
   | _ ->
       Buffer.add_string b "        uint64_t f = 2ULL;\n";
       Buffer.add_string b "        f |= (uint64_t)ctx.cf;\n";
       Buffer.add_string b "        f |= ((uint64_t)ctx.zf << 6);\n";
       Buffer.add_string b "        f |= ((uint64_t)ctx.sf << 7);\n";
       Buffer.add_string b "        f |= ((uint64_t)ctx.of << 11);\n";
       Buffer.add_string b "        ctx.set_reg(dst, f);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SET_FLAGS_R: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t f = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.cf = (f & 1ULL) != 0;\n";
       Buffer.add_string b "        ctx.zf = (f & 0x40ULL) != 0;\n";
       Buffer.add_string b "        ctx.sf = (f & 0x80ULL) != 0;\n";
       Buffer.add_string b "        ctx.of = (f & 0x800ULL) != 0;\n"
   | 1 ->
       Buffer.add_string b "        uint64_t f = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.cf = static_cast<bool>(f & 1ULL);\n";
       Buffer.add_string b "        ctx.zf = static_cast<bool>(f & 0x40ULL);\n";
       Buffer.add_string b "        ctx.sf = static_cast<bool>(f & 0x80ULL);\n";
       Buffer.add_string b "        ctx.of = static_cast<bool>(f & 0x800ULL);\n"
   | _ ->
       Buffer.add_string b "        uint64_t mask = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.cf = ((mask >> 0) & 1) != 0;\n";
       Buffer.add_string b "        ctx.zf = ((mask >> 6) & 1) != 0;\n";
       Buffer.add_string b "        ctx.sf = ((mask >> 7) & 1) != 0;\n";
       Buffer.add_string b "        ctx.of = ((mask >> 11) & 1) != 0;\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n"
