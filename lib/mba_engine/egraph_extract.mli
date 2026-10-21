(* ASGARD-5877: E-graph Equality Expansion Extraction & Chooser Hook *)

open Mba

type chooser = eligible_count:int -> site_tag:(int * int) -> int

val pure_rng_chooser : Random.State.t -> chooser

type extracted = expr * int * int

val ast_size : expr -> int
val op_count : expr -> int
val alternation : expr -> int

val extract :
  ?chooser:chooser ->
  rng:Random.State.t ->
  ?max_depth:int ->
  Egraph_types.t ->
  int ->
  extracted
