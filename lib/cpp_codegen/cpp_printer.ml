(* lib/cpp_codegen/cpp_printer.ml
   C++20/C11 text generator based on the structured formatting of Stdlib.Format *)

open Cpp_ast
open Format

let rec pp_ctype fmt = function
  | Void          -> fprintf fmt "void"
  | Bool          -> fprintf fmt "bool"
  | Char          -> fprintf fmt "char"
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

let escape_c_string s =
  let b = Buffer.create (String.length s + 8) in
  String.iter (function
    | '\\' -> Buffer.add_string b "\\\\"
    | '"' -> Buffer.add_string b "\\\""
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c -> Buffer.add_char b c
  ) s;
  Buffer.contents b

let rec pp_expr fmt = function
  | LitU64 v          -> fprintf fmt "0x%016LxULL" v
  | LitU32 v          -> fprintf fmt "0x%08lxU" v
  | LitI64 v          -> fprintf fmt "%LdLL" v
  | LitInt n          -> fprintf fmt "%d" n
  | LitU8 b           -> fprintf fmt "0x%02X" (b land 0xFF)
  | LitBool b         -> fprintf fmt "%s" (if b then "true" else "false")
  | LitStr s          -> fprintf fmt "\"%s\"" (escape_c_string s)
  | LitNull           -> fprintf fmt "nullptr"
  | SizeOfType ty     -> fprintf fmt "sizeof(%a)" pp_ctype ty
  | InitList []       -> fprintf fmt "{}"
  | InitList es       ->
      let has_nested = List.exists (function InitList _ -> true | _ -> false) es in
      if has_nested then
        fprintf fmt "{@;<1 4>@[<v>%a@]@;<1 0>}"
          (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ",@,") pp_expr) es
      else if List.length es <= 8 then
        fprintf fmt "{ %a }"
          (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ") pp_expr) es
      else
        fprintf fmt "{@;<1 4>@[<hv>%a@]@;<1 0>}"
          (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ",@ ") pp_expr) es
  | Var s             -> fprintf fmt "%s" s
  | Member (e, f)     -> fprintf fmt "%a.%s" pp_expr_atom e f
  | PtrMember (e, f)  -> fprintf fmt "%a->%s" pp_expr_atom e f
  | Index (a, i)      -> fprintf fmt "%a[%a]" pp_expr_atom a pp_expr i
  | Unary (op, e)     -> fprintf fmt "(%s%a)" (unop_str op) pp_expr_atom e
  | Binary (op, a, b) -> fprintf fmt "(%a %s %a)" pp_expr a (binop_str op) pp_expr b
  | Ternary (c, t, f) -> fprintf fmt "(%a ? %a : %a)" pp_expr c pp_expr t pp_expr f
  | Cast (ty, e)      -> fprintf fmt "static_cast<%a>(%a)" pp_ctype ty pp_expr e
  | CCast (ty, e)     -> fprintf fmt "((%a)(%a))" pp_ctype ty pp_expr e
  | BitCast (ty, e)   -> fprintf fmt "std::bit_cast<%a>(%a)" pp_ctype ty pp_expr e
  | ReinterpretCast (ty, e) -> fprintf fmt "reinterpret_cast<%a>(%a)" pp_ctype ty pp_expr e
  | Call (fn, args)   ->
      fprintf fmt "%s(%a)" fn
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ") pp_expr) args
  | LabelAddr lbl     -> fprintf fmt "&&%s" lbl
  | DesignatedIndex (i, v) -> fprintf fmt "[%a] = %a" pp_expr i pp_expr v
  | DesignatedRange (s, e, v) -> fprintf fmt "[%a ... %a] = %a" pp_expr s pp_expr e pp_expr v

