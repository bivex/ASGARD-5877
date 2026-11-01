(* ASGARD-5877: Triple Modular Redundancy (TMR) E-graph Synthesis *)

open Mba
open Egraph_extract

type tmr_lane = Lane_arith | Lane_bool | Lane_canonical

let extract_biased ~rng ~lane eg root_id : expr =
  let bias_weight e =
    match domain_of e with
    | Arith -> (match lane with Lane_arith -> 3 | _ -> 0)
    | Bool  -> (match lane with Lane_bool  -> 3 | _ -> 0)
    | Leaf  -> 0
  in
  let (e, _, _) = extract_with_bias ~rng ~bias:bias_weight eg root_id in
  e

let synth_tmr_triplet ~rng eg root_id : expr * expr * expr =
  let e1 = extract_biased ~rng ~lane:Lane_arith eg root_id in
  let e2 = extract_biased ~rng ~lane:Lane_bool  eg root_id in
  let e3, _, _ = extract ~rng eg root_id in
  (e1, e2, e3)

let synth_triplet_from_expr ~rng ?(config = Egraph.default_config) (e : expr) : expr * expr * expr =
  let eg = Egraph_types.create () in
  let root = Egraph_types.add_expr eg e in
  let _ = Egraph.saturate ~rng ~config eg in
  Egraph.rebuild eg;
  synth_tmr_triplet ~rng eg root
