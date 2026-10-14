(* lib/cpp_codegen/cpp_printer.ml
   Генератор текста C++20/C11 на базе структурного форматирования Stdlib.Format *)

open Cpp_ast
open Format

let rec pp_ctype fmt = function
  | Void          -> fprintf fmt "void"
  | Bool          -> fprintf fmt "bool"
  | Int8          -> fprintf fmt "int8_t"
  | Int16         -> fprintf fmt "int16_t"
  | Int32         -> fprintf fmt "int32_t"
  | Int64         -> fprintf fmt "int64_t"
  | UInt8         -> fprintf fmt "uint8_t"
  | UInt16        -> fprintf fmt "uint16_t"
  | UInt32        -> fprintf fmt "uint32_t"
  | UInt64        -> fprintf fmt "uint64_t"
  | UIntPtr       -> fprintf fmt "uintptr_t"
  | SizeT         -> fprintf fmt "size_t"
  | Float         -> fprintf fmt "float"
  | Double        -> fprintf fmt "double"
  | Ptr t         -> fprintf fmt "%a*" pp_ctype t
  | ConstPtr t    -> fprintf fmt "const %a*" pp_ctype t
  | VolatilePtr t -> fprintf fmt "volatile %a*" pp_ctype t
  | Ref t         -> fprintf fmt "%a&" pp_ctype t
  | ConstRef t    -> fprintf fmt "const %a&" pp_ctype t
  | Array (t, n)  -> fprintf fmt "%a[%d]" pp_ctype t n
  | StructType s  -> fprintf fmt "%s" s

let binop_str = function
  | Add -> "+"  | Sub -> "-"  | Mul -> "*"  | Div -> "/"  | Rem -> "%"
  | BitXor -> "^" | BitAnd -> "&" | BitOr -> "|" | Shl -> "<<" | Shr -> ">>"
  | Eq -> "==" | Ne -> "!=" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="
  | LogAnd -> "&&" | LogOr -> "||"

let unop_str = function
  | BitNot -> "~" | Neg -> "-" | LogNot -> "!" | Deref -> "*" | AddrOf -> "&"

let rec pp_expr fmt = function
  | LitU64 v          -> fprintf fmt "0x%016LxULL" v
  | LitU32 v          -> fprintf fmt "0x%08lxU" v
  | LitI64 v          -> fprintf fmt "%LdLL" v
  | LitInt n          -> fprintf fmt "%d" n
  | LitBool b         -> fprintf fmt "%s" (if b then "true" else "false")
  | LitStr s          -> fprintf fmt "\"%s\"" s
  | Var s             -> fprintf fmt "%s" s
  | Member (e, f)     -> fprintf fmt "%a.%s" pp_expr_atom e f
  | PtrMember (e, f)  -> fprintf fmt "%a->%s" pp_expr_atom e f
  | Index (a, i)      -> fprintf fmt "%a[%a]" pp_expr_atom a pp_expr i
  | Unary (op, e)     -> fprintf fmt "(%s%a)" (unop_str op) pp_expr_atom e
  | Binary (op, a, b) -> fprintf fmt "(%a %s %a)" pp_expr a (binop_str op) pp_expr b
  | Ternary (c, t, f) -> fprintf fmt "(%a ? %a : %a)" pp_expr c pp_expr t pp_expr f
  | Cast (ty, e)      -> fprintf fmt "static_cast<%a>(%a)" pp_ctype ty pp_expr e
  | BitCast (ty, e)   -> fprintf fmt "std::bit_cast<%a>(%a)" pp_ctype ty pp_expr e
  | ReinterpretCast (ty, e) -> fprintf fmt "reinterpret_cast<%a>(%a)" pp_ctype ty pp_expr e
  | Call (fn, args)   ->
      fprintf fmt "%s(%a)" fn
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ") pp_expr) args

and pp_expr_atom fmt e = match e with
  | Var _ | LitU64 _ | LitU32 _ | LitI64 _ | LitInt _ | LitBool _ | LitStr _ | Index _ | Member _ | PtrMember _ | Call _ ->
      pp_expr fmt e
  | _ -> fprintf fmt "(%a)" pp_expr e

(* Statement-condition context.
   [Binary], [Unary] and [Ternary] expressions already wrap themselves in
   parentheses via [pp_expr], and the statement keyword (if/while) adds its
   own pair, so printing the condition with [pp_expr] yields e.g.
   "if ((w == 1))". The extra pair around an equality comparison trips
   clang's -Wparentheses-equality. Since every operand is printed with
   [pp_expr] (which self-parenthesizes), dropping only the outermost
   wrapper preserves the exact operator grouping. *)
