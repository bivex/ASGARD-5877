open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

[@@@warning "-32"]

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

let let_u16 name expr = decl_var UInt16 name ~init:expr
let let_u8 name expr = decl_var UInt8 name ~init:expr
let let_i64 name expr = decl_var Int64 name ~init:expr
let let_i32 name expr = decl_var Int32 name ~init:expr
let let_size_t name expr = decl_var SizeT name ~init:expr
let get_vreg_lane r lane = call "ctx.get_vreg_lane" [r; lane]
let set_vreg_lane r lane val_e = expr_stmt (call "ctx.set_vreg_lane" [r; lane; val_e])
let set_vreg dst_e l0 l1 = expr_stmt (call "ctx.set_vreg" [dst_e; l0; l1])

let emit_simd_handlers ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  let vadd_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vd" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]]);
           decl_var (StructType "uint64x2_t") "vs" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]]);
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vaddq_u64" [var "vd"; var "vs"]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vd" ~init:(call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")]);
             decl_var (StructType "__m128i") "vs" ~init:(call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")]);
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_add_epi64" [var "vd"; var "vs"]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             set_vreg (var "dst") (var "d0" +~ var "s0") (var "d1" +~ var "s1");
           ]
         ]
       ]
     | 1 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vaddq_u64" [
             call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]];
             call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]];
           ]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_add_epi64" [
               call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")];
               call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")];
             ]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             let_u64 "_r0" (var "d0" +~ var "s0");
             let_u64 "_r1" (var "d1" +~ var "s1");
             set_vreg (var "dst") (var "_r0") (var "_r1");
           ]
         ]
       ]
     | _ -> [
         let_u64 "_res0" (var "d0" +~ var "s0");
         let_u64 "_res1" (var "d1" +~ var "s1");
         set_vreg (var "dst") (var "_res0") (var "_res1");
       ])
  in
  emit_handler_ast b "H_VADD_VV" (vadd_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vsub_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vd" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]]);
           decl_var (StructType "uint64x2_t") "vs" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]]);
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vsubq_u64" [var "vd"; var "vs"]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vd" ~init:(call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")]);
             decl_var (StructType "__m128i") "vs" ~init:(call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")]);
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_sub_epi64" [var "vd"; var "vs"]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             set_vreg (var "dst") (var "d0" -~ var "s0") (var "d1" -~ var "s1");
           ]
         ]
       ]
     | 1 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vsubq_u64" [
             call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]];
             call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]];
           ]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_sub_epi64" [
               call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")];
               call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")];
             ]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             let_u64 "_r0" (var "d0" -~ var "s0");
             let_u64 "_r1" (var "d1" -~ var "s1");
             set_vreg (var "dst") (var "_r0") (var "_r1");
           ]
         ]
       ]
     | _ -> [
         let_u64 "_res0" (var "d0" -~ var "s0");
         let_u64 "_res1" (var "d1" -~ var "s1");
         set_vreg (var "dst") (var "_res0") (var "_res1");
       ])
  in
  emit_handler_ast b "H_VSUB_VV" (vsub_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vmul_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [ set_vreg (var "dst") (var "d0" *~ var "s0") (var "d1" *~ var "s1") ]
     | 1 -> [
         let_u64 "_m0" (var "d0" *~ var "s0");
         let_u64 "_m1" (var "d1" *~ var "s1");
         set_vreg (var "dst") (var "_m0") (var "_m1");
       ]
     | _ -> [
         set_vreg (var "dst") (cast UInt64 (var "d0" *~ var "s0")) (cast UInt64 (var "d1" *~ var "s1"));
       ])
  in
  emit_handler_ast b "H_VMUL_VV" (vmul_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vxor_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vd" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]]);
           decl_var (StructType "uint64x2_t") "vs" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]]);
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "veorq_u64" [var "vd"; var "vs"]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vd" ~init:(call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")]);
             decl_var (StructType "__m128i") "vs" ~init:(call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")]);
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_xor_si128" [var "vd"; var "vs"]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             set_vreg (var "dst") (var "d0" ^~ var "s0") (var "d1" ^~ var "s1");
           ]
         ]
       ]
     | 1 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "veorq_u64" [
             call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]];
             call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]];
           ]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_xor_si128" [
               call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")];
               call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")];
             ]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             let_u64 "_r0" (var "d0" ^~ var "s0");
             let_u64 "_r1" (var "d1" ^~ var "s1");
             set_vreg (var "dst") (var "_r0") (var "_r1");
           ]
         ]
       ]
     | _ -> [
         let_u64 "_res0" (var "d0" ^~ var "s0");
         let_u64 "_res1" (var "d1" ^~ var "s1");
         set_vreg (var "dst") (var "_res0") (var "_res1");
       ])
  in
  emit_handler_ast b "H_VXOR_VV" (vxor_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vec_mov_stmts = match pick_variant 3 with
    | 0 -> [
        let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
        for_range "i" (i32 0) ((var "bits" +~ i32 63) /~ i32 64) [
          set_vreg_lane (var "dst") (var "i") (get_vreg_lane (var "src") (var "i"));
        ];
      ]
    | 1 -> [
        let_size_t "_words" (cast SizeT ((cast UInt32 (var "imm" &~ u64 0x3FFL) +~ i32 63) /~ i32 64));
        for_range "i" (i32 0) (var "_words") [
          let_u64 "_v" (get_vreg_lane (var "src") (var "i"));
          set_vreg_lane (var "dst") (var "i") (var "_v");
        ];
      ]
    | _ -> [
        let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
        decl_var SizeT "i" ~init:(i32 0);
        while_loop (var "i" <~ ((var "bits" +~ i32 63) /~ i32 64)) [
          set_vreg_lane (var "dst") (var "i") (get_vreg_lane (var "src") (var "i"));
          (var "i" += i32 1);
        ];
      ]
  in
  emit_handler_ast b "H_VEC_MOV" (vec_mov_stmts @ [ inc_instrs; fetch_next ]);
  Buffer.add_string b "    H_VEC_BINOP: {\n";
  Buffer.add_string b "        uint32_t src2 = (uint32_t)(imm & 31);\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);\n";
  Buffer.add_string b "        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);\n";
  Buffer.add_string b "        if (lane_bits == 0) lane_bits = 64;\n";
  Buffer.add_string b "        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);\n";
  Buffer.add_string b "        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);\n";
  Buffer.add_string b "        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));\n";
  Buffer.add_string b "        for (size_t bit = 0; bit < bits; bit += lane_bits) {\n";
  Buffer.add_string b "            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);\n";
  Buffer.add_string b "            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;\n";
  Buffer.add_string b "            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;\n";
  Buffer.add_string b "            uint64_t value = 0;\n";
  Buffer.add_string b "            if (elem == 1 && vop <= 2) {\n";
  Buffer.add_string b "                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));\n";
  Buffer.add_string b "                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));\n";
  Buffer.add_string b "                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);\n";
  Buffer.add_string b "                value = std::bit_cast<uint32_t>(fr);\n";
  Buffer.add_string b "            } else if (elem == 1 && vop == 11) {\n";
  Buffer.add_string b "                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));\n";
  Buffer.add_string b "                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));\n";
  Buffer.add_string b "                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));\n";
  Buffer.add_string b "            } else if (elem == 1 && vop == 12) {\n";
  Buffer.add_string b "                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));\n";
  Buffer.add_string b "                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));\n";
  Buffer.add_string b "                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));\n";
  Buffer.add_string b "            } else if (elem == 2 && vop <= 2) {\n";
  Buffer.add_string b "                double fa = std::bit_cast<double>(a);\n";
  Buffer.add_string b "                double fb = std::bit_cast<double>(b);\n";
  Buffer.add_string b "                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);\n";
  Buffer.add_string b "                value = std::bit_cast<uint64_t>(fr);\n";
  Buffer.add_string b "            } else if (elem == 2 && vop == 11) {\n";
  Buffer.add_string b "                double fa = std::bit_cast<double>(a);\n";
  Buffer.add_string b "                double fb = std::bit_cast<double>(b);\n";
  Buffer.add_string b "                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));\n";
  Buffer.add_string b "            } else if (elem == 2 && vop == 12) {\n";
  Buffer.add_string b "                double fa = std::bit_cast<double>(a);\n";
  Buffer.add_string b "                double fb = std::bit_cast<double>(b);\n";
  Buffer.add_string b "                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));\n";
  Buffer.add_string b "            } else {\n";
  Buffer.add_string b "                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));\n";
  Buffer.add_string b "                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));\n";
  Buffer.add_string b "                switch (vop) {\n";
  Buffer.add_string b "                    case 0: value = a + b; break;\n";
  Buffer.add_string b "                    case 1: value = a - b; break;\n";
  Buffer.add_string b "                    case 2: value = a * b; break;\n";
  Buffer.add_string b "                    case 3: value = a & b; break;\n";
  Buffer.add_string b "                    case 4: value = a | b; break;\n";
  Buffer.add_string b "                    case 5: value = a ^ b; break;\n";
  Buffer.add_string b "                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }\n";
  Buffer.add_string b "                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }\n";
  Buffer.add_string b "                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }\n";
  Buffer.add_string b "                    case 9: value = (a == b) ? mask : 0; break;\n";
  Buffer.add_string b "                    case 10: value = (sa > sb) ? mask : 0; break;\n";
  Buffer.add_string b "                    case 11: value = (sa < sb) ? a : b; break;\n";
  Buffer.add_string b "                    case 12: value = (sa > sb) ? a : b; break;\n";
  Buffer.add_string b "                    case 13: value = (a < b) ? a : b; break;\n";
  Buffer.add_string b "                    case 14: value = (a > b) ? a : b; break;\n";
  Buffer.add_string b "                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;\n";
  Buffer.add_string b "                    case 16: value = (~a) & b; break;\n";
  Buffer.add_string b "                    case 17: {\n";
  Buffer.add_string b "                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);\n";
  Buffer.add_string b "                        size_t half_idx = block_lane / 2;\n";
  Buffer.add_string b "                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;\n";
  Buffer.add_string b "                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);\n";
  Buffer.add_string b "                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 18: {\n";
  Buffer.add_string b "                        size_t num_lanes = 128 / lane_bits;\n";
  Buffer.add_string b "                        size_t block_lane = (bit / lane_bits) % num_lanes;\n";
  Buffer.add_string b "                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);\n";
  Buffer.add_string b "                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;\n";
  Buffer.add_string b "                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);\n";
  Buffer.add_string b "                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 21: {\n";
  Buffer.add_string b "                        uint8_t ctrl = (uint8_t)(b & 0xff);\n";
  Buffer.add_string b "                        if (ctrl & 0x80) value = 0;\n";
  Buffer.add_string b "                        else {\n";
  Buffer.add_string b "                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);\n";
  Buffer.add_string b "                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;\n";
  Buffer.add_string b "                        }\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 23: {\n";
  Buffer.add_string b "                        size_t num_lanes = 128 / lane_bits;\n";
  Buffer.add_string b "                        size_t block_lane = (bit / lane_bits) % num_lanes;\n";
  Buffer.add_string b "                        size_t half_len = num_lanes / 2;\n";
  Buffer.add_string b "                        size_t src_reg = (block_lane < half_len) ? src : src2;\n";
  Buffer.add_string b "                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);\n";
  Buffer.add_string b "                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);\n";
  Buffer.add_string b "                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 24: {\n";
  Buffer.add_string b "                        size_t num_lanes = 128 / lane_bits;\n";
  Buffer.add_string b "                        size_t block_lane = (bit / lane_bits) % num_lanes;\n";
  Buffer.add_string b "                        size_t half_len = num_lanes / 2;\n";
  Buffer.add_string b "                        size_t src_reg = (block_lane < half_len) ? src : src2;\n";
  Buffer.add_string b "                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);\n";
  Buffer.add_string b "                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);\n";
  Buffer.add_string b "                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 25: {\n";
  Buffer.add_string b "                        size_t num_lanes = 128 / lane_bits;\n";
  Buffer.add_string b "                        size_t block_lane = (bit / lane_bits) % num_lanes;\n";
  Buffer.add_string b "                        size_t k = block_lane / 2;\n";
  Buffer.add_string b "                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;\n";
  Buffer.add_string b "                        size_t sel_elem = k * 2;\n";
  Buffer.add_string b "                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);\n";
  Buffer.add_string b "                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 26: {\n";
  Buffer.add_string b "                        size_t num_lanes = 128 / lane_bits;\n";
  Buffer.add_string b "                        size_t block_lane = (bit / lane_bits) % num_lanes;\n";
  Buffer.add_string b "                        size_t k = block_lane / 2;\n";
  Buffer.add_string b "                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;\n";
  Buffer.add_string b "                        size_t sel_elem = k * 2 + 1;\n";
  Buffer.add_string b "                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);\n";
  Buffer.add_string b "                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 28: {\n";
  Buffer.add_string b "                        uint8_t idx = (uint8_t)(b & 0xff);\n";
  Buffer.add_string b "                        if (idx < 16) {\n";
  Buffer.add_string b "                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);\n";
  Buffer.add_string b "                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;\n";
  Buffer.add_string b "                        } else {\n";
  Buffer.add_string b "                            value = 0;\n";
  Buffer.add_string b "                        }\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 29: {\n";
  Buffer.add_string b "                        uint8_t idx = (uint8_t)(b & 0xff);\n";
  Buffer.add_string b "                        if (idx < 16) {\n";
  Buffer.add_string b "                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);\n";
  Buffer.add_string b "                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;\n";
  Buffer.add_string b "                        } else {\n";
  Buffer.add_string b "                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;\n";
  Buffer.add_string b "                        }\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 30: {\n";
  Buffer.add_string b "                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;\n";
  Buffer.add_string b "                        if (sb == 0) value = ~0ULL;\n";
  Buffer.add_string b "                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;\n";
  Buffer.add_string b "                        else value = (uint64_t)(sa / sb);\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 31: {\n";
  Buffer.add_string b "                        value = (b != 0) ? (a / b) : mask;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 32: {\n";
  Buffer.add_string b "                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;\n";
  Buffer.add_string b "                        if (sb == 0) value = a;\n";
  Buffer.add_string b "                        else if (sb == -1 && sa == min_val) value = 0;\n";
  Buffer.add_string b "                        else value = (uint64_t)(sa % sb);\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 33: {\n";
  Buffer.add_string b "                        value = (b != 0) ? (a % b) : a;\n";
  Buffer.add_string b "                        break;\n";
  Buffer.add_string b "                    }\n";
  Buffer.add_string b "                    case 34: value = (a != b) ? mask : 0; break;\n";
  Buffer.add_string b "                    case 35: value = (sa <= sb) ? mask : 0; break;\n";
  Buffer.add_string b "                    case 36: value = (a < b) ? mask : 0; break;\n";
  Buffer.add_string b "                    case 37: value = (a <= b) ? mask : 0; break;\n";
  Buffer.add_string b "                    default: value = a ^ b; break;\n";
  Buffer.add_string b "                }\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);\n";
  Buffer.add_string b "            uint64_t packed_mask = mask << shift;\n";
  Buffer.add_string b "            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_IMM: {\n";
  Buffer.add_string b "        uint64_t imm_val = imm & 0xffULL;\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);\n";
  Buffer.add_string b "        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);\n";
  Buffer.add_string b "        if (lane_bits == 0) lane_bits = 64;\n";
  Buffer.add_string b "        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);\n";
  Buffer.add_string b "        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));\n";
  Buffer.add_string b "        for (size_t bit = 0; bit < bits; bit += lane_bits) {\n";
  Buffer.add_string b "            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);\n";
  Buffer.add_string b "            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;\n";
  Buffer.add_string b "            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));\n";
  Buffer.add_string b "            uint64_t value = 0;\n";
  Buffer.add_string b "            switch (vop) {\n";
  Buffer.add_string b "                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }\n";
  Buffer.add_string b "                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }\n";
  Buffer.add_string b "                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }\n";
  Buffer.add_string b "                case 21: {\n";
  Buffer.add_string b "                    size_t lane_in_128 = (bit / 32) % 4;\n";
  Buffer.add_string b "                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;\n";
  Buffer.add_string b "                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);\n";
  Buffer.add_string b "                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;\n";
  Buffer.add_string b "                    break;\n";
  Buffer.add_string b "                }\n";
  Buffer.add_string b "                case 22: {\n";
  Buffer.add_string b "                    size_t lane_idx = bit / lane_bits;\n";
  Buffer.add_string b "                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;\n";
  Buffer.add_string b "                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);\n";
  Buffer.add_string b "                    break;\n";
  Buffer.add_string b "                }\n";
  Buffer.add_string b "                default: value = a; break;\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);\n";
  Buffer.add_string b "            uint64_t packed_mask = mask << shift;\n";
  Buffer.add_string b "            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_CLEAR_UPPER: {\n";
  Buffer.add_string b "        ctx.set_vreg_lane(dst, 2, 0ULL);\n";
  Buffer.add_string b "        ctx.set_vreg_lane(dst, 3, 0ULL);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_ZERO_UPPER: {\n";
  Buffer.add_string b "        for (size_t i = 0; i < 16; ++i) {\n";
  Buffer.add_string b "            ctx.set_vreg_lane(i, 2, 0ULL);\n";
  Buffer.add_string b "            ctx.set_vreg_lane(i, 3, 0ULL);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_PMOVMSKB: {\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)(imm & 0x3ff);\n";
  Buffer.add_string b "        uint32_t num_bytes = bits / 8;\n";
  Buffer.add_string b "        uint64_t mask = 0;\n";
  Buffer.add_string b "        for (uint32_t b = 0; b < num_bytes; ++b) {\n";
  Buffer.add_string b "            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;\n";
  Buffer.add_string b "            if (byte_val & 0x80) mask |= (1ULL << b);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.set_reg(dst, mask);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_LOAD: {\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);\n";
  Buffer.add_string b "        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;\n";
  Buffer.add_string b "        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_STORE: {\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);\n";
  Buffer.add_string b "        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;\n";
  Buffer.add_string b "        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_SPLAT: {\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)(imm & 0xffff);\n";
  Buffer.add_string b "        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);\n";
  Buffer.add_string b "        uint64_t val = ctx.get_reg(src);\n";
  Buffer.add_string b "        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);\n";
  Buffer.add_string b "        uint64_t val_masked = val & mask;\n";
  Buffer.add_string b "        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;\n";
  Buffer.add_string b "        for (uint32_t l = 0; l < num_lanes; ++l) {\n";
  Buffer.add_string b "            uint32_t pos = l * lane_bits;\n";
  Buffer.add_string b "            uint32_t chunk = pos / 64;\n";
  Buffer.add_string b "            uint32_t shift = pos % 64;\n";
  Buffer.add_string b "            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);\n";
  Buffer.add_string b "            uint64_t cur = ctx.get_vreg_lane(dst, chunk);\n";
  Buffer.add_string b "            cur = (cur & ~packed_mask) | (val_masked << shift);\n";
  Buffer.add_string b "            ctx.set_vreg_lane(dst, chunk, cur);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_VEC_EXT: {\n";
  Buffer.add_string b "        uint32_t src2 = (uint32_t)(imm & 31);\n";
  Buffer.add_string b "        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);\n";
  Buffer.add_string b "        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);\n";
  Buffer.add_string b "        if (bits == 0) bits = 128;\n";
  Buffer.add_string b "        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {\n";
  Buffer.add_string b "            size_t total_idx = (byte_idx % 16) + shift_bytes;\n";
  Buffer.add_string b "            uint64_t val = 0;\n";
  Buffer.add_string b "            if (total_idx < 16) {\n";
  Buffer.add_string b "                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);\n";
  Buffer.add_string b "                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;\n";
  Buffer.add_string b "            } else {\n";
  Buffer.add_string b "                size_t m_idx = total_idx - 16;\n";
  Buffer.add_string b "                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);\n";
  Buffer.add_string b "                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);\n";
  Buffer.add_string b "            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);\n";
  Buffer.add_string b "            uint64_t clr = old_v & ~(0xffULL << shift);\n";
  Buffer.add_string b "            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n\n"

let emit_mem_and_ffi_handlers ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  Buffer.add_string b "    H_CALL_EXTERN: {\n";
  Buffer.add_string b "        size_t sym_idx = (size_t)imm;\n";
  Buffer.add_string b "        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);\n";
  Buffer.add_string b "        if (sym_ptr) {\n";
  Buffer.add_string b "            uint32_t sym_h = g_external_symbols[sym_idx].hash;\n";
  Buffer.add_string b "            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;\n";
  Buffer.add_string b "#if defined(ASGARD_GUEST_ARM64)
            uint64_t a0 = ctx.get_reg(REG_X0);
            uint64_t a1 = ctx.get_reg(REG_X1);
            uint64_t a2 = ctx.get_reg(REG_X2);
            uint64_t a3 = ctx.get_reg(REG_X3);
            uint64_t a4 = ctx.get_reg(REG_X4);
            uint64_t a5 = ctx.get_reg(REG_X5);
            uint64_t a6 = ctx.get_reg(REG_X6);
            uint64_t a7 = ctx.get_reg(REG_X7);
#elif defined(ASGARD_GUEST_RISCV64)
            uint64_t a0 = ctx.get_reg(REG_A0);
            uint64_t a1 = ctx.get_reg(REG_A1);
            uint64_t a2 = ctx.get_reg(REG_A2);
            uint64_t a3 = ctx.get_reg(REG_A3);
            uint64_t a4 = ctx.get_reg(REG_A4);
            uint64_t a5 = ctx.get_reg(REG_A5);
            uint64_t a6 = ctx.get_reg(REG_A6);
            uint64_t a7 = ctx.get_reg(REG_A7);
#else
            uint64_t a0 = ctx.get_reg(REG_RDI) ? ctx.get_reg(REG_RDI) : ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RSI);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RCX);
            uint64_t a4 = ctx.get_reg(REG_R8);
            uint64_t a5 = ctx.get_reg(REG_R9);
            uint64_t a6 = ctx.get_reg(REG_RAX);
            uint64_t a7 = ctx.get_reg(REG_RBX);
