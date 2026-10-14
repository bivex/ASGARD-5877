open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_handler_ast b label (stmts : stmt list) =
  Buffer.add_string b (Printf.sprintf "    %s: {\n" label);
  List.iter (fun s ->
    Buffer.add_string b "        ";
    Buffer.add_string b (string_of_stmt s);
    Buffer.add_char b '\n';
  ) stmts;
  Buffer.add_string b "    }\n"

let emit_control_handlers b ?rng ~enable_nanomites ~enable_running_key ?(enable_address_bound = false) () =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  let maybe_reanchor () : stmt list =
    if enable_running_key then
      if enable_address_bound then
        [ expr_stmt (call "ctx.reanchor_running_key" [cast UInt64 (var "vIP_idx"); var "g_handlers_hash"]) ]
      else
        [ expr_stmt (call "ctx.reanchor_running_key" [cast UInt64 (var "vIP_idx")]) ]
    else []
  in

  (* H_JMP: Direct unconditional branch *)
  let jmp_stmts =
    if enable_nanomites then [
      raw "#if defined(__APPLE__)";
      (var "vIP_idx" := cast SizeT (var "imm"));
      raw "#elif defined(_WIN32)";
      (var "asgard_nanomites::g_nanomite_dispatcher.current_trap_id" := cast UInt32 (var "vIP_idx"));
      (var "asgard_nanomites::g_nanomite_dispatcher.current_condition" := i32 1);
      expr_stmt (call "asgard_nanomites::g_nanomite_dispatcher.register_nanomite" [
        cast UInt32 (var "vIP_idx");
        cast UInt64 (var "imm");
        cast UInt64 (var "imm");
        cast UInt64 (var "seed" ^~ cast UInt32 (var "vIP_idx"))
      ]);
      expr_stmt (call "__debugbreak" []);
      (var "vIP_idx" := ternary (ne (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target") (i32 0))
                                  (cast SizeT (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target"))
                                  (cast SizeT (var "imm")));
      raw "#elif defined(__linux__) && !defined(_MSC_VER)";
      (var "asgard_nanomites::g_nanomite_dispatcher.current_trap_id" := cast UInt32 (var "vIP_idx"));
      (var "asgard_nanomites::g_nanomite_dispatcher.current_condition" := i32 1);
      expr_stmt (call "asgard_nanomites::g_nanomite_dispatcher.register_nanomite" [
        cast UInt32 (var "vIP_idx");
        cast UInt64 (var "imm");
        cast UInt64 (var "imm");
        cast UInt64 (var "seed" ^~ cast UInt32 (var "vIP_idx"))
      ]);
      expr_stmt (call "raise" [var "SIGTRAP"]);
      (var "vIP_idx" := ternary (ne (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target") (i32 0))
                                  (cast SizeT (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target"))
                                  (cast SizeT (var "imm")));
      raw "#else";
      (var "vIP_idx" := cast SizeT (var "imm"));
      raw "#endif";
    ] else match pick_variant 3 with
      | 0 -> [ (var "vIP_idx" := cast SizeT (var "imm")) ]
      | 1 -> [ decl_var ~init:(cast SizeT (var "imm")) SizeT "_target"; (var "vIP_idx" := var "_target") ]
      | _ -> [ (var "vIP_idx" := cast SizeT (cast UInt64 (var "imm") &~ bit_not (u64 0L))) ]
  in
  emit_handler_ast b "H_JMP" (jmp_stmts @ maybe_reanchor () @ [ inc_instrs; fetch_next ]);

  (* H_JCC: Conditional branch with branchless evaluation *)
  let cond_decode_stmts = [
    probe_start;
    decl_var ~init:(cast UInt8 (((var "word" >>~ u64 18L) +~ u64 0x0FL) -~ ((var "word" >>~ u64 18L) |~ u64 0x0FL))) UInt8 "cond";
    decl_var ~init:(cast UInt64 ((var "word" >>~ u64 22L) &~ u64 0x1FFFFFL)) UInt64 "base_vip";
    decl_var ~init:(cast UInt64 ((var "word" >>~ u64 43L) &~ u64 0x1FFFFFL)) UInt64 "enc_delta";
    decl_var ~init:(((cast UInt64 (var "cond") *~ u64 0x5877L) ^~ u64 0x1337BEEFL) &~ u64 0x1FFFFFL) UInt64 "salt";
    decl_var ~init:(var "enc_delta" ^~ var "salt") UInt64 "delta";
    decl_var ~init:(var "base_vip" ^~ var "delta") UInt64 "t_true";
    decl_var ~init:(var "base_vip") UInt64 "t_false";
    decl_var ~init:(ternary (call "eval_condition" [var "ctx"; var "cond"]) (u64 1L) (u64 0L)) UInt64 "c";
  ] in
  let branch_stmts =
    if enable_nanomites then [
      raw "#if defined(__APPLE__)";
      (var "vIP_idx" := cast SizeT ((var "c" *~ var "t_true") +~ ((u64 1L -~ var "c") *~ var "t_false")));
      raw "#elif defined(_WIN32)";
      (var "asgard_nanomites::g_nanomite_dispatcher.current_trap_id" := cast UInt32 (var "vIP_idx"));
      (var "asgard_nanomites::g_nanomite_dispatcher.current_condition" := cast UInt32 (var "c"));
      expr_stmt (call "asgard_nanomites::g_nanomite_dispatcher.register_nanomite" [
        cast UInt32 (var "vIP_idx");
        var "t_true";
        var "t_false";
        cast UInt64 (var "seed" ^~ cast UInt32 (var "vIP_idx"))
      ]);
      expr_stmt (call "__debugbreak" []);
      (var "vIP_idx" := ternary (ne (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target") (i32 0))
                                  (cast SizeT (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target"))
                                  (cast SizeT ((var "c" *~ var "t_true") +~ ((u64 1L -~ var "c") *~ var "t_false"))));
      raw "#elif defined(__linux__) && !defined(_MSC_VER)";
      (var "asgard_nanomites::g_nanomite_dispatcher.current_trap_id" := cast UInt32 (var "vIP_idx"));
      (var "asgard_nanomites::g_nanomite_dispatcher.current_condition" := cast UInt32 (var "c"));
      expr_stmt (call "asgard_nanomites::g_nanomite_dispatcher.register_nanomite" [
        cast UInt32 (var "vIP_idx");
        var "t_true";
        var "t_false";
        cast UInt64 (var "seed" ^~ cast UInt32 (var "vIP_idx"))
      ]);
      expr_stmt (call "raise" [var "SIGTRAP"]);
      (var "vIP_idx" := ternary (ne (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target") (i32 0))
                                  (cast SizeT (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target"))
                                  (cast SizeT ((var "c" *~ var "t_true") +~ ((u64 1L -~ var "c") *~ var "t_false"))));
      raw "#else";
      (var "vIP_idx" := cast SizeT ((var "c" *~ var "t_true") +~ ((u64 1L -~ var "c") *~ var "t_false")));
      raw "#endif";
    ] else match pick_variant 3 with
      | 0 -> [
          (var "vIP_idx" := cast SizeT (call "asgard::branchless_vip::select_vip" [var "c"; var "t_true"; var "t_false"]))
        ]
      | 1 -> [
          (var "vIP_idx" := cast SizeT ((var "c" *~ var "t_true") +~ ((u64 1L -~ var "c") *~ var "t_false")))
        ]
      | _ -> [
          let_u64 "_mask" (u64 0L -~ var "c");
          (var "vIP_idx" := cast SizeT ((var "t_true" &~ var "_mask") |~ (var "t_false" &~ bit_not (var "_mask"))))
        ]
  in
  emit_handler_ast b "H_JCC" (cond_decode_stmts @ branch_stmts @ maybe_reanchor () @ [ probe_check; inc_instrs; fetch_next ]);

  (* H_CMOV: Conditional move *)
  let cmov_stmts = [
    probe_start;
    decl_var ~init:(cast UInt8 (((var "word" >>~ u64 18L) +~ u64 0x0FL) -~ ((var "word" >>~ u64 18L) |~ u64 0x0FL))) UInt8 "cond";
  ] @ (match pick_variant 3 with
    | 0 -> [
        if_then (call "eval_condition" [var "ctx"; var "cond"]) [ set_reg (var "dst") reg_src ]
      ]
    | 1 -> [
        let_u64 "_m" (ternary (call "eval_condition" [var "ctx"; var "cond"]) (bit_not (u64 0L)) (u64 0L));
        set_reg (var "dst") ((reg_src &~ var "_m") |~ (reg_dst &~ bit_not (var "_m")))
      ]
    | _ -> [
        let_u64 "_s" reg_src;
        let_u64 "_d" reg_dst;
        set_reg (var "dst") (ternary (call "eval_condition" [var "ctx"; var "cond"]) (var "_s") (var "_d"))
      ]) @ [ probe_check; inc_instrs; fetch_next ]
  in
  emit_handler_ast b "H_CMOV" cmov_stmts;

  (* H_SETCC: Conditional set byte *)
  let setcc_stmts = [
    probe_start;
    decl_var ~init:(cast UInt8 (((var "word" >>~ u64 18L) +~ u64 0x0FL) -~ ((var "word" >>~ u64 18L) |~ u64 0x0FL))) UInt8 "cond";
  ] @ (match pick_variant 3 with
    | 0 -> [
        let_u64 "val" (ternary (call "eval_condition" [var "ctx"; var "cond"]) (u64 1L) (u64 0L));
        set_reg (var "dst") (var "val")
      ]
    | 1 -> [
        set_reg (var "dst") (cast UInt64 (ternary (call "eval_condition" [var "ctx"; var "cond"]) (i32 1) (i32 0)))
      ]
    | _ -> [
        let_u64 "_val" (u64 0L);
        if_then (call "eval_condition" [var "ctx"; var "cond"]) [ (var "_val" := u64 1L) ];
        set_reg (var "dst") (var "_val")
      ]) @ [ probe_check; inc_instrs; fetch_next ]
  in
  emit_handler_ast b "H_SETCC" setcc_stmts;

  (* H_CALL: Direct call *)
  let call_stmts = [
    expr_stmt (call "ctx.push" [cast UInt64 (var "vIP_idx")]);
  ] @ (if enable_nanomites then [
    raw "#if defined(__APPLE__)";
    (var "vIP_idx" := cast SizeT (var "imm"));
    raw "#elif defined(_WIN32)";
    (var "asgard_nanomites::g_nanomite_dispatcher.current_trap_id" := cast UInt32 (var "vIP_idx"));
    (var "asgard_nanomites::g_nanomite_dispatcher.current_condition" := i32 1);
    expr_stmt (call "asgard_nanomites::g_nanomite_dispatcher.register_nanomite" [
      cast UInt32 (var "vIP_idx");
      cast UInt64 (var "imm");
      cast UInt64 (var "imm");
      cast UInt64 (var "seed" ^~ cast UInt32 (var "vIP_idx"))
    ]);
    expr_stmt (call "__debugbreak" []);
    (var "vIP_idx" := ternary (ne (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target") (i32 0))
                                (cast SizeT (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target"))
                                (cast SizeT (var "imm")));
    raw "#elif defined(__linux__) && !defined(_MSC_VER)";
    (var "asgard_nanomites::g_nanomite_dispatcher.current_trap_id" := cast UInt32 (var "vIP_idx"));
    (var "asgard_nanomites::g_nanomite_dispatcher.current_condition" := i32 1);
    expr_stmt (call "asgard_nanomites::g_nanomite_dispatcher.register_nanomite" [
      cast UInt32 (var "vIP_idx");
      cast UInt64 (var "imm");
      cast UInt64 (var "imm");
      cast UInt64 (var "seed" ^~ cast UInt32 (var "vIP_idx"))
    ]);
    expr_stmt (call "raise" [var "SIGTRAP"]);
    (var "vIP_idx" := ternary (ne (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target") (i32 0))
                                (cast SizeT (var "asgard_nanomites::g_nanomite_dispatcher.resolved_target"))
                                (cast SizeT (var "imm")));
    raw "#else";
    (var "vIP_idx" := cast SizeT (var "imm"));
    raw "#endif";
  ] else match pick_variant 3 with
    | 0 -> [ (var "vIP_idx" := cast SizeT (var "imm")) ]
    | 1 -> [
        decl_var ~init:(cast SizeT (var "imm")) SizeT "_target_vip";
        (var "vIP_idx" := var "_target_vip")
      ]
    | _ -> [
        let_u64 "_imm_target" (cast UInt64 (var "imm"));
        (var "vIP_idx" := cast SizeT (var "_imm_target"))
      ]) @ maybe_reanchor () @ [ inc_instrs; fetch_next ]
  in
  emit_handler_ast b "H_CALL" call_stmts;

  (* Helper for indirect ABI dispatch on x86_64 vs generic *)
  let indirect_abi_args = [
    raw "#if defined(__x86_64__) || defined(_M_X64)";
    let_u64 "a0" (call "ctx.get_reg" [var "REG_RDI"]);
    let_u64 "a1" (call "ctx.get_reg" [var "REG_RSI"]);
    let_u64 "a2" (call "ctx.get_reg" [var "REG_RDX"]);
    let_u64 "a3" (call "ctx.get_reg" [var "REG_RCX"]);
    let_u64 "a4" (call "ctx.get_reg" [var "REG_R8"]);
    let_u64 "a5" (call "ctx.get_reg" [var "REG_R9"]);
    raw "#else";
    let_u64 "a0" (call "ctx.get_reg" [var "REG_RAX"]);
    let_u64 "a1" (call "ctx.get_reg" [var "REG_RCX"]);
    let_u64 "a2" (call "ctx.get_reg" [var "REG_RDX"]);
    let_u64 "a3" (call "ctx.get_reg" [var "REG_RBX"]);
    let_u64 "a4" (call "ctx.get_reg" [var "REG_RSI"]);
    let_u64 "a5" (call "ctx.get_reg" [var "REG_RDI"]);
    raw "#endif";
  ] in
  let emit_indirect_call_stmts target_e ~is_jump =
    indirect_abi_args @ [
      raw "typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);";
      decl_var ~init:(reinterpret_cast (StructType "indirect_fn_t") target_e) (StructType "indirect_fn_t") "fn";
      let_u64 "ret_val" (call "fn" [var "a0"; var "a1"; var "a2"; var "a3"; var "a4"; var "a5"]);
      set_reg (var "REG_RAX") (var "ret_val");
    ] @ (if is_jump then [ goto "EXIT_VM" ] else [])
  in

  (* H_IJMP_R: Register-indirect jump or native FFI dispatch *)
  let ijmp_stmts = [
    let_u64 "target" (call "ctx.get_reg" [var "dst"]);
  ] @ (match pick_variant 3 with
    | 0 -> [
        if_then_else (var "target" <~ var "count")
          [ (var "vIP_idx" := cast SizeT (var "target")) ]
          [ if_then (ne (var "target") (u64 0L)) (emit_indirect_call_stmts (var "target") ~is_jump:true) ]
      ]
    | 1 -> [
        if_then_else (call "__builtin_expect" [var "target" <~ var "count"; i32 1])
          [ (var "vIP_idx" := cast SizeT (var "target")) ]
          [ if_then (ne (var "target") (i32 0)) (emit_indirect_call_stmts (var "target") ~is_jump:true) ]
      ]
    | _ -> [
        decl_var ~init:(cast SizeT (var "target")) SizeT "_t_idx";
        if_then_else (var "_t_idx" <~ var "count")
          [ (var "vIP_idx" := var "_t_idx") ]
          [ if_then (ne (var "target") (u64 0L)) (emit_indirect_call_stmts (var "target") ~is_jump:true) ]
      ]) @ maybe_reanchor () @ [ inc_instrs; fetch_next ]
  in
  emit_handler_ast b "H_IJMP_R" ijmp_stmts;

  (* H_ICALL_R: Register-indirect call or native FFI dispatch *)
  let icall_stmts = [
    let_u64 "target_ptr" (call "ctx.get_reg" [var "dst"]);
  ] @ (match pick_variant 3 with
    | 0 -> [
        if_then_else (var "target_ptr" <~ var "count")
          [
            expr_stmt (call "ctx.push" [cast UInt64 (var "vIP_idx")]);
            (var "vIP_idx" := cast SizeT (var "target_ptr"));
          ]
          [ if_then (ne (var "target_ptr") (u64 0L)) (emit_indirect_call_stmts (var "target_ptr") ~is_jump:false) ]
      ]
    | 1 -> [
        if_then_else (call "__builtin_expect" [var "target_ptr" <~ var "count"; i32 1])
          [
            let_u64 "_ret" (cast UInt64 (var "vIP_idx"));
            expr_stmt (call "ctx.push" [var "_ret"]);
            (var "vIP_idx" := cast SizeT (var "target_ptr"));
          ]
          [ if_then (ne (var "target_ptr") (i32 0)) (emit_indirect_call_stmts (var "target_ptr") ~is_jump:false) ]
      ]
    | _ -> [
        if_then_else (var "target_ptr" <~ var "count")
          [
            expr_stmt (call "ctx.push" [cast UInt64 (var "vIP_idx")]);
            (var "vIP_idx" := cast SizeT (var "target_ptr"));
          ]
          [ if_then (ne (var "target_ptr") (u64 0L)) (emit_indirect_call_stmts (var "target_ptr") ~is_jump:false) ]
      ]) @ maybe_reanchor () @ [ inc_instrs; fetch_next ]
  in
  emit_handler_ast b "H_ICALL_R" icall_stmts;

  (* H_RET & H_EXIT: Strict label formatting for transform_domain_labels compatibility *)
  (match pick_variant 3 with
   | 0 ->
       let s = String.concat " " (List.map string_of_stmt [ inc_instrs; goto "EXIT_VM" ]) in
       Buffer.add_string b (Printf.sprintf "    H_RET: case_ret: %s\n" s);
       Buffer.add_string b (Printf.sprintf "    H_EXIT: %s\n\n" s)
   | 1 ->
       let s = String.concat " " (List.map string_of_stmt [
         if_then (log_not (call "ctx.verify_canaries" [])) [ (var "ctx.trapped" := bool_lit true) ];
         inc_instrs;
         goto "EXIT_VM"
       ]) in
       Buffer.add_string b (Printf.sprintf "    H_RET: case_ret: { %s }\n" s);
       Buffer.add_string b (Printf.sprintf "    H_EXIT: { %s }\n\n" s)
   | _ ->
       let s = String.concat " " (List.map string_of_stmt [
         if_then (var "ctx.sp" >~ i32 512) [ (var "ctx.trapped" := bool_lit true) ];
         Assign (AssignAdd, var "ctx.executed_instructions", i32 1);
         goto "EXIT_VM"
       ]) in
       Buffer.add_string b (Printf.sprintf "    H_RET: case_ret: { %s }\n" s);
       Buffer.add_string b (Printf.sprintf "    H_EXIT: { %s }\n\n" s));

  (* Multi-VM Domain morphing bridges *)
  let bridge_flow_stmts = match pick_variant 3 with
    | 0 -> [
        expr_stmt (call "ctx.morph_math_to_flow" [cast UInt64 (var "imm")]);
        inc_instrs;
        fetch_next;
      ]
    | 1 -> [
        let_u64 "_imm_flow" (cast UInt64 (var "imm"));
        expr_stmt (call "ctx.morph_math_to_flow" [var "_imm_flow"]);
        Assign (AssignAdd, var "ctx.executed_instructions", i32 1);
        fetch_next;
      ]
    | _ -> [
        expr_stmt (call "ctx.morph_math_to_flow" [cast UInt64 (var "imm" &~ u64 0xFFFFFFFFFFFFFFFFL)]);
        inc_instrs;
        fetch_next;
      ]
  in
  let bridge_math_stmts = match pick_variant 3 with
    | 0 -> [
        expr_stmt (call "ctx.morph_flow_to_math" [cast UInt64 (var "imm")]);
        inc_instrs;
        fetch_next;
      ]
    | 1 -> [
        let_u64 "_imm_math" (cast UInt64 (var "imm"));
        expr_stmt (call "ctx.morph_flow_to_math" [var "_imm_math"]);
        Assign (AssignAdd, var "ctx.executed_instructions", i32 1);
        fetch_next;
      ]
    | _ -> [
        expr_stmt (call "ctx.morph_flow_to_math" [cast UInt64 (var "imm" &~ u64 0xFFFFFFFFFFFFFFFFL)]);
        inc_instrs;
        fetch_next;
      ]
  in
  emit_handler_ast b "H_BRIDGE_TO_FLOW" bridge_flow_stmts;
  emit_handler_ast b "H_BRIDGE_TO_MATH" bridge_math_stmts

let emit_super_operators ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  (* H_FUSED_MOV_ADD_RRI *)
  let fused_mov_add_stmts = (match pick_variant 3 with
    | 0 -> [ set_reg (var "dst") (reg_src +~ cast UInt64 (var "imm")) ]
    | 1 -> [
        let_u64 "_base" reg_src;
        set_reg (var "dst") (var "_base" +~ cast UInt64 (var "imm"))
      ]
    | _ -> [
        let_u64 "_s" reg_src;
        let_u64 "_i" (cast UInt64 (var "imm"));
        set_reg (var "dst") ((var "_s" ^~ var "_i") +~ (u64 2L *~ (var "_s" &~ var "_i")))
      ]) @ [
    Assign (AssignAdd, var "ctx.executed_instructions", i32 2);
    fetch_next;
  ] in
  emit_handler_ast b "H_FUSED_MOV_ADD_RRI" fused_mov_add_stmts;

  (* H_FUSED_ADD_IMUL_RRI *)
  let fused_add_imul_stmts = (match pick_variant 3 with
    | 0 -> [ set_reg (var "dst") ((reg_dst +~ reg_src) *~ cast UInt64 (var "imm")) ]
    | 1 -> [
        let_u64 "_sum" (reg_dst +~ reg_src);
        set_reg (var "dst") (var "_sum" *~ cast UInt64 (var "imm"))
      ]
    | _ -> [
        let_u64 "_imm" (cast UInt64 (var "imm"));
        let_u64 "_res" ((reg_dst *~ var "_imm") +~ (reg_src *~ var "_imm"));
        set_reg (var "dst") (var "_res")
      ]) @ [
    Assign (AssignAdd, var "ctx.executed_instructions", i32 2);
    fetch_next;
  ] in
  emit_handler_ast b "H_FUSED_ADD_IMUL_RRI" fused_add_imul_stmts;

  (* H_FUSED_ADD_XOR_RRI *)
  let fused_add_xor_stmts = (match pick_variant 3 with
    | 0 -> [ set_reg (var "dst") ((reg_dst +~ reg_src) ^~ cast UInt64 (var "imm")) ]
    | 1 -> [
        let_u64 "_sum" (reg_dst +~ reg_src);
        let_u64 "_imm" (cast UInt64 (var "imm"));
        set_reg (var "dst") ((var "_sum" +~ var "_imm") -~ (u64 2L *~ (var "_sum" &~ var "_imm")))
      ]
    | _ -> [
        let_u64 "_imm" (cast UInt64 (var "imm"));
        let_u64 "_sum" (reg_dst +~ reg_src);
        set_reg (var "dst") ((var "_sum" |~ var "_imm") -~ (var "_sum" &~ var "_imm"))
      ]) @ [
    Assign (AssignAdd, var "ctx.executed_instructions", i32 2);
    fetch_next;
  ] in
  emit_handler_ast b "H_FUSED_ADD_XOR_RRI" fused_add_xor_stmts;

  (* H_FUSED_SUB_XOR_RRI *)
  let fused_sub_xor_stmts = (match pick_variant 3 with
    | 0 -> [ set_reg (var "dst") ((reg_dst -~ reg_src) ^~ cast UInt64 (var "imm")) ]
    | 1 -> [
        let_u64 "_diff" (reg_dst -~ reg_src);
        let_u64 "_imm" (cast UInt64 (var "imm"));
        set_reg (var "dst") ((var "_diff" +~ var "_imm") -~ (u64 2L *~ (var "_diff" &~ var "_imm")))
      ]
    | _ -> [
        let_u64 "_imm" (cast UInt64 (var "imm"));
        let_u64 "_diff" (reg_dst -~ reg_src);
        set_reg (var "dst") ((var "_diff" |~ var "_imm") -~ (var "_diff" &~ var "_imm"))
      ]) @ [
    Assign (AssignAdd, var "ctx.executed_instructions", i32 2);
    fetch_next;
  ] in
  emit_handler_ast b "H_FUSED_SUB_XOR_RRI" fused_sub_xor_stmts;

  (* H_FUSED_XOR_ADD_RRI *)
  let fused_xor_add_stmts = (match pick_variant 3 with
    | 0 -> [ set_reg (var "dst") ((reg_dst ^~ reg_src) +~ cast UInt64 (var "imm")) ]
    | 1 -> [
        let_u64 "_a" reg_dst;
        let_u64 "_b" reg_src;
        let_u64 "_x" ((var "_a" +~ var "_b") -~ (u64 2L *~ (var "_a" &~ var "_b")));
        set_reg (var "dst") (var "_x" +~ cast UInt64 (var "imm"))
      ]
    | _ -> [
        let_u64 "_a" reg_dst;
        let_u64 "_b" reg_src;
        let_u64 "_x" ((var "_a" |~ var "_b") -~ (var "_a" &~ var "_b"));
        let_u64 "_i" (cast UInt64 (var "imm"));
        set_reg (var "dst") ((var "_x" |~ var "_i") +~ (var "_x" &~ var "_i"))
      ]) @ [
    Assign (AssignAdd, var "ctx.executed_instructions", i32 2);
    fetch_next;
  ] in
  emit_handler_ast b "H_FUSED_XOR_ADD_RRI" fused_xor_add_stmts;

  (* H_FUSED_CMP_CMOV *)
  let fused_cmp_cmov_stmts = [
    let_u64 "a" reg_dst;
    let_u64 "b" (cast UInt64 (var "imm"));
    decl_var ~init:(cast UInt8 ((var "word" >>~ u64 50L) &~ u64 0x0FL)) UInt8 "cond";
    decl_var ~init:(cast UInt32 ((var "word" >>~ u64 54L) &~ u64 0x7FL)) UInt32 "bits";
    expr_stmt (call "compute_sub_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
  ] @ (match pick_variant 3 with
    | 0 -> [
        if_then (call "eval_condition" [var "ctx"; var "cond"]) [ set_reg (var "dst") reg_src ]
      ]
    | 1 -> [
        let_u64 "_m" (ternary (call "eval_condition" [var "ctx"; var "cond"]) (bit_not (u64 0L)) (u64 0L));
        set_reg (var "dst") ((reg_src &~ var "_m") |~ (var "a" &~ bit_not (var "_m")))
      ]
    | _ -> [
        let_u64 "_val" (ternary (call "eval_condition" [var "ctx"; var "cond"]) reg_src (var "a"));
        set_reg (var "dst") (var "_val")
      ]) @ [
    Assign (AssignAdd, var "ctx.executed_instructions", i32 2);
    fetch_next;
  ] in
  emit_handler_ast b "H_FUSED_CMP_CMOV" fused_cmp_cmov_stmts
