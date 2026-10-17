open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_probes b ~enable_timing_probes =
  if enable_timing_probes then begin
    emit_preproc_if ~indent:"    " b
      ~elifs:[
        ("defined(__aarch64__)", (fun () ->
           emit_macro_def ~indent:"    " b "PROBE_START()" ~value:"uint64_t _t0; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t0))";
           emit_macro_def ~indent:"    " b "PROBE_CHECK()" ~value:"do { uint64_t _t1; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)"));
        ("defined(__riscv) || defined(__riscv__)", (fun () ->
           emit_macro_def ~indent:"    " b "PROBE_START()" ~value:"uint64_t _t0; __asm__ volatile(\"rdtime %0\" : \"=r\"(_t0))";
           emit_macro_def ~indent:"    " b "PROBE_CHECK()" ~value:"do { uint64_t _t1; __asm__ volatile(\"rdtime %0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)"));
      ]
      ~else_fn:(fun () ->
         emit_macro_def ~indent:"    " b "PROBE_START()" ~value:"uint64_t _t0 = 0";
         emit_macro_def ~indent:"    " b "PROBE_CHECK()" ~value:"do {} while(0)")
      "defined(__x86_64__)"
      (fun () ->
         emit_macro_def ~indent:"    " b "PROBE_START()" ~value:"uint64_t _t0 = __builtin_ia32_rdtsc()";
         emit_macro_def ~indent:"    " b "PROBE_CHECK()" ~value:"do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)");
    Buffer.add_char b '\n';
  end else begin
    emit_macro_def ~indent:"    " b "PROBE_START()" ~value:"do {} while(0)";
    emit_macro_def ~indent:"    " b "PROBE_CHECK()" ~value:"do {} while(0)";
    Buffer.add_char b '\n';
  end

let emit_handler_inline_ast b label (stmts : stmt list) =
  Buffer.add_string b (Printf.sprintf "    %s: { " label);
  List.iter (fun s ->
    Buffer.add_string b (string_of_stmt s);
    Buffer.add_char b ' ';
  ) stmts;
  Buffer.add_string b "}\n"

let emit_handler_ast b label (stmts : stmt list) =
  Buffer.add_string b (Printf.sprintf "    %s: {\n" label);
  List.iter (fun s ->
    Buffer.add_string b "        ";
    Buffer.add_string b (string_of_stmt s);
    Buffer.add_char b '\n';
  ) stmts;
  Buffer.add_string b "    }\n"

