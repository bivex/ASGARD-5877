(** E-Graph Equality Saturation → C++ Handler Expression Emitter.
    Uses Cpp_codegen typed AST to render egraph-expanded expressions. *)

open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

(** Render an [Mba.expr] as a typed [Cpp_ast.expr].
    [a_expr] and [b_expr] are the AST expressions to substitute for Var "a" / "b". *)
let rec expr_to_ast ~a_expr ~b_expr = function
  | Mba_engine.Mba.Var "a" -> a_expr
  | Mba_engine.Mba.Var "b" -> b_expr
  | Mba_engine.Mba.Var _ -> u64 0L
  | Mba_engine.Mba.Const c -> u64 c
  | Mba_engine.Mba.Add (x, y) -> (expr_to_ast ~a_expr ~b_expr x) +~ (expr_to_ast ~a_expr ~b_expr y)
  | Mba_engine.Mba.Sub (x, y) -> (expr_to_ast ~a_expr ~b_expr x) -~ (expr_to_ast ~a_expr ~b_expr y)
  | Mba_engine.Mba.Mul (x, y) -> (expr_to_ast ~a_expr ~b_expr x) *~ (expr_to_ast ~a_expr ~b_expr y)
  | Mba_engine.Mba.And (x, y) -> (expr_to_ast ~a_expr ~b_expr x) &~ (expr_to_ast ~a_expr ~b_expr y)
  | Mba_engine.Mba.Or (x, y) -> (expr_to_ast ~a_expr ~b_expr x) |~ (expr_to_ast ~a_expr ~b_expr y)
  | Mba_engine.Mba.Xor (x, y) -> (expr_to_ast ~a_expr ~b_expr x) ^~ (expr_to_ast ~a_expr ~b_expr y)
  | Mba_engine.Mba.Not x -> bit_not (expr_to_ast ~a_expr ~b_expr x)
  | Mba_engine.Mba.Neg x -> neg_u64 (expr_to_ast ~a_expr ~b_expr x)

(** Legacy wrapper returning string *)
let expr_to_cpp ~a_cpp ~b_cpp expr =
  string_of_expr (expr_to_ast ~a_expr:(var a_cpp) ~b_expr:(var b_cpp) expr)

(** E-graph config for handler obfuscation: tight budget so codegen stays fast. *)
let handler_egraph_config : Mba_engine.Egraph.config =
  { node_limit = 120; time_budget_s = 0.08; iter_limit = 6 }

(** Expand [op] via equality saturation, then render as typed AST expression. *)
let expand_op_to_ast ~rng ~a_expr ~b_expr ~fallback op_expr =
  match Mba_engine.Egraph.expand ~rng ~config:handler_egraph_config op_expr with
  | exception _ -> fallback
  | expanded -> expr_to_ast ~a_expr ~b_expr expanded

let expand_op_to_cpp ~rng ~a_cpp ~b_cpp ~fallback op_expr =
  string_of_expr
    (expand_op_to_ast ~rng ~a_expr:(var a_cpp) ~b_expr:(var b_cpp) ~fallback:(var fallback) op_expr)

(** Typed AST generators for VM arithmetic handlers *)
let egraph_add_rr_ast ~rng =
  expand_op_to_ast ~rng ~a_expr:reg_dst ~b_expr:reg_src
    ~fallback:(reg_dst +~ reg_src)
    (Mba_engine.Mba.Add (Var "a", Var "b"))

let egraph_sub_rr_ast ~rng =
  expand_op_to_ast ~rng ~a_expr:reg_dst ~b_expr:reg_src
    ~fallback:(reg_dst -~ reg_src)
    (Mba_engine.Mba.Sub (Var "a", Var "b"))

let egraph_xor_rr_ast ~rng =
  expand_op_to_ast ~rng ~a_expr:reg_dst ~b_expr:reg_src
    ~fallback:(reg_dst ^~ reg_src)
    (Mba_engine.Mba.Xor (Var "a", Var "b"))

let egraph_and_rr_ast ~rng =
  expand_op_to_ast ~rng ~a_expr:reg_dst ~b_expr:reg_src
    ~fallback:(reg_dst &~ reg_src)
    (Mba_engine.Mba.And (Var "a", Var "b"))

let egraph_or_rr_ast ~rng =
  expand_op_to_ast ~rng ~a_expr:reg_dst ~b_expr:reg_src
    ~fallback:(reg_dst |~ reg_src)
    (Mba_engine.Mba.Or (Var "a", Var "b"))

(** String wrappers for existing callers *)
let egraph_add_rr ~rng = string_of_expr (egraph_add_rr_ast ~rng)
let egraph_sub_rr ~rng = string_of_expr (egraph_sub_rr_ast ~rng)
let egraph_xor_rr ~rng = string_of_expr (egraph_xor_rr_ast ~rng)
let egraph_and_rr ~rng = string_of_expr (egraph_and_rr_ast ~rng)
let egraph_or_rr ~rng  = string_of_expr (egraph_or_rr_ast ~rng)
