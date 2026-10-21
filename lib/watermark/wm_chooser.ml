(* ASGARD-5877: Watermark Chooser Hook for E-graph Equality Expansion *)

type carrier_point = {
  function_name   : string;
  call_site_salt  : int64;
  site_tag        : int * int;
  eligible_count  : int;
  chosen_idx      : int;
  payload_bit_idx : int option;
}

type manifest = {
  build_id        : string;
  derivation_key  : int64;
  client_payload  : int64;
  carrier_points  : carrier_point list;
}

let mix_tag (call_site_salt : int64) ((cid, depth) : int * int) : int64 =
  let h_site = Int64.logxor (Int64.shift_left (Int64.of_int cid) 16) (Int64.of_int depth) in
  Wm_embed.splitmix64 (Int64.logxor call_site_salt h_site)

let is_carrier_slot ~(derivation_key : int64) ~(global_tag : int64) ~(carrier_rate : float) : int option =
  let prf = Wm_embed.splitmix64 (Int64.logxor derivation_key global_tag) in
  let threshold = Int64.of_float (carrier_rate *. 65536.0) in
  let sample = Int64.logand prf 0xFFFFL in
  if sample < threshold then
    let bit_idx = Int64.to_int (Int64.logand (Int64.shift_right_logical prf 16) 0x3FL) mod 48 in
    Some bit_idx
  else None

let balanced_split ~(key : int64) (eligible_count : int) : int array * int array =
  let z_list, o_list = Wm_embed.balanced_split ~key eligible_count in
  (Array.of_list z_list, Array.of_list o_list)

let make
    ~(derivation_key : int64)
    ~(client_payload : int64)
    ~(call_site_salt : int64)
    ~(function_name : string)
    ~(entropy_rng : Random.State.t)
    ?(carrier_rate = 0.35)
    ?recorded_points
    () : Mba_engine.Egraph_extract.chooser =
  fun ~eligible_count ~site_tag ->
    if eligible_count <= 1 then 0
    else
      let global_tag = mix_tag call_site_salt site_tag in
      match is_carrier_slot ~derivation_key ~global_tag ~carrier_rate with
      | None ->
          let idx = Random.State.int entropy_rng eligible_count in
          (match recorded_points with
          | Some r ->
              r := {
                function_name;
                call_site_salt;
                site_tag;
                eligible_count;
                chosen_idx = idx;
                payload_bit_idx = None;
              } :: !r
          | None -> ());
          idx
      | Some payload_bit_idx ->
          let bit = Wm_embed.get_bit client_payload payload_bit_idx in
          let key = Int64.logxor derivation_key global_tag in
          let pool_zeros, pool_ones = balanced_split ~key eligible_count in
          let pool = if bit then pool_ones else pool_zeros in
          let selected = pool.(Random.State.int entropy_rng (Array.length pool)) in
          (match recorded_points with
          | Some r ->
              r := {
                function_name;
                call_site_salt;
                site_tag;
                eligible_count;
                chosen_idx = selected;
                payload_bit_idx = Some payload_bit_idx;
              } :: !r
          | None -> ());
          selected

let carrier_point_to_json (cp : carrier_point) : Yojson.Safe.t =
  let (cid, depth) = cp.site_tag in
  `Assoc [
    ("function_name", `String cp.function_name);
    ("call_site_salt", `String (Printf.sprintf "0x%016LX" cp.call_site_salt));
    ("site_tag", `List [ `Int cid; `Int depth ]);
    ("eligible_count", `Int cp.eligible_count);
    ("chosen_idx", `Int cp.chosen_idx);
    ("payload_bit_idx", match cp.payload_bit_idx with Some b -> `Int b | None -> `Null);
  ]

let carrier_point_of_json = function
  | `Assoc fields ->
      let fn = List.assoc_opt "function_name" fields in
      let salt = List.assoc_opt "call_site_salt" fields in
      let stag = List.assoc_opt "site_tag" fields in
      let elig = List.assoc_opt "eligible_count" fields in
      let chosen = List.assoc_opt "chosen_idx" fields in
      let bit = List.assoc_opt "payload_bit_idx" fields in
      (match (fn, salt, stag, elig, chosen) with
      | (Some (`String fn_name), Some (`String salt_str), Some (`List [ `Int cid; `Int depth ]), Some (`Int el), Some (`Int ch)) ->
          let salt_val = Int64.of_string salt_str in
          let bit_val = match bit with Some (`Int b) -> Some b | _ -> None in
          Ok {
            function_name = fn_name;
            call_site_salt = salt_val;
            site_tag = (cid, depth);
            eligible_count = el;
            chosen_idx = ch;
            payload_bit_idx = bit_val;
          }
      | _ -> Error "Invalid carrier_point json")
  | _ -> Error "carrier_point not an object"

let manifest_to_json (m : manifest) : Yojson.Safe.t =
  `Assoc [
    ("build_id", `String m.build_id);
    ("derivation_key", `String (Printf.sprintf "0x%016LX" m.derivation_key));
    ("client_payload", `String (Printf.sprintf "0x%016LX" m.client_payload));
    ("carrier_points", `List (List.map carrier_point_to_json m.carrier_points));
  ]

let manifest_of_json = function
  | `Assoc fields ->
      let bid = List.assoc_opt "build_id" fields in
      let dkey = List.assoc_opt "derivation_key" fields in
      let cpay = List.assoc_opt "client_payload" fields in
      let pts = List.assoc_opt "carrier_points" fields in
      (match (bid, dkey, cpay, pts) with
      | (Some (`String build_id), Some (`String dk_str), Some (`String cp_str), Some (`List pt_list)) ->
          let dk = Int64.of_string dk_str in
          let cp = Int64.of_string cp_str in
          let parsed_pts = ref [] in
          let has_err = ref None in
          List.iter
            (fun j ->
              match carrier_point_of_json j with
              | Ok p -> parsed_pts := p :: !parsed_pts
              | Error e -> has_err := Some e)
            pt_list;
          (match !has_err with
          | Some e -> Error e
          | None ->
              Ok {
                build_id;
                derivation_key = dk;
                client_payload = cp;
                carrier_points = List.rev !parsed_pts;
              })
      | _ -> Error "Invalid manifest json")
  | _ -> Error "manifest not an object"

let save_manifest (path : string) (m : manifest) : unit =
  let j = manifest_to_json m in
  Yojson.Safe.to_file path j

let load_manifest (path : string) : (manifest, string) result =
  try
    let j = Yojson.Safe.from_file path in
    manifest_of_json j
  with exn -> Error (Printexc.to_string exn)