and pp_expr_atom fmt e = match e with
  | Var _ | LitU64 _ | LitU32 _ | LitI64 _ | LitInt _ | LitU8 _ | LitBool _ | LitStr _ | LitNull | SizeOfType _ | InitList _ | Index _ | Member _ | PtrMember _ | Call _ | CCast _ | LabelAddr _ | DesignatedIndex _ | DesignatedRange _ ->
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
  | DeclVar { align_as; is_static; is_thread_local; is_const; is_constexpr; is_volatile; ty; name; init } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      let prefix =
        align_str
        ^ (if is_static then "static " else "")
        ^ (if is_thread_local then "thread_local " else "")
        ^ (if is_constexpr then "constexpr "
           else if is_const then "const "
           else if is_volatile then "volatile "
           else "")
      in
      (match ty, init with
       | Array (elem_ty, n), None ->
           let sz_str = if n > 0 then string_of_int n else "" in
           fprintf fmt "%s%a %s[%s];" prefix pp_ctype elem_ty name sz_str
       | Array (elem_ty, n), Some e ->
           let sz_str = if n > 0 then string_of_int n else "" in
           fprintf fmt "%s%a %s[%s] = %a;" prefix pp_ctype elem_ty name sz_str pp_expr e
       | _, Some e ->
           fprintf fmt "%s%a %s = %a;" prefix pp_ctype ty name pp_expr e
       | _, None ->
           fprintf fmt "%s%a %s;" prefix pp_ctype ty name)
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
  | DoWhile (cond, body) ->
      fprintf fmt "do {@[<v 4>@,%a@]@,} while (%a);" pp_stmt_list body pp_condition cond
  | Switch { cond; cases; default } ->
      fprintf fmt "switch (%a) {@[<v 2>@," pp_expr cond;
      List.iter (fun (ce, comment_opt, body) ->
        match comment_opt with
        | Some c -> fprintf fmt "case %a: /* %s */ {@[<v 4>@,%a@]@,}@," pp_expr ce c pp_stmt_list body
        | None -> fprintf fmt "case %a: {@[<v 4>@,%a@]@,}@," pp_expr ce pp_stmt_list body
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
  | ComputedGoto target ->
      fprintf fmt "goto *%a;" pp_expr target
  | Label s ->
      fprintf fmt "%s:" s
  | PreprocIfStmt (cond, then_b, else_b) ->
      pp_preproc_if_stmt fmt cond then_b else_b
  | PreprocIfdefStmt (macro, then_b, else_b) ->
      fprintf fmt "@\n#ifdef %s@\n@[<v 0>%a@]" macro pp_stmt_list then_b;
      (match else_b with
       | [] -> ()
       | _ -> fprintf fmt "@\n#else@\n@[<v 0>%a@]" pp_stmt_list else_b);
      fprintf fmt "@\n#endif@\n"
  | PreprocIfndefStmt (macro, then_b, else_b) ->
      fprintf fmt "@\n#ifndef %s@\n@[<v 0>%a@]" macro pp_stmt_list then_b;
      (match else_b with
       | [] -> ()
       | _ -> fprintf fmt "@\n#else@\n@[<v 0>%a@]" pp_stmt_list else_b);
      fprintf fmt "@\n#endif@\n"
  | MacroDefStmt (name, Some v) ->
      fprintf fmt "@\n#define %s %a@\n" name pp_expr v
  | MacroDefStmt (name, None) ->
      fprintf fmt "@\n#define %s@\n" name
  | MacroDefRawStmt (name, Some s) ->
      fprintf fmt "@\n#define %s %s@\n" name s
  | MacroDefRawStmt (name, None) ->
      fprintf fmt "@\n#define %s@\n" name
  | MacroUndefStmt name ->
      fprintf fmt "@\n#undef %s@\n" name
  | Raw s ->
      fprintf fmt "%s" s
  | FenceSeqCst ->
      fprintf fmt "std::atomic_signal_fence(std::memory_order_seq_cst);"
  | Comment s ->
      fprintf fmt "// %s" s

and pp_preproc_if_stmt fmt cond then_b else_b =
  fprintf fmt "@\n#if %s@\n@[<v 0>%a@]" cond pp_stmt_list then_b;
  pp_preproc_if_stmt_tail fmt else_b

and pp_preproc_if_stmt_tail fmt = function
  | [PreprocIfStmt (cond, then_b, else_b)] ->
      fprintf fmt "@\n#elif %s@\n@[<v 0>%a@]" cond pp_stmt_list then_b;
      pp_preproc_if_stmt_tail fmt else_b
  | [] ->
      fprintf fmt "@\n#endif@\n"
  | else_b ->
      fprintf fmt "@\n#else@\n@[<v 0>%a@]@\n#endif@\n" pp_stmt_list else_b

and pp_stmt_list fmt stmts =
  pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n") pp_stmt fmt stmts

let pp_attr fmt = function
  | AlwaysInline -> fprintf fmt "__attribute__((always_inline)) inline "
  | NoInline     -> fprintf fmt "__attribute__((noinline)) "
  | InlineFn     -> fprintf fmt "inline "
  | Nodiscard    -> fprintf fmt "[[nodiscard]] "
  | NoExcept     -> ()
  | ConstexprFn  -> fprintf fmt "constexpr "
  | StaticFn     -> fprintf fmt "static "
  | Constructor  -> fprintf fmt "__attribute__((constructor)) "

let pp_attrs fmt attrs =
  let has_always_inline = List.mem AlwaysInline attrs in
  let filtered =
    if has_always_inline then
      List.filter (fun a -> a <> InlineFn) attrs
    else attrs
  in
  List.iter (pp_attr fmt) filtered

let pp_struct_member fmt = function
  | MemberField { is_volatile; ty; name; init = Some e } ->
      fprintf fmt "%s%a %s = %a;@," (if is_volatile then "volatile " else "") pp_ctype ty name pp_expr e
  | MemberField { is_volatile; ty = Array (Array (et, sz2), sz1); name; init = None } ->
      fprintf fmt "%s%a %s[%d][%d];@," (if is_volatile then "volatile " else "") pp_ctype et name sz1 sz2
  | MemberField { is_volatile; ty = Array (et, sz); name; init = None } ->
      fprintf fmt "%s%a %s[%d];@," (if is_volatile then "volatile " else "") pp_ctype et name sz
  | MemberField { is_volatile; ty; name; init = None } ->
      fprintf fmt "%s%a %s;@," (if is_volatile then "volatile " else "") pp_ctype ty name
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
      pp_attrs fmt attrs;
      if is_static then fprintf fmt "static ";
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
      pp_attrs fmt attrs;
      if is_static then fprintf fmt "static ";
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
      pp_attrs fmt attrs;
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
  | MemberDestructor { attrs; name; body } ->
      pp_attrs fmt attrs;
      fprintf fmt "~%s() {@[<v 4>@,%a@]@,}@," name pp_stmt_list body
  | MemberRaw s ->
      fprintf fmt "%s@," s
  | MemberComment s ->
      fprintf fmt "// %s@," s

let rec pp_top_decl fmt = function
  | Pragma s ->
      fprintf fmt "#pragma %s" s
  | MacroDef (name, Some v) ->
      fprintf fmt "#define %s %a" name pp_expr v
  | MacroDef (name, None) ->
      fprintf fmt "#define %s" name
  | MacroDefRaw (name, Some s) ->
      fprintf fmt "#define %s %s" name s
  | MacroDefRaw (name, None) ->
      fprintf fmt "#define %s" name
  | MacroUndef name ->
      fprintf fmt "#undef %s" name
  | PreprocIf (cond, then_decls, else_decls) ->
      pp_preproc_if_decl fmt cond then_decls else_decls
  | PreprocIfdef (macro, then_decls, else_decls) ->
      fprintf fmt "@\n#ifdef %s@\n@[<v 0>%a@]" macro
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) then_decls;
      (match else_decls with
       | [] -> ()
       | _ ->
           fprintf fmt "@\n#else@\n@[<v 0>%a@]"
             (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) else_decls);
      fprintf fmt "@\n#endif@\n"
  | PreprocIfndef (macro, then_decls, else_decls) ->
      fprintf fmt "@\n#ifndef %s@\n@[<v 0>%a@]" macro
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) then_decls;
      (match else_decls with
       | [] -> ()
       | _ ->
           fprintf fmt "@\n#else@\n@[<v 0>%a@]"
             (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) else_decls);
      fprintf fmt "@\n#endif@\n"
  | IncludeSys h ->
      fprintf fmt "#include <%s>" h
  | IncludeLocal h ->
      fprintf fmt "#include \"%s\"" h
  | ConstexprGlobal (ty, name, e) ->
      fprintf fmt "constexpr %a %s = %a;" pp_ctype ty name pp_expr e
  | GlobalVar { align_as; is_extern_c; is_weak; is_static; is_thread_local; is_const; is_constexpr; is_volatile; ty; name; init } ->
      let align_str = match align_as with
        | Some n -> Printf.sprintf "alignas(%d) " n
        | None -> ""
      in
      let prefix =
        align_str
        ^ (if is_extern_c then "extern \"C\" " else "")
        ^ (if is_weak then "__attribute__((weak)) " else "")
        ^ (if is_static then "static " else "")
        ^ (if is_thread_local then "thread_local " else "")
        ^ (if is_volatile then "volatile " else "")
        ^ (if is_constexpr then "constexpr "
           else if is_const then "const "
           else "")
      in
      (match ty with
       | Array (Array (et, sz2), sz1) ->
           let sz1_str = if sz1 > 0 then string_of_int sz1 else "" in
           let sz2_str = if sz2 > 0 then string_of_int sz2 else "" in
           (match init with
            | Some e -> fprintf fmt "%s%a %s[%s][%s] = %a;" prefix pp_ctype et name sz1_str sz2_str pp_expr e
            | None -> fprintf fmt "%s%a %s[%s][%s];" prefix pp_ctype et name sz1_str sz2_str)
       | Array (et, sz) ->
           let sz_str = if sz > 0 then string_of_int sz else "" in
           (match init with
            | Some e -> fprintf fmt "%s%a %s[%s] = %a;" prefix pp_ctype et name sz_str pp_expr e
            | None -> fprintf fmt "%s%a %s[%s];" prefix pp_ctype et name sz_str)
       | _ ->
           (match init with
            | Some e -> fprintf fmt "%s%a %s = %a;" prefix pp_ctype ty name pp_expr e
            | None -> fprintf fmt "%s%a %s;" prefix pp_ctype ty name))
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
      pp_attrs fmt attrs;
      let is_noexcept = List.mem NoExcept attrs in
      fprintf fmt "%a %s(%a)%s {@[<v 4>@,%a@]@,}"
        pp_ctype ret_type name
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
           (fun fmt (ty, pname) -> fprintf fmt "%a %s" pp_ctype ty pname)) params
        (if is_noexcept then " noexcept" else "")
        pp_stmt_list body
  | FuncProto { attrs; ret_type; name; params; _ } ->
      pp_attrs fmt attrs;
      let is_noexcept = List.mem NoExcept attrs in
      fprintf fmt "%a %s(%a)%s;"
        pp_ctype ret_type name
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt ", ")
           (fun fmt (ty, pname) ->
              if pname = "" then pp_ctype fmt ty
              else fprintf fmt "%a %s" pp_ctype ty pname)) params
        (if is_noexcept then " noexcept" else "")
  | Typedef (ty, name) ->
      fprintf fmt "typedef %a %s;" pp_ctype ty name
  | Namespace (ns, decls) ->
      fprintf fmt "namespace %s {@[<v 0>@,@,%a@]@,@,} // namespace %s"
        ns (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@,@,") pp_top_decl) decls ns
  | RawTop s ->
      fprintf fmt "%s" s
  | CommentTop s ->
      if String.starts_with ~prefix:"/*" s then
        fprintf fmt "%s" s
      else
        fprintf fmt "// %s" s

and pp_preproc_if_decl fmt cond then_decls else_decls =
  fprintf fmt "@\n#if %s@\n@[<v 0>%a@]" cond
    (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) then_decls;
  pp_preproc_if_decl_tail fmt else_decls

and pp_preproc_if_decl_tail fmt = function
  | [PreprocIf (cond, then_decls, else_decls)] ->
      fprintf fmt "@\n#elif %s@\n@[<v 0>%a@]" cond
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) then_decls;
      pp_preproc_if_decl_tail fmt else_decls
  | [] ->
      fprintf fmt "@\n#endif@\n"
  | else_decls ->
      fprintf fmt "@\n#else@\n@[<v 0>%a@]@\n#endif@\n"
        (pp_print_list ~pp_sep:(fun fmt () -> fprintf fmt "@\n@\n") pp_top_decl) else_decls

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

