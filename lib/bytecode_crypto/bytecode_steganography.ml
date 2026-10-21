(** Steganographic Bytecode Storage Engine.
    Distributes authenticated bytecode words across pre-existing innocuous
    carriers (Nullspace MBA zero-coefficients, Ghost padding junk immediates,
    Chameleon jitter noise constants) rather than a single contiguous signature-bearing blob. *)

type carrier_kind =
  | NullspaceCoeff of int
  | GhostImm of int
  | JitterConst of int

type carrier_site = {
  kind : carrier_kind;
  bit_offset : int;
  bit_width : int;
}

type stego_plan = {
  sites_per_word : carrier_site list array;
  extraction_key : int64;
}

let default_fragments_per_word = 6
let default_fragment_width = 11 (* 6 * 11 = 66 >= 64 bits *)

let embed_word
    ~(rng : Random.State.t)
    ~(carriers_available : carrier_kind array)
    (word : int64) : carrier_site list * (carrier_kind * int64) list =
  let k = default_fragments_per_word in
  let frag_w = default_fragment_width in
  let num_carriers = Array.length carriers_available in
  if num_carriers = 0 then
    failwith "embed_word: no carriers available for steganographic embedding";
  let pool = Array.copy carriers_available in
  let pool_len = Array.length pool in
  let shuffle_len = Stdlib.min k pool_len in
  for i = 0 to shuffle_len - 1 do
    let j = i + Random.State.int rng (pool_len - i) in
    let tmp = pool.(i) in
    pool.(i) <- pool.(j);
    pool.(j) <- tmp
  done;
  let sites = ref [] in
  let patched = ref [] in
  for i = 0 to k - 1 do
    let carrier = pool.(i mod pool_len) in
    let bit_off = i * frag_w in
    let eff_width = if bit_off + frag_w > 64 then 64 - bit_off else frag_w in
    if eff_width > 0 then begin
      let mask =
        if eff_width >= 64 then -1L
        else Int64.sub (Int64.shift_left 1L eff_width) 1L
      in
      let frag = Int64.logand (Int64.shift_right_logical word bit_off) mask in
      sites := { kind = carrier; bit_offset = bit_off; bit_width = eff_width } :: !sites;
      patched := (carrier, frag) :: !patched
    end
  done;
  (List.rev !sites, List.rev !patched)

let extract_word
    ~(carrier_values : carrier_kind -> int64)
    (sites : carrier_site list) : int64 =
  List.fold_left (fun acc site ->
    let raw_val = carrier_values site.kind in
    let mask =
      if site.bit_width >= 64 then -1L
      else Int64.sub (Int64.shift_left 1L site.bit_width) 1L
    in
    let frag = Int64.logand raw_val mask in
    Int64.logor acc (Int64.shift_left frag site.bit_offset)
  ) 0L sites

let embed_bytecode
    ~(rng : Random.State.t)
    ~(extraction_key : int64)
    ~(carriers_available : carrier_kind array)
    (code_words : int64 list) : stego_plan * (carrier_kind * int64) list =
  let total_words = List.length code_words in
  let k = default_fragments_per_word in
  let sites_array = Array.make total_words [] in
  let all_patches = ref [] in
  let total_carriers = Array.length carriers_available in
  List.iteri (fun idx w ->
    let word_carriers =
      if total_carriers >= total_words * k then
        Array.sub carriers_available (idx * k) k
      else
        carriers_available
    in
    let (sites, patches) = embed_word ~rng ~carriers_available:word_carriers w in
    sites_array.(idx) <- sites;
    all_patches := List.rev_append patches !all_patches
  ) code_words;
  let plan = {
    sites_per_word = sites_array;
    extraction_key;
  } in
  (plan, List.rev !all_patches)

let extract_bytecode
    ~(carrier_values : carrier_kind -> int64)
    (plan : stego_plan) : int64 list =
  let total_words = Array.length plan.sites_per_word in
  let result = ref [] in
  for idx = 0 to total_words - 1 do
    let sites = plan.sites_per_word.(idx) in
    let w = extract_word ~carrier_values sites in
    result := w :: !result
  done;
  List.rev !result

let embed_into_nullspace_zero
    ~(rng : Random.State.t)
    ~(terms_count : int)
    ~(fragment : int64)
    ~(bit_width : int) : Mba_engine.Nullspace_mba.minterm_term list * int =
  let terms = Mba_engine.Nullspace_mba.synth_minterm_zero ~rng ~terms_count:(Stdlib.max terms_count 4) in
  (* Term table representation: bfunc_id -> coeff *)
  let term_table = Hashtbl.create 16 in
  List.iter (fun (t : Mba_engine.Nullspace_mba.minterm_term) ->
    Hashtbl.replace term_table t.bfunc_id t.coeff
  ) terms;

  (* Pick a candidate term with non-trivial boolean function not in pure basis {1, 2, 4, 8} *)
  let candidates =
    List.filter (fun (t : Mba_engine.Nullspace_mba.minterm_term) ->
      t.bfunc_id <> 1 && t.bfunc_id <> 2 && t.bfunc_id <> 4 && t.bfunc_id <> 8 && t.bfunc_id <> 0 && t.bfunc_id <> 15
    ) terms
  in
  let target_id, c_orig =
    match candidates with
    | t :: _ -> (t.bfunc_id, t.coeff)
    | [] ->
        (* Fallback: add a fresh non-basis term (e.g. id=6: XOR) with random coeff *)
        let code = 6 in
        let r = Int64.logor (Random.State.int64 rng Int64.max_int) 1L in
        Hashtbl.replace term_table code r;
        (* Subtract from basis according to truth table of XOR (0, 1, 1, 0 -> v10=1, v01=1) *)
        let cur2 = Option.value ~default:0L (Hashtbl.find_opt term_table 2) in
        let cur4 = Option.value ~default:0L (Hashtbl.find_opt term_table 4) in
        Hashtbl.replace term_table 2 (Int64.sub cur2 r);
        Hashtbl.replace term_table 4 (Int64.sub cur4 r);
        (code, r)
  in

  let mask =
    if bit_width >= 64 then -1L
    else Int64.sub (Int64.shift_left 1L bit_width) 1L
  in
  let clean_frag = Int64.logand fragment mask in
  let c_patched = Int64.logor (Int64.logand c_orig (Int64.lognot mask)) clean_frag in
  let delta = Int64.sub c_patched c_orig in
  Hashtbl.replace term_table target_id c_patched;

  (* Compensate delta on orthogonal minterms e1 (8), e2 (4), e3 (2), e4 (1) *)
  let v00 = target_id land 1 in
  let v01 = (target_id lsr 1) land 1 in
  let v10 = (target_id lsr 2) land 1 in
  let v11 = (target_id lsr 3) land 1 in

  let adjust_basis basis_id flag =
    if flag <> 0 then begin
      let prev = Option.value ~default:0L (Hashtbl.find_opt term_table basis_id) in
      Hashtbl.replace term_table basis_id (Int64.sub prev delta)
    end
  in
  adjust_basis 8 v11;
  adjust_basis 4 v10;
  adjust_basis 2 v01;
  adjust_basis 1 v00;

  let final_terms =
    Hashtbl.fold (fun id coeff acc ->
      if coeff <> 0L then { Mba_engine.Nullspace_mba.bfunc_id = id; coeff } :: acc
      else acc
    ) term_table []
  in
  (* Verify that the compensated expression is still identically zero *)
  assert (Mba_engine.Nullspace_mba.verify_minterm_zero final_terms);
  (final_terms, target_id)
