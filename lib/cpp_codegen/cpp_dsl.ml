(* lib/cpp_codegen/cpp_dsl.ml
   Комбинаторы для лаконичного построения C++20 AST в стиле функционального EDSL *)

open Cpp_ast

let u64 (v : int64) : expr = LitU64 v
let u32 (v : int32) : expr = LitU32 v
let i32 (v : int)   : expr = LitInt v
let bool_lit (b : bool) : expr = LitBool b
let var (s : string) : expr = Var s

let ( $. ) (e : expr) (field : string) : expr = Member (e, field)
let ( $-> ) (e : expr) (field : string) : expr = PtrMember (e, field)
let ( .%[] ) (arr : expr) (i : expr) : expr = Index (arr, i)
let idx (arr : expr) (i : expr) : expr = Index (arr, i)

let ( +~ ) a b = Binary (Add, a, b)
let ( -~ ) a b = Binary (Sub, a, b)
let ( *~ ) a b = Binary (Mul, a, b)
let ( /~ ) a b = Binary (Div, a, b)
let ( %~ ) a b = Binary (Rem, a, b)

let ( ^~ ) a b = Binary (BitXor, a, b)
let ( &~ ) a b = Binary (BitAnd, a, b)
let ( |~ ) a b = Binary (BitOr, a, b)
let ( <<~ ) a b = Binary (Shl, a, b)
let ( >>~ ) a b = Binary (Shr, a, b)

let ( ==~ ) a b = Binary (Eq, a, b)
let ( !=~ ) a b = Binary (Ne, a, b)
let ( <~ )  a b = Binary (Lt, a, b)
let ( <=~ ) a b = Binary (Le, a, b)
let ( >~ )  a b = Binary (Gt, a, b)
let ( >=~ ) a b = Binary (Ge, a, b)

let ( &&~ ) a b = Binary (LogAnd, a, b)
let ( ||~ ) a b = Binary (LogOr, a, b)

let bit_not a = Unary (BitNot, a)
let log_not a = Unary (LogNot, a)
let deref a = Unary (Deref, a)
let addr_of a = Unary (AddrOf, a)
let neg_u64 a = Binary (Sub, LitU64 0L, a)
let cast ty e = Cast (ty, e)
let bit_cast ty e = BitCast (ty, e)
let call fn args = Call (fn, args)

let ternary c t f = Ternary (c, t, f)

let let_u64 name init_e : stmt =
  DeclVar { is_const = false; is_constexpr = false; is_volatile = false;
            ty = UInt64; name; init = Some init_e }

let const_u64 name init_e : stmt =
  DeclVar { is_const = true; is_constexpr = false; is_volatile = false;
            ty = UInt64; name; init = Some init_e }

let constexpr_u64 name (v : int64) : stmt =
  DeclVar { is_const = false; is_constexpr = true; is_volatile = false;
            ty = UInt64; name; init = Some (LitU64 v) }

let decl_var ?(is_const=false) ?(is_constexpr=false) ?(is_volatile=false) ?init ty name : stmt =
  DeclVar { is_const; is_constexpr; is_volatile; ty; name; init }

let ( := ) lhs rhs : stmt = Assign (AssignPlain, lhs, rhs)
let ( += ) lhs rhs : stmt = Assign (AssignAdd, lhs, rhs)
let ( -= ) lhs rhs : stmt = Assign (AssignSub, lhs, rhs)
let ( ^= ) lhs rhs : stmt = Assign (AssignXor, lhs, rhs)
let ( |= ) lhs rhs : stmt = Assign (AssignOr, lhs, rhs)
let ( &= ) lhs rhs : stmt = Assign (AssignAnd, lhs, rhs)
let ( /= ) lhs rhs : stmt = Assign (AssignDiv, lhs, rhs)

let ret (e : expr) : stmt = Return (Some e)
let ret_void : stmt = Return None
let expr_stmt (e : expr) : stmt = ExprStmt e
let if_then cond then_b : stmt = If (cond, then_b, [])
let if_then_else cond then_b else_b : stmt = If (cond, then_b, else_b)
let for_range var_name start_e limit_e body : stmt = ForRange { var_name; start_e; limit_e; body }
let switch cond cases default : stmt = Switch { cond; cases; default }
let fence_seq_cst : stmt = FenceSeqCst
let comment s : stmt = Comment s
