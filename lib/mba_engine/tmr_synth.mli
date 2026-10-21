(* ASGARD-5877: Triple Modular Redundancy (TMR) E-graph Synthesis *)

open Mba

type tmr_lane = Lane_arith | Lane_bool | Lane_canonical

val extract_biased :
  rng:Random.State.t ->
  lane:tmr_lane ->
  Egraph_types.t ->
  int ->
  expr

val synth_tmr_triplet :
  rng:Random.State.t ->
  Egraph_types.t ->
  int ->
  expr * expr * expr

val synth_triplet_from_expr :
  rng:Random.State.t ->
  ?config:Egraph.config ->
  expr ->
  expr * expr * expr
