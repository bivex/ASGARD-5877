let emit_control_handlers b ?rng ~enable_nanomites ~enable_running_key ?(enable_address_bound = false) () =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  let maybe_reanchor () =
    if enable_running_key then begin
      if enable_address_bound then
        Buffer.add_string b "        ctx.reanchor_running_key((uint64_t)vIP_idx, g_handlers_hash);\n"
      else
        Buffer.add_string b "        ctx.reanchor_running_key((uint64_t)vIP_idx);\n"
    end
  in

  Buffer.add_string b "    H_JMP: {\n";
  if enable_nanomites then begin
    Buffer.add_string b "#if defined(__APPLE__)\n";
    Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
    Buffer.add_string b "#elif defined(_WIN32)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        __debugbreak();\n";
    Buffer.add_string b "        vIP_idx = asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0 ? (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target : (size_t)imm;\n";
    Buffer.add_string b "#elif defined(__linux__) && !defined(_MSC_VER)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        raise(SIGTRAP);\n";
    Buffer.add_string b "        vIP_idx = asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0 ? (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target : (size_t)imm;\n";
    Buffer.add_string b "#else\n";
    Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
    Buffer.add_string b "#endif\n";
  end else begin
    (match pick_variant 3 with
     | 0 -> Buffer.add_string b "        vIP_idx = (size_t)imm;\n"
     | 1 -> Buffer.add_string b "        size_t _target = (size_t)imm; vIP_idx = _target;\n"
     | _ -> Buffer.add_string b "        vIP_idx = (size_t)((uint64_t)imm & ~0ULL);\n");
  end;
  maybe_reanchor ();
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_JCC: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  Buffer.add_string b "        uint64_t t_true = (uint64_t)((word >> 22) & 0x1FFFFFULL);\n";
  Buffer.add_string b "        uint64_t t_false = (uint64_t)((word >> 43) & 0x1FFFFFULL);\n";
  Buffer.add_string b "        uint64_t c = eval_condition(ctx, cond) ? 1ULL : 0ULL;\n";
  if enable_nanomites then begin
    Buffer.add_string b "#if defined(__APPLE__)\n";
    Buffer.add_string b "        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);\n";
    Buffer.add_string b "#elif defined(_WIN32)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = (uint32_t)c;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, t_true, t_false, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        __debugbreak();\n";
    Buffer.add_string b "        vIP_idx = asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0 ? (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target : (size_t)(c * t_true + (1ULL - c) * t_false);\n";
    Buffer.add_string b "#elif defined(__linux__) && !defined(_MSC_VER)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = (uint32_t)c;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, t_true, t_false, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        raise(SIGTRAP);\n";
    Buffer.add_string b "        vIP_idx = asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0 ? (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target : (size_t)(c * t_true + (1ULL - c) * t_false);\n";
    Buffer.add_string b "#else\n";
    Buffer.add_string b "        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);\n";
    Buffer.add_string b "#endif\n";
  end else begin
    (match pick_variant 3 with
     | 0 ->
         Buffer.add_string b "        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);\n"
     | 1 ->
         Buffer.add_string b "        if (c) { vIP_idx = (size_t)t_true; } else { vIP_idx = (size_t)t_false; }\n"
     | _ ->
         Buffer.add_string b "        uint64_t _mask = c ? ~0ULL : 0ULL;\n";
         Buffer.add_string b "        vIP_idx = (size_t)((t_true & _mask) | (t_false & ~_mask));\n");
  end;
  maybe_reanchor ();
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMOV: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _m = eval_condition(ctx, cond) ? ~0ULL : 0ULL;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(src) & _m) | (ctx.get_reg(dst) & ~_m));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_reg(src), _d = ctx.get_reg(dst);\n";
       Buffer.add_string b "        ctx.set_reg(dst, eval_condition(ctx, cond) ? _s : _d);\n");
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SETCC: {\n";
  Buffer.add_string b "        PROBE_START();\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t val = eval_condition(ctx, cond) ? 1ULL : 0ULL;\n";
       Buffer.add_string b "        ctx.set_reg(dst, val);\n"
   | 1 ->
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(eval_condition(ctx, cond) ? 1 : 0));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _val = 0ULL;\n";
       Buffer.add_string b "        if (eval_condition(ctx, cond)) _val = 1ULL;\n";
       Buffer.add_string b "        ctx.set_reg(dst, _val);\n");
  Buffer.add_string b "        PROBE_CHECK();\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CALL: {\n";
  Buffer.add_string b "        ctx.push((uint64_t)vIP_idx);\n";
   if enable_nanomites then begin
     Buffer.add_string b "#if defined(__APPLE__)\n";
     Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
     Buffer.add_string b "#elif defined(_WIN32)\n";
     Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
     Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;\n";
     Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
     Buffer.add_string b "        __debugbreak();\n";
     Buffer.add_string b "        vIP_idx = asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0 ? (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target : (size_t)imm;\n";
     Buffer.add_string b "#elif defined(__linux__) && !defined(_MSC_VER)\n";
     Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
     Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;\n";
     Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
     Buffer.add_string b "        raise(SIGTRAP);\n";
     Buffer.add_string b "        vIP_idx = asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0 ? (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target : (size_t)imm;\n";
     Buffer.add_string b "#else\n";
     Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
     Buffer.add_string b "#endif\n";
   end else begin
     (match pick_variant 3 with
      | 0 -> Buffer.add_string b "        vIP_idx = (size_t)imm;\n"
      | 1 ->
          Buffer.add_string b "        size_t _target_vip = static_cast<size_t>(imm);\n";
          Buffer.add_string b "        vIP_idx = _target_vip;\n"
      | _ ->
          Buffer.add_string b "        uint64_t _imm_target = (uint64_t)imm;\n";
          Buffer.add_string b "        vIP_idx = (size_t)_imm_target;\n");
   end;
  maybe_reanchor ();
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IJMP_R: {\n";
  Buffer.add_string b "        uint64_t target = ctx.get_reg(dst);\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        if (target < count) {\n";
       Buffer.add_string b "            vIP_idx = (size_t)target;\n";
       Buffer.add_string b "        } else if (target) {\n"
   | 1 ->
       Buffer.add_string b "        if (__builtin_expect(target < count, 1)) {\n";
       Buffer.add_string b "            vIP_idx = static_cast<size_t>(target);\n";
       Buffer.add_string b "        } else if (target != 0) {\n"
   | _ ->
       Buffer.add_string b "        size_t _t_idx = (size_t)target;\n";
       Buffer.add_string b "        if (_t_idx < count) {\n";
       Buffer.add_string b "            vIP_idx = _t_idx;\n";
       Buffer.add_string b "        } else if (target) {\n");
  Buffer.add_string b "#if defined(__x86_64__) || defined(_M_X64)\n";
  Buffer.add_string b "            uint64_t a0 = ctx.get_reg(REG_RDI);\n";
  Buffer.add_string b "            uint64_t a1 = ctx.get_reg(REG_RSI);\n";
  Buffer.add_string b "            uint64_t a2 = ctx.get_reg(REG_RDX);\n";
  Buffer.add_string b "            uint64_t a3 = ctx.get_reg(REG_RCX);\n";
  Buffer.add_string b "            uint64_t a4 = ctx.get_reg(REG_R8);\n";
  Buffer.add_string b "            uint64_t a5 = ctx.get_reg(REG_R9);\n";
  Buffer.add_string b "#else\n";
  Buffer.add_string b "            uint64_t a0 = ctx.get_reg(REG_RAX);\n";
  Buffer.add_string b "            uint64_t a1 = ctx.get_reg(REG_RCX);\n";
  Buffer.add_string b "            uint64_t a2 = ctx.get_reg(REG_RDX);\n";
  Buffer.add_string b "            uint64_t a3 = ctx.get_reg(REG_RBX);\n";
  Buffer.add_string b "            uint64_t a4 = ctx.get_reg(REG_RSI);\n";
  Buffer.add_string b "            uint64_t a5 = ctx.get_reg(REG_RDI);\n";
  Buffer.add_string b "#endif\n";
  Buffer.add_string b "            typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);\n";
  Buffer.add_string b "            indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);\n";
  Buffer.add_string b "            uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);\n";
  Buffer.add_string b "            ctx.set_reg(REG_RAX, ret_val);\n";
  Buffer.add_string b "            goto EXIT_VM;\n";
  Buffer.add_string b "        }\n";
  maybe_reanchor ();
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ICALL_R: {\n";
  Buffer.add_string b "        uint64_t target_ptr = ctx.get_reg(dst);\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        if (target_ptr < count) {\n";
       Buffer.add_string b "            ctx.push((uint64_t)vIP_idx);\n";
       Buffer.add_string b "            vIP_idx = (size_t)target_ptr;\n";
       Buffer.add_string b "        } else if (target_ptr) {\n"
   | 1 ->
       Buffer.add_string b "        if (__builtin_expect(target_ptr < count, 1)) {\n";
       Buffer.add_string b "            uint64_t _ret = (uint64_t)vIP_idx;\n";
       Buffer.add_string b "            ctx.push(_ret);\n";
       Buffer.add_string b "            vIP_idx = static_cast<size_t>(target_ptr);\n";
       Buffer.add_string b "        } else if (target_ptr != 0) {\n"
   | _ ->
       Buffer.add_string b "        if (target_ptr < count) {\n";
       Buffer.add_string b "            ctx.push(static_cast<uint64_t>(vIP_idx));\n";
       Buffer.add_string b "            vIP_idx = (size_t)target_ptr;\n";
       Buffer.add_string b "        } else if (target_ptr) {\n");
  Buffer.add_string b "#if defined(__x86_64__) || defined(_M_X64)\n";
  Buffer.add_string b "            uint64_t a0 = ctx.get_reg(REG_RDI);\n";
  Buffer.add_string b "            uint64_t a1 = ctx.get_reg(REG_RSI);\n";
  Buffer.add_string b "            uint64_t a2 = ctx.get_reg(REG_RDX);\n";
  Buffer.add_string b "            uint64_t a3 = ctx.get_reg(REG_RCX);\n";
  Buffer.add_string b "            uint64_t a4 = ctx.get_reg(REG_R8);\n";
  Buffer.add_string b "            uint64_t a5 = ctx.get_reg(REG_R9);\n";
  Buffer.add_string b "#else\n";
  Buffer.add_string b "            uint64_t a0 = ctx.get_reg(REG_RAX);\n";
  Buffer.add_string b "            uint64_t a1 = ctx.get_reg(REG_RCX);\n";
  Buffer.add_string b "            uint64_t a2 = ctx.get_reg(REG_RDX);\n";
  Buffer.add_string b "            uint64_t a3 = ctx.get_reg(REG_RBX);\n";
  Buffer.add_string b "            uint64_t a4 = ctx.get_reg(REG_RSI);\n";
  Buffer.add_string b "            uint64_t a5 = ctx.get_reg(REG_RDI);\n";
  Buffer.add_string b "#endif\n";
  Buffer.add_string b "            typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);\n";
  Buffer.add_string b "            indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);\n";
  Buffer.add_string b "            uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);\n";
  Buffer.add_string b "            ctx.set_reg(REG_RAX, ret_val);\n";
  Buffer.add_string b "        }\n";
  maybe_reanchor ();
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;\n";
       Buffer.add_string b "    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;\n\n"
   | 1 ->
       Buffer.add_string b "    H_RET: case_ret: { if (!ctx.verify_canaries()) { ctx.trapped = true; } ctx.executed_instructions++; goto EXIT_VM; }\n";
       Buffer.add_string b "    H_EXIT: { if (!ctx.verify_canaries()) { ctx.trapped = true; } ctx.executed_instructions++; goto EXIT_VM; }\n\n"
   | _ ->
       Buffer.add_string b "    H_RET: case_ret: { if (ctx.sp > 512) { ctx.trapped = true; } ctx.executed_instructions += 1; goto EXIT_VM; }\n";
       Buffer.add_string b "    H_EXIT: { if (ctx.sp > 512) { ctx.trapped = true; } ctx.executed_instructions += 1; goto EXIT_VM; }\n\n");

  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "    H_BRIDGE_TO_FLOW: {\n";
       Buffer.add_string b "        ctx.morph_math_to_flow((uint64_t)imm);\n";
       Buffer.add_string b "        ctx.executed_instructions++;\n";
       Buffer.add_string b "        FETCH_NEXT();\n";
       Buffer.add_string b "    }\n";
       Buffer.add_string b "    H_BRIDGE_TO_MATH: {\n";
       Buffer.add_string b "        ctx.morph_flow_to_math((uint64_t)imm);\n";
       Buffer.add_string b "        ctx.executed_instructions++;\n";
       Buffer.add_string b "        FETCH_NEXT();\n";
       Buffer.add_string b "    }\n\n"
   | 1 ->
       Buffer.add_string b "    H_BRIDGE_TO_FLOW: {\n";
       Buffer.add_string b "        uint64_t _imm_flow = static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        ctx.morph_math_to_flow(_imm_flow);\n";
       Buffer.add_string b "        ctx.executed_instructions += 1;\n";
       Buffer.add_string b "        FETCH_NEXT();\n";
       Buffer.add_string b "    }\n";
       Buffer.add_string b "    H_BRIDGE_TO_MATH: {\n";
       Buffer.add_string b "        uint64_t _imm_math = static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        ctx.morph_flow_to_math(_imm_math);\n";
       Buffer.add_string b "        ctx.executed_instructions += 1;\n";
       Buffer.add_string b "        FETCH_NEXT();\n";
       Buffer.add_string b "    }\n\n"
   | _ ->
       Buffer.add_string b "    H_BRIDGE_TO_FLOW: {\n";
       Buffer.add_string b "        ctx.morph_math_to_flow((uint64_t)(imm & 0xFFFFFFFFFFFFFFFFULL));\n";
       Buffer.add_string b "        ctx.executed_instructions++;\n";
       Buffer.add_string b "        FETCH_NEXT();\n";
       Buffer.add_string b "    }\n";
       Buffer.add_string b "    H_BRIDGE_TO_MATH: {\n";
       Buffer.add_string b "        ctx.morph_flow_to_math((uint64_t)(imm & 0xFFFFFFFFFFFFFFFFULL));\n";
       Buffer.add_string b "        ctx.executed_instructions++;\n";
       Buffer.add_string b "        FETCH_NEXT();\n";
       Buffer.add_string b "    }\n\n")