let pp_condition fmt e =
  match e with
  | Binary (op, a, b) -> fprintf fmt "%a %s %a" pp_expr a (binop_str op) pp_expr b
  | Ternary (c, t, f) -> fprintf fmt "%a ? %a : %a" pp_expr c pp_expr t pp_expr f
  | Unary (op, e') -> fprintf fmt "%s%a" (unop_str op) pp_expr e'
  | _ -> pp_expr fmt e

let assign_op_str = function
  | AssignPlain -> "="  | AssignAdd -> "+=" | AssignSub -> "-=" | AssignMul -> "*="
  | AssignXor   -> "^=" | AssignOr  -> "|=" | AssignAnd -> "&=" | AssignDiv -> "/="

let rec pp_stmt fmt = function
  | DeclVar { is_const; is_constexpr; is_volatile; ty; name; init } ->
      let prefix =
        if is_constexpr then "constexpr "
        else if is_const then "const "
        else if is_volatile then "volatile "
        else ""
      in
      (match ty, init with
       | Array (elem_ty, n), None ->
           fprintf fmt "%s%a %s[%d]{};" prefix pp_ctype elem_ty name n
       | _, Some e ->
           fprintf fmt "%s%a %s = %a;" prefix pp_ctype ty name pp_expr e
       | _, None ->
           fprintf fmt "%s%a %s{};" prefix pp_ctype ty name)
  | Assign (op, lhs, rhs) ->
      fprintf fmt "%a %s %a;" pp_expr lhs (assign_op_str op) pp_expr rhs
  | ExprStmt e ->
      fprintf fmt "%a;" pp_expr e
  | Return (Some e) ->
      fprintf fmt "return %a;" pp_expr e
  | Return None ->
      fprintf fmt "return;"
  | Block stmts ->
      fprintf fmt "{@[<v 4>@,%a@]@,}" pp_stmt_list stmts
  | If (cond, then_b, []) ->
      fprintf fmt "if (%a) {@[<v 4>@,%a@]@,}" pp_condition cond pp_stmt_list then_b
  | If (cond, then_b, else_b) ->
      fprintf fmt "if (%a) {@[<v 4>@,%a@]@,} else {@[<v 4>@,%a@]@,}"
        pp_condition cond pp_stmt_list then_b pp_stmt_list else_b
  | ForRange { var_name; start_e; limit_e; body } ->
      fprintf fmt "for (size_t %s = %a; %s < %a; ++%s) {@[<v 4>@,%a@]@,}"
        var_name pp_expr start_e var_name pp_expr limit_e var_name pp_stmt_list body
  | While (cond, body) ->
      fprintf fmt "while (%a) {@[<v 4>@,%a@]@,}" pp_condition cond pp_stmt_list body
  | Switch { cond; cases; default } ->
      fprintf fmt "switch (%a) {@[<v 2>@," pp_expr cond;
      List.iter (fun (ce, body) ->
        fprintf fmt "case %a: {@[<v 4>@,%a@]@,}@," pp_expr ce pp_stmt_list body
      ) cases;
      (match default with
       | Some d -> fprintf fmt "default: {@[<v 4>@,%a@]@,}" pp_stmt_list d
       | None -> ());
      fprintf fmt "@]@,}"
  | Break ->
      fprintf fmt "break;"
  | Continue ->
      fprintf fmt "continue;"
  | Goto s ->
      fprintf fmt "goto %s;" s
  | Label s ->
      fprintf fmt "%s:" s
  | Raw s ->
      fprintf fmt "%s" s
  | FenceSeqCst ->
      fprintf fmt "std::atomic_signal_fence(std::memory_order_seq_cst);"
  | Comment s ->
      fprintf fmt "// %s" s

and pp_stmt_list fmt stmts =
  pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@,") pp_stmt fmt stmts

let pp_attr fmt = function
  | AlwaysInline -> fprintf fmt "__attribute__((always_inline)) inline "
  | NoInline     -> fprintf fmt "__attribute__((noinline)) "
  | InlineFn     -> fprintf fmt "inline "
  | Nodiscard    -> fprintf fmt "[[nodiscard]] "
  | NoExcept     -> ()
  | ConstexprFn  -> fprintf fmt "constexpr "
  | StaticFn     -> fprintf fmt "static "

let pp_struct_member fmt = function
  | MemberField { ty; name; init = Some e } ->
      fprintf fmt "%a %s = %a;@," pp_ctype ty name pp_expr e
  | MemberField { ty = Array (Array (et, sz2), sz1); name; init = None } ->
      fprintf fmt "%a %s[%d][%d];@," pp_ctype et name sz1 sz2
  | MemberField { ty = Array (et, sz); name; init = None } ->
      fprintf fmt "%a %s[%d];@," pp_ctype et name sz
  | MemberField { ty; name; init = None } ->
      fprintf fmt "%a %s;@," pp_ctype ty name
  | MemberStaticConstexpr { ty; name; init } ->
      fprintf fmt "static inline constexpr %a %s = %a;@," pp_ctype ty name pp_expr init
  | MemberVisibility Public ->
      fprintf fmt "public:@,"
  | MemberVisibility Private ->
      fprintf fmt "private:@,"
  | MemberVisibility Protected ->
      fprintf fmt "protected:@,"
  | MemberStaticAssert (e, msg) ->
      fprintf fmt "static_assert(%a, \"%s\");@," pp_expr e msg
  | MemberMethod { attrs; is_static; is_const; template_params; ret_type; name; params; body } ->
      if template_params <> [] then
        fprintf fmt "template <%s>@," (String.concat ", " template_params);
      if is_static then fprintf fmt "static ";
      List.iter (pp_attr fmt) attrs;
      let is_noexcept = List.mem NoExcept attrs in
      fprintf fmt "%a %s(%a)%s%s {@[<v 4>@,%a@]@,}@,"
        pp_ctype ret_type name
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
           (fun fmt (ty, pname) ->
              if pname = "" then pp_ctype fmt ty
              else fprintf fmt "%a %s" pp_ctype ty pname)) params
        (if is_const then " const" else "")
        (if is_noexcept then " noexcept" else "")
        pp_stmt_list body
  | MemberMethodDecl { attrs; is_static; is_const; template_params; ret_type; name; params } ->
      if template_params <> [] then
        fprintf fmt "template <%s>@," (String.concat ", " template_params);
      if is_static then fprintf fmt "static ";
      List.iter (pp_attr fmt) attrs;
      let is_noexcept = List.mem NoExcept attrs in
      fprintf fmt "%a %s(%a)%s%s;@,"
        pp_ctype ret_type name
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
           (fun fmt (ty, pname) ->
              if pname = "" then pp_ctype fmt ty
              else fprintf fmt "%a %s" pp_ctype ty pname)) params
        (if is_const then " const" else "")
        (if is_noexcept then " noexcept" else "")
  | MemberConstructor { attrs; is_explicit; name; params; init_list; body } ->
      List.iter (pp_attr fmt) attrs;
      if is_explicit then fprintf fmt "explicit ";
      let is_noexcept = List.mem NoExcept attrs in
      let init_str =
        match init_list with
        | [] -> ""
        | inits ->
            let b = Buffer.create 64 in
            let f = formatter_of_buffer b in
            fprintf f " : %a"
              (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
                 (fun fmt (fname, e) -> fprintf fmt "%s(%a)" fname pp_expr e))
              inits;
            pp_print_flush f ();
            Buffer.contents b
      in
      fprintf fmt "%s(%a)%s%s {@[<v 4>@,%a@]@,}@,"
        name
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
           (fun fmt (ty, pname) ->
              if pname = "" then pp_ctype fmt ty
              else fprintf fmt "%a %s" pp_ctype ty pname)) params
        (if is_noexcept then " noexcept" else "")
        init_str
        pp_stmt_list body
  | MemberRaw s ->
      fprintf fmt "%s@," s
  | MemberComment s ->
      fprintf fmt "// %s@," s

