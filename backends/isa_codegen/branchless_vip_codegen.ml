(* Branchless VIP conditionals: C++ header codegen (Input: eval variant, Output: C++20 header text). *)
(* Split out of domain/ir/branchless_vip.ml: emission never belonged to the pure IR layer. *)
open Int64
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let build_branchless_vip_ast ?(default_variant = 1) () : top_decl list =
  (* Variant 0: Two's complement sign-bit: 1 - ((d | -d) >> 63) *)
  let is_zero_v0_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64_v0";
    params   = [(UInt64, "d")];
    body     = [
      ret (u64 1L -~ ((var "d" |~ (u64 0L -~ var "d")) >>~ u64 63L));
    ];
  } in

  (* Variant 1: Warren Subtraction Borrow from Zero: ((~d) & (d - 1)) >> 63 *)
  let is_zero_v1_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64_v1";
    params   = [(UInt64, "d")];
    body     = [
      ret (((bit_not (var "d")) &~ (var "d" -~ u64 1L)) >>~ u64 63L);
    ];
  } in

  (* Variant 2: Mixed Boolean-Arithmetic (MBA) Decomposition: 1 - (((d ^ -d) + (d & -d)) >> 63) *)
  let is_zero_v2_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64_v2";
    params   = [(UInt64, "d")];
    body     = [
      let_u64 "neg_d" (u64 0L -~ var "d");
      let_u64 "or_val" ((var "d" ^~ var "neg_d") +~ (var "d" &~ var "neg_d"));
      ret (u64 1L -~ (var "or_val" >>~ u64 63L));
    ];
  } in

  (* Variant 3: De Morgan Sign Bit Inversion: (~(d | -d) >> 63) & 1 *)
  let is_zero_v3_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64_v3";
    params   = [(UInt64, "d")];
    body     = [
      ret (((bit_not (var "d" |~ (u64 0L -~ var "d"))) >>~ u64 63L) &~ u64 1L);
    ];
  } in

  (* Variant 4: Boolean XOR Bit Flipping: ((d | -d) >> 63) ^ 1 *)
  let is_zero_v4_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64_v4";
    params   = [(UInt64, "d")];
    body     = [
      ret (((var "d" |~ (u64 0L -~ var "d")) >>~ u64 63L) ^~ u64 1L);
    ];
  } in

  (* Primary is_zero_u64 delegates to selected variant (default v1 to break classic signature) *)
  let default_fn_name = Printf.sprintf "is_zero_u64_v%d" (default_variant mod 5) in
  let is_zero_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64";
    params   = [(UInt64, "d")];
    body     = [
      ret (call default_fn_name [var "d"]);
    ];
  } in

  let is_ult_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_ult_u64";
    params   = [(UInt64, "x"); (UInt64, "y")];
    body     = [
      let_u64 "diff" (var "x" -~ var "y");
      let_u64 "borrow" (((bit_not (var "x")) &~ var "y") |~ (((bit_not (var "x")) |~ var "y") &~ var "diff"));
      ret (var "borrow" >>~ u64 63L);
    ];
  } in

  let is_slt_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_slt_u64";
    params   = [(UInt64, "x"); (UInt64, "y")];
    body     = [
      constexpr_u64 "SIGN_BIT" min_int;
      ret (call "is_ult_u64" [var "x" ^~ var "SIGN_BIT"; var "y" ^~ var "SIGN_BIT"]);
    ];
  } in

  let select_vip_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "select_vip";
    params   = [(UInt64, "cond_bit"); (UInt64, "target_vip"); (UInt64, "fallthrough_vip")];
    body     = [
      ret (var "fallthrough_vip" +~ (var "cond_bit" *~ (var "target_vip" -~ var "fallthrough_vip")));
    ];
  } in

  [
    IncludeSys "cstdint";
    Namespace ("asgard::branchless_vip", [
      is_zero_v0_fn;
      is_zero_v1_fn;
      is_zero_v2_fn;
      is_zero_v3_fn;
      is_zero_v4_fn;
      is_zero_fn;
      is_ult_fn;
      is_slt_fn;
      select_vip_fn;
    ]);
  ]

let emit_branchless_vip_cpp_header () : string =
  Cpp_codegen.Cpp_printer.render_header_unit (build_branchless_vip_ast ())