let emit_super_operators ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  Buffer.add_string b "    H_FUSED_MOV_ADD_RRI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        ctx.set_reg(dst, ctx.get_reg(src) + (uint64_t)imm);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _base = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _base + static_cast<uint64_t>(imm));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_reg(src), _i = (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_s ^ _i) + 2 * (_s & _i));\n");
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_FUSED_ADD_IMUL_RRI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) * (uint64_t)imm);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _sum = ctx.get_reg(dst) + ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _sum * static_cast<uint64_t>(imm));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _imm = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t _res = (ctx.get_reg(dst) * _imm) + (ctx.get_reg(src) * _imm);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _res);\n");
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_FUSED_ADD_XOR_RRI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) ^ (uint64_t)imm);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _sum = ctx.get_reg(dst) + ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t _imm = static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_sum + _imm) - 2 * (_sum & _imm));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _imm = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t _sum = ctx.get_reg(dst) + ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_sum | _imm) - (_sum & _imm));\n");
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_FUSED_SUB_XOR_RRI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) - ctx.get_reg(src)) ^ (uint64_t)imm);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _diff = ctx.get_reg(dst) - ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t _imm = static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_diff + _imm) - 2 * (_diff & _imm));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _imm = (uint64_t)imm;\n";
       Buffer.add_string b "        uint64_t _diff = ctx.get_reg(dst) - ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_diff | _imm) - (_diff & _imm));\n");
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_FUSED_XOR_ADD_RRI: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (uint64_t)imm);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _a = ctx.get_reg(dst), _b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t _x = (_a + _b) - 2 * (_a & _b);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _x + static_cast<uint64_t>(imm));\n"
   | _ ->
       Buffer.add_string b "        uint64_t _a = ctx.get_reg(dst), _b = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t _x = (_a | _b) - (_a & _b);\n";
       Buffer.add_string b "        uint64_t _i = (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (_x | _i) + (_x & _i));\n");
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";

  Buffer.add_string b "    H_FUSED_CMP_CMOV: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 54) & 0x7F);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 54) & 0x7F);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        uint64_t _m = eval_condition(ctx, cond) ? ~0ULL : 0ULL;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(src) & _m) | (a & ~_m));\n"
   | _ ->
       Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
       Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);\n";
       Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 54) & 0x7F);\n";
       Buffer.add_string b "        compute_sub_flags(ctx, a, b, bits);\n";
       Buffer.add_string b "        uint64_t _val = eval_condition(ctx, cond) ? ctx.get_reg(src) : a;\n";
       Buffer.add_string b "        ctx.set_reg(dst, _val);\n");
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n\n"