let emit_alu_handlers b ~rng ~enable_egraph_expansion ?(enable_ephemeral_jit = false) () =
  let pick_variant n = Random.State.int rng n in
  let rand_u64 () =
    let lo = Random.State.int64 rng 0x100000000L in
    let hi = Random.State.int64 rng 0x100000000L in
    Int64.logor (Int64.shift_left hi 32) lo
  in
  let wrap_metamorphic_involution_ast expr =
    let c_odd = Int64.logor (Random.State.int64 rng Int64.max_int) 1L in
    let shifted e = ((e &~ u64 0x7FFFFFFFL) *~ u64 c_odd) <<~ u64 33L in
    let e_once = expr ^~ (shifted expr) in
    e_once ^~ (shifted e_once)
  in
  let imm_u64 = cast UInt64 (var "imm") in
  let eph_call op d s imm_e =
    expr_stmt (call "asgard_ephemeral_jit::execute_ephemeral_vm_op" [
      var "g_ephemeral_jit_buf"; var "ctx"; var op; d; s; imm_e
    ])
  in

  let synth_basis_add () =
    let basis = Random_visa_domain.Isa_metamorphic_synth.synth_orthogonal_alu_basis rng ~op1_id:0 ~op2_id:1 in
    let (w1, w2, w_const) = Random_visa_domain.Isa_metamorphic_synth.lower_std_op_to_basis basis Random_visa_domain.Isa_metamorphic_synth.StdAdd in
    let psi1_expr = (u64 basis.psi1.c_xor *~ (reg_dst ^~ reg_src)) +~ (u64 basis.psi1.c_and *~ (reg_dst &~ reg_src)) +~ u64 basis.psi1.bias in
    let psi2_expr = (u64 basis.psi2.c_xor *~ (reg_dst ^~ reg_src)) +~ (u64 basis.psi2.c_and *~ (reg_dst &~ reg_src)) +~ u64 basis.psi2.bias in
    (u64 w1 *~ psi1_expr) +~ (u64 w2 *~ psi2_expr) +~ u64 w_const
  in

  let synth_basis_sub () =
    let basis = Random_visa_domain.Isa_metamorphic_synth.synth_orthogonal_alu_basis rng ~op1_id:0 ~op2_id:1 in
    let (w1, w2, w_const) = Random_visa_domain.Isa_metamorphic_synth.lower_std_op_to_basis basis Random_visa_domain.Isa_metamorphic_synth.StdSub in
    let psi1_expr = (u64 basis.psi1.c_xor *~ (reg_dst ^~ reg_src)) +~ (u64 basis.psi1.c_and *~ (reg_dst &~ reg_src)) +~ u64 basis.psi1.bias in
    let psi2_expr = (u64 basis.psi2.c_xor *~ (reg_dst ^~ reg_src)) +~ (u64 basis.psi2.c_and *~ (reg_dst &~ reg_src)) +~ u64 basis.psi2.bias in
    (u64 w1 *~ psi1_expr) +~ (u64 w2 *~ psi2_expr) +~ u64 w_const
  in

  let synth_basis_xor () =
    let basis = Random_visa_domain.Isa_metamorphic_synth.synth_orthogonal_alu_basis rng ~op1_id:0 ~op2_id:1 in
    let (w1, w2, w_const) = Random_visa_domain.Isa_metamorphic_synth.lower_std_op_to_basis basis Random_visa_domain.Isa_metamorphic_synth.StdXor in
    let psi1_expr = (u64 basis.psi1.c_xor *~ (reg_dst ^~ reg_src)) +~ (u64 basis.psi1.c_and *~ (reg_dst &~ reg_src)) +~ u64 basis.psi1.bias in
    let psi2_expr = (u64 basis.psi2.c_xor *~ (reg_dst ^~ reg_src)) +~ (u64 basis.psi2.c_and *~ (reg_dst &~ reg_src)) +~ u64 basis.psi2.bias in
    (u64 w1 *~ psi1_expr) +~ (u64 w2 *~ psi2_expr) +~ u64 w_const
  in

  let synth_chameleon_expr ~x ~y sem =
    let w = Chameleon_handlers.synth_chameleon_weights rng sem in
    let (y_term, add_bias) = match sem with
      | Chameleon_handlers.SemSub -> (bit_not y, u64 1L)
      | _ -> (y, u64 0L)
    in
    let term_xor = u64 w.w_xor *~ (x ^~ y_term) in
    let term_and = u64 w.w_and *~ (x &~ y_term) in
    let term_or  = u64 w.w_or  *~ (x |~ y_term) in
    let sum = (term_xor +~ term_and) +~ term_or in
    let res = if sem = Chameleon_handlers.SemSub then sum +~ add_bias else sum in
    if Random.State.bool rng then
      (res +~ u64 w.w_bias) -~ u64 w.w_bias
    else
      res
  in

  let dynamic_runtime_variant e1 e2 =
    let bit = Random.State.int rng 32 in
    let cond = ((var "k_dyn" >>~ u64 (Int64.of_int bit)) &~ u64 1L) ==~ u64 1L in
    ternary cond e1 e2
  in

  let pick_poly_add_ast () =
    let raw = match Random.State.int rng 5 with
      | 0 -> synth_chameleon_expr ~x:reg_dst ~y:reg_src Chameleon_handlers.SemAdd
      | 1 -> (reg_dst ^~ reg_src) +~ (u64 2L *~ (reg_dst &~ reg_src))
      | 2 -> (reg_dst |~ reg_src) +~ (reg_dst &~ reg_src)
      | 3 -> (u64 2L *~ (reg_dst |~ reg_src)) -~ (reg_dst ^~ reg_src)
      | _ -> synth_basis_add ()
    in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let pick_poly_sub_ast () =
    let raw = match Random.State.int rng 4 with
      | 0 -> synth_chameleon_expr ~x:reg_dst ~y:reg_src Chameleon_handlers.SemSub
      | 1 -> (reg_dst ^~ reg_src) -~ (u64 2L *~ (bit_not reg_dst &~ reg_src))
      | 2 -> (u64 2L *~ (reg_dst &~ bit_not reg_src)) -~ (reg_dst ^~ reg_src)
      | _ -> synth_basis_sub ()
    in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let pick_poly_xor_ast () =
    let raw = match Random.State.int rng 5 with
      | 0 -> synth_chameleon_expr ~x:reg_dst ~y:reg_src Chameleon_handlers.SemXor
      | 1 -> (reg_dst +~ reg_src) -~ (u64 2L *~ (reg_dst &~ reg_src))
      | 2 -> (reg_dst |~ reg_src) -~ (reg_dst &~ reg_src)
      | 3 -> synth_basis_xor ()
      | _ -> (reg_dst ^~ reg_src)
    in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in

  let h_add_rr_expr_ast () =
    let raw = if enable_egraph_expansion then Egraph_cpp_emitter.egraph_add_rr_ast ~rng
              else pick_poly_add_ast () in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let h_sub_rr_expr_ast () =
    let raw = if enable_egraph_expansion then Egraph_cpp_emitter.egraph_sub_rr_ast ~rng
              else pick_poly_sub_ast () in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let h_xor_rr_expr_ast () =
    let raw = if enable_egraph_expansion then Egraph_cpp_emitter.egraph_xor_rr_ast ~rng
              else pick_poly_xor_ast () in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let pick_poly_and_ast () =
    let raw = match Random.State.int rng 4 with
      | 0 -> synth_chameleon_expr ~x:reg_dst ~y:reg_src Chameleon_handlers.SemAnd
      | 1 -> reg_dst &~ reg_src
      | 2 -> (reg_dst +~ reg_src) -~ (reg_dst |~ reg_src)
      | _ -> (reg_dst ^~ reg_src) ^~ (reg_dst |~ reg_src)
    in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let pick_poly_or_ast () =
    let raw = match Random.State.int rng 4 with
      | 0 -> synth_chameleon_expr ~x:reg_dst ~y:reg_src Chameleon_handlers.SemOr
      | 1 -> reg_dst |~ reg_src
      | 2 -> (reg_dst ^~ reg_src) +~ (reg_dst &~ reg_src)
      | _ -> (reg_dst +~ reg_src) -~ (reg_dst &~ reg_src)
    in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in

  let h_and_rr_expr_ast () =
    let raw = if enable_egraph_expansion then Egraph_cpp_emitter.egraph_and_rr_ast ~rng
              else pick_poly_and_ast () in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in
  let h_or_rr_expr_ast () =
    let raw = if enable_egraph_expansion then Egraph_cpp_emitter.egraph_or_rr_ast ~rng
              else pick_poly_or_ast () in
    if Random.State.bool rng then wrap_metamorphic_involution_ast raw else raw
  in

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_NOP" [ inc_instrs; fetch_next ]
   | 1 -> emit_handler_inline_ast b "H_NOP" [ (var "ctx.executed_instructions" += i32 1); fetch_next ]
   | _ -> emit_handler_inline_ast b "H_NOP" [ expr_stmt (c_cast Void (var "dst")); inc_instrs; fetch_next ]);
  if enable_ephemeral_jit then begin
    emit_pp_if b "defined(ASGARD_EPHEMERAL_JIT)";
    emit_handler_inline_ast b "H_MOV_RR" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RR" (var "dst") (var "src") (i32 0);
      inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_MOV_RR_A1" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RR" (var "dst") (var "src") (i32 0);
      inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_MOV_RR_A2" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RR" (var "dst") (var "src") (i32 0);
      inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_MOV_RI" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RI" (var "dst") (i32 0) (cast UInt64 (cast UInt32 (var "imm")));
      inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_MOV_RI_A1" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RI" (var "dst") (i32 0) (cast UInt64 (cast UInt32 (var "imm")));
      inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_MOV_RI_A2" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RI" (var "dst") (i32 0) (cast UInt64 (cast UInt32 (var "imm")));
      inc_instrs; fetch_next
    ];
    emit_pp_else b
  end;
  let k_mov = rand_u64 () in
  let c_mov = rand_u64 () in
  let mov_expr = dynamic_runtime_variant ((var "_s" ^~ u64 k_mov) ^~ u64 k_mov) ((var "_s" +~ u64 c_mov) -~ u64 c_mov) in
  emit_handler_inline_ast b "H_MOV_RR" [
    let_u64 "_s" reg_src;
    let_u64 "_v" mov_expr;
    set_reg (var "dst") (var "_v");
    inc_instrs; fetch_next
  ];
  let k_movi = rand_u64 () in
  let c_movi = rand_u64 () in
  let movi_expr = dynamic_runtime_variant ((var "_imm" ^~ u64 k_movi) ^~ u64 k_movi) ((var "_imm" +~ u64 c_movi) -~ u64 c_movi) in
  emit_handler_inline_ast b "H_MOV_RI" [
    let_u64 "_imm" (cast UInt64 (cast UInt32 (var "imm")));
    let_u64 "_v" movi_expr;
    set_reg (var "dst") (var "_v");
    inc_instrs; fetch_next
  ];
  let k_mov1 = rand_u64 () in
  let mov1_expr = dynamic_runtime_variant ((var "_s" +~ u64 0x13375877L) -~ u64 0x13375877L) ((var "_s" ^~ u64 k_mov1) ^~ u64 k_mov1) in
  emit_handler_inline_ast b "H_MOV_RR_A1" [
    let_u64 "_s" reg_src;
    let_u64 "_v" mov1_expr;
    set_reg (var "dst") (var "_v");
    inc_instrs; fetch_next
  ];
  let mov2_expr = dynamic_runtime_variant (bit_not (bit_not (var "_s"))) (var "_s" ^~ u64 0L) in
  emit_handler_inline_ast b "H_MOV_RR_A2" [
    let_u64 "_s" reg_src;
    let_u64 "_v" mov2_expr;
    set_reg (var "dst") (var "_v");
    inc_instrs; fetch_next
  ];
  let k_movi1 = rand_u64 () in
  let movi1_expr = dynamic_runtime_variant ((var "_imm" ^~ u64 k_movi1) ^~ u64 k_movi1) ((var "_imm" +~ u64 0x58771337L) -~ u64 0x58771337L) in
  emit_handler_inline_ast b "H_MOV_RI_A1" [
    let_u64 "_imm" (cast UInt64 (cast UInt32 (var "imm")));
    let_u64 "_v" movi1_expr;
    set_reg (var "dst") (var "_v");
    inc_instrs; fetch_next
  ];
  let movi2_expr = dynamic_runtime_variant (bit_not (bit_not (var "_imm"))) ((var "_imm" +~ u64 0xDEADBEEFL) -~ u64 0xDEADBEEFL) in
  emit_handler_inline_ast b "H_MOV_RI_A2" [
    let_u64 "_imm" (cast UInt64 (cast UInt32 (var "imm")));
    let_u64 "_v" movi2_expr;
    set_reg (var "dst") (var "_v");
    inc_instrs; fetch_next
  ];
  if enable_ephemeral_jit then
    emit_pp_endif b;
  let mov_high_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "high_val" (cast UInt64 (cast UInt32 (var "imm")) <<~ i32 32);
        set_reg (var "dst") ((reg_dst &~ u64 0xFFFFFFFFL) |~ var "high_val");
      ]
    | 1 -> [
        let_u64 "_d" reg_dst;
        let_u64 "_hi" (cast UInt64 (cast UInt32 (var "imm")) <<~ i32 32);
        set_reg (var "dst") ((var "_d" &~ u64 0xFFFFFFFFL) ^~ var "_hi");
      ]
    | _ -> [
        let_u32 "_low32" (cast UInt32 reg_dst);
        set_reg (var "dst") ((cast UInt64 (cast UInt32 (var "imm")) <<~ i32 32) |~ cast UInt64 (var "_low32"));
      ]
  in
  emit_handler_ast b "H_MOV_HIGH" (mov_high_stmts @ [ inc_instrs; fetch_next ]);
  if enable_ephemeral_jit then begin
    emit_pp_if b "defined(ASGARD_EPHEMERAL_JIT)";
    emit_handler_inline_ast b "H_NEG_RR" [
      probe_start;
      eph_call "asgard_ephemeral_jit::EPH_OP_NEG_R" (var "dst") (var "dst") (i32 0);
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_NOT_RR" [
      probe_start;
      eph_call "asgard_ephemeral_jit::EPH_OP_NOT_R" (var "dst") (var "dst") (i32 0);
      probe_check; inc_instrs; fetch_next
    ];
    emit_pp_else b
  end;
  let neg_expr = dynamic_runtime_variant (bit_not (var "_v") +~ u64 1L) (u64 0L -~ var "_v") in
  emit_handler_inline_ast b "H_NEG_RR" [
    probe_start;
    let_u64 "_v" reg_dst;
    set_reg (var "dst") neg_expr;
    probe_check; inc_instrs; fetch_next
  ];
  let not_expr = dynamic_runtime_variant (bit_not (var "_v")) (var "_v" ^~ bit_not (u64 0L)) in
  emit_handler_inline_ast b "H_NOT_RR" [
    probe_start;
    let_u64 "_v" reg_dst;
    set_reg (var "dst") not_expr;
    probe_check; inc_instrs; fetch_next
  ];
  if enable_ephemeral_jit then
    emit_pp_endif b;
  let bswap_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        decl_var UInt64 "res";
        if_then_else (var "bits" ==~ i32 16) [
          var "res" := cast UInt64 (call "__builtin_bswap16" [cast UInt16 (var "val")])
        ] [
          if_then_else (var "bits" ==~ i32 32) [
            var "res" := cast UInt64 (call "__builtin_bswap32" [cast UInt32 (var "val")])
          ] [
            var "res" := call "__builtin_bswap64" [var "val"]
          ]
        ];
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "_val" reg_src;
        let_u32 "_b" (cast UInt32 (var "imm"));
        let_u64 "_r" (
          ternary (var "_b" ==~ i32 16)
            (cast UInt64 (call "__builtin_bswap16" [cast UInt16 (var "_val")]))
            (ternary (var "_b" ==~ i32 32)
               (cast UInt64 (call "__builtin_bswap32" [cast UInt32 (var "_val")]))
               (call "__builtin_bswap64" [var "_val"]))
        );
        set_reg (var "dst") (var "_r");
      ]
    | _ -> [
        let_u32 "bits" (cast UInt32 (var "imm"));
        if_then_else (var "bits" ==~ i32 16) [
          set_reg (var "dst") (cast UInt64 (call "__builtin_bswap16" [cast UInt16 reg_src]))
        ] [
          if_then_else (var "bits" ==~ i32 32) [
            set_reg (var "dst") (cast UInt64 (call "__builtin_bswap32" [cast UInt32 reg_src]))
          ] [
            set_reg (var "dst") (call "__builtin_bswap64" [reg_src])
          ]
        ]
      ]
  in
  emit_handler_ast b "H_BSWAP_RR" (bswap_stmts @ [ inc_instrs; fetch_next ]);

  let clz_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "mask" (ternary (var "bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "bits") -~ u64 1L));
        let_u64 "mval" (var "val" &~ var "mask");
        decl_var UInt64 "res";
        if_then_else (var "bits" <=~ i32 32) [
          let_u32 "v32" (cast UInt32 (var "mval"));
          var "res" := ternary (var "v32" ==~ i32 0)
            (cast UInt64 (var "bits"))
            (cast UInt64 (call "__builtin_clz" [var "v32"] -~ (i32 32 -~ var "bits")))
        ] [
          var "res" := ternary (var "mval" ==~ u64 0L)
            (u64 64L)
            (cast UInt64 (call "__builtin_clzll" [var "mval"]))
        ];
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "_s" reg_src;
        let_u32 "_bits" (cast UInt32 (var "imm"));
        let_u64 "_mask" (ternary (var "_bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "_bits") -~ u64 1L));
        let_u64 "_ms" (var "_s" &~ var "_mask");
        if_then_else (var "_bits" <=~ i32 32) [
          let_u32 "_v32" (cast UInt32 (var "_ms"));
          set_reg (var "dst") (ternary (var "_v32" ==~ i32 0)
            (cast UInt64 (var "_bits"))
            (cast UInt64 (call "__builtin_clz" [var "_v32"] -~ (i32 32 -~ var "_bits"))))
        ] [
          set_reg (var "dst") (ternary (var "_ms" ==~ u64 0L)
            (u64 64L)
            (cast UInt64 (call "__builtin_clzll" [var "_ms"])))
        ]
      ]
    | _ -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "mask" (ternary (var "bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "bits") -~ u64 1L));
        let_u64 "mval" (var "val" &~ var "mask");
        let_u64 "_clz" (
          ternary (var "bits" <=~ i32 32)
            (ternary (cast UInt32 (var "mval") ==~ i32 0)
               (cast UInt64 (var "bits"))
               (cast UInt64 (call "__builtin_clz" [cast UInt32 (var "mval")] -~ (i32 32 -~ var "bits"))))
            (ternary (var "mval" ==~ u64 0L)
               (u64 64L)
               (cast UInt64 (call "__builtin_clzll" [var "mval"])))
        );
        set_reg (var "dst") (var "_clz");
      ]
  in
  emit_handler_ast b "H_CLZ_RR" (clz_stmts @ [ inc_instrs; fetch_next ]);

  let ctz_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "mask" (ternary (var "bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "bits") -~ u64 1L));
        let_u64 "mval" (var "val" &~ var "mask");
        decl_var UInt64 "res";
        if_then_else (var "bits" <=~ i32 32) [
          let_u32 "v32" (cast UInt32 (var "mval"));
          var "res" := ternary (var "v32" ==~ i32 0)
            (cast UInt64 (var "bits"))
            (cast UInt64 (call "__builtin_ctz" [var "v32"]))
        ] [
          var "res" := ternary (var "mval" ==~ u64 0L)
            (u64 64L)
            (cast UInt64 (call "__builtin_ctzll" [var "mval"]))
        ];
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "_s" reg_src;
        let_u32 "_bits" (cast UInt32 (var "imm"));
        let_u64 "_mask" (ternary (var "_bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "_bits") -~ u64 1L));
        let_u64 "_ms" (var "_s" &~ var "_mask");
        if_then_else (var "_bits" <=~ i32 32) [
          let_u32 "_v32" (cast UInt32 (var "_ms"));
          set_reg (var "dst") (ternary (var "_v32" ==~ i32 0)
            (cast UInt64 (var "_bits"))
            (cast UInt64 (call "__builtin_ctz" [var "_v32"])))
        ] [
          set_reg (var "dst") (ternary (var "_ms" ==~ u64 0L)
            (u64 64L)
            (cast UInt64 (call "__builtin_ctzll" [var "_ms"])))
        ]
      ]
    | _ -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "mask" (ternary (var "bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "bits") -~ u64 1L));
        let_u64 "mval" (var "val" &~ var "mask");
        let_u64 "_ctz" (
          ternary (var "bits" <=~ i32 32)
            (ternary (cast UInt32 (var "mval") ==~ i32 0)
               (cast UInt64 (var "bits"))
               (cast UInt64 (call "__builtin_ctz" [cast UInt32 (var "mval")])))
            (ternary (var "mval" ==~ u64 0L)
               (u64 64L)
               (cast UInt64 (call "__builtin_ctzll" [var "mval"])))
        );
        set_reg (var "dst") (var "_ctz");
      ]
  in
  emit_handler_ast b "H_CTZ_RR" (ctz_stmts @ [ inc_instrs; fetch_next ]);

  let popcnt_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "mask" (ternary (var "bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "bits") -~ u64 1L));
        let_u64 "mval" (var "val" &~ var "mask");
        let_u64 "res" (
          ternary (var "bits" <=~ i32 32)
            (cast UInt64 (call "__builtin_popcount" [cast UInt32 (var "mval")]))
            (cast UInt64 (call "__builtin_popcountll" [var "mval"]))
        );
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "_s" reg_src;
        let_u32 "_b" (cast UInt32 (var "imm"));
        let_u64 "_mask" (ternary (var "_b" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "_b") -~ u64 1L));
        let_u64 "_ms" (var "_s" &~ var "_mask");
        let_u64 "_res" (
          ternary (var "_b" <=~ i32 32)
            (cast UInt64 (call "__builtin_popcount" [cast UInt32 (var "_ms")]))
            (cast UInt64 (call "__builtin_popcountll" [var "_ms"]))
        );
        set_reg (var "dst") (var "_res");
      ]
    | _ -> [
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "mask" (ternary (var "bits" >=~ i32 64) (bit_not (u64 0L)) ((u64 1L <<~ var "bits") -~ u64 1L));
        let_u64 "mval" (reg_src &~ var "mask");
        if_then_else (var "bits" <=~ i32 32) [
          set_reg (var "dst") (cast UInt64 (call "__builtin_popcount" [cast UInt32 (var "mval")]))
        ] [
          set_reg (var "dst") (cast UInt64 (call "__builtin_popcountll" [var "mval"]))
        ]
      ]
  in
  emit_handler_ast b "H_POPCNT_RR" (popcnt_stmts @ [ inc_instrs; fetch_next ]);

  let rbit_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "res" (u64 0L);
        for_range "i" (i32 0) (var "bits") [
          if_then (((var "val" >>~ var "i") &~ u64 1L) <>~ u64 0L) [
            var "res" |= (u64 1L <<~ ((var "bits" -~ i32 1) -~ var "i"))
          ]
        ];
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "_val" reg_src;
        let_u32 "_bits" (cast UInt32 (var "imm"));
        let_u64 "_res" (u64 0L);
        let_u32 "_i" (i32 0);
        while_loop (var "_i" <~ var "_bits") [
          if_then (((var "_val" >>~ var "_i") &~ u64 1L) <>~ u64 0L) [
            var "_res" |= (u64 1L <<~ ((var "_bits" -~ i32 1) -~ var "_i"))
          ];
          (var "_i" += i32 1)
        ];
        set_reg (var "dst") (var "_res");
      ]
    | _ -> [
        let_u64 "val" reg_src;
        let_u32 "bits" (cast UInt32 (var "imm"));
        let_u64 "res" (u64 0L);
        for_range "i" (i32 0) (var "bits") [
          let_u64 "_b" ((var "val" >>~ var "i") &~ u64 1L);
          (var "res" ^= (var "_b" <<~ ((var "bits" -~ i32 1) -~ var "i")))
        ];
        set_reg (var "dst") (var "res");
      ]
  in
  emit_handler_ast b "H_RBIT_RR" (rbit_stmts @ [ inc_instrs; fetch_next ]);
  if enable_ephemeral_jit then begin
    emit_pp_if b "defined(ASGARD_EPHEMERAL_JIT)";
    emit_handler_inline_ast b "H_ADD_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_ADD_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ADD_RR_A1" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_ADD_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ADD_RR_A2" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_ADD_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ADD_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_ADD_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SUB_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_SUB_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SUB_RR_A1" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_SUB_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SUB_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_SUB_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_IMUL_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_MUL_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_IMUL_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_MUL_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_XOR_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_XOR_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_XOR_RR_A1" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_XOR_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_XOR_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_XOR_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_AND_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_AND_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_AND_RR_A1" [ eph_call "asgard_ephemeral_jit::EPH_OP_AND_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_AND_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_AND_RI" (var "dst") (i32 0) imm_u64; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_OR_RR"  [ eph_call "asgard_ephemeral_jit::EPH_OP_OR_RR"  (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_OR_RR_A1"  [ eph_call "asgard_ephemeral_jit::EPH_OP_OR_RR"  (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_OR_RI"  [ eph_call "asgard_ephemeral_jit::EPH_OP_OR_RI"  (var "dst") (i32 0) imm_u64; inc_instrs; fetch_next ];
    emit_pp_else b
  end;
    emit_handler_inline_ast b "H_ADD_RR" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (h_add_rr_expr_ast ()) ((reg_dst ^~ reg_src) +~ (u64 2L *~ (reg_dst &~ reg_src))));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_ADD_RI" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (reg_dst +~ imm_u64) ((reg_dst ^~ imm_u64) +~ (u64 2L *~ (reg_dst &~ imm_u64))));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_ADD_RR_A1" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant ((reg_dst |~ reg_src) +~ (reg_dst &~ reg_src)) ((u64 2L *~ (reg_dst |~ reg_src)) -~ (reg_dst ^~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_ADD_RR_A2" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant ((reg_dst ^~ reg_src) +~ (u64 2L *~ (reg_dst &~ reg_src))) ((reg_dst |~ reg_src) +~ (reg_dst &~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_SUB_RR" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (h_sub_rr_expr_ast ()) ((reg_dst ^~ reg_src) -~ (u64 2L *~ (bit_not reg_dst &~ reg_src))));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_SUB_RR_A1" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant ((u64 2L *~ (reg_dst &~ bit_not reg_src)) -~ (reg_dst ^~ reg_src)) ((reg_dst ^~ reg_src) -~ (u64 2L *~ (bit_not reg_dst &~ reg_src))));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_SUB_RI" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (reg_dst -~ imm_u64) ((reg_dst ^~ imm_u64) -~ (u64 2L *~ (bit_not reg_dst &~ imm_u64))));
      probe_check; inc_instrs; fetch_next
    ];
    let imul_mba a b =
      dynamic_runtime_variant (a *~ b) (((a &~ b) *~ (a |~ b)) +~ ((a &~ bit_not b) *~ (bit_not a &~ b)))
    in
    emit_handler_inline_ast b "H_IMUL_RR" [
      probe_start;
      let_u64 "a" reg_dst;
      let_u64 "b" reg_src;
      let_u64 "res" (imul_mba (var "a") (var "b"));
      set_reg (var "dst") (var "res");
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_IMUL_RI" [
      probe_start;
      let_u64 "a" reg_dst;
      let_u64 "b" imm_u64;
      let_u64 "res" (imul_mba (var "a") (var "b"));
      set_reg (var "dst") (var "res");
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_XOR_RR" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (h_xor_rr_expr_ast ()) ((reg_dst |~ reg_src) -~ (reg_dst &~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_XOR_RR_A1" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant ((reg_dst |~ reg_src) -~ (reg_dst &~ reg_src)) ((reg_dst +~ reg_src) -~ (u64 2L *~ (reg_dst &~ reg_src))));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_XOR_RI" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (reg_dst ^~ imm_u64) ((reg_dst |~ imm_u64) -~ (reg_dst &~ imm_u64)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_AND_RR" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (h_and_rr_expr_ast ()) ((reg_dst +~ reg_src) -~ (reg_dst |~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_AND_RR_A1" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant ((reg_dst +~ reg_src) -~ (reg_dst |~ reg_src)) ((reg_dst |~ reg_src) -~ (reg_dst ^~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_AND_RI" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (reg_dst &~ imm_u64) ((reg_dst +~ imm_u64) -~ (reg_dst |~ imm_u64)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_OR_RR" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (h_or_rr_expr_ast ()) ((reg_dst ^~ reg_src) +~ (reg_dst &~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_OR_RR_A1" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant ((reg_dst ^~ reg_src) +~ (reg_dst &~ reg_src)) ((reg_dst +~ reg_src) -~ (reg_dst &~ reg_src)));
      probe_check; inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_OR_RI" [
      probe_start;
      set_reg (var "dst") (dynamic_runtime_variant (reg_dst |~ imm_u64) ((reg_dst ^~ imm_u64) +~ (reg_dst &~ imm_u64)));
      probe_check; inc_instrs; fetch_next
    ];
  if enable_ephemeral_jit then
    emit_pp_endif b;

  if enable_ephemeral_jit then begin
    emit_pp_if b "defined(ASGARD_EPHEMERAL_JIT)";
    emit_handler_inline_ast b "H_ROL_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_ROL_RI" (var "dst") (i32 0) (cast UInt64 (var "imm")); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ROR_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_ROR_RI" (var "dst") (i32 0) (cast UInt64 (var "imm")); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SHL_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_SHL_RI" (var "dst") (i32 0) (cast UInt64 (var "imm")); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SHR_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_SHR_RI" (var "dst") (i32 0) (cast UInt64 (var "imm")); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SAR_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_SAR_RI" (var "dst") (i32 0) (cast UInt64 (var "imm")); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ROL_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_ROL_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ROR_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_ROR_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SHL_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_SHL_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SHR_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_SHR_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SAR_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_SAR_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_pp_else b
  end;
  let rol_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") ((var "val" <<~ var "shift") |~ (var "val" >>~ ((i32 64 -~ var "shift") &~ i32 63)))
      ]
    | 1 -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") ((var "v" <<~ var "s") |~ (var "v" >>~ ((i32 64 -~ var "s") &~ i32 63)))
      ]
    | _ -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        let_u64 "_res" ((var "val" <<~ var "shift") |~ (var "val" >>~ ((i32 64 -~ var "shift") &~ i32 63)));
        set_reg (var "dst") (var "_res")
      ]
  in
  emit_handler_ast b "H_ROL_RI" (rol_ri_stmts @ [ inc_instrs; fetch_next ]);

  let ror_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") ((var "val" >>~ var "shift") |~ (var "val" <<~ ((i32 64 -~ var "shift") &~ i32 63)))
      ]
    | 1 -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") ((var "v" >>~ var "s") |~ (var "v" <<~ ((i32 64 -~ var "s") &~ i32 63)))
      ]
    | _ -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        let_u64 "_res" ((var "val" >>~ var "shift") |~ (var "val" <<~ ((i32 64 -~ var "shift") &~ i32 63)));
        set_reg (var "dst") (var "_res")
      ]
  in
  emit_handler_ast b "H_ROR_RI" (ror_ri_stmts @ [ inc_instrs; fetch_next ]);

  let shl_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (var "val" <<~ var "shift")
      ]
    | 1 -> [
        let_u64 "_res" (reg_dst <<~ cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (var "_res")
      ]
    | _ -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (var "v" <<~ var "s")
      ]
  in
  emit_handler_ast b "H_SHL_RI" (shl_ri_stmts @ [ inc_instrs; fetch_next ]);

  let shr_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (var "val" >>~ var "shift")
      ]
    | 1 -> [
        let_u64 "_res" (reg_dst >>~ cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (var "_res")
      ]
    | _ -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (var "v" >>~ var "s")
      ]
  in
  emit_handler_ast b "H_SHR_RI" (shr_ri_stmts @ [ inc_instrs; fetch_next ]);

  let sar_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (cast UInt64 (cast Int64 (var "val") >>~ var "shift"))
      ]
    | 1 -> [
        decl_var Int64 "sval" ~init:(cast Int64 reg_dst);
        let_u32 "shift" (cast UInt32 (var "imm" &~ i32 63));
        set_reg (var "dst") (cast UInt64 (var "sval" >>~ var "shift"))
      ]
    | _ -> [
        let_u64 "_res" (cast UInt64 (cast Int64 reg_dst >>~ cast UInt32 (var "imm" &~ i32 63)));
        set_reg (var "dst") (var "_res")
      ]
  in
  emit_handler_ast b "H_SAR_RI" (sar_ri_stmts @ [ inc_instrs; fetch_next ]);

  let rol_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") ((var "val" <<~ var "shift") |~ (var "val" >>~ ((i32 64 -~ var "shift") &~ i32 63)))
      ]
    | 1 -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") ((var "v" <<~ var "s") |~ (var "v" >>~ ((i32 64 -~ var "s") &~ i32 63)))
      ]
    | _ -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        let_u64 "_res" ((var "val" <<~ var "shift") |~ (var "val" >>~ ((i32 64 -~ var "shift") &~ i32 63)));
        set_reg (var "dst") (var "_res")
      ]
  in
  emit_handler_ast b "H_ROL_RR" (rol_rr_stmts @ [ inc_instrs; fetch_next ]);

  let ror_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") ((var "val" >>~ var "shift") |~ (var "val" <<~ ((i32 64 -~ var "shift") &~ i32 63)))
      ]
    | 1 -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") ((var "v" >>~ var "s") |~ (var "v" <<~ ((i32 64 -~ var "s") &~ i32 63)))
      ]
    | _ -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        let_u64 "_res" ((var "val" >>~ var "shift") |~ (var "val" <<~ ((i32 64 -~ var "shift") &~ i32 63)));
        set_reg (var "dst") (var "_res")
      ]
  in
  emit_handler_ast b "H_ROR_RR" (ror_rr_stmts @ [ inc_instrs; fetch_next ]);

  let shl_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (var "val" <<~ var "shift")
      ]
    | 1 -> [
        let_u64 "_res" (reg_dst <<~ cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (var "_res")
      ]
    | _ -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (var "v" <<~ var "s")
      ]
  in
  emit_handler_ast b "H_SHL_RR" (shl_rr_stmts @ [ inc_instrs; fetch_next ]);

  let shr_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (var "val" >>~ var "shift")
      ]
    | 1 -> [
        let_u64 "_res" (reg_dst >>~ cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (var "_res")
      ]
    | _ -> [
        let_u64 "v" reg_dst;
        let_u32 "s" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (var "v" >>~ var "s")
      ]
  in
  emit_handler_ast b "H_SHR_RR" (shr_rr_stmts @ [ inc_instrs; fetch_next ]);

  let sar_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (cast UInt64 (cast Int64 (var "val") >>~ var "shift"))
      ]
    | 1 -> [
        decl_var Int64 "sval" ~init:(cast Int64 reg_dst);
        let_u32 "shift" (cast UInt32 (reg_src &~ u64 63L));
        set_reg (var "dst") (cast UInt64 (var "sval" >>~ var "shift"))
      ]
    | _ -> [
        let_u64 "_res" (cast UInt64 (cast Int64 reg_dst >>~ cast UInt32 (reg_src &~ u64 63L)));
        set_reg (var "dst") (var "_res")
      ]
  in
  emit_handler_ast b "H_SAR_RR" (sar_rr_stmts @ [ inc_instrs; fetch_next ]);
  if enable_ephemeral_jit then
    emit_pp_endif b;
  let div_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        if_then (var "b" ==~ u64 0L) [
          var "ctx.trapped" := bool_lit true;
          goto "EXIT_VM";
        ];
        set_reg (var "dst") (var "a" /~ var "b");
      ]
    | 1 -> [
        let_u64 "b" reg_src;
        if_then (call "__builtin_expect" [log_not (var "b"); i32 0] <>~ i32 0) [
          var "ctx.trapped" := bool_lit true;
          goto "EXIT_VM";
        ];
        set_reg (var "dst") (reg_dst /~ var "b");
      ]
    | _ -> [
        let_u64 "_divisor" reg_src;
        if_then (var "_divisor" ==~ u64 0L) [
          var "ctx.trapped" := bool_lit true;
          goto "EXIT_VM";
        ];
        let_u64 "_dividend" reg_dst;
        set_reg (var "dst") (var "_dividend" /~ var "_divisor");
      ]
  in
  emit_handler_ast b "H_DIV_RR" (div_rr_stmts @ [ inc_instrs; fetch_next ]);

  let idiv_rr_stmts = match pick_variant 3 with
    | 0 -> [
        decl_var Int64 "a" ~init:(cast Int64 reg_dst);
        decl_var Int64 "b" ~init:(cast Int64 reg_src);
        if_then ((var "b" ==~ i32 0) ||~ ((var "b" ==~ i32 (-1)) &&~ (var "a" ==~ var "INT64_MIN"))) [
          var "ctx.trapped" := bool_lit true;
          goto "EXIT_VM";
        ];
        decl_var Int64 "q" ~init:(ternary (var "b" ==~ i32 (-1))
          (cast Int64 (u64 0L -~ cast UInt64 (var "a")))
          (var "a" /~ var "b"));
        set_reg (var "dst") (cast UInt64 (var "q"));
      ]
    | 1 ->
        let idiv_overflow_cond = (var "b" ==~ i32 0) ||~ ((var "b" ==~ i32 (-1)) &&~ (var "a" ==~ var "INT64_MIN")) in
        [
          decl_var Int64 "b" ~init:(cast Int64 reg_src);
          decl_var Int64 "a" ~init:(cast Int64 reg_dst);
          if_then (call "__builtin_expect" [idiv_overflow_cond; i32 0] <>~ i32 0) [
            var "ctx.trapped" := bool_lit true;
            goto "EXIT_VM";
          ];
          decl_var Int64 "q" ~init:(ternary (var "b" ==~ i32 (-1))
            (cast Int64 (u64 0L -~ cast UInt64 (var "a")))
            (var "a" /~ var "b"));
          set_reg (var "dst") (cast UInt64 (var "q"));
        ]
    | _ -> [
        decl_var Int64 "_d" ~init:(cast Int64 reg_dst);
        decl_var Int64 "_s" ~init:(cast Int64 reg_src);
        if_then ((var "_s" ==~ i32 0) ||~ ((var "_s" ==~ i32 (-1)) &&~ (var "_d" ==~ var "INT64_MIN"))) [
          var "ctx.trapped" := bool_lit true;
          goto "EXIT_VM";
        ];
        decl_var Int64 "_quot" ~init:(ternary (var "_s" ==~ i32 (-1)) (neg (var "_d")) (var "_d" /~ var "_s"));
        set_reg (var "dst") (cast UInt64 (var "_quot"));
      ]
  in
  emit_handler_ast b "H_IDIV_RR" (idiv_rr_stmts @ [ inc_instrs; fetch_next ]);

  let mulh_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        preproc_if_stmt "defined(__SIZEOF_INT128__)" [
          let_u64 "res" (cast UInt64 ((c_cast (StructType "unsigned __int128") (var "a") *~ c_cast (StructType "unsigned __int128") (var "b")) >>~ i32 64));
          set_reg (var "dst") (var "res");
        ] ~else_stmts:[
          let_u64 "a_lo" (cast UInt32 (var "a"));
          let_u64 "a_hi" (var "a" >>~ i32 32);
          let_u64 "b_lo" (cast UInt32 (var "b"));
          let_u64 "b_hi" (var "b" >>~ i32 32);
          let_u64 "p0" (var "a_lo" *~ var "b_lo");
          let_u64 "p1" (var "a_lo" *~ var "b_hi");
          let_u64 "p2" (var "a_hi" *~ var "b_lo");
          let_u64 "p3" (var "a_hi" *~ var "b_hi");
          let_u64 "cy" (((var "p0" >>~ i32 32) +~ cast UInt32 (var "p1") +~ cast UInt32 (var "p2")) >>~ i32 32);
          let_u64 "res" (var "p3" +~ (var "p1" >>~ i32 32) +~ (var "p2" >>~ i32 32) +~ var "cy");
          set_reg (var "dst") (var "res");
        ]
      ]
    | 1 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        preproc_if_stmt "defined(__SIZEOF_INT128__)" [
          decl_var (StructType "unsigned __int128") "_prod" ~init:(c_cast (StructType "unsigned __int128") (var "a") *~ c_cast (StructType "unsigned __int128") (var "b"));
          let_u64 "res" (cast UInt64 (var "_prod" >>~ i32 64));
          set_reg (var "dst") (var "res");
        ] ~else_stmts:[
          let_u64 "a_lo" (cast UInt32 (var "a"));
          let_u64 "a_hi" (var "a" >>~ i32 32);
          let_u64 "b_lo" (cast UInt32 (var "b"));
          let_u64 "b_hi" (var "b" >>~ i32 32);
          let_u64 "p0" (var "a_lo" *~ var "b_lo");
          let_u64 "p1" (var "a_lo" *~ var "b_hi");
          let_u64 "p2" (var "a_hi" *~ var "b_lo");
          let_u64 "p3" (var "a_hi" *~ var "b_hi");
          let_u64 "cy" (((var "p0" >>~ i32 32) +~ cast UInt32 (var "p1") +~ cast UInt32 (var "p2")) >>~ i32 32);
          let_u64 "res" (var "p3" +~ (var "p1" >>~ i32 32) +~ (var "p2" >>~ i32 32) +~ var "cy");
          set_reg (var "dst") (var "res");
        ]
      ]
    | _ -> [
        preproc_if_stmt "defined(__SIZEOF_INT128__)" [
          let_u64 "res" (cast UInt64 ((c_cast (StructType "unsigned __int128") reg_dst *~ c_cast (StructType "unsigned __int128") reg_src) >>~ i32 64));
          set_reg (var "dst") (var "res");
        ] ~else_stmts:[
          let_u64 "a" reg_dst;
          let_u64 "b" reg_src;
          let_u64 "a_lo" (cast UInt32 (var "a"));
          let_u64 "a_hi" (var "a" >>~ i32 32);
          let_u64 "b_lo" (cast UInt32 (var "b"));
          let_u64 "b_hi" (var "b" >>~ i32 32);
          let_u64 "cy" (((var "a_lo" *~ var "b_lo" >>~ i32 32) +~ cast UInt32 (var "a_lo" *~ var "b_hi") +~ cast UInt32 (var "a_hi" *~ var "b_lo")) >>~ i32 32);
          let_u64 "res" ((var "a_hi" *~ var "b_hi") +~ ((var "a_lo" *~ var "b_hi") >>~ i32 32) +~ ((var "a_hi" *~ var "b_lo") >>~ i32 32) +~ var "cy");
          set_reg (var "dst") (var "res");
        ]
      ]
  in
  emit_handler_ast b "H_MULH_RR" (mulh_rr_stmts @ [ inc_instrs; fetch_next ]);

  let imulh_rr_stmts = match pick_variant 3 with
    | 0 -> [
        decl_var Int64 "a" ~init:(cast Int64 reg_dst);
        decl_var Int64 "b" ~init:(cast Int64 reg_src);
        preproc_if_stmt "defined(__SIZEOF_INT128__)" [
          let_u64 "res" (cast UInt64 ((c_cast (StructType "signed __int128") (var "a") *~ c_cast (StructType "signed __int128") (var "b")) >>~ i32 64));
          set_reg (var "dst") (var "res");
        ] ~else_stmts:[
          let_u64 "ua" (cast UInt64 (var "a"));
          let_u64 "ub" (cast UInt64 (var "b"));
          let_u64 "a_lo" (cast UInt32 (var "ua"));
          let_u64 "a_hi" (var "ua" >>~ i32 32);
          let_u64 "b_lo" (cast UInt32 (var "ub"));
          let_u64 "b_hi" (var "ub" >>~ i32 32);
          let_u64 "p0" (var "a_lo" *~ var "b_lo");
          let_u64 "p1" (var "a_lo" *~ var "b_hi");
          let_u64 "p2" (var "a_hi" *~ var "b_lo");
          let_u64 "p3" (var "a_hi" *~ var "b_hi");
          let_u64 "cy" (((var "p0" >>~ i32 32) +~ cast UInt32 (var "p1") +~ cast UInt32 (var "p2")) >>~ i32 32);
          decl_var UInt64 "res" ~init:(var "p3" +~ (var "p1" >>~ i32 32) +~ (var "p2" >>~ i32 32) +~ var "cy");
          if_then (var "a" <~ i32 0) [ var "res" -= var "ub" ];
          if_then (var "b" <~ i32 0) [ var "res" -= var "ua" ];
          set_reg (var "dst") (var "res");
        ]
      ]
    | 1 -> [
        decl_var Int64 "a" ~init:(cast Int64 reg_dst);
        decl_var Int64 "b" ~init:(cast Int64 reg_src);
        preproc_if_stmt "defined(__SIZEOF_INT128__)" [
          decl_var (StructType "signed __int128") "_prod" ~init:(c_cast (StructType "signed __int128") (var "a") *~ c_cast (StructType "signed __int128") (var "b"));
          let_u64 "res" (cast UInt64 (var "_prod" >>~ i32 64));
          set_reg (var "dst") (var "res");
        ] ~else_stmts:[
          let_u64 "ua" (cast UInt64 (var "a"));
          let_u64 "ub" (cast UInt64 (var "b"));
          let_u64 "a_lo" (cast UInt32 (var "ua"));
          let_u64 "a_hi" (var "ua" >>~ i32 32);
          let_u64 "b_lo" (cast UInt32 (var "ub"));
          let_u64 "b_hi" (var "ub" >>~ i32 32);
          let_u64 "p0" (var "a_lo" *~ var "b_lo");
          let_u64 "p1" (var "a_lo" *~ var "b_hi");
          let_u64 "p2" (var "a_hi" *~ var "b_lo");
          let_u64 "p3" (var "a_hi" *~ var "b_hi");
          let_u64 "cy" (((var "p0" >>~ i32 32) +~ cast UInt32 (var "p1") +~ cast UInt32 (var "p2")) >>~ i32 32);
          decl_var UInt64 "res" ~init:(var "p3" +~ (var "p1" >>~ i32 32) +~ (var "p2" >>~ i32 32) +~ var "cy");
          if_then (var "a" <~ i32 0) [ var "res" -= var "ub" ];
          if_then (var "b" <~ i32 0) [ var "res" -= var "ua" ];
          set_reg (var "dst") (var "res");
        ]
      ]
    | _ -> [
        preproc_if_stmt "defined(__SIZEOF_INT128__)" [
          let_u64 "res" (cast UInt64 ((c_cast (StructType "signed __int128") (cast Int64 reg_dst) *~ c_cast (StructType "signed __int128") (cast Int64 reg_src)) >>~ i32 64));
          set_reg (var "dst") (var "res");
        ] ~else_stmts:[
          decl_var Int64 "a" ~init:(cast Int64 reg_dst);
          decl_var Int64 "b" ~init:(cast Int64 reg_src);
          let_u64 "ua" (cast UInt64 (var "a"));
          let_u64 "ub" (cast UInt64 (var "b"));
          let_u64 "a_lo" (cast UInt32 (var "ua"));
          let_u64 "a_hi" (var "ua" >>~ i32 32);
          let_u64 "b_lo" (cast UInt32 (var "ub"));
          let_u64 "b_hi" (var "ub" >>~ i32 32);
          let_u64 "cy" (((var "a_lo" *~ var "b_lo" >>~ i32 32) +~ cast UInt32 (var "a_lo" *~ var "b_hi") +~ cast UInt32 (var "a_hi" *~ var "b_lo")) >>~ i32 32);
          decl_var UInt64 "res" ~init:((var "a_hi" *~ var "b_hi") +~ ((var "a_lo" *~ var "b_hi") >>~ i32 32) +~ ((var "a_hi" *~ var "b_lo") >>~ i32 32) +~ var "cy");
          if_then (var "a" <~ i32 0) [ var "res" -= var "ub" ];
          if_then (var "b" <~ i32 0) [ var "res" -= var "ua" ];
          set_reg (var "dst") (var "res");
        ]
      ]
  in
  emit_handler_ast b "H_IMULH_RR" (imulh_rr_stmts @ [ inc_instrs; fetch_next ]);

  let cmp_ri_stmts = match pick_variant 3 with
    | 0 -> [
        probe_start;
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL));
        expr_stmt (call "compute_sub_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
        probe_check; inc_instrs; fetch_next
      ]
    | 1 -> [
        probe_start;
        let_u64 "_d" reg_dst;
        expr_stmt (call "compute_sub_flags" [var "ctx"; var "_d"; imm_u64; cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL)]);
        probe_check; inc_instrs; fetch_next
      ]
    | _ -> [
        probe_start;
        let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL));
        let_u64 "_imm" imm_u64;
        expr_stmt (call "compute_sub_flags" [var "ctx"; reg_dst; var "_imm"; var "bits"]);
        probe_check; inc_instrs; fetch_next
      ]
  in
  emit_handler_ast b "H_CMP_RI" cmp_ri_stmts;

  let cmp_rr_stmts = match pick_variant 3 with
    | 0 -> [
        probe_start;
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL));
        expr_stmt (call "compute_sub_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
        probe_check; inc_instrs; fetch_next
      ]
    | 1 -> [
        probe_start;
        let_u64 "_a" reg_dst;
        let_u64 "_b" reg_src;
        expr_stmt (call "compute_sub_flags" [var "ctx"; var "_a"; var "_b"; cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL)]);
        probe_check; inc_instrs; fetch_next
      ]
    | _ -> [
        probe_start;
        let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL));
        expr_stmt (call "compute_sub_flags" [var "ctx"; reg_dst; reg_src; var "bits"]);
        probe_check; inc_instrs; fetch_next
      ]
  in
  emit_handler_ast b "H_CMP_RR" cmp_rr_stmts;

  emit_handler_ast b "H_CMP_RI_A1" [
    probe_start;
    let_u64 "_d" reg_dst;
    expr_stmt (call "compute_sub_flags" [var "ctx"; var "_d"; imm_u64; cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL)]);
    probe_check; inc_instrs; fetch_next
  ];

  emit_handler_ast b "H_CMP_RI_A2" [
    probe_start;
    let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL));
    let_u64 "_imm" imm_u64;
    expr_stmt (call "compute_sub_flags" [var "ctx"; reg_dst; var "_imm"; var "bits"]);
    probe_check; inc_instrs; fetch_next
  ];

  emit_handler_ast b "H_CMP_RR_A1" [
    probe_start;
    let_u64 "_a" reg_dst;
    let_u64 "_b" reg_src;
    expr_stmt (call "compute_sub_flags" [var "ctx"; var "_a"; var "_b"; cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x7FL)]);
    probe_check; inc_instrs; fetch_next
  ];

  let push_sp_bound = (var "cur_sp" >=~ u64 0x10008L) &&~ (var "cur_sp" <=~ u64 0x7FFFFFFFFFFFL) in
  let push_stmts = match Random.State.int rng 3 with
    | 0 -> [
        let_u64 "val" reg_dst;
        expr_stmt (call "ctx.push" [var "val"]);
        let_u64 "cur_sp" (call "ctx.get_reg" [var "REG_RSP"]);
        if_then push_sp_bound [
          let_u64 "sp_val" (var "cur_sp" -~ u64 8L);
          expr_stmt (call "ctx.set_reg" [var "REG_RSP"; var "sp_val"]);
          deref (reinterpret_cast (Ptr UInt64) (var "sp_val")) := var "val";
        ];
      ]
    | 1 -> [
        let_u64 "val" reg_dst;
        expr_stmt (call "ctx.push" [var "val"]);
        let_u64 "cur_sp" (call "ctx.get_reg" [var "REG_RSP"]);
        if_then push_sp_bound [
          decl_var (Ptr UInt64) "sp_ptr" ~init:(reinterpret_cast (Ptr UInt64) (var "cur_sp" -~ u64 8L));
          expr_stmt (call "ctx.set_reg" [var "REG_RSP"; reinterpret_cast UInt64 (var "sp_ptr")]);
          deref (var "sp_ptr") := var "val";
        ];
      ]
    | _ -> [
        let_u64 "val" reg_dst;
        expr_stmt (call "ctx.push" [var "val"]);
        let_u64 "cur_sp" (call "ctx.get_reg" [var "REG_RSP"]);
        if_then push_sp_bound [
          let_u64 "sp_val" (var "cur_sp" -~ u64 8L);
          expr_stmt (call "ctx.set_reg" [var "REG_RSP"; var "sp_val"]);
          expr_stmt (call "std::memcpy" [reinterpret_cast (Ptr Void) (var "sp_val"); addr_of (var "val"); sizeof_ty UInt64]);
        ];
      ]
  in
  emit_handler_ast b "H_PUSH_R" (push_stmts @ [ inc_instrs; fetch_next ]);

  let pop_sp_bound = (var "cur_sp" >=~ u64 0x10000L) &&~ (var "cur_sp" <=~ u64 0x7FFFFFFFFFFFL) in
  let pop_stmts = match Random.State.int rng 3 with
    | 0 -> [
        let_u64 "cur_sp" (call "ctx.get_reg" [var "REG_RSP"]);
        let_u64 "val" (u64 0L);
        if_then_else pop_sp_bound [
          var "val" := deref (reinterpret_cast (ConstPtr UInt64) (var "cur_sp"));
          expr_stmt (call "ctx.set_reg" [var "REG_RSP"; var "cur_sp" +~ u64 8L]);
          expr_stmt (call "ctx.pop" []);
        ] [
          var "val" := call "ctx.pop" [];
        ];
        set_reg (var "dst") (var "val");
      ]
    | 1 -> [
        let_u64 "cur_sp" (call "ctx.get_reg" [var "REG_RSP"]);
        let_u64 "val" (u64 0L);
        if_then_else pop_sp_bound [
          expr_stmt (call "std::memcpy" [addr_of (var "val"); reinterpret_cast (ConstPtr Void) (var "cur_sp"); sizeof_ty UInt64]);
          expr_stmt (call "ctx.set_reg" [var "REG_RSP"; var "cur_sp" +~ u64 8L]);
          expr_stmt (call "ctx.pop" []);
        ] [
          var "val" := call "ctx.pop" [];
        ];
        set_reg (var "dst") (var "val");
      ]
    | _ -> [
        let_u64 "cur_sp" (call "ctx.get_reg" [var "REG_RSP"]);
        let_u64 "val" (u64 0L);
        if_then_else pop_sp_bound [
          decl_var (ConstPtr UInt64) "sp_ptr" ~init:(reinterpret_cast (ConstPtr UInt64) (var "cur_sp"));
          var "val" := deref (var "sp_ptr");
          expr_stmt (call "ctx.set_reg" [var "REG_RSP"; var "cur_sp" +~ sizeof_ty UInt64]);
          expr_stmt (call "ctx.pop" []);
        ] [
          var "val" := call "ctx.pop" [];
        ];
        set_reg (var "dst") (var "val");
      ]
  in
  emit_handler_ast b "H_POP_R" (pop_stmts @ [ inc_instrs; fetch_next ]);
  let adc_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u64 "c" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "res" (var "a" +~ var "b" +~ var "c");
        var "ctx.cf" := ((var "res" <~ var "a") ||~ ((var "c" <>~ u64 0L) &&~ (var "res" ==~ var "a")));
        var "ctx.of" := ((((var "a" ^~ var "res") &~ (var "b" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u64 "c" (cast UInt64 (var "ctx.cf"));
        let_u64 "res" ((var "a" +~ var "b") +~ var "c");
        var "ctx.cf" := ((var "res" <~ var "a") ||~ ((var "c" <>~ u64 0L) &&~ (var "res" ==~ var "a")));
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := ((var "res" >>~ i32 63) <>~ u64 0L);
        var "ctx.of" := ((((var "a" ^~ var "res") &~ (var "b" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        set_reg (var "dst") (var "res");
      ]
    | _ -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u64 "c" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "ab" (var "a" +~ var "b");
        let_u64 "res" (var "ab" +~ var "c");
        var "ctx.cf" := ((var "ab" <~ var "a") ||~ (var "res" <~ var "ab"));
        var "ctx.of" := ((((var "a" ^~ var "res") &~ (var "b" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
  in
  emit_handler_ast b "H_ADC_RR" (adc_rr_stmts @ [ inc_instrs; fetch_next ]);

  let adc_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u64 "c" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "res" (var "a" +~ var "b" +~ var "c");
        var "ctx.cf" := ((var "res" <~ var "a") ||~ ((var "c" <>~ u64 0L) &&~ (var "res" ==~ var "a")));
        var "ctx.of" := ((((var "a" ^~ var "res") &~ (var "b" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u64 "c" (cast UInt64 (var "ctx.cf"));
        let_u64 "res" ((var "a" +~ var "b") +~ var "c");
        var "ctx.cf" := ((var "res" <~ var "a") ||~ ((var "c" <>~ u64 0L) &&~ (var "res" ==~ var "a")));
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := ((var "res" >>~ i32 63) <>~ u64 0L);
        var "ctx.of" := ((((var "a" ^~ var "res") &~ (var "b" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        set_reg (var "dst") (var "res");
      ]
    | _ -> [
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u64 "c" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "ab" (var "a" +~ var "b");
        let_u64 "res" (var "ab" +~ var "c");
        var "ctx.cf" := ((var "ab" <~ var "a") ||~ (var "res" <~ var "ab"));
        var "ctx.of" := ((((var "a" ^~ var "res") &~ (var "b" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
  in
  emit_handler_ast b "H_ADC_RI" (adc_ri_stmts @ [ inc_instrs; fetch_next ]);

  let sbb_rr_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u64 "borrow" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "res" (var "a" -~ var "b" -~ var "borrow");
        var "ctx.cf" := ((var "a" <~ var "b") ||~ ((var "borrow" <>~ u64 0L) &&~ (var "a" ==~ var "b")));
        var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u64 "borrow" (cast UInt64 (var "ctx.cf"));
        let_u64 "res" ((var "a" -~ var "b") -~ var "borrow");
        var "ctx.cf" := ((var "a" <~ var "b") ||~ ((var "borrow" <>~ u64 0L) &&~ (var "a" ==~ var "b")));
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := ((var "res" >>~ i32 63) <>~ u64 0L);
        var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        set_reg (var "dst") (var "res");
      ]
    | _ -> [
        let_u64 "a" reg_dst;
        let_u64 "b" reg_src;
        let_u64 "borrow" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "res" (var "a" -~ (var "b" +~ var "borrow"));
        var "ctx.cf" := ((var "a" <~ var "b") ||~ ((var "borrow" <>~ u64 0L) &&~ (var "a" ==~ var "b")));
        var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
  in
  emit_handler_ast b "H_SBB_RR" (sbb_rr_stmts @ [ inc_instrs; fetch_next ]);

  let sbb_ri_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u64 "borrow" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "res" (var "a" -~ var "b" -~ var "borrow");
        var "ctx.cf" := ((var "a" <~ var "b") ||~ ((var "borrow" <>~ u64 0L) &&~ (var "a" ==~ var "b")));
        var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
    | 1 -> [
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u64 "borrow" (cast UInt64 (var "ctx.cf"));
        let_u64 "res" ((var "a" -~ var "b") -~ var "borrow");
        var "ctx.cf" := ((var "a" <~ var "b") ||~ ((var "borrow" <>~ u64 0L) &&~ (var "a" ==~ var "b")));
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := ((var "res" >>~ i32 63) <>~ u64 0L);
        var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        set_reg (var "dst") (var "res");
      ]
    | _ -> [
        let_u64 "a" reg_dst;
        let_u64 "b" imm_u64;
        let_u64 "borrow" (ternary (var "ctx.cf") (u64 1L) (u64 0L));
        let_u64 "res" (var "a" -~ (var "b" +~ var "borrow"));
        var "ctx.cf" := ((var "a" <~ var "b") ||~ ((var "borrow" <>~ u64 0L) &&~ (var "a" ==~ var "b")));
        var "ctx.of" := ((((var "a" ^~ var "b") &~ (var "a" ^~ var "res")) >>~ i32 63) <>~ u64 0L);
        var "ctx.zf" := (var "res" ==~ u64 0L);
        var "ctx.sf" := (cast Int64 (var "res") <~ i32 0);
        set_reg (var "dst") (var "res");
      ]
  in
  emit_handler_ast b "H_SBB_RI" (sbb_ri_stmts @ [ inc_instrs; fetch_next ]);

  let ccmp_cond = cast UInt8 (((var "word" >>~ i32 18) +~ u64 0x0FL) -~ ((var "word" >>~ i32 18) |~ u64 0x0FL)) in
  let ccmp_nzcv = cast UInt8 (((var "word" >>~ i32 22) +~ u64 0x0FL) -~ ((var "word" >>~ i32 22) |~ u64 0x0FL)) in
  let ccmp_imm_b = cast UInt64 (((var "word" >>~ i32 26) +~ u64 0x1FL) -~ ((var "word" >>~ i32 26) |~ u64 0x1FL)) in
  let ccmp_bits = cast UInt32 (((var "word" >>~ i32 50) +~ u64 0x7FL) -~ ((var "word" >>~ i32 50) |~ u64 0x7FL)) in
  let nzcv_fallback = [
    var "ctx.sf" := ((var "nzcv" &~ i32 8) <>~ i32 0);
    var "ctx.zf" := ((var "nzcv" &~ i32 4) <>~ i32 0);
    var "ctx.cf" := ((var "nzcv" &~ i32 2) <>~ i32 0);
    var "ctx.of" := ((var "nzcv" &~ i32 1) <>~ i32 0);
  ] in

  let ccmp_rr_eval = [
    let_u64 "a" reg_dst;
    let_u64 "b" reg_src;
    expr_stmt (call "compute_sub_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
  ] in
  let ccmp_rr_stmts =
    decl_var UInt8 "cond" ~init:ccmp_cond ::
    decl_var UInt8 "nzcv" ~init:ccmp_nzcv ::
    decl_var UInt32 "bits" ~init:ccmp_bits ::
    (match pick_variant 2 with
     | 0 -> [
         if_then_else (call "eval_condition" [var "ctx"; var "cond"])
           ccmp_rr_eval
           nzcv_fallback
       ]
     | _ -> [
         if_then_else (log_not (call "eval_condition" [var "ctx"; var "cond"]))
           nzcv_fallback
           ccmp_rr_eval
       ])
  in
  emit_handler_ast b "H_CCMP_RR" (ccmp_rr_stmts @ [ inc_instrs; fetch_next ]);

  let ccmp_ri_eval = [
    let_u64 "a" reg_dst;
    expr_stmt (call "compute_sub_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
  ] in
  let ccmp_ri_stmts =
    decl_var UInt8 "cond" ~init:ccmp_cond ::
    decl_var UInt8 "nzcv" ~init:ccmp_nzcv ::
    decl_var UInt64 "b" ~init:ccmp_imm_b ::
    decl_var UInt32 "bits" ~init:ccmp_bits ::
    (match pick_variant 2 with
     | 0 -> [
         if_then_else (call "eval_condition" [var "ctx"; var "cond"])
           ccmp_ri_eval
           nzcv_fallback
       ]
     | _ -> [
         if_then_else (log_not (call "eval_condition" [var "ctx"; var "cond"]))
           nzcv_fallback
           ccmp_ri_eval
       ])
  in
  emit_handler_ast b "H_CCMP_RI" (ccmp_ri_stmts @ [ inc_instrs; fetch_next ]);

  let ccmn_rr_eval = [
    let_u64 "a" reg_dst;
    let_u64 "b" reg_src;
    expr_stmt (call "compute_add_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
  ] in
  let ccmn_rr_stmts =
    decl_var UInt8 "cond" ~init:ccmp_cond ::
    decl_var UInt8 "nzcv" ~init:ccmp_nzcv ::
    decl_var UInt32 "bits" ~init:ccmp_bits ::
    (match pick_variant 2 with
     | 0 -> [
         if_then_else (call "eval_condition" [var "ctx"; var "cond"])
           ccmn_rr_eval
           nzcv_fallback
       ]
     | _ -> [
         if_then_else (log_not (call "eval_condition" [var "ctx"; var "cond"]))
           nzcv_fallback
           ccmn_rr_eval
       ])
  in
  emit_handler_ast b "H_CCMN_RR" (ccmn_rr_stmts @ [ inc_instrs; fetch_next ]);

  let ccmn_ri_eval = [
    let_u64 "a" reg_dst;
    expr_stmt (call "compute_add_flags" [var "ctx"; var "a"; var "b"; var "bits"]);
  ] in
  let ccmn_ri_stmts =
    decl_var UInt8 "cond" ~init:ccmp_cond ::
    decl_var UInt8 "nzcv" ~init:ccmp_nzcv ::
    decl_var UInt64 "b" ~init:ccmp_imm_b ::
    decl_var UInt32 "bits" ~init:ccmp_bits ::
    (match pick_variant 2 with
     | 0 -> [
         if_then_else (call "eval_condition" [var "ctx"; var "cond"])
           ccmn_ri_eval
           nzcv_fallback
       ]
     | _ -> [
         if_then_else (log_not (call "eval_condition" [var "ctx"; var "cond"]))
           nzcv_fallback
           ccmn_ri_eval
       ])
  in
  emit_handler_ast b "H_CCMN_RI" (ccmn_ri_stmts @ [ inc_instrs; fetch_next ]);

  let get_flags_stmts = match pick_variant 3 with
    | 0 -> [
        decl_var UInt64 "f" ~init:(u64 2L);
        if_then (var "ctx.cf") [ var "f" |= u64 1L ];
        if_then (var "ctx.zf") [ var "f" |= u64 0x40L ];
        if_then (var "ctx.sf") [ var "f" |= u64 0x80L ];
        if_then (var "ctx.of") [ var "f" |= u64 0x800L ];
        set_reg (var "dst") (var "f");
      ]
    | 1 -> [
        let_u64 "f" (u64 2L |~
          ternary (var "ctx.cf") (u64 1L) (u64 0L) |~
          ternary (var "ctx.zf") (u64 0x40L) (u64 0L) |~
          ternary (var "ctx.sf") (u64 0x80L) (u64 0L) |~
          ternary (var "ctx.of") (u64 0x800L) (u64 0L));
        set_reg (var "dst") (var "f");
      ]
    | _ -> [
        decl_var UInt64 "f" ~init:(u64 2L);
        var "f" |= cast UInt64 (var "ctx.cf");
        var "f" |= (cast UInt64 (var "ctx.zf") <<~ i32 6);
        var "f" |= (cast UInt64 (var "ctx.sf") <<~ i32 7);
        var "f" |= (cast UInt64 (var "ctx.of") <<~ i32 11);
        set_reg (var "dst") (var "f");
      ]
  in
  emit_handler_ast b "H_GET_FLAGS_R" (get_flags_stmts @ [ inc_instrs; fetch_next ]);

  let set_flags_stmts = match pick_variant 3 with
    | 0 -> [
        let_u64 "f" reg_src;
        var "ctx.cf" := ((var "f" &~ u64 1L) <>~ u64 0L);
        var "ctx.zf" := ((var "f" &~ u64 0x40L) <>~ u64 0L);
        var "ctx.sf" := ((var "f" &~ u64 0x80L) <>~ u64 0L);
        var "ctx.of" := ((var "f" &~ u64 0x800L) <>~ u64 0L);
      ]
    | 1 -> [
        let_u64 "f" reg_src;
        var "ctx.cf" := cast Bool (var "f" &~ u64 1L);
        var "ctx.zf" := cast Bool (var "f" &~ u64 0x40L);
        var "ctx.sf" := cast Bool (var "f" &~ u64 0x80L);
        var "ctx.of" := cast Bool (var "f" &~ u64 0x800L);
      ]
    | _ -> [
        let_u64 "mask" reg_src;
        var "ctx.cf" := (((var "mask" >>~ i32 0) &~ u64 1L) <>~ u64 0L);
        var "ctx.zf" := (((var "mask" >>~ i32 6) &~ u64 1L) <>~ u64 0L);
        var "ctx.sf" := (((var "mask" >>~ i32 7) &~ u64 1L) <>~ u64 0L);
        var "ctx.of" := (((var "mask" >>~ i32 11) &~ u64 1L) <>~ u64 0L);
      ]
  in
  emit_handler_ast b "H_SET_FLAGS_R" (set_flags_stmts @ [ inc_instrs; fetch_next ])
