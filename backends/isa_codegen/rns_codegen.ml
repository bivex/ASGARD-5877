(* RNS-4 / Garner CRT — C++ header codegen (Input: Vm_ir.Rns spec constants → Output: C++20 header text). *)
(* Split out of domain/ir/rns.ml: emission never belonged to the pure IR layer. *)
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer
open Vm_ir.Rns

let emit_cpp_rns_ast () : top_decl list =
  let constants = [
    global_var ~is_static:true ~is_constexpr:true UInt64 "M1" ~init:(u64 m1);
    global_var ~is_static:true ~is_constexpr:true UInt64 "M2" ~init:(u64 m2);
    global_var ~is_static:true ~is_constexpr:true UInt64 "M3" ~init:(u64 m3);
    global_var ~is_static:true ~is_constexpr:true UInt64 "M4" ~init:(u64 m4);
    global_var ~is_static:true ~is_constexpr:true UInt64 "INV_M1_M2" ~init:(u64 inv_m1_mod_m2);
    global_var ~is_static:true ~is_constexpr:true UInt64 "INV_M1_M3" ~init:(u64 inv_m1_mod_m3);
    global_var ~is_static:true ~is_constexpr:true UInt64 "INV_M1_M4" ~init:(u64 inv_m1_mod_m4);
    global_var ~is_static:true ~is_constexpr:true UInt64 "INV_M2_M3" ~init:(u64 inv_m2_mod_m3);
    global_var ~is_static:true ~is_constexpr:true UInt64 "INV_M2_M4" ~init:(u64 inv_m2_mod_m4);
    global_var ~is_static:true ~is_constexpr:true UInt64 "INV_M3_M4" ~init:(u64 inv_m3_mod_m4);
  ] in

  let rns_val_struct =
    struct_decl "RNSVal" [
      (UInt64, "r1");
      (UInt64, "r2");
      (UInt64, "r3");
      (UInt64, "r4");
    ]
  in

  let encode_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      (StructType "RNSVal")
      "encode"
      [(UInt64, "x")]
      [
        ret (init_list [
          var "x" %~ var "M1";
          var "x" %~ var "M2";
          var "x" %~ var "M3";
          var "x" %~ var "M4";
        ]);
      ]
  in

  let add_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      (StructType "RNSVal")
      "add"
      [(StructType "RNSVal", "a"); (StructType "RNSVal", "b")]
      [
        ret (init_list [
          ((var "a" $. "r1") +~ (var "b" $. "r1")) %~ var "M1";
          ((var "a" $. "r2") +~ (var "b" $. "r2")) %~ var "M2";
          ((var "a" $. "r3") +~ (var "b" $. "r3")) %~ var "M3";
          ((var "a" $. "r4") +~ (var "b" $. "r4")) %~ var "M4";
        ]);
      ]
  in

  let sub_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      (StructType "RNSVal")
      "sub"
      [(StructType "RNSVal", "a"); (StructType "RNSVal", "b")]
      [
        ret (init_list [
          (((var "a" $. "r1") +~ var "M1") -~ ((var "b" $. "r1") %~ var "M1")) %~ var "M1";
          (((var "a" $. "r2") +~ var "M2") -~ ((var "b" $. "r2") %~ var "M2")) %~ var "M2";
          (((var "a" $. "r3") +~ var "M3") -~ ((var "b" $. "r3") %~ var "M3")) %~ var "M3";
          (((var "a" $. "r4") +~ var "M4") -~ ((var "b" $. "r4") %~ var "M4")) %~ var "M4";
        ]);
      ]
  in

  let mul_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      (StructType "RNSVal")
      "mul"
      [(StructType "RNSVal", "a"); (StructType "RNSVal", "b")]
      [
        ret (init_list [
          ((var "a" $. "r1") *~ ((var "b" $. "r1") %~ var "M1")) %~ var "M1";
          ((var "a" $. "r2") *~ ((var "b" $. "r2") %~ var "M2")) %~ var "M2";
          ((var "a" $. "r3") *~ ((var "b" $. "r3") %~ var "M3")) %~ var "M3";
          ((var "a" $. "r4") *~ ((var "b" $. "r4") %~ var "M4")) %~ var "M4";
        ]);
      ]
  in

  let decode_fn =
    func_decl
      ~attrs:[StaticFn; InlineFn; AlwaysInline; NoExcept]
      UInt64
      "decode"
      [(StructType "RNSVal", "r")]
      [
        let_u64 "v1" (var "r" $. "r1");
        let_u64 "diff2" ((((var "r" $. "r2") +~ var "M2") -~ ((var "v1") %~ var "M2")) %~ var "M2");
        let_u64 "v2" ((var "diff2" *~ var "INV_M1_M2") %~ var "M2");

        let_u64 "diff1_3" ((((var "r" $. "r3") +~ var "M3") -~ ((var "v1") %~ var "M3")) %~ var "M3");
        let_u64 "term1_3" ((var "diff1_3" *~ var "INV_M1_M3") %~ var "M3");
        let_u64 "diff2_3" ((((var "term1_3") +~ var "M3") -~ ((var "v2") %~ var "M3")) %~ var "M3");
        let_u64 "v3" ((var "diff2_3" *~ var "INV_M2_M3") %~ var "M3");

        let_u64 "diff1_4" ((((var "r" $. "r4") +~ var "M4") -~ ((var "v1") %~ var "M4")) %~ var "M4");
        let_u64 "term1_4" ((var "diff1_4" *~ var "INV_M1_M4") %~ var "M4");
        let_u64 "diff2_4" ((((var "term1_4") +~ var "M4") -~ ((var "v2") %~ var "M4")) %~ var "M4");
        let_u64 "term2_4" ((var "diff2_4" *~ var "INV_M2_M4") %~ var "M4");
        let_u64 "diff3_4" ((((var "term2_4") +~ var "M4") -~ ((var "v3") %~ var "M4")) %~ var "M4");
        let_u64 "v4" ((var "diff3_4" *~ var "INV_M3_M4") %~ var "M4");

        let_u64 "term_v2" (var "v2" *~ var "M1");
        let_u64 "term_v3" (var "v3" *~ (var "M1" *~ var "M2"));
        let_u64 "term_v4" (var "v4" *~ ((var "M1" *~ var "M2") *~ var "M3"));

        ret (var "v1" +~ var "term_v2" +~ var "term_v3" +~ var "term_v4");
      ]
  in

  [
    comment_top "=========================================================================";
    comment_top "ASGARD-5877: RESIDUE NUMBER SYSTEM (RNS-4) & GARNER CRT ARITHMETIC";
    comment_top "Non-Linear Diophantine Residue Channels for Anti-SMT Hardening";
    comment_top "=========================================================================";
    IncludeSys "stdint.h";
    namespace_def "asgard_rns" (
      constants @ [
        rns_val_struct;
        encode_fn;
        add_fn;
        sub_fn;
        mul_fn;
        decode_fn;
      ]
    );
  ]

let emit_cpp_rns_header () =
  "#pragma once\n" ^ render_top_decls (emit_cpp_rns_ast ())
