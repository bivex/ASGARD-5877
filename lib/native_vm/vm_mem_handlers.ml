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
  let vec_binop_stmts = [
    let_u32 "src2" (cast UInt32 (var "imm" &~ u64 31L));
    let_u32 "bits" (cast UInt32 ((var "imm" >>~ i32 5) &~ u64 0x3FFL));
    decl_var UInt32 "lane_bits" ~init:(cast UInt32 ((var "imm" >>~ i32 15) &~ u64 0xFFL));
    if_then (var "lane_bits" ==~ i32 0) [ var "lane_bits" := i32 64 ];
    let_u32 "vop" (cast UInt32 ((var "imm" >>~ i32 23) &~ u64 0x1FL));
    let_u32 "elem" (cast UInt32 ((var "imm" >>~ i32 28) &~ u64 0x3L));
    let_u64 "mask" (ternary (var "lane_bits" ==~ i32 8) (u64 0xFFL)
      (ternary (var "lane_bits" ==~ i32 16) (u64 0xFFFFL)
        (ternary (var "lane_bits" ==~ i32 32) (u64 0xFFFFFFFFL) (u64 (-1L)))));
    decl_var SizeT "bit" ~init:(i32 0);
    while_loop (var "bit" <~ var "bits") [
      let_size_t "chunk" (var "bit" /~ i32 64);
      decl_var UInt32 "shift" ~init:(cast UInt32 (var "bit" %~ i32 64));
      let_u64 "a" ((get_vreg_lane (var "src") (var "chunk") >>~ var "shift") &~ var "mask");
      let_u64 "b" ((get_vreg_lane (var "src2") (var "chunk") >>~ var "shift") &~ var "mask");
      decl_var UInt64 "value" ~init:(u64 0L);
      if_then_else ((var "elem" ==~ i32 1) &&~ (var "vop" <=~ i32 2)) [
        decl_var Float "fa" ~init:(bit_cast Float (cast UInt32 (var "a")));
        decl_var Float "fb" ~init:(bit_cast Float (cast UInt32 (var "b")));
        decl_var Float "fr" ~init:(ternary (var "vop" ==~ i32 0) (var "fa" +~ var "fb")
          (ternary (var "vop" ==~ i32 1) (var "fa" -~ var "fb") (var "fa" *~ var "fb")));
        var "value" := bit_cast UInt32 (var "fr");
      ] [
        if_then_else ((var "elem" ==~ i32 1) &&~ (var "vop" ==~ i32 11)) [
          decl_var Float "fa" ~init:(bit_cast Float (cast UInt32 (var "a")));
          decl_var Float "fb" ~init:(bit_cast Float (cast UInt32 (var "b")));
          var "value" := bit_cast UInt32 (call "std::fmin" [var "fa"; var "fb"]);
        ] [
          if_then_else ((var "elem" ==~ i32 1) &&~ (var "vop" ==~ i32 12)) [
            decl_var Float "fa" ~init:(bit_cast Float (cast UInt32 (var "a")));
            decl_var Float "fb" ~init:(bit_cast Float (cast UInt32 (var "b")));
            var "value" := bit_cast UInt32 (call "std::fmax" [var "fa"; var "fb"]);
          ] [
            if_then_else ((var "elem" ==~ i32 2) &&~ (var "vop" <=~ i32 2)) [
              decl_var Double "fa" ~init:(bit_cast Double (var "a"));
              decl_var Double "fb" ~init:(bit_cast Double (var "b"));
              decl_var Double "fr" ~init:(ternary (var "vop" ==~ i32 0) (var "fa" +~ var "fb")
                (ternary (var "vop" ==~ i32 1) (var "fa" -~ var "fb") (var "fa" *~ var "fb")));
              var "value" := bit_cast UInt64 (var "fr");
            ] [
              if_then_else ((var "elem" ==~ i32 2) &&~ (var "vop" ==~ i32 11)) [
                decl_var Double "fa" ~init:(bit_cast Double (var "a"));
                decl_var Double "fb" ~init:(bit_cast Double (var "b"));
                var "value" := bit_cast UInt64 (call "std::fmin" [var "fa"; var "fb"]);
              ] [
                if_then_else ((var "elem" ==~ i32 2) &&~ (var "vop" ==~ i32 12)) [
                  decl_var Double "fa" ~init:(bit_cast Double (var "a"));
                  decl_var Double "fb" ~init:(bit_cast Double (var "b"));
                  var "value" := bit_cast UInt64 (call "std::fmax" [var "fa"; var "fb"]);
                ] [
                  let_i64 "sa" (ternary (var "lane_bits" ==~ i32 8) (cast Int64 (c_cast Int8 (var "a")))
                    (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (var "a")))
                      (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (var "a"))) (cast Int64 (var "a")))));
                  let_i64 "sb" (ternary (var "lane_bits" ==~ i32 8) (cast Int64 (c_cast Int8 (var "b")))
                    (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (var "b")))
                      (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (var "b"))) (cast Int64 (var "b")))));
                  switch_annotated (var "vop") [
                    case (i32 0) [ var "value" := var "a" +~ var "b"; break_stmt ];
                    case (i32 1) [ var "value" := var "a" -~ var "b"; break_stmt ];
                    case (i32 2) [ var "value" := var "a" *~ var "b"; break_stmt ];
                    case (i32 3) [ var "value" := var "a" &~ var "b"; break_stmt ];
                    case (i32 4) [ var "value" := var "a" |~ var "b"; break_stmt ];
                    case (i32 5) [ var "value" := var "a" ^~ var "b"; break_stmt ];
                    case (i32 6) [
                      block [
                        let_u32 "cnt" (cast UInt32 (get_vreg_lane (var "src2") (i32 0) &~ u64 0xFFL));
                        var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" <<~ var "cnt");
                        break_stmt;
                      ]
                    ];
                    case (i32 7) [
                      block [
                        let_u32 "cnt" (cast UInt32 (get_vreg_lane (var "src2") (i32 0) &~ u64 0xFFL));
                        var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" >>~ var "cnt");
                        break_stmt;
                      ]
                    ];
                    case (i32 8) [
                      block [
                        let_u32 "cnt" (cast UInt32 (get_vreg_lane (var "src2") (i32 0) &~ u64 0xFFL));
                        var "value" := ternary (var "cnt" >=~ var "lane_bits")
                          (ternary (var "sa" <~ i32 0) (var "mask") (u64 0L))
                          ((cast UInt64 (var "sa" >>~ var "cnt")) &~ var "mask");
                        break_stmt;
                      ]
                    ];
                    case (i32 9) [ var "value" := ternary (var "a" ==~ var "b") (var "mask") (u64 0L); break_stmt ];
                    case (i32 10) [ var "value" := ternary (var "sa" >~ var "sb") (var "mask") (u64 0L); break_stmt ];
                    case (i32 11) [ var "value" := ternary (var "sa" <~ var "sb") (var "a") (var "b"); break_stmt ];
                    case (i32 12) [ var "value" := ternary (var "sa" >~ var "sb") (var "a") (var "b"); break_stmt ];
                    case (i32 13) [ var "value" := ternary (var "a" <~ var "b") (var "a") (var "b"); break_stmt ];
                    case (i32 14) [ var "value" := ternary (var "a" >~ var "b") (var "a") (var "b"); break_stmt ];
                    case (i32 15) [
                      var "value" := (cast UInt64 (ternary (var "sa" <~ i32 0) (neg (var "sa")) (var "sa"))) &~ var "mask";
                      break_stmt;
                    ];
                    case (i32 16) [ var "value" := (bit_not (var "a")) &~ var "b"; break_stmt ];
                    case (i32 17) [
                      block [
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ (i32 128 /~ var "lane_bits"));
                        let_size_t "half_idx" (var "block_lane" /~ i32 2);
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "half_idx" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 18) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "half_idx" ((var "num_lanes" /~ i32 2) +~ (var "block_lane" /~ i32 2));
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "half_idx" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 21) [
                      block [
                        let_u8 "ctrl" (cast UInt8 (var "b" &~ u64 0xFFL));
                        if_then_else ((var "ctrl" &~ i32 0x80) <>~ i32 0) [
                          var "value" := u64 0L;
                        ] [
                          let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ ((var "ctrl" &~ i32 0xF) *~ i32 8));
                          var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFL;
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 23) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "half_len" (var "num_lanes" /~ i32 2);
                        let_size_t "src_reg" (ternary (var "block_lane" <~ var "half_len") (var "src") (var "src2"));
                        let_size_t "sel_elem" (ternary (var "block_lane" <~ var "half_len") (var "block_lane" *~ i32 2) ((var "block_lane" -~ var "half_len") *~ i32 2));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 24) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "half_len" (var "num_lanes" /~ i32 2);
                        let_size_t "src_reg" (ternary (var "block_lane" <~ var "half_len") (var "src") (var "src2"));
                        let_size_t "sel_elem" (ternary (var "block_lane" <~ var "half_len") ((var "block_lane" *~ i32 2) +~ i32 1) (((var "block_lane" -~ var "half_len") *~ i32 2) +~ i32 1));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 25) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "k" (var "block_lane" /~ i32 2);
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "sel_elem" (var "k" *~ i32 2);
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 26) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "k" (var "block_lane" /~ i32 2);
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "sel_elem" ((var "k" *~ i32 2) +~ i32 1);
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 28) [
                      block [
                        let_u8 "idx" (cast UInt8 (var "b" &~ u64 0xFFL));
                        if_then_else (var "idx" <~ i32 16) [
                          let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "idx" *~ i32 8));
                          var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFL;
                        ] [
                          var "value" := u64 0L;
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 29) [
                      block [
                        let_u8 "idx" (cast UInt8 (var "b" &~ u64 0xFFL));
                        if_then_else (var "idx" <~ i32 16) [
                          let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "idx" *~ i32 8));
                          var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFL;
                        ] [
                          var "value" := (get_vreg_lane (var "dst") (var "chunk") >>~ var "shift") &~ u64 0xFFL;
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 30) [
                      block [
                        let_i64 "min_val" (ternary (var "lane_bits" ==~ i32 64) (cast Int64 (u64 0x8000000000000000L))
                          (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (u64 0x80000000L)))
                            (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (i32 0x8000)))
                              (cast Int64 (c_cast Int8 (i32 0x80))))));
                        if_then_else (var "sb" ==~ i32 0) [
                          var "value" := u64 (-1L);
                        ] [
                          if_then_else ((var "sb" ==~ i32 (-1)) &&~ (var "sa" ==~ var "min_val")) [
                            var "value" := cast UInt64 (var "sa");
                          ] [
                            var "value" := cast UInt64 (var "sa" /~ var "sb");
                          ];
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 31) [
                      var "value" := ternary (var "b" <>~ i32 0) (var "a" /~ var "b") (var "mask");
                      break_stmt;
                    ];
                    case (i32 32) [
                      block [
                        let_i64 "min_val" (ternary (var "lane_bits" ==~ i32 64) (cast Int64 (u64 0x8000000000000000L))
                          (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (u64 0x80000000L)))
                            (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (i32 0x8000)))
                              (cast Int64 (c_cast Int8 (i32 0x80))))));
                        if_then_else (var "sb" ==~ i32 0) [
                          var "value" := var "a";
                        ] [
                          if_then_else ((var "sb" ==~ i32 (-1)) &&~ (var "sa" ==~ var "min_val")) [
                            var "value" := u64 0L;
                          ] [
                            var "value" := cast UInt64 (var "sa" %~ var "sb");
                          ];
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 33) [
                      var "value" := ternary (var "b" <>~ i32 0) (var "a" %~ var "b") (var "a");
                      break_stmt;
                    ];
                    case (i32 34) [ var "value" := ternary (var "a" <>~ var "b") (var "mask") (u64 0L); break_stmt ];
                    case (i32 35) [ var "value" := ternary (var "sa" <=~ var "sb") (var "mask") (u64 0L); break_stmt ];
                    case (i32 36) [ var "value" := ternary (var "a" <~ var "b") (var "mask") (u64 0L); break_stmt ];
                    case (i32 37) [ var "value" := ternary (var "a" <=~ var "b") (var "mask") (u64 0L); break_stmt ];
                  ] (Some [ var "value" := var "a" ^~ var "b"; break_stmt ])
                ]
              ]
            ]
          ]
        ]
      ];
      let_u64 "old_value" (get_vreg_lane (var "dst") (var "chunk"));
      let_u64 "packed_mask" (var "mask" <<~ var "shift");
      set_vreg_lane (var "dst") (var "chunk")
        ((var "old_value" &~ bit_not (var "packed_mask")) |~ ((var "value" &~ var "mask") <<~ var "shift"));
      (var "bit" += var "lane_bits");
    ];
  ] in
  emit_handler_ast b "H_VEC_BINOP" (vec_binop_stmts @ [ inc_instrs; fetch_next ]);

  let vec_imm_stmts = [
    let_u64 "imm_val" (var "imm" &~ u64 0xFFL);
    let_u32 "bits" (cast UInt32 ((var "imm" >>~ i32 8) &~ u64 0x3FFL));
    decl_var UInt32 "lane_bits" ~init:(cast UInt32 ((var "imm" >>~ i32 18) &~ u64 0xFFL));
    if_then (var "lane_bits" ==~ i32 0) [ var "lane_bits" := i32 64 ];
    let_u32 "vop" (cast UInt32 ((var "imm" >>~ i32 26) &~ u64 0x1FL));
    let_u64 "mask" (ternary (var "lane_bits" ==~ i32 8) (u64 0xFFL)
      (ternary (var "lane_bits" ==~ i32 16) (u64 0xFFFFL)
        (ternary (var "lane_bits" ==~ i32 32) (u64 0xFFFFFFFFL) (u64 (-1L)))));
    decl_var SizeT "bit" ~init:(i32 0);
    while_loop (var "bit" <~ var "bits") [
      let_size_t "chunk" (var "bit" /~ i32 64);
      decl_var UInt32 "shift" ~init:(cast UInt32 (var "bit" %~ i32 64));
      let_u64 "a" ((get_vreg_lane (var "src") (var "chunk") >>~ var "shift") &~ var "mask");
      let_i64 "sa" (ternary (var "lane_bits" ==~ i32 8) (cast Int64 (c_cast Int8 (var "a")))
        (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (var "a")))
          (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (var "a"))) (cast Int64 (var "a")))));
      decl_var UInt64 "value" ~init:(u64 0L);
      switch_annotated (var "vop") [
        case (i32 6) [
          block [
            let_u32 "cnt" (cast UInt32 (var "imm_val"));
            var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" <<~ var "cnt");
            break_stmt;
          ]
        ];
        case (i32 7) [
          block [
            let_u32 "cnt" (cast UInt32 (var "imm_val"));
            var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" >>~ var "cnt");
            break_stmt;
          ]
        ];
        case (i32 8) [
          block [
            let_u32 "cnt" (cast UInt32 (var "imm_val"));
            var "value" := ternary (var "cnt" >=~ var "lane_bits")
              (ternary (var "sa" <~ i32 0) (var "mask") (u64 0L))
              ((cast UInt64 (var "sa" >>~ var "cnt")) &~ var "mask");
            break_stmt;
          ]
        ];
        case (i32 21) [
          block [
            let_size_t "lane_in_128" ((var "bit" /~ i32 32) %~ i32 4);
            let_size_t "sel" ((var "imm_val" >>~ (var "lane_in_128" *~ i32 2)) &~ u64 3L);
            let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel" *~ i32 32));
            var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFFFFFFFL;
            break_stmt;
          ]
        ];
        case (i32 22) [
          block [
            let_size_t "lane_idx" (var "bit" /~ var "lane_bits");
            let_size_t "sel" ((var "imm_val" >>~ (var "lane_idx" %~ i32 8)) &~ u64 1L);
            var "value" := ternary (var "sel" ==~ i32 0) (var "a")
              ((get_vreg_lane (var "dst") (var "chunk") >>~ var "shift") &~ var "mask");
            break_stmt;
          ]
        ];
      ] (Some [ var "value" := var "a"; break_stmt ]);
      let_u64 "old_value" (get_vreg_lane (var "dst") (var "chunk"));
      let_u64 "packed_mask" (var "mask" <<~ var "shift");
      set_vreg_lane (var "dst") (var "chunk")
        ((var "old_value" &~ bit_not (var "packed_mask")) |~ ((var "value" &~ var "mask") <<~ var "shift"));
      (var "bit" += var "lane_bits");
    ];
  ] in
  emit_handler_ast b "H_VEC_IMM" (vec_imm_stmts @ [ inc_instrs; fetch_next ]);

  emit_handler_ast b "H_VEC_CLEAR_UPPER" [
    set_vreg_lane (var "dst") (i32 2) (u64 0L);
    set_vreg_lane (var "dst") (i32 3) (u64 0L);
    inc_instrs; fetch_next;
  ];

  emit_handler_ast b "H_VEC_ZERO_UPPER" [
    for_range "i" (i32 0) (i32 16) [
      set_vreg_lane (var "i") (i32 2) (u64 0L);
      set_vreg_lane (var "i") (i32 3) (u64 0L);
    ];
    inc_instrs; fetch_next;
  ];

  let pmovmskb_stmts = [
    let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
    let_u32 "num_bytes" (var "bits" /~ i32 8);
    decl_var UInt64 "mask" ~init:(u64 0L);
    for_range "b_idx" (i32 0) (var "num_bytes") [
      let_u64 "byte_val" ((get_vreg_lane (var "src") (var "b_idx" /~ i32 8) >>~ ((var "b_idx" %~ i32 8) *~ i32 8)) &~ u64 0xFFL);
      if_then ((var "byte_val" &~ u64 0x80L) <>~ u64 0L) [
        (var "mask" |= (u64 1L <<~ var "b_idx"));
      ];
    ];
    set_reg (var "dst") (var "mask");
  ] in
  emit_handler_ast b "H_PMOVMSKB" (pmovmskb_stmts @ [ inc_instrs; fetch_next ]);

  let vec_load_stmts = [
    let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x3FFL));
    let_u64 "address" (reg_src +~ cast UInt64 (var "imm"));
    for_range "i" (i32 0) ((var "bits" +~ i32 63) /~ i32 64) [
      decl_var UInt64 "value" ~init:(u64 0L);
      expr_stmt (call "std::memcpy" [
        addr_of (var "value");
        reinterpret_cast (ConstPtr Void) (var "address" +~ (var "i" *~ i32 8));
        sizeof_expr (var "value")
      ]);
      set_vreg_lane (var "dst") (var "i") (var "value");
    ];
  ] in
  emit_handler_ast b "H_VEC_LOAD" (vec_load_stmts @ [ inc_instrs; fetch_next ]);

  let vec_store_stmts = [
    let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x3FFL));
    let_u64 "address" (reg_dst +~ cast UInt64 (var "imm"));
    for_range "i" (i32 0) ((var "bits" +~ i32 63) /~ i32 64) [
      expr_stmt (call "std::memcpy" [
        reinterpret_cast (Ptr Void) (var "address" +~ (var "i" *~ i32 8));
        addr_of (idx (idx (var "ctx.vregs") (var "src" &~ i32 31)) (var "i" &~ i32 7));
        sizeof_ty UInt64
      ]);
    ];
  ] in
  emit_handler_ast b "H_VEC_STORE" (vec_store_stmts @ [ inc_instrs; fetch_next ]);

  let vec_splat_stmts = [
    let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0xFFFFL));
    let_u32 "lane_bits" (cast UInt32 ((var "imm" >>~ i32 16) &~ u64 0xFFFFL));
    let_u64 "val" reg_src;
    let_u64 "mask" (ternary (var "lane_bits" >=~ i32 64) (u64 (-1L)) ((u64 1L <<~ var "lane_bits") -~ u64 1L));
    let_u64 "val_masked" (var "val" &~ var "mask");
    let_u32 "num_lanes" (ternary (var "lane_bits" >~ i32 0) (var "bits" /~ var "lane_bits") (i32 0));
    for_range "l" (i32 0) (var "num_lanes") [
      let_u32 "pos" (var "l" *~ var "lane_bits");
      let_u32 "chunk" (var "pos" /~ i32 64);
      let_u32 "shift" (var "pos" %~ i32 64);
      let_u64 "packed_mask" (ternary (var "lane_bits" >=~ i32 64) (u64 (-1L)) (var "mask" <<~ var "shift"));
      decl_var UInt64 "cur" ~init:(get_vreg_lane (var "dst") (var "chunk"));
      var "cur" := (var "cur" &~ bit_not (var "packed_mask")) |~ (var "val_masked" <<~ var "shift");
      set_vreg_lane (var "dst") (var "chunk") (var "cur");
    ];
  ] in
  emit_handler_ast b "H_VEC_SPLAT" (vec_splat_stmts @ [ inc_instrs; fetch_next ]);

  let vec_ext_stmts = [
    let_u32 "src2" (cast UInt32 (var "imm" &~ u64 31L));
    let_u32 "shift_bytes" (cast UInt32 ((var "imm" >>~ i32 5) &~ u64 15L));
    decl_var UInt32 "bits" ~init:(cast UInt32 ((var "imm" >>~ i32 9) &~ u64 0x3FFL));
    if_then (var "bits" ==~ i32 0) [ var "bits" := i32 128 ];
    for_range "byte_idx" (i32 0) (var "bits" /~ i32 8) [
      let_size_t "total_idx" ((var "byte_idx" %~ i32 16) +~ var "shift_bytes");
      decl_var UInt64 "val" ~init:(u64 0L);
      if_then_else (var "total_idx" <~ i32 16) [
        let_size_t "bit_pos" (((var "byte_idx" /~ i32 16) *~ i32 128) +~ (var "total_idx" *~ i32 8));
        var "val" := (get_vreg_lane (var "src") (var "bit_pos" /~ i32 64) >>~ (var "bit_pos" %~ i32 64)) &~ u64 0xFFL;
      ] [
        let_size_t "m_idx" (var "total_idx" -~ i32 16);
        let_size_t "bit_pos" (((var "byte_idx" /~ i32 16) *~ i32 128) +~ (var "m_idx" *~ i32 8));
        var "val" := (get_vreg_lane (var "src2") (var "bit_pos" /~ i32 64) >>~ (var "bit_pos" %~ i32 64)) &~ u64 0xFFL;
      ];
      let_size_t "chunk" ((var "byte_idx" *~ i32 8) /~ i32 64);
      decl_var UInt32 "shift" ~init:(cast UInt32 ((var "byte_idx" *~ i32 8) %~ i32 64));
      let_u64 "old_v" (get_vreg_lane (var "dst") (var "chunk"));
      let_u64 "clr" (var "old_v" &~ bit_not (u64 0xFFL <<~ var "shift"));
      set_vreg_lane (var "dst") (var "chunk") (var "clr" |~ (var "val" <<~ var "shift"));
    ];
  ] in
  emit_handler_ast b "H_VEC_EXT" (vec_ext_stmts @ [ inc_instrs; fetch_next ])

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
