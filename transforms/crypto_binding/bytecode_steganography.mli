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

val default_fragments_per_word : int
val default_fragment_width : int

val embed_word :
  rng:Random.State.t ->
  carriers_available:carrier_kind array ->
  int64 ->
  carrier_site list * (carrier_kind * int64) list

val extract_word :
  carrier_values:(carrier_kind -> int64) ->
  carrier_site list ->
  int64

val embed_bytecode :
  rng:Random.State.t ->
  extraction_key:int64 ->
  carriers_available:carrier_kind array ->
  int64 list ->
  stego_plan * (carrier_kind * int64) list

val extract_bytecode :
  carrier_values:(carrier_kind -> int64) ->
  stego_plan ->
  int64 list

val embed_into_nullspace_zero :
  rng:Random.State.t ->
  terms_count:int ->
  fragment:int64 ->
  bit_width:int ->
  Mba_engine.Nullspace_mba.minterm_term list * int
