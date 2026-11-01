(* ASGARD-5877: E-graph Equality Expansion Extraction & Chooser Hook *)

open Mba

type chooser = eligible_count:int -> site_tag:(int * int) -> int

val pure_rng_chooser : Random.State.t -> chooser

type domain = Arith | Bool | Leaf
val domain_of : expr -> domain

type extracted = expr * int * int

val ast_size : expr -> int
val op_count : expr -> int
val alternation : expr -> int

val extract :
  ?chooser:chooser ->
  ?bias:(expr -> int) ->
  rng:Random.State.t ->
  ?max_depth:int ->
  Egraph_types.t ->
  int ->
  extracted

val extract_with_bias :
  rng:Random.State.t ->
  bias:(expr -> int) ->
  ?chooser:chooser ->
  ?max_depth:int ->
  Egraph_types.t ->
  int ->
  extracted
