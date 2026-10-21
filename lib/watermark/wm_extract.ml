(* ASGARD-5877: Offline Watermark Extractor & Recovery *)

type extraction_match = {
  candidate_payload : int64;
  confidence        : float;
  matching_points   : int;
  total_carrier_pts : int;
  recovered_payload : int64;
}

let evaluate_candidate
    ~(derivation_key : int64)
    ~(candidate_payload : int64)
    ~(observed_points : Wm_chooser.carrier_point list) : extraction_match =
  let votes_ones = Array.make 48 0 in
  let votes_zeros = Array.make 48 0 in
  let total_carrier_pts = ref 0 in
  let matching_points = ref 0 in

  List.iter
    (fun (p : Wm_chooser.carrier_point) ->
      if p.eligible_count > 1 then begin
        let global_tag = Wm_chooser.mix_tag p.call_site_salt p.site_tag in
        match Wm_chooser.is_carrier_slot ~derivation_key ~global_tag ~carrier_rate:0.35 with
        | Some bit_idx ->
            incr total_carrier_pts;
            let key = Int64.logxor derivation_key global_tag in
            let pool_zeros, pool_ones = Wm_chooser.balanced_split ~key p.eligible_count in
            let is_one = Array.mem p.chosen_idx pool_ones in
            let is_zero = Array.mem p.chosen_idx pool_zeros in
            let expected_bit = Wm_embed.get_bit candidate_payload bit_idx in
            if is_one && not is_zero then begin
              votes_ones.(bit_idx) <- votes_ones.(bit_idx) + 1;
              if expected_bit then incr matching_points
            end else if is_zero && not is_one then begin
              votes_zeros.(bit_idx) <- votes_zeros.(bit_idx) + 1;
              if not expected_bit then incr matching_points
            end
        | None -> ()
      end)
    observed_points;

  let recovered = ref 0L in
  for b = 0 to 47 do
    let o = votes_ones.(b) in
    let z = votes_zeros.(b) in
    if o >= z && (o > 0 || z > 0) then
      recovered := Int64.logor !recovered (Int64.shift_left 1L b)
  done;

  let confidence =
    if !total_carrier_pts = 0 then 0.0
    else float_of_int !matching_points /. float_of_int !total_carrier_pts
  in
  {
    candidate_payload;
    confidence;
    matching_points = !matching_points;
    total_carrier_pts = !total_carrier_pts;
    recovered_payload = !recovered;
  }

let scan_candidates
    ~(build_seed : int64)
    ~(candidates : int64 list)
    ~(observed_points : Wm_chooser.carrier_point list) : extraction_match option =
  let scored =
    List.map
      (fun cand ->
        let wm_id = Wm_types.derive ~build_seed ~client_payload:cand in
        evaluate_candidate
          ~derivation_key:wm_id.derivation_key
          ~candidate_payload:cand
          ~observed_points)
      candidates
  in
  let sorted = List.sort (fun a b -> Float.compare b.confidence a.confidence) scored in
  match sorted with
  | best :: _ when best.confidence >= 0.70 && best.total_carrier_pts >= 10 ->
      Some best
  | _ -> None
