(* ASGARD-5877: Watermark Embedding with SplitMix64 Group Partitioning & Repetition ECC *)

open Wm_types

type embedder = {
  scheme        : wm_scheme;
  watermark     : watermark_id;
  mutable point_idx : int;
  rng           : Random.State.t;
}

val splitmix64 : int64 -> int64

val get_bit : int64 -> int -> bool

val balanced_split :
  key:int64 ->
  int ->
  int list * int list
(** Partitions [0 .. count-1] into (zeros_group, ones_group) using SplitMix64.
    Guarantees both groups are non-empty whenever [count >= 2]. *)

val partition_choices :
  parity_salt:int64 ->
  'a list ->
  ('a list * 'a list)

val create_embedder :
  ?scheme:wm_scheme ->
  watermark:watermark_id ->
  rng:Random.State.t ->
  unit ->
  embedder

val embed_choice :
  embedder:embedder ->
  choices:'a list ->
  'a

val embed_index :
  embedder:embedder ->
  num_choices:int ->
  int

type extracted_result = {
  recovered_payload : int64;
  confidence        : float;
  points_observed   : int;
  matching_candidate: bool;
}

val extract_from_choices :
  scheme:wm_scheme ->
  derivation_key:int64 ->
  candidate_payload:int64 ->
  observed_choices:(int * int) list ->
  extracted_result
