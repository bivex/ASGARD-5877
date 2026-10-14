(* Pairwise coprime primes such that M = m1 * m2 * m3 * m4 > 2^64 *)
let m1 = 65537L (* 2^16 + 1 *)
let m2 = 65521L (* Largest prime < 2^16 *)
let m3 = 65519L (* Second largest prime < 2^16 *)
let m4 = 65497L (* Third largest prime < 2^16 *)

type rns_val = {
  r1 : int64;
  r2 : int64;
  r3 : int64;
  r4 : int64;
}

let mod_pos (a : int64) (m : int64) : int64 =
  let rem = Int64.rem a m in
  if rem < 0L then Int64.add rem m else rem

(* Extended Euclidean Algorithm for Modular Inverse *)
let ext_gcd a b =
  let rec loop r0 r1 s0 s1 =
    if r1 = 0L then (r0, s0)
    else
      let q = Int64.div r0 r1 in
      let r2 = Int64.sub r0 (Int64.mul q r1) in
      let s2 = Int64.sub s0 (Int64.mul q s1) in
      loop r1 r2 s1 s2
  in
  loop a b 1L 0L

let inv_mod a m =
  let (_, s) = ext_gcd a m in
  mod_pos s m

(* Compute 2^63 mod m accurately *)
let two_pow_63_mod m =
  let rec pow2 exp =
    if exp = 0 then 1L
    else
      let half = pow2 (exp / 2) in
      let half_sq = mod_pos (Int64.mul half half) m in
      if exp mod 2 = 0 then half_sq
      else mod_pos (Int64.mul half_sq 2L) m
  in
  pow2 63

let two_63_m1 = two_pow_63_mod m1
let two_63_m2 = two_pow_63_mod m2
let two_63_m3 = two_pow_63_mod m3
let two_63_m4 = two_pow_63_mod m4

(** Computes unsigned 64-bit integer modulo m *)
let u64_mod (x : int64) (m : int64) (two_63_m : int64) : int64 =
  let low_63 = Int64.logand x 0x7FFFFFFFFFFFFFFFL in
  let rem_low = Int64.rem low_63 m in
  if x >= 0L then rem_low
  else mod_pos (Int64.add rem_low two_63_m) m

(* Precomputed modular inverses for Garner's Mixed Radix Algorithm *)
let inv_m1_mod_m2 = inv_mod m1 m2
let inv_m1_mod_m3 = inv_mod m1 m3
let inv_m1_mod_m4 = inv_mod m1 m4

let inv_m2_mod_m3 = inv_mod m2 m3
let inv_m2_mod_m4 = inv_mod m2 m4

let inv_m3_mod_m4 = inv_mod m3 m4

let encode (x : int64) : rns_val =
  {
    r1 = u64_mod x m1 two_63_m1;
    r2 = u64_mod x m2 two_63_m2;
    r3 = u64_mod x m3 two_63_m3;
    r4 = u64_mod x m4 two_63_m4;
  }

let add (a : rns_val) (b : rns_val) : rns_val =
  {
    r1 = mod_pos (Int64.add a.r1 b.r1) m1;
    r2 = mod_pos (Int64.add a.r2 b.r2) m2;
    r3 = mod_pos (Int64.add a.r3 b.r3) m3;
    r4 = mod_pos (Int64.add a.r4 b.r4) m4;
  }

let sub (a : rns_val) (b : rns_val) : rns_val =
  {
    r1 = mod_pos (Int64.sub a.r1 b.r1) m1;
    r2 = mod_pos (Int64.sub a.r2 b.r2) m2;
    r3 = mod_pos (Int64.sub a.r3 b.r3) m3;
    r4 = mod_pos (Int64.sub a.r4 b.r4) m4;
  }

let mul (a : rns_val) (b : rns_val) : rns_val =
  {
    r1 = mod_pos (Int64.mul a.r1 b.r1) m1;
    r2 = mod_pos (Int64.mul a.r2 b.r2) m2;
    r3 = mod_pos (Int64.mul a.r3 b.r3) m3;
    r4 = mod_pos (Int64.mul a.r4 b.r4) m4;
  }

(** Decodes an RNS 4-tuple back to 64-bit integer using Garner's Mixed-Radix Conversion *)
let decode (r : rns_val) : int64 =
  let v1 = r.r1 in
  
  let v2 =
    let diff = mod_pos (Int64.sub r.r2 v1) m2 in
    mod_pos (Int64.mul diff inv_m1_mod_m2) m2
  in
  
  let v3 =
    let diff1 = mod_pos (Int64.sub r.r3 v1) m3 in
    let term1 = mod_pos (Int64.mul diff1 inv_m1_mod_m3) m3 in
    let diff2 = mod_pos (Int64.sub term1 v2) m3 in
    mod_pos (Int64.mul diff2 inv_m2_mod_m3) m3
  in
  
  let v4 =
    let diff1 = mod_pos (Int64.sub r.r4 v1) m4 in
    let term1 = mod_pos (Int64.mul diff1 inv_m1_mod_m4) m4 in
    let diff2 = mod_pos (Int64.sub term1 v2) m4 in
    let term2 = mod_pos (Int64.mul diff2 inv_m2_mod_m4) m4 in
    let diff3 = mod_pos (Int64.sub term2 v3) m4 in
    mod_pos (Int64.mul diff3 inv_m3_mod_m4) m4
  in
  
  (* X = v1 + v2 * m1 + v3 * (m1 * m2) + v4 * (m1 * m2 * m3) mod 2^64 *)
  let term_v2 = Int64.mul v2 m1 in
  let term_v3 = Int64.mul v3 (Int64.mul m1 m2) in
  let term_v4 = Int64.mul v4 (Int64.mul (Int64.mul m1 m2) m3) in
  
  Int64.add (Int64.add v1 term_v2) (Int64.add term_v3 term_v4)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

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
