(* lib/cpp_codegen/cpp_dsl.ml
   Combinators for concise construction of a C++20 AST in the style of a functional EDSL *)

open Cpp_ast

let u64 (v : int64) : expr = LitU64 v
let u32 (v : int32) : expr = LitU32 v
let u8 (v : int)     : expr = LitU8 v
let i32 (v : int)   : expr = LitInt v
let bool_lit (b : bool) : expr = LitBool b
let var (s : string) : expr = Var s
let init_list (es : expr list) : expr = InitList es
let label_addr (s : string) : expr = LabelAddr s
let desig_idx (i : expr) (v : expr) : expr = DesignatedIndex (i, v)
let desig_range (s : expr) (e : expr) (v : expr) : expr = DesignatedRange (s, e, v)

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
let ( <>~ ) a b = Binary (Ne, a, b)
let ( !=~ ) a b = Binary (Ne, a, b)
let ne a b = Binary (Ne, a, b)
let eq a b = Binary (Eq, a, b)
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
let neg a = Unary (Neg, a)
let neg_u64 a = Binary (Sub, LitU64 0L, a)
let cast ty e = Cast (ty, e)
let c_cast ty e = CCast (ty, e)
let ccast ty e = CCast (ty, e)
let bit_cast ty e = BitCast (ty, e)
let reinterpret_cast ty e = ReinterpretCast (ty, e)
let sizeof_expr e = Call ("sizeof", [e])
let sizeof_ty (ty : ctype) : expr = SizeOfType ty
let nullptr : expr = LitNull
let call fn args = Call (fn, args)

let ternary c t f = Ternary (c, t, f)

let decl_var ?align_as ?(is_static=false) ?(is_thread_local=false) ?(is_const=false) ?(is_constexpr=false) ?(is_volatile=false) ?init ty name : stmt =
  DeclVar { align_as; is_static; is_thread_local; is_const; is_constexpr; is_volatile; ty; name; init }

let let_u64 name init_e : stmt = decl_var UInt64 name ~init:init_e
let const_u64 name init_e : stmt = decl_var ~is_const:true UInt64 name ~init:init_e
let constexpr_u64 name (v : int64) : stmt = decl_var ~is_constexpr:true UInt64 name ~init:(LitU64 v)
let let_u32 name init_e : stmt = decl_var UInt32 name ~init:init_e
let const_u32 name init_e : stmt = decl_var ~is_const:true UInt32 name ~init:init_e

let i64 (v : int64) : expr = LitI64 v
let str_lit (s : string) : expr = LitStr s

let ( := ) lhs rhs : stmt = Assign (AssignPlain, lhs, rhs)
let ( += ) lhs rhs : stmt = Assign (AssignAdd, lhs, rhs)
let ( -= ) lhs rhs : stmt = Assign (AssignSub, lhs, rhs)
let ( *= ) lhs rhs : stmt = Assign (AssignMul, lhs, rhs)
let ( ^= ) lhs rhs : stmt = Assign (AssignXor, lhs, rhs)
let ( |= ) lhs rhs : stmt = Assign (AssignOr, lhs, rhs)
let ( &= ) lhs rhs : stmt = Assign (AssignAnd, lhs, rhs)
let ( /= ) lhs rhs : stmt = Assign (AssignDiv, lhs, rhs)

let block (stmts : stmt list) : stmt = Block stmts
let ret (e : expr) : stmt = Return (Some e)
let ret_void : stmt = Return None
let expr_stmt (e : expr) : stmt = ExprStmt e
let if_then cond then_b : stmt = If (cond, then_b, [])
let if_then_else cond then_b else_b : stmt = If (cond, then_b, else_b)
let for_range var_name start_e limit_e body : stmt = ForRange { var_name; start_e; limit_e; body }
let while_loop cond body : stmt = While (cond, body)
let do_while cond body : stmt = DoWhile (cond, body)
let switch cond (cases : (expr * stmt list) list) default : stmt =
  Switch { cond; cases = List.map (fun (e, b) -> (e, None, b)) cases; default }
