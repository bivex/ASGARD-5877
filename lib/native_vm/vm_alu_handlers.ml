let emit_probes b ~enable_timing_probes =
  if enable_timing_probes then begin
    Buffer.add_string b "    #if defined(__x86_64__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #elif defined(__aarch64__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t0))\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile(\"mrs %0, cntvct_el0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #elif defined(__riscv) || defined(__riscv__)\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0; __asm__ volatile(\"rdtime %0\" : \"=r\"(_t0))\n";
    Buffer.add_string b "    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile(\"rdtime %0\" : \"=r\"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)\n";
    Buffer.add_string b "    #else\n";
    Buffer.add_string b "    #define PROBE_START() uint64_t _t0 = 0\n";
    Buffer.add_string b "    #define PROBE_CHECK() do {} while(0)\n";
    Buffer.add_string b "    #endif\n\n";
  end else begin
    Buffer.add_string b "    #define PROBE_START() do {} while(0)\n";
    Buffer.add_string b "    #define PROBE_CHECK() do {} while(0)\n\n";
  end

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

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
    Buffer.add_string b "#if defined(ASGARD_EPHEMERAL_JIT)\n";
    emit_handler_inline_ast b "H_MOV_RR" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RR" (var "dst") (var "src") (i32 0);
      inc_instrs; fetch_next
    ];
    emit_handler_inline_ast b "H_MOV_RI" [
      eph_call "asgard_ephemeral_jit::EPH_OP_MOV_RI" (var "dst") (i32 0) (cast UInt64 (cast UInt32 (var "imm")));
      inc_instrs; fetch_next
    ];
    Buffer.add_string b "#else\n"
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
    Buffer.add_string b "#endif\n";
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
    Buffer.add_string b "#if defined(ASGARD_EPHEMERAL_JIT)\n";
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
    Buffer.add_string b "#else\n"
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
    Buffer.add_string b "#endif\n";
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
    Buffer.add_string b "#if defined(ASGARD_EPHEMERAL_JIT)\n";
    emit_handler_inline_ast b "H_ADD_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_ADD_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_ADD_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_ADD_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SUB_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_SUB_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_SUB_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_SUB_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_IMUL_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_MUL_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_IMUL_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_MUL_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_XOR_RR" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_XOR_RR" (var "dst") (var "src") (i32 0); probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_XOR_RI" [ probe_start; eph_call "asgard_ephemeral_jit::EPH_OP_XOR_RI" (var "dst") (i32 0) imm_u64; probe_check; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_AND_RR" [ eph_call "asgard_ephemeral_jit::EPH_OP_AND_RR" (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_AND_RI" [ eph_call "asgard_ephemeral_jit::EPH_OP_AND_RI" (var "dst") (i32 0) imm_u64; inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_OR_RR"  [ eph_call "asgard_ephemeral_jit::EPH_OP_OR_RR"  (var "dst") (var "src") (i32 0); inc_instrs; fetch_next ];
    emit_handler_inline_ast b "H_OR_RI"  [ eph_call "asgard_ephemeral_jit::EPH_OP_OR_RI"  (var "dst") (i32 0) imm_u64; inc_instrs; fetch_next ];
    Buffer.add_string b "#else\n"
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
    Buffer.add_string b "#endif\n";

  if enable_ephemeral_jit then begin
    Buffer.add_string b "#if defined(ASGARD_EPHEMERAL_JIT)\n";
    Buffer.add_string b "    H_ROL_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ROL_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_ROR_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ROR_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SHL_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SHL_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SHR_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SHR_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SAR_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SAR_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_ROL_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ROL_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_ROR_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ROR_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SHL_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SHL_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SHR_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SHR_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "    H_SAR_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SAR_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }\n";
    Buffer.add_string b "#else\n"
  end;
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
  if enable_ephemeral_jit then
    Buffer.add_string b "#endif\n";
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
  Buffer.add_string b "    H_CMP_RI_A1: {\n        PROBE_START();\n        uint64_t _d = ctx.get_reg(dst);\n        compute_sub_flags(ctx, _d, static_cast<uint64_t>(imm), static_cast<uint32_t>((word >> 50) & 0x7F));\n        PROBE_CHECK();\n        ctx.executed_instructions++; FETCH_NEXT();\n    }\n";
  Buffer.add_string b "    H_CMP_RI_A2: {\n        PROBE_START();\n        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);\n        uint64_t _imm = (uint64_t)imm;\n        compute_sub_flags(ctx, ctx.get_reg(dst), _imm, bits);\n        PROBE_CHECK();\n        ctx.executed_instructions++; FETCH_NEXT();\n    }\n";
  Buffer.add_string b "    H_CMP_RR_A1: {\n        PROBE_START();\n        uint64_t _a = ctx.get_reg(dst), _b = ctx.get_reg(src);\n        compute_sub_flags(ctx, _a, _b, static_cast<uint32_t>((word >> 50) & 0x7F));\n        PROBE_CHECK();\n        ctx.executed_instructions++; FETCH_NEXT();\n    }\n";
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
