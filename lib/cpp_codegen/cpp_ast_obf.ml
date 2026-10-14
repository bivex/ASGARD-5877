(* lib/cpp_codegen/cpp_ast_obf.ml
   Автоматический рандомизатор и обфускатор дерева C++ выражений и идентификаторов *)

open Cpp_ast

let is_commutative = function
  | Add | Mul | BitXor | BitAnd | BitOr | Eq | Ne -> true
  | _ -> false

(** Рекурсивно меняет местами ветви коммутативных операций по крипто-зерну *)
let rec scramble_expr (rng : Random.State.t) (e : expr) : expr =
  match e with
  | Binary (op, a, b) ->
      let a' = scramble_expr rng a in
      let b' = scramble_expr rng b in
      if is_commutative op && Random.State.bool rng then
        Binary (op, b', a')
      else
        Binary (op, a', b')
  | Unary (op, a) -> Unary (op, scramble_expr rng a)
  | Ternary (c, t, f) ->
      Ternary (scramble_expr rng c, scramble_expr rng t, scramble_expr rng f)
  | Cast (ty, a) -> Cast (ty, scramble_expr rng a)
  | CCast (ty, a) -> CCast (ty, scramble_expr rng a)
  | BitCast (ty, a) -> BitCast (ty, scramble_expr rng a)
  | ReinterpretCast (ty, a) -> ReinterpretCast (ty, scramble_expr rng a)
  | Index (arr, i) -> Index (scramble_expr rng arr, scramble_expr rng i)
  | Member (a, f) -> Member (scramble_expr rng a, f)
  | PtrMember (a, f) -> PtrMember (scramble_expr rng a, f)
  | Call (fn, args) -> Call (fn, List.map (scramble_expr rng) args)
  | InitList es -> InitList (List.map (scramble_expr rng) es)
  | LabelAddr _ -> e
  | DesignatedIndex (i, v) -> DesignatedIndex (scramble_expr rng i, scramble_expr rng v)
  | DesignatedRange (s, limit, v) -> DesignatedRange (scramble_expr rng s, scramble_expr rng limit, scramble_expr rng v)
  | LitU64 _ | LitU32 _ | LitI64 _ | LitInt _ | LitU8 _ | LitBool _ | LitStr _ | LitNull | SizeOfType _ | Var _ -> e

let rec scramble_stmt (rng : Random.State.t) (s : stmt) : stmt =
  match s with
  | DeclVar d ->
      DeclVar { d with init = Option.map (scramble_expr rng) d.init }
  | Assign (op, l, r) ->
      Assign (op, scramble_expr rng l, scramble_expr rng r)
  | ExprStmt e -> ExprStmt (scramble_expr rng e)
  | Return e -> Return (Option.map (scramble_expr rng) e)
  | Block b -> Block (List.map (scramble_stmt rng) b)
  | If (c, t, f) ->
      If (scramble_expr rng c, List.map (scramble_stmt rng) t, List.map (scramble_stmt rng) f)
  | ForRange r ->
      ForRange { r with start_e = scramble_expr rng r.start_e;
                        limit_e = scramble_expr rng r.limit_e;
                        body    = List.map (scramble_stmt rng) r.body }
  | While (c, b) ->
      While (scramble_expr rng c, List.map (scramble_stmt rng) b)
  | DoWhile (c, b) ->
      DoWhile (scramble_expr rng c, List.map (scramble_stmt rng) b)
  | Switch r ->
      Switch {
        cond    = scramble_expr rng r.cond;
        cases   = List.map (fun (ce, c, body) ->
                    (scramble_expr rng ce, c, List.map (scramble_stmt rng) body)) r.cases;
        default = Option.map (List.map (scramble_stmt rng)) r.default;
      }
  | ComputedGoto e -> ComputedGoto (scramble_expr rng e)
  | PreprocIfStmt (c, t, f) ->
      PreprocIfStmt (c, List.map (scramble_stmt rng) t, List.map (scramble_stmt rng) f)
  | Break | Continue | Goto _ | Label _ | Raw _ | FenceSeqCst | Comment _ | MacroUndefStmt _ -> s

let scramble_struct_member rng = function
  | MemberField f ->
      MemberField { f with init = Option.map (scramble_expr rng) f.init }
  | MemberMethod m ->
      MemberMethod { m with body = List.map (scramble_stmt rng) m.body }
  | MemberMethodDecl _ as m -> m
  | MemberConstructor c ->
      MemberConstructor {
        c with
        init_list = List.map (fun (n, e) -> (n, scramble_expr rng e)) c.init_list;
        body = List.map (scramble_stmt rng) c.body;
      }
  | MemberStaticConstexpr c ->
      MemberStaticConstexpr { c with init = scramble_expr rng c.init }
  | MemberStaticAssert (e, msg) ->
      MemberStaticAssert (scramble_expr rng e, msg)
  | (MemberVisibility _ | MemberRaw _ | MemberComment _) as m -> m

let rec scramble_top_decl (rng : Random.State.t) (d : top_decl) : top_decl =
  match d with
  | FuncDecl f ->
      FuncDecl { f with body = List.map (scramble_stmt rng) f.body }
  | StructDef s ->
      StructDef { s with members = List.map (scramble_struct_member rng) s.members }
  | ClassDef s ->
      ClassDef { s with members = List.map (scramble_struct_member rng) s.members }
  | TemplateStructDef t ->
      TemplateStructDef { t with def = { t.def with members = List.map (scramble_struct_member rng) t.def.members } }
  | TemplateClassDef t ->
      TemplateClassDef { t with def = { t.def with members = List.map (scramble_struct_member rng) t.def.members } }
  | UnionDef s ->
      UnionDef { s with members = List.map (scramble_struct_member rng) s.members }
  | Namespace (ns, decls) ->
      Namespace (ns, List.map (scramble_top_decl rng) decls)
  | ConstexprGlobal (ty, name, e) ->
      ConstexprGlobal (ty, name, scramble_expr rng e)
  | GlobalVar g ->
      GlobalVar { g with init = Option.map (scramble_expr rng) g.init }
  | MacroDef (name, opt) ->
      MacroDef (name, Option.map (scramble_expr rng) opt)
  | MacroUndef _ -> d
  | PreprocIf (c, t, f) ->
      PreprocIf (c, List.map (scramble_top_decl rng) t, List.map (scramble_top_decl rng) f)
  | PreprocIfdef (m, t, f) ->
      PreprocIfdef (m, List.map (scramble_top_decl rng) t, List.map (scramble_top_decl rng) f)
  | PreprocIfndef (m, t, f) ->
      PreprocIfndef (m, List.map (scramble_top_decl rng) t, List.map (scramble_top_decl rng) f)
  | Pragma _ | StructDecl _ | UnionDecl _ | EnumDecl _ | RawTop _ | CommentTop _ | IncludeSys _ | IncludeLocal _ | FuncProto _ | Typedef _ -> d