let switch_annotated cond (cases : (expr * string option * stmt list) list) default : stmt =
  Switch { cond; cases; default }
let case ?comment ce body : expr * string option * stmt list = (ce, comment, body)
let break_stmt : stmt = Break
let continue_stmt : stmt = Continue
let goto (s : string) : stmt = Goto s
let computed_goto (e : expr) : stmt = ComputedGoto e
let label (s : string) : stmt = Label s
let preproc_if_stmt ?(elifs=[]) ?(else_stmts=[]) cond then_b : stmt =
  let rec build = function
    | [] -> else_stmts
    | (c, b) :: rest -> [PreprocIfStmt (c, b, build rest)]
  in
  PreprocIfStmt (cond, then_b, build elifs)
let preproc_ifdef_stmt ?(else_stmts=[]) macro then_b : stmt = PreprocIfdefStmt (macro, then_b, else_stmts)
let preproc_ifndef_stmt ?(else_stmts=[]) macro then_b : stmt = PreprocIfndefStmt (macro, then_b, else_stmts)
let macro_def_stmt ?value name : stmt = MacroDefStmt (name, value)
let macro_def_raw_stmt ?value name : stmt = MacroDefRawStmt (name, value)
let macro_undef_stmt (s : string) : stmt = MacroUndefStmt s
let raw (s : string) : stmt = Raw s
let fence_seq_cst : stmt = FenceSeqCst
let comment s : stmt = Comment s

let member_field ?(is_volatile=false) ?init ty name : struct_member = MemberField { is_volatile; ty; name; init }
let member_method ?(attrs=[]) ?(is_static=false) ?(is_const=false) ?(template_params=[]) ret_type name params body : struct_member =
  MemberMethod { attrs; is_static; is_const; template_params; ret_type; name; params; body }
let member_method_decl ?(attrs=[]) ?(is_static=false) ?(is_const=false) ?(template_params=[]) ret_type name params : struct_member =
  MemberMethodDecl { attrs; is_static; is_const; template_params; ret_type; name; params }
let member_constructor ?(attrs=[]) ?(is_explicit=false) ?(params=[]) ?(init_list=[]) name body : struct_member =
  MemberConstructor { attrs; is_explicit; name; params; init_list; body }
let member_destructor ?(attrs=[]) name body : struct_member =
  MemberDestructor { attrs; name; body }
let member_static_constexpr ty name init : struct_member = MemberStaticConstexpr { ty; name; init }
let member_public : struct_member = MemberVisibility Public
let member_private : struct_member = MemberVisibility Private
let member_protected : struct_member = MemberVisibility Protected
let member_static_assert e msg : struct_member = MemberStaticAssert (e, msg)
let member_raw s : struct_member = MemberRaw s
let member_comment s : struct_member = MemberComment s
let struct_decl ?align_as name fields : top_decl = StructDecl { align_as; name; fields }
let struct_def ?align_as name members : top_decl = StructDef { align_as; name; members }
let class_def ?align_as name members : top_decl = ClassDef { align_as; name; members }
let template_struct_def ?align_as ~template_params name members : top_decl =
  TemplateStructDef { template_params; def = { align_as; name; members } }
let template_class_def ?align_as ~template_params name members : top_decl =
  TemplateClassDef { template_params; def = { align_as; name; members } }
