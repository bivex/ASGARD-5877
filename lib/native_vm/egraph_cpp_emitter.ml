(** E-Graph Equality Saturation → C++ Handler Expression Emitter.

    Takes a [Mba.expr] that has been equality-saturated and max-complexity
    extracted by [Mba_engine.Egraph.expand], and renders it as a C++
    expression string referencing [ctx.get_reg(dst)] for variable "a" and
    [ctx.get_reg(src)] for variable "b".

    The emitted string is plugged directly into the VM handler body, e.g.:

      H_ADD_RR: { ctx.set_reg(dst, <egraph_expr>); FETCH_NEXT(); }

    This gives every arithmetic handler an algebraically-equivalent but
    structurally unique form under each randomization seed, defeating
    pattern-matching decompiler signatures.
*)

open Mba_engine.Mba

(** Render a [Mba.expr] as a parenthesized C++ uint64_t expression.
    [a_cpp] and [b_cpp] are the C++ strings to substitute for Var "a" / "b".
    Constants are emitted as [0x...ULL] hex literals. *)
let rec expr_to_cpp ~a_cpp ~b_cpp = function
  | Var "a" -> a_cpp
  | Var "b" -> b_cpp
  | Var _ -> "0ULL"
  | Const c ->
      (* Use hex for readability; handle negative via cast *)
      if c >= 0L then Printf.sprintf "0x%LXull" c
      else Printf.sprintf "(uint64_t)(%LdLL)" c
  | Add (x, y) ->
      Printf.sprintf "(%s + %s)"
        (expr_to_cpp ~a_cpp ~b_cpp x)
        (expr_to_cpp ~a_cpp ~b_cpp y)
  | Sub (x, y) ->
      Printf.sprintf "(%s - %s)"
        (expr_to_cpp ~a_cpp ~b_cpp x)
        (expr_to_cpp ~a_cpp ~b_cpp y)
  | Mul (x, y) ->
      Printf.sprintf "(%s * %s)"
        (expr_to_cpp ~a_cpp ~b_cpp x)
        (expr_to_cpp ~a_cpp ~b_cpp y)
  | And (x, y) ->
      Printf.sprintf "(%s & %s)"
        (expr_to_cpp ~a_cpp ~b_cpp x)
        (expr_to_cpp ~a_cpp ~b_cpp y)
  | Or (x, y) ->
      Printf.sprintf "(%s | %s)"
        (expr_to_cpp ~a_cpp ~b_cpp x)
        (expr_to_cpp ~a_cpp ~b_cpp y)
  | Xor (x, y) ->
      Printf.sprintf "(%s ^ %s)"
        (expr_to_cpp ~a_cpp ~b_cpp x)
        (expr_to_cpp ~a_cpp ~b_cpp y)
  | Not x ->
      Printf.sprintf "(~%s)" (expr_to_cpp ~a_cpp ~b_cpp x)
  | Neg x ->
      Printf.sprintf "(-%s)" (expr_to_cpp ~a_cpp ~b_cpp x)

(** E-graph config for handler obfuscation: tight budget so codegen stays fast. *)
let handler_egraph_config : Mba_engine.Egraph.config =
  { node_limit = 120; time_budget_s = 0.08; iter_limit = 6 }

(** Expand [op] (an binary Mba operator like [Add (Var "a", Var "b")]) via
    equality saturation, then render the max-complexity extracted form as a
    C++ expression string. Falls back to [fallback] on any error. *)
let expand_op_to_cpp ~rng ~a_cpp ~b_cpp ~fallback op_expr =
  match
    Mba_engine.Egraph.expand ~rng ~config:handler_egraph_config op_expr
  with
  | exception _ -> fallback
  | expanded -> expr_to_cpp ~a_cpp ~b_cpp expanded

(** Generate an egraph-saturated C++ expression for [H_ADD_RR]:
    dst ← egraph(a + b) where a = ctx.get_reg(dst), b = ctx.get_reg(src). *)
let egraph_add_rr ~rng =
  expand_op_to_cpp ~rng
    ~a_cpp:"ctx.get_reg(dst)"
    ~b_cpp:"ctx.get_reg(src)"
    ~fallback:"(ctx.get_reg(dst) + ctx.get_reg(src))"
    (Add (Var "a", Var "b"))

(** [H_SUB_RR]: dst ← egraph(a − b) *)
let egraph_sub_rr ~rng =
  expand_op_to_cpp ~rng
    ~a_cpp:"ctx.get_reg(dst)"
    ~b_cpp:"ctx.get_reg(src)"
    ~fallback:"(ctx.get_reg(dst) - ctx.get_reg(src))"
    (Sub (Var "a", Var "b"))

(** [H_XOR_RR]: dst ← egraph(a ^ b) *)
let egraph_xor_rr ~rng =
  expand_op_to_cpp ~rng
    ~a_cpp:"ctx.get_reg(dst)"
    ~b_cpp:"ctx.get_reg(src)"
    ~fallback:"(ctx.get_reg(dst) ^ ctx.get_reg(src))"
    (Xor (Var "a", Var "b"))

(** [H_AND_RR]: dst ← egraph(a & b) *)
let egraph_and_rr ~rng =
  expand_op_to_cpp ~rng
    ~a_cpp:"ctx.get_reg(dst)"
    ~b_cpp:"ctx.get_reg(src)"
    ~fallback:"(ctx.get_reg(dst) & ctx.get_reg(src))"
    (And (Var "a", Var "b"))

(** [H_OR_RR]: dst ← egraph(a | b) *)
let egraph_or_rr ~rng =
  expand_op_to_cpp ~rng
    ~a_cpp:"ctx.get_reg(dst)"
    ~b_cpp:"ctx.get_reg(src)"
    ~fallback:"(ctx.get_reg(dst) | ctx.get_reg(src))"
    (Or (Var "a", Var "b"))
