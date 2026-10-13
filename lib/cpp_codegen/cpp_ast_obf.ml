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
  | BitCast (ty, a) -> BitCast (ty, scramble_expr rng a)
  | Index (arr, i) -> Index (scramble_expr rng arr, scramble_expr rng i)
  | Member (a, f) -> Member (scramble_expr rng a, f)
  | PtrMember (a, f) -> PtrMember (scramble_expr rng a, f)
  | Call (fn, args) -> Call (fn, List.map (scramble_expr rng) args)
  | LitU64 _ | LitU32 _ | LitInt _ | LitBool _ | Var _ -> e

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
  | Switch r ->
      Switch {
        cond    = scramble_expr rng r.cond;
        cases   = List.map (fun (ce, body) ->
                    (scramble_expr rng ce, List.map (scramble_stmt rng) body)) r.cases;
        default = Option.map (List.map (scramble_stmt rng)) r.default;
      }
  | FenceSeqCst | Comment _ -> s

let rec scramble_top_decl (rng : Random.State.t) (d : top_decl) : top_decl =
  match d with
  | FuncDecl f ->
      FuncDecl { f with body = List.map (scramble_stmt rng) f.body }
  | Namespace (ns, decls) ->
      Namespace (ns, List.map (scramble_top_decl rng) decls)
  | ConstexprGlobal (ty, name, e) ->
      ConstexprGlobal (ty, name, scramble_expr rng e)
  | StructDecl _ | IncludeSys _ | IncludeLocal _ -> d