#endif\n";
  Buffer.add_string b "            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));\n";
  Buffer.add_string b "            uint64_t ret_val = 0;\n";
  Buffer.add_string b "            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {\n";
  Buffer.add_string b "                typedef int (*printf_fn_t)(const char*, ...);\n";
  Buffer.add_string b "                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);\n";
  Buffer.add_string b "#if defined(__APPLE__) && defined(__aarch64__)\n";
  Buffer.add_string b "                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);\n";
  Buffer.add_string b "#else\n";
  Buffer.add_string b "                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string b "#endif\n";
  Buffer.add_string b "            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {\n";
  Buffer.add_string b "                typedef int (*fprintf_fn_t)(void*, const char*, ...);\n";
  Buffer.add_string b "                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);\n";
  Buffer.add_string b "#if defined(__APPLE__) && defined(__aarch64__)\n";
  Buffer.add_string b "                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);\n";
  Buffer.add_string b "#else\n";
  Buffer.add_string b "                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string b "#endif\n";
  Buffer.add_string b "            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {\n";
  Buffer.add_string b "                typedef int (*sprintf_fn_t)(char*, const char*, ...);\n";
  Buffer.add_string b "                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);\n";
  Buffer.add_string b "#if defined(__APPLE__) && defined(__aarch64__)\n";
  Buffer.add_string b "                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);\n";
  Buffer.add_string b "#else\n";
  Buffer.add_string b "                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string b "#endif\n";
  Buffer.add_string b "            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {\n";
  Buffer.add_string b "                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);\n";
  Buffer.add_string b "                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);\n";
  Buffer.add_string b "#if defined(__APPLE__) && defined(__aarch64__)\n";
  Buffer.add_string b "                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);\n";
  Buffer.add_string b "#else\n";
  Buffer.add_string b "                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string b "#endif\n";
  Buffer.add_string b "            } else {\n";
  Buffer.add_string b "                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);\n";
  Buffer.add_string b "                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);\n";
  Buffer.add_string b "                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            ctx.set_reg(REG_RAX, ret_val);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n\n";

  Buffer.add_string b "    H_LOAD_64: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, *reinterpret_cast<const uint64_t*>(addr));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, *reinterpret_cast<const uint64_t*>(_base + imm));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint64_t _v = 0;\n";
       Buffer.add_string b "        std::memcpy(&_v, reinterpret_cast<const void*>(_ptr), sizeof(uint64_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, _v);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_LOAD_32: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(addr)));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(_base + imm)));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint32_t _v32 = 0;\n";
       Buffer.add_string b "        std::memcpy(&_v32, reinterpret_cast<const void*>(_ptr), sizeof(uint32_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)_v32);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_LOAD_16: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(addr)));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(_base + imm)));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint16_t _v16 = 0;\n";
       Buffer.add_string b "        std::memcpy(&_v16, reinterpret_cast<const void*>(_ptr), sizeof(uint16_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)_v16);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_LOAD_8: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint8_t*>(addr)));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint8_t*>(_base + imm)));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint8_t _v8 = 0;\n";
       Buffer.add_string b "        std::memcpy(&_v8, reinterpret_cast<const void*>(_ptr), sizeof(uint8_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)_v8);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_LOAD_S32: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int32_t*>(addr)));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int32_t*>(_base + imm)));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        int32_t _s32 = 0;\n";
       Buffer.add_string b "        std::memcpy(&_s32, reinterpret_cast<const void*>(_ptr), sizeof(int32_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)_s32);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_LOAD_S16: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(addr)));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(_base + imm)));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        int16_t _s16 = 0;\n";
       Buffer.add_string b "        std::memcpy(&_s16, reinterpret_cast<const void*>(_ptr), sizeof(int16_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)_s16);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_LOAD_S8: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int8_t*>(addr)));\n"
   | 1 ->
       Buffer.add_string b "        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int8_t*>(_base + imm)));\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        int8_t _s8 = 0;\n";
       Buffer.add_string b "        std::memcpy(&_s8, reinterpret_cast<const void*>(_ptr), sizeof(int8_t));\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)_s8);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_STORE_64: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(src);\n"
   | 1 ->
       Buffer.add_string b "        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint64_t*>(_target) = ctx.get_reg(src);\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint64_t _src_v = ctx.get_reg(src);\n";
       Buffer.add_string b "        std::memcpy(reinterpret_cast<void*>(_ptr), &_src_v, sizeof(uint64_t));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_STORE_32: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint32_t*>(addr) = (uint32_t)ctx.get_reg(src);\n"
   | 1 ->
       Buffer.add_string b "        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint32_t*>(_target) = (uint32_t)ctx.get_reg(src);\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint32_t _v32 = (uint32_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        std::memcpy(reinterpret_cast<void*>(_ptr), &_v32, sizeof(uint32_t));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_STORE_16: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint16_t*>(addr) = (uint16_t)ctx.get_reg(src);\n"
   | 1 ->
       Buffer.add_string b "        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint16_t*>(_target) = (uint16_t)ctx.get_reg(src);\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint16_t _v16 = (uint16_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        std::memcpy(reinterpret_cast<void*>(_ptr), &_v16, sizeof(uint16_t));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_STORE_8: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(src);\n"
   | 1 ->
       Buffer.add_string b "        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;\n";
       Buffer.add_string b "        *reinterpret_cast<uint8_t*>(_target) = (uint8_t)ctx.get_reg(src);\n"
   | _ ->
       Buffer.add_string b "        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);\n";
       Buffer.add_string b "        uint8_t _v8 = (uint8_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        std::memcpy(reinterpret_cast<void*>(_ptr), &_v8, sizeof(uint8_t));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_RESOLVE_SYM: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        size_t sym_idx = (size_t)imm;\n";
       Buffer.add_string b "        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)sym_ptr);\n"
   | 1 ->
       Buffer.add_string b "        size_t _idx = static_cast<size_t>(imm);\n";
       Buffer.add_string b "        void* _p = asgard_resolve_sym_idx((int32_t)_idx);\n";
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(reinterpret_cast<uintptr_t>(_p)));\n"
   | _ ->
       Buffer.add_string b "        size_t sym_idx = (size_t)imm;\n";
       Buffer.add_string b "        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)sym_ptr);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FADD_DD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a + b), 0);\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a + _b), 0);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) + std::bit_cast<double>(_i)), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FSUB_DD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a - b), 0);\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a - _b), 0);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) - std::bit_cast<double>(_i)), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FMUL_DD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a * b), 0);\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a * _b), 0);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) * std::bit_cast<double>(_i)), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FDIV_DD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);\n";
       Buffer.add_string b "        double r = a / b;\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));\n";
       Buffer.add_string b "        double _q = (_b == 0.0) ? ((_a == 0.0) ? NAN : (std::signbit(_a) ^ std::signbit(_b) ? -INFINITY : INFINITY)) : (_a / _b);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_q), 0);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(_s), b = std::bit_cast<double>(_i);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>((b != 0.0) ? (a / b) : 0.0), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FSQRT_D: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw);\n";
       Buffer.add_string b "        double r = std::sqrt(a);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        double _root = (_a < 0.0) ? NAN : std::sqrt(_a);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_root), 0);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(_s);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>((a >= 0.0) ? std::sqrt(a) : 0.0), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FCMP_DD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);\n";
       Buffer.add_string b "        bool is_nan = std::isnan(a) || std::isnan(b);\n";
       Buffer.add_string b "        ctx.zf = is_nan || (a == b);\n";
       Buffer.add_string b "        ctx.cf = is_nan || (a < b);\n";
       Buffer.add_string b "        ctx.pf = is_nan;\n";
       Buffer.add_string b "        ctx.sf = false;\n";
       Buffer.add_string b "        ctx.of = false;\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));\n";
       Buffer.add_string b "        bool _nan = std::isnan(_a) || std::isnan(_b);\n";
       Buffer.add_string b "        ctx.of = false;\n";
       Buffer.add_string b "        ctx.sf = false;\n";
       Buffer.add_string b "        ctx.cf = _nan || (_a < _b);\n";
       Buffer.add_string b "        ctx.zf = _nan || (_a == _b);\n";
       Buffer.add_string b "        ctx.pf = _nan;\n"
   | _ ->
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(_s), b = std::bit_cast<double>(_i);\n";
       Buffer.add_string b "        bool _nan = std::isnan(a) || std::isnan(b), _eq = (a == b), _lt = (a < b);\n";
       Buffer.add_string b "        ctx.zf = _nan || _eq; ctx.cf = _nan || _lt; ctx.pf = _nan; ctx.sf = false; ctx.of = false;\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FCVTZS: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)((int64_t)a));\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        int64_t _s64 = static_cast<int64_t>(_a);\n";
       Buffer.add_string b "        ctx.set_reg(dst, static_cast<uint64_t>(_s64));\n"
   | _ ->
       Buffer.add_string b "        ctx.set_reg(dst, (uint64_t)(int64_t)std::bit_cast<double>(ctx.get_vreg_lane(src, 0)));\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_SCVTF: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        int64_t v = (int64_t)ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);\n"
   | 1 ->
       Buffer.add_string b "        int64_t _s = static_cast<int64_t>(ctx.get_reg(src));\n";
       Buffer.add_string b "        double _d = static_cast<double>(_s);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);\n"
   | _ ->
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)(int64_t)ctx.get_reg(src)), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FCVTZU: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t a_raw = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "        double a = std::bit_cast<double>(a_raw);\n";
       Buffer.add_string b "        ctx.set_reg(dst, (a < 0.0) ? 0ULL : (uint64_t)a);\n"
   | 1 ->
       Buffer.add_string b "        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        uint64_t _u64 = (_a < 0.0) ? 0ULL : static_cast<uint64_t>(_a);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _u64);\n"
   | _ ->
       Buffer.add_string b "        double a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "        if (a < 0.0) ctx.set_reg(dst, 0ULL); else ctx.set_reg(dst, (uint64_t)a);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_UCVTF: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t v = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);\n"
   | 1 ->
       Buffer.add_string b "        double _d = static_cast<double>(ctx.get_reg(src));\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _v = ctx.get_reg(src);\n";
       Buffer.add_string b "        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)_v), 0);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FCVT: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        if ((uint32_t)imm == 1) {\n";
       Buffer.add_string b "            uint64_t a_raw = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "            double d64 = std::bit_cast<double>(a_raw);\n";
       Buffer.add_string b "            float f32 = static_cast<float>(d64);\n";
       Buffer.add_string b "            uint32_t u32 = std::bit_cast<uint32_t>(f32);\n";
       Buffer.add_string b "            uint64_t old_val = ctx.get_vreg_lane(dst, 0);\n";
       Buffer.add_string b "            ctx.set_vreg(dst, (old_val & 0xFFFFFFFF00000000ULL) | (uint64_t)u32, 0);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            uint64_t a_raw = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "            float f32 = std::bit_cast<float>((uint32_t)a_raw);\n";
       Buffer.add_string b "            ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);\n";
       Buffer.add_string b "        }\n"
   | 1 ->
       Buffer.add_string b "        if (static_cast<uint32_t>(imm) == 1) {\n";
       Buffer.add_string b "            double _d = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "            float _f = static_cast<float>(_d);\n";
       Buffer.add_string b "            uint32_t _u = std::bit_cast<uint32_t>(_f);\n";
       Buffer.add_string b "            uint64_t _prev = ctx.get_vreg_lane(dst, 0);\n";
       Buffer.add_string b "            ctx.set_vreg(dst, (_prev & 0xFFFFFFFF00000000ULL) | static_cast<uint64_t>(_u), 0);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            uint32_t _raw32 = static_cast<uint32_t>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "            float _f = std::bit_cast<float>(_raw32);\n";
       Buffer.add_string b "            double _d = static_cast<double>(_f);\n";
       Buffer.add_string b "            ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        if ((uint32_t)imm == 1) {\n";
       Buffer.add_string b "            double d64 = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "            float f32 = (float)d64;\n";
       Buffer.add_string b "            uint32_t u32 = std::bit_cast<uint32_t>(f32);\n";
       Buffer.add_string b "            ctx.set_vreg(dst, (ctx.get_vreg_lane(dst, 0) & 0xFFFFFFFF00000000ULL) | (uint64_t)u32, 0);\n";
       Buffer.add_string b "        } else {\n";
       Buffer.add_string b "            float f32 = std::bit_cast<float>((uint32_t)ctx.get_vreg_lane(src, 0));\n";
       Buffer.add_string b "            ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);\n";
       Buffer.add_string b "        }\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ATOMIC_LOAD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);\n";
       Buffer.add_string b "        ctx.set_reg(dst, ptr->load(std::memory_order_seq_cst));\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        uint64_t _val = __atomic_load_n(reinterpret_cast<uint64_t*>(_addr), __ATOMIC_SEQ_CST);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _val);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(src) + (uint64_t)imm;\n";
       Buffer.add_string b "        std::atomic_thread_fence(std::memory_order_seq_cst);\n";
       Buffer.add_string b "        uint64_t _loaded = *reinterpret_cast<volatile uint64_t*>(_addr);\n";
       Buffer.add_string b "        std::atomic_thread_fence(std::memory_order_seq_cst);\n";
       Buffer.add_string b "        ctx.set_reg(dst, _loaded);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ATOMIC_STORE: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);\n";
       Buffer.add_string b "        ptr->store(ctx.get_reg(src), std::memory_order_seq_cst);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        __atomic_store_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);\n"
   | _ ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        (void)__atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ATOMIC_CAS: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);\n";
       Buffer.add_string b "        uint64_t expected = ctx.get_reg(src);\n";
       Buffer.add_string b "        uint64_t desired = ctx.get_reg(REG_RAX);\n";
       Buffer.add_string b "        ptr->compare_exchange_strong(expected, desired, std::memory_order_seq_cst);\n";
       Buffer.add_string b "        ctx.set_reg(src, expected);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        uint64_t _exp = ctx.get_reg(src), _des = ctx.get_reg(REG_RAX);\n";
       Buffer.add_string b "        __atomic_compare_exchange_n(reinterpret_cast<uint64_t*>(_addr), &_exp, _des, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);\n";
       Buffer.add_string b "        ctx.set_reg(src, _exp);\n"
   | _ ->
       Buffer.add_string b "        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(ctx.get_reg(dst) + (uint64_t)imm);\n";
       Buffer.add_string b "        uint64_t expected = ctx.get_reg(src);\n";
       Buffer.add_string b "        while (!ptr->compare_exchange_weak(expected, ctx.get_reg(REG_RAX), std::memory_order_seq_cst, std::memory_order_seq_cst)) {\n";
       Buffer.add_string b "            if (expected != ctx.get_reg(src)) break;\n";
       Buffer.add_string b "        }\n";
       Buffer.add_string b "        ctx.set_reg(src, expected);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ATOMIC_ADD: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);\n";
       Buffer.add_string b "        uint64_t old = ptr->fetch_add(ctx.get_reg(src), std::memory_order_seq_cst);\n";
       Buffer.add_string b "        ctx.set_reg(src, old);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        uint64_t _old = __atomic_fetch_add(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);\n";
       Buffer.add_string b "        ctx.set_reg(src, _old);\n"
   | _ ->
       Buffer.add_string b "        uint64_t* ptr = reinterpret_cast<uint64_t*>(ctx.get_reg(dst) + (uint64_t)imm);\n";
       Buffer.add_string b "        uint64_t old = __atomic_load_n(ptr, __ATOMIC_RELAXED);\n";
       Buffer.add_string b "        uint64_t add_val = ctx.get_reg(src);\n";
       Buffer.add_string b "        while (!__atomic_compare_exchange_n(ptr, &old, old + add_val, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}\n";
       Buffer.add_string b "        ctx.set_reg(src, old);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_ATOMIC_SWP: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;\n";
       Buffer.add_string b "        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);\n";
       Buffer.add_string b "        uint64_t old = ptr->exchange(ctx.get_reg(src), std::memory_order_seq_cst);\n";
       Buffer.add_string b "        ctx.set_reg(src, old);\n"
   | 1 ->
       Buffer.add_string b "        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);\n";
       Buffer.add_string b "        uint64_t _old = __atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);\n";
       Buffer.add_string b "        ctx.set_reg(src, _old);\n"
   | _ ->
       Buffer.add_string b "        uint64_t* ptr = reinterpret_cast<uint64_t*>(ctx.get_reg(dst) + (uint64_t)imm);\n";
       Buffer.add_string b "        uint64_t old = __atomic_load_n(ptr, __ATOMIC_RELAXED);\n";
       Buffer.add_string b "        uint64_t new_val = ctx.get_reg(src);\n";
       Buffer.add_string b "        while (!__atomic_compare_exchange_n(ptr, &old, new_val, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}\n";
       Buffer.add_string b "        ctx.set_reg(src, old);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  emit_handler_inline_ast b "H_FENCE" [
    expr_stmt (call "std::atomic_thread_fence" [var "std::memory_order_seq_cst"]);
    inc_instrs; fetch_next;
  ];
  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_MOV_VR" [
       expr_stmt (call "ctx.set_vreg_lane" [var "dst"; i32 0; reg_src]);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_ast b "H_MOV_VR" [
       let_u64 "_val" reg_src;
       decl_var (Array (UInt64, 1)) "_buf";
       expr_stmt (call "std::memcpy" [var "_buf"; addr_of (var "_val"); call "sizeof" [var "uint64_t"]]);
       expr_stmt (call "ctx.set_vreg_lane" [var "dst"; i32 0; idx (var "_buf") (i32 0)]);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_ast b "H_MOV_VR" [
       let_u64 "_val" (reg_src ^~ u64 0xA5A5A5A55A5A5A5AL);
       expr_stmt (call "ctx.set_vreg_lane" [var "dst"; i32 0; var "_val" ^~ u64 0xA5A5A5A55A5A5A5AL]);
       inc_instrs; fetch_next;
     ]);
  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_MOV_RV" [
       set_reg (var "dst") (call "ctx.get_vreg_lane" [var "src"; i32 0]);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_ast b "H_MOV_RV" [
       let_u64 "_val" (call "ctx.get_vreg_lane" [var "src"; i32 0]);
       decl_var (Array (UInt64, 1)) "_buf";
       expr_stmt (call "std::memcpy" [var "_buf"; addr_of (var "_val"); call "sizeof" [var "uint64_t"]]);
       set_reg (var "dst") (idx (var "_buf") (i32 0));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_ast b "H_MOV_RV" [
       let_u64 "_val" (call "ctx.get_vreg_lane" [var "src"; i32 0] ^~ u64 0x5A5A5A5AA5A5A5A5L);
       set_reg (var "dst") (var "_val" ^~ u64 0x5A5A5A5AA5A5A5A5L);
       inc_instrs; fetch_next;
     ]);
  Buffer.add_string b "    H_FCSEL_VV: {\n";
  (match pick_variant 3 with
   | 0 ->
       Buffer.add_string b "        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
       Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_vreg_lane(dst, 0, ctx.get_vreg_lane(src, 0));\n"
   | 1 ->
       Buffer.add_string b "        if (eval_condition(ctx, static_cast<uint8_t>((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL))))) {\n";
       Buffer.add_string b "            uint64_t _v = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "            ctx.set_vreg_lane(dst, 0, _v);\n";
       Buffer.add_string b "        }\n"
   | _ ->
       Buffer.add_string b "        uint8_t _c = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));\n";
       Buffer.add_string b "        uint64_t _s = ctx.get_vreg_lane(src, 0);\n";
       Buffer.add_string b "        if (eval_condition(ctx, _c)) ctx.set_vreg_lane(dst, 0, _s);\n");
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n\n"