let union_decl ?align_as name fields : top_decl = UnionDecl { align_as; name; fields }
let union_def ?align_as name members : top_decl = UnionDef { align_as; name; members }
let enum_decl ?underlying_ty name items : top_decl = EnumDecl { name; underlying_ty; items }
let func_decl ?(attrs=[]) ret_type name params body : top_decl = FuncDecl { attrs; ret_type; name; params; body }
let func_proto ?(attrs=[]) ret_type name params : top_decl = FuncProto { attrs; ret_type; name; params; body = [] }
let typedef ty name : top_decl = Typedef (ty, name)
let pragma s : top_decl = Pragma s
let macro_def ?value name : top_decl = MacroDef (name, value)
let macro_def_raw ?value name : top_decl = MacroDefRaw (name, value)
let macro_undef name : top_decl = MacroUndef name
let preproc_if ?(elifs=[]) ?(else_decls=[]) cond then_decls : top_decl =
  let rec build = function
    | [] -> else_decls
    | (c, d) :: rest -> [PreprocIf (c, d, build rest)]
  in
  PreprocIf (cond, then_decls, build elifs)
let preproc_ifdef ?(else_decls=[]) macro then_decls : top_decl = PreprocIfdef (macro, then_decls, else_decls)
let preproc_ifndef ?(else_decls=[]) macro then_decls : top_decl = PreprocIfndef (macro, then_decls, else_decls)
let include_sys s : top_decl = IncludeSys s
let include_local s : top_decl = IncludeLocal s
let global_var ?align_as ?(is_extern_c=false) ?(is_weak=false) ?(is_static=false) ?(is_thread_local=false) ?(is_const=false) ?(is_constexpr=false) ?(is_volatile=false) ?init ty name : top_decl =
  GlobalVar { align_as; is_extern_c; is_weak; is_static; is_thread_local; is_const; is_constexpr; is_volatile; ty; name; init }
let raw_top s : top_decl = RawTop s
let comment_top s : top_decl = CommentTop s
let namespace_def name decls : top_decl = Namespace (name, decls)

(* Convenient VM shortcuts for generating handlers *)
let reg_dst : expr = call "ctx.get_reg" [var "dst"]
let reg_src : expr = call "ctx.get_reg" [var "src"]
let set_reg dst_e val_e : stmt = expr_stmt (call "ctx.set_reg" [dst_e; val_e])
let fetch_next : stmt = expr_stmt (call "FETCH_NEXT" [])
let probe_start : stmt = expr_stmt (call "PROBE_START" [])
let probe_check : stmt = expr_stmt (call "PROBE_CHECK" [])
let inc_instrs : stmt = raw "ctx.executed_instructions++;"

(* EDSL Buffer-level preprocessor emitters (for emission into existing Buffer.t streams) *)
let emit_pp_if ?(indent="") b cond = Buffer.add_string b (Printf.sprintf "%s#if %s\n" indent cond)
let emit_pp_elif ?(indent="") b cond = Buffer.add_string b (Printf.sprintf "%s#elif %s\n" indent cond)
let emit_pp_else ?(indent="") b = Buffer.add_string b (Printf.sprintf "%s#else\n" indent)
let emit_pp_endif ?(indent="") b = Buffer.add_string b (Printf.sprintf "%s#endif\n" indent)
let emit_pp_ifdef ?(indent="") b m = Buffer.add_string b (Printf.sprintf "%s#ifdef %s\n" indent m)
let emit_pp_ifndef ?(indent="") b m = Buffer.add_string b (Printf.sprintf "%s#ifndef %s\n" indent m)
let emit_macro_def ?(indent="") b ?value name =
  match value with
  | Some v -> Buffer.add_string b (Printf.sprintf "%s#define %s %s\n" indent name v)
  | None -> Buffer.add_string b (Printf.sprintf "%s#define %s\n" indent name)
let emit_macro_undef ?(indent="") b name = Buffer.add_string b (Printf.sprintf "%s#undef %s\n" indent name)

let emit_preproc_if ?(indent="") b ?(elifs=[]) ?else_fn cond then_fn =
  emit_pp_if ~indent b cond;
  then_fn ();
  List.iter (fun (c, f) -> emit_pp_elif ~indent b c; f ()) elifs;
  (match else_fn with Some f -> emit_pp_else ~indent b; f () | None -> ());
  emit_pp_endif ~indent b
