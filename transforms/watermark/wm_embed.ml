(* ASGARD-5877: Watermark Embedding with SplitMix64 Group Partitioning & Repetition ECC *)

open Wm_types

type embedder = {
  scheme        : wm_scheme;
  watermark     : watermark_id;
  mutable point_idx : int;
  rng           : Random.State.t;
}

let splitmix64 (x : int64) : int64 =
  let z = Int64.add x (-0x61C8864680B583EBL) in (* 0x9E3779B97F4A7C15L *)
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30)) (-0x40A7B892E31B1A47L) in (* 0xBF58476D1CE4E5B9L *)
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27)) (-0x6B2F5644ECCEEE15L) in (* 0x94D049BB133111EBL *)
  Int64.logxor z (Int64.shift_right_logical z 31)

let get_bit (payload : int64) (bit_idx : int) : bool =
  let shift = bit_idx mod 64 in
  Int64.logand (Int64.shift_right_logical payload shift) 1L = 1L

let balanced_split ~(key : int64) (eligible_count : int) : int list * int list =
  if eligible_count <= 1 then ([ 0 ], [ 0 ])
  else
    let zeros = ref [] in
    let ones = ref [] in
    for i = 0 to eligible_count - 1 do
      let h = splitmix64 (Int64.logxor key (Int64.mul (Int64.of_int i) (-0x61C8864680B583EBL))) in
      if Int64.logand h 1L = 0L then zeros := i :: !zeros
      else ones := i :: !ones
    done;
    let z = List.rev !zeros in
    let o = List.rev !ones in
    match (z, o) with
    | ([], all_ones) -> ([ List.hd all_ones ], List.tl all_ones)
    | (all_zeros, []) -> (List.tl all_zeros, [ List.hd all_zeros ])
    | (z_list, o_list) -> (z_list, o_list)

let partition_choices ~(parity_salt : int64) (choices : 'a list) : 'a list * 'a list =
  let n = List.length choices in
  let arr = Array.of_list choices in
  let zeros_idx, ones_idx = balanced_split ~key:parity_salt n in
  let zeros = List.map (fun i -> arr.(i)) zeros_idx in
  let ones = List.map (fun i -> arr.(i)) ones_idx in
  (zeros, ones)

let create_embedder ?(scheme = default_scheme) ~(watermark : watermark_id) ~(rng : Random.State.t) () : embedder =
  {
    scheme;
    watermark;
    point_idx = 0;
    rng;
  }

let embed_index ~(embedder : embedder) ~(num_choices : int) : int =
  if num_choices <= 1 then 0
  else
    let p = embedder.point_idx in
    embedder.point_idx <- p + 1;
    let bit_idx = (p / embedder.scheme.redundancy) mod embedder.scheme.payload_bits in
    let target_bit = get_bit embedder.watermark.raw_bits bit_idx in
    let point_salt = splitmix64 (Int64.add embedder.watermark.derivation_key (Int64.of_int p)) in
    let zeros_idx, ones_idx = balanced_split ~key:point_salt num_choices in
    let pool = if target_bit then ones_idx else zeros_idx in
    let pick_sub_idx = Random.State.int embedder.rng (List.length pool) in
    List.nth pool pick_sub_idx

let embed_choice ~(embedder : embedder) ~(choices : 'a list) : 'a =
  let n = List.length choices in
  if n <= 1 then List.hd choices
  else
    let idx = embed_index ~embedder ~num_choices:n in
    List.nth choices idx

type extracted_result = {
  recovered_payload : int64;
  confidence        : float;
  points_observed   : int;
  matching_candidate: bool;
}

let extract_from_choices
    ~(scheme : wm_scheme)
    ~(derivation_key : int64)
    ~(candidate_payload : int64)
    ~(observed_choices : (int * int) list) : extracted_result =
  let votes_ones = Array.make scheme.payload_bits 0 in
  let votes_zeros = Array.make scheme.payload_bits 0 in
  let total_votes = ref 0 in
  let matching_votes = ref 0 in

  List.iteri
    (fun p (num_choices, chosen_idx) ->
      if num_choices > 1 then begin
        let bit_idx = (p / scheme.redundancy) mod scheme.payload_bits in
        let point_salt = splitmix64 (Int64.add derivation_key (Int64.of_int p)) in
        let zeros_idx, ones_idx = balanced_split ~key:point_salt num_choices in
        let vote_is_one = List.mem chosen_idx ones_idx in
        let vote_is_zero = List.mem chosen_idx zeros_idx in
        if vote_is_one && not vote_is_zero then begin
          votes_ones.(bit_idx) <- votes_ones.(bit_idx) + 1;
          incr total_votes;
          let expected_bit = get_bit candidate_payload bit_idx in
          if expected_bit then incr matching_votes
        end else if vote_is_zero && not vote_is_one then begin
          votes_zeros.(bit_idx) <- votes_zeros.(bit_idx) + 1;
          incr total_votes;
          let expected_bit = get_bit candidate_payload bit_idx in
          if not expected_bit then incr matching_votes
        end
      end)
    observed_choices;

  let recovered = ref 0L in
  let agreement_count = ref 0 in
  for b = 0 to scheme.payload_bits - 1 do
    let o = votes_ones.(b) in
    let z = votes_zeros.(b) in
    let bit_val = o > z in
    if bit_val then
      recovered := Int64.logor !recovered (Int64.shift_left 1L b);
    agreement_count := !agreement_count + max o z
  done;

  let confidence =
    if !total_votes = 0 then 0.0
    else float_of_int !matching_votes /. float_of_int !total_votes
  in
  let matching = !recovered = candidate_payload && confidence >= 0.70 in
  {
    recovered_payload = !recovered;
    confidence;
    points_observed = !total_votes;
    matching_candidate = matching;
  }
