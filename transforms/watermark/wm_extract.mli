(* ASGARD-5877: Offline Watermark Extractor & Recovery *)

type extraction_match = {
  candidate_payload : int64;
  confidence        : float;
  matching_points   : int;
  total_carrier_pts : int;
  recovered_payload : int64;
}

val evaluate_candidate :
  derivation_key:int64 ->
  candidate_payload:int64 ->
  observed_points:Wm_chooser.carrier_point list ->
  extraction_match

val scan_candidates :
  build_seed:int64 ->
  candidates:int64 list ->
  observed_points:Wm_chooser.carrier_point list ->
  extraction_match option
(** Evaluates candidate licenses/payloads against observed points and returns
    the best matching candidate with confidence score >= 0.70. *)
