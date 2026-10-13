open Int64

type branch_cond =
  | CondEq
  | CondNe
  | CondUlt
  | CondUge
  | CondSlt
  | CondSge

let eval_is_zero_branchless (d : int64) : int64 =
  (* В 2-дополнительном коде (d | -d) имеет старший бит 63 равным 0 ТОЛЬКО при d = 0L *)
  let non_zero_bit = shift_right_logical (logor d (neg d)) 63 in
  sub 1L non_zero_bit

let eval_ult_branchless (x : int64) (y : int64) : int64 =
  (* Беззнаковый заем (borrow / Carry Flag при x - y):
     Формула Уоррена (Hacker's Delight): borrow = (~x & y) | ((~x | y) & (x - y))
     Старший бит 63 равен 1 тогда и только тогда, когда x <u y *)
  let diff = sub x y in
  let not_x = lognot x in
  let borrow = logor (logand not_x y) (logand (logor not_x y) diff) in
  shift_right_logical borrow 63

let eval_slt_branchless (x : int64) (y : int64) : int64 =
  (* Знаковое сравнение x <s y сводится к беззнаковому переворотом знакового бита 2^63 *)
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
  (* Выбираем дельту ключа арифметическим мультиплексором без ветвлений *)
  let active_delta = add (mul b key_delta_taken) (mul not_b key_delta_fallthrough) in
  let next_key = mul (logxor base_key active_delta) 0x9E3779B97F4A7C15L in
  (next_vip, next_key)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let build_branchless_vip_ast () : top_decl list =
  let is_zero_fn = FuncDecl {
    attrs    = [AlwaysInline; ConstexprFn; NoExcept];
    ret_type = UInt64;
    name     = "is_zero_u64";
    params   = [(UInt64, "d")];
    body     = [
      ret (u64 1L -~ ((var "d" |~ (u64 0L -~ var "d")) >>~ u64 63L));
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
      is_zero_fn;
      is_ult_fn;
      is_slt_fn;
      select_vip_fn;
    ]);
  ]

let emit_branchless_vip_cpp_header () : string =
  Cpp_codegen.Cpp_printer.render_header_unit (build_branchless_vip_ast ())