let emit_decoy_handlers ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in
  let k_dyn = var "k_dyn" in
  let op = var "op" in
  let imm_u64 = cast UInt64 (var "imm") in
  let reg_mask = var "ctx.reg_mask" in

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_0" [
       (reg_mask ^= (((k_dyn *~ u64 0x6A09E667F3BCC908L) +~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ (u64 0x5877L +~ imm_u64));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_0" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= ((k_dyn ^~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") ((var "_d" ^~ u64 0x5877L) +~ reg_mask);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_0" [
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x9E3779B97F4A7C15L) |~ u64 1L));
       set_reg (var "dst") (bit_not reg_dst ^~ bit_not (u64 0x5877L));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_1" [
       (reg_mask ^= ((k_dyn +~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_1" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (var "_d" +~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_1" [
       (reg_mask ^= ((k_dyn ^~ imm_u64) |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ imm_u64) +~ (u64 2L *~ (reg_dst &~ imm_u64)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_2" [
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xBF58476D1CE4E5B9L) |~ u64 1L));
       set_reg (var "dst") (reg_dst *~ u64 0x9E37L);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_2" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= ((k_dyn *~ u64 0x9E37L) |~ u64 1L));
       set_reg (var "dst") ((var "_d" *~ u64 0x9E37L) ^~ reg_mask);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_2" [
       (reg_mask ^= ((k_dyn ^~ u64 0x9E37L) |~ u64 1L));
       set_reg (var "dst") (reg_dst *~ u64 0x9E37L);
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_3" [
       (reg_mask ^= ((k_dyn >>~ i32 13) |~ u64 1L));
       set_reg (var "dst") ((reg_dst <<~ i32 3) |~ (reg_dst >>~ i32 61));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_3" [
       let_u64 "_v" reg_dst;
       (reg_mask ^= (((cast UInt64 op) <<~ i32 7) |~ u64 1L));
       set_reg (var "dst") ((var "_v" <<~ i32 3) ^~ (var "_v" >>~ i32 61));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_3" [
       let_u64 "_l" (reg_dst <<~ i32 3);
       let_u64 "_r" (reg_dst >>~ i32 61);
       (reg_mask ^= ((k_dyn *~ u64 0x517CC1B727220A95L) |~ u64 1L));
       set_reg (var "dst") (var "_l" |~ var "_r");
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_4" [
       (reg_mask ^= (((k_dyn ^~ imm_u64) *~ u64 0x9E3779B97F4A7C15L) |~ u64 1L));
       set_reg (var "dst") (reg_src ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_4" [
       let_u64 "_s" reg_src;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xCAFEL) |~ u64 1L));
       set_reg (var "dst") (var "_s" ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_4" [
       (reg_mask ^= ((k_dyn +~ cast UInt64 (var "src")) |~ u64 1L));
       set_reg (var "dst") ((reg_src |~ imm_u64) -~ (reg_src &~ imm_u64));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_5" [
       (reg_mask ^= ((k_dyn *~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (reg_dst &~ bit_not reg_src);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_5" [
       let_u64 "_d" reg_dst; let_u64 "_s" reg_src;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (var "_d" &~ bit_not (var "_s"));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_5" [
       (reg_mask ^= ((k_dyn ^~ cast UInt64 (var "dst")) |~ u64 1L));
       set_reg (var "dst") (bit_not (bit_not reg_dst |~ reg_src));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_6" [
       (reg_mask ^= ((k_dyn ^~ u64 0xCAFEBABEL) |~ u64 1L));
       set_reg (var "dst") (reg_dst |~ u64 0xCAFEBABEL);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_6" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xCAFEBABEL) |~ u64 1L));
       set_reg (var "dst") (var "_d" |~ u64 0xCAFEBABEL);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_6" [
       (reg_mask ^= ((k_dyn +~ u64 0xCAFEBABEL) |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ u64 0xCAFEBABEL) +~ (reg_dst &~ u64 0xCAFEBABEL));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_7" [
       (reg_mask ^= ((k_dyn >>~ i32 5) |~ u64 1L));
       set_reg (var "dst") ((reg_dst >>~ i32 5) ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_7" [
       let_u64 "_sh" (reg_dst >>~ i32 5);
       (reg_mask ^= (((cast UInt64 op) ^~ imm_u64) |~ u64 1L));
       set_reg (var "dst") (var "_sh" ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_7" [
       (reg_mask ^= ((k_dyn *~ u64 0x94D049BB133111EBL) |~ u64 1L));
       set_reg (var "dst") (((reg_dst >>~ i32 5) |~ imm_u64) -~ ((reg_dst >>~ i32 5) &~ imm_u64));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_8" [
       (reg_mask ^= ((k_dyn ^~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (reg_dst -~ u64 0x1337L);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_8" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) -~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (var "_d" -~ u64 0x1337L);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_8" [
       (reg_mask ^= ((k_dyn *~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ (bit_not (u64 0x1337L) +~ u64 1L));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_9" [
       (reg_mask ^= (((k_dyn +~ u64 1L) *~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ (reg_src +~ u64 1L));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_9" [
       let_u64 "_rhs" (reg_src +~ u64 1L);
       (reg_mask ^= (((cast UInt64 op) ^~ var "_rhs") |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ var "_rhs");
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_9" [
       (reg_mask ^= ((k_dyn ^~ cast UInt64 (var "src")) |~ u64 1L));
       set_reg (var "dst") ((reg_dst |~ (reg_src +~ u64 1L)) -~ (reg_dst &~ (reg_src +~ u64 1L)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_10" [
       (reg_mask ^= ((k_dyn *~ u64 6364136223846793005L) |~ u64 1L));
       set_reg (var "dst") ((reg_dst *~ u64 6364136223846793005L) +~ u64 1L);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_10" [
       let_u64 "_m" (reg_dst *~ u64 6364136223846793005L);
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x6A09L) |~ u64 1L));
       set_reg (var "dst") (var "_m" +~ u64 1L);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_10" [
       (reg_mask ^= ((k_dyn +~ u64 0x6364L) |~ u64 1L));
       set_reg (var "dst") ((reg_dst *~ u64 6364136223846793005L) +~ u64 1L);
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_11" [
       (reg_mask ^= ((k_dyn <<~ i32 7) |~ u64 1L));
       set_reg (var "dst") ((reg_dst <<~ i32 7) ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_11" [
       let_u64 "_sh" (reg_dst <<~ i32 7);
       (reg_mask ^= (((cast UInt64 op) <<~ i32 7) |~ u64 1L));
       set_reg (var "dst") (var "_sh" ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_11" [
       (reg_mask ^= ((k_dyn *~ u64 0x517CC1B727220A95L) |~ u64 1L));
       set_reg (var "dst") (((reg_dst <<~ i32 7) |~ imm_u64) -~ ((reg_dst <<~ i32 7) &~ imm_u64));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_12" [
       (reg_mask ^= ((k_dyn ^~ u64 0xDEADBEEFL) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ u64 0xDEADBEEFL);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_12" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xDEADBEEFL) |~ u64 1L));
       set_reg (var "dst") (var "_d" ^~ u64 0xDEADBEEFL);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_12" [
       (reg_mask ^= ((k_dyn +~ u64 0xDEADBEEFL) |~ u64 1L));
       set_reg (var "dst") (bit_not reg_dst ^~ bit_not (u64 0xDEADBEEFL));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_13" [
       (reg_mask ^= ((k_dyn +~ cast UInt64 (var "src")) |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ reg_src);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_13" [
       let_u64 "_a" reg_dst; let_u64 "_b" reg_src;
       (reg_mask ^= (((cast UInt64 op) +~ var "_a") |~ u64 1L));
       set_reg (var "dst") (var "_a" +~ var "_b");
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_13" [
       (reg_mask ^= ((k_dyn ^~ cast UInt64 (var "dst")) |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ reg_src) +~ (u64 2L *~ (reg_dst &~ reg_src)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_14" [
       (reg_mask ^= ((k_dyn ^~ (imm_u64 *~ u64 3L)) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ (imm_u64 *~ u64 3L));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_14" [
       let_u64 "_adj" (imm_u64 *~ u64 3L);
       (reg_mask ^= (((cast UInt64 op) *~ var "_adj") |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ var "_adj");
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_14" [
       (reg_mask ^= ((k_dyn *~ u64 3L) |~ u64 1L));
       set_reg (var "dst") ((reg_dst |~ (imm_u64 *~ u64 3L)) -~ (reg_dst &~ (imm_u64 *~ u64 3L)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_15" [
       (reg_mask ^= (bit_not k_dyn |~ u64 1L));
       set_reg (var "dst") (bit_not reg_dst);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_15" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (bit_not (cast UInt64 op) |~ u64 1L));
       set_reg (var "dst") (bit_not (var "_d"));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_15" [
       (reg_mask ^= ((k_dyn *~ u64 0xBF58476D1CE4E5B9L) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ bit_not (u64 0L));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY" [
       let_u64 "_p" (((k_dyn *~ u64 0x5877CAFEBEEFL) ^~ ((cast UInt64 op) *~ u64 0x9E3779B97F4A7C15L)) ^~ u64 0xDEADBEEF5A5A5A5AL);
       (reg_mask ^= (var "_p" |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ reg_mask);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY" [
       let_u64 "_p" ((((cast UInt64 op) *~ u64 0xBF58476D1CE4E5B9L) ^~ (k_dyn *~ u64 0x6A09E667F3BCC908L)) ^~ u64 0xCAFEBABE13375877L);
       (reg_mask ^= (var "_p" |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ reg_mask) +~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY" [
       let_u64 "_p" ((k_dyn ^~ ((cast UInt64 op) *~ u64 0x517CC1B727220A95L)) *~ u64 0x94D049BB133111EBL);
       (reg_mask ^= (var "_p" |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ reg_mask);
       inc_instrs; fetch_next;
     ])
