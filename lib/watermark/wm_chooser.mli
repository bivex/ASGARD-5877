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

val mix_tag : int64 -> int * int -> int64

val is_carrier_slot :
  derivation_key:int64 ->
  global_tag:int64 ->
  carrier_rate:float ->
  int option

val balanced_split :
  key:int64 ->
  int ->
  int array * int array

val make :
  derivation_key:int64 ->
  client_payload:int64 ->
  call_site_salt:int64 ->
  function_name:string ->
  entropy_rng:Random.State.t ->
  ?carrier_rate:float ->
  ?recorded_points:carrier_point list ref ->
  unit ->
  Mba_engine.Egraph_extract.chooser

val manifest_to_json : manifest -> Yojson.Safe.t
val manifest_of_json : Yojson.Safe.t -> (manifest, string) result
val save_manifest : string -> manifest -> unit
val load_manifest : string -> (manifest, string) result
