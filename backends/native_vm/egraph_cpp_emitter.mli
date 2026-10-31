(** E-Graph Equality Saturation → C++ Handler Expression Emitter (Typed AST). *)

open Cpp_codegen.Cpp_ast

val expr_to_ast :
  a_expr:expr -> b_expr:expr -> Mba_engine.Mba.expr -> expr

val expand_op_to_ast :
  rng:Random.State.t ->
  a_expr:expr ->
  b_expr:expr ->
  fallback:expr ->
  Mba_engine.Mba.expr ->
  expr

val egraph_add_rr_ast : rng:Random.State.t -> expr
val egraph_sub_rr_ast : rng:Random.State.t -> expr
val egraph_xor_rr_ast : rng:Random.State.t -> expr
val egraph_and_rr_ast : rng:Random.State.t -> expr
val egraph_or_rr_ast : rng:Random.State.t -> expr

val expr_to_cpp : a_cpp:string -> b_cpp:string -> Mba_engine.Mba.expr -> string
val expand_op_to_cpp :
  rng:Random.State.t ->
  a_cpp:string ->
  b_cpp:string ->
  fallback:string ->
  Mba_engine.Mba.expr ->
  string

val egraph_add_rr : rng:Random.State.t -> string
val egraph_sub_rr : rng:Random.State.t -> string
val egraph_xor_rr : rng:Random.State.t -> string
val egraph_and_rr : rng:Random.State.t -> string
val egraph_or_rr : rng:Random.State.t -> string
