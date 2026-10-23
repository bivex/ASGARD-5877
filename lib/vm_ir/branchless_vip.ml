open Int64

type branch_cond =
  | CondEq
  | CondNe
  | CondUlt
  | CondUge
  | CondSlt
  | CondSge

let eval_is_zero_branchless ?(variant = 0) (d : int64) : int64 =
  match variant mod 5 with
  | 0 ->
      (* Formula 0: Two's complement sign-bit: 1 - ((d | -d) >> 63) *)
      let non_zero_bit = shift_right_logical (logor d (neg d)) 63 in
      sub 1L non_zero_bit
  | 1 ->
      (* Formula 1: Warren borrow from zero: ((~d) & (d - 1)) >> 63 *)
      let not_d = lognot d in
      let d_minus_1 = sub d 1L in
      shift_right_logical (logand not_d d_minus_1) 63
  | 2 ->
      (* Formula 2: MBA OR decomposition: 1 - (((d ^ -d) + (d & -d)) >> 63) *)
      let neg_d = neg d in
      let val_or = add (logxor d neg_d) (logand d neg_d) in
      sub 1L (shift_right_logical val_or 63)
  | 3 ->
      (* Formula 3: De Morgan sign extraction: (~(d | -d) >> 63) & 1 *)
      let not_or = lognot (logor d (neg d)) in
      logand (shift_right_logical not_or 63) 1L
  | _ ->
      (* Formula 4: Boolean XOR bit flipping: ((d | -d) >> 63) ^ 1 *)
      let non_zero_bit = shift_right_logical (logor d (neg d)) 63 in
      logxor non_zero_bit 1L
let eval_ult_branchless (x : int64) (y : int64) : int64 =
  (* Unsigned borrow (borrow / Carry Flag for x - y):
     Warren's formula (Hacker's Delight): borrow = (~x & y) | ((~x | y) & (x - y))
     Bit 63 equals 1 if and only if x <u y *)
  let diff = sub x y in
  let not_x = lognot x in
  let borrow = logor (logand not_x y) (logand (logor not_x y) diff) in
  shift_right_logical borrow 63

let eval_slt_branchless (x : int64) (y : int64) : int64 =
  (* Signed comparison x <s y reduces to an unsigned one by flipping the sign bit 2^63 *)
  let sign_flip = 0x8000000000000000L in
  eval_ult_branchless (logxor x sign_flip) (logxor y sign_flip)

let eval_cond_branchless (cond : branch_cond) (x : int64) (y : int64) : int64 =
  match cond with
  | CondEq  -> eval_is_zero_branchless (sub x y)
  | CondNe  -> logxor 1L (eval_is_zero_branchless (sub x y))
  | CondUlt -> eval_ult_branchless x y
  | CondUge -> logxor 1L (eval_ult_branchless x y)
  | CondSlt -> eval_slt_branchless x y
  | CondSge -> logxor 1L (eval_slt_branchless x y)

let compute_next_vip_branchless
    ~(cond : branch_cond) ~(lhs : int64) ~(rhs : int64)
    ~(target_vip : int64) ~(fallthrough_vip : int64) : int64 =
  let b = eval_cond_branchless cond lhs rhs in
  let delta = sub target_vip fallthrough_vip in
  add fallthrough_vip (mul b delta)

let compute_vip_and_key_branchless
    ~(cond : branch_cond) ~(lhs : int64) ~(rhs : int64)
    ~(target_vip : int64) ~(fallthrough_vip : int64)
    ~(base_key : int64) ~(key_delta_taken : int64) ~(key_delta_fallthrough : int64)
    : int64 * int64 =
  let b = eval_cond_branchless cond lhs rhs in
  let not_b = sub 1L b in
  let next_vip = add fallthrough_vip (mul b (sub target_vip fallthrough_vip)) in
  (* We select the key delta with a branchless arithmetic multiplexer *)
  let active_delta = add (mul b key_delta_taken) (mul not_b key_delta_fallthrough) in
  let next_key = mul (logxor base_key active_delta) 0x9E3779B97F4A7C15L in
  (next_vip, next_key)

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

