let emit_control_handlers b ~enable_nanomites ~enable_running_key ?(enable_address_bound = false) () =
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
    Buffer.add_string b "#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        raise(SIGTRAP);\n";
    Buffer.add_string b "        vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;\n";
    Buffer.add_string b "#else\n";
    Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
    Buffer.add_string b "#endif\n";
  end else begin
    Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
  end;
  maybe_reanchor ();
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_JCC: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        uint64_t t_true = (uint64_t)((word >> 22) & 0x1FFFFFULL);\n";
  Buffer.add_string b "        uint64_t t_false = (uint64_t)((word >> 43) & 0x1FFFFFULL);\n";
  Buffer.add_string b "        uint64_t c = eval_condition(ctx, cond) ? 1ULL : 0ULL;\n";
  if enable_nanomites then begin
    Buffer.add_string b "#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = (uint32_t)c;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, t_true, t_false, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        raise(SIGTRAP);\n";
    Buffer.add_string b "        vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;\n";
    Buffer.add_string b "#else\n";
    Buffer.add_string b "        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);\n";
    Buffer.add_string b "#endif\n";
  end else begin
    Buffer.add_string b "        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);\n";
  end;
  maybe_reanchor ();
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
  if enable_nanomites then begin
    Buffer.add_string b "#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;\n";
    Buffer.add_string b "        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));\n";
    Buffer.add_string b "        raise(SIGTRAP);\n";
    Buffer.add_string b "        vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;\n";
    Buffer.add_string b "#else\n";
    Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
    Buffer.add_string b "#endif\n";
  end else begin
    Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
  end;
  maybe_reanchor ();
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;\n";
  Buffer.add_string b "    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;\n\n";

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

let emit_super_operators b =
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
  Buffer.add_string b "    }\n\n"