let rec pp_top_decl fmt = function
  | IncludeSys h ->
      fprintf fmt "#include <%s>" h
  | IncludeLocal h ->
      fprintf fmt "#include \"%s\"" h
  | ConstexprGlobal (ty, name, e) ->
      fprintf fmt "constexpr %a %s = %a;" pp_ctype ty name pp_expr e
  | StructDecl { align_as; name; fields } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "struct %s%s {@[<v 4>@," align_str name;
      List.iter (fun (ty, fname) ->
        match ty with
        | Array (et, sz) -> fprintf fmt "%a %s[%d];@," pp_ctype et fname sz
        | _ -> fprintf fmt "%a %s;@," pp_ctype ty fname
      ) fields;
      fprintf fmt "@]@,};"
  | UnionDecl { align_as; name; fields } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "union %s%s {@[<v 4>@," align_str name;
      List.iter (fun (ty, fname) ->
        match ty with
        | Array (et, sz) -> fprintf fmt "%a %s[%d];@," pp_ctype et fname sz
        | _ -> fprintf fmt "%a %s;@," pp_ctype ty fname
      ) fields;
      fprintf fmt "@]@,};"
  | StructDef { align_as; name; members } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "struct %s%s {@[<v 4>@," align_str name;
      List.iter (pp_struct_member fmt) members;
      fprintf fmt "@]@,};"
  | ClassDef { align_as; name; members } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "class %s%s {@[<v 4>@," align_str name;
      List.iter (pp_struct_member fmt) members;
      fprintf fmt "@]@,};"
  | TemplateStructDef { template_params; def = { align_as; name; members } } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "template <%s>@,struct %s%s {@[<v 4>@,"
        (String.concat ", " template_params) align_str name;
      List.iter (pp_struct_member fmt) members;
      fprintf fmt "@]@,};"
  | TemplateClassDef { template_params; def = { align_as; name; members } } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "template <%s>@,class %s%s {@[<v 4>@,"
        (String.concat ", " template_params) align_str name;
      List.iter (pp_struct_member fmt) members;
      fprintf fmt "@]@,};"
  | UnionDef { align_as; name; members } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      fprintf fmt "union %s%s {@[<v 4>@," align_str name;
      List.iter (pp_struct_member fmt) members;
      fprintf fmt "@]@,};"
  | EnumDecl { name; underlying_ty; items } ->
      let ty_str = match underlying_ty with
        | Some t ->
            let buf = Buffer.create 16 in
            let f = formatter_of_buffer buf in
            fprintf f " : %a" pp_ctype t;
            pp_print_flush f ();
            Buffer.contents buf
        | None -> ""
      in
      fprintf fmt "enum %s%s {@[<v 4>@," name ty_str;
      List.iter (fun (iname, val_opt) ->
        match val_opt with
        | Some e -> fprintf fmt "%s = %a,@," iname pp_expr e
        | None -> fprintf fmt "%s,@," iname
      ) items;
      fprintf fmt "@]@,};"
  | FuncDecl { attrs; ret_type; name; params; body } ->
      List.iter (pp_attr fmt) attrs;
      let is_noexcept = List.mem NoExcept attrs in
      fprintf fmt "%a %s(%a)%s {@[<v 4>@,%a@]@,}"
        pp_ctype ret_type name
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
           (fun fmt (ty, pname) -> fprintf fmt "%a %s" pp_ctype ty pname)) params
        (if is_noexcept then " noexcept" else "")
        pp_stmt_list body
  | Namespace (ns, decls) ->
      fprintf fmt "namespace %s {@[<v 0>@,@,%a@]@,@,} // namespace %s"
        ns (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@,@,") pp_top_decl) decls ns
  | RawTop s ->
      fprintf fmt "%s" s
  | CommentTop s ->
      fprintf fmt "// %s" s

let render_header_unit (decls : top_decl list) : string =
  let buf = Buffer.create 4096 in
  let fmt = formatter_of_buffer buf in
  fprintf fmt "@[<v 0>#pragma once@,// AUTO-GENERATED BY ASGARD-5877 TYPED C++20 EDSL@,@,%a@,@]@."
    (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@,@,") pp_top_decl) decls;
  Buffer.contents buf

let render_top_decls (decls : top_decl list) : string =
  let buf = Buffer.create 4096 in
  let fmt = formatter_of_buffer buf in
  fprintf fmt "@[<v 0>%a@]@."
    (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@,@,") pp_top_decl) decls;
  Buffer.contents buf

let string_of_ctype (t : ctype) : string =
  let buf = Buffer.create 32 in
  let fmt = formatter_of_buffer buf in
  pp_ctype fmt t;
  pp_print_flush fmt ();
  Buffer.contents buf

let string_of_expr (e : expr) : string =
  let buf = Buffer.create 64 in
  let fmt = formatter_of_buffer buf in
  pp_expr fmt e;
  pp_print_flush fmt ();
  Buffer.contents buf

let string_of_stmt (s : stmt) : string =
  let buf = Buffer.create 128 in
  let fmt = formatter_of_buffer buf in
  pp_stmt fmt s;
  pp_print_flush fmt ();
  Buffer.contents buf

let string_of_stmts (stmts : stmt list) : string =
  let buf = Buffer.create 256 in
  let fmt = formatter_of_buffer buf in
  pp_stmt_list fmt stmts;
  pp_print_flush fmt ();
  Buffer.contents buf

let string_of_top_decl (d : top_decl) : string =
  render_top_decls [d]

let render_top_decl (d : top_decl) : string =
  render_top_decls [d]

