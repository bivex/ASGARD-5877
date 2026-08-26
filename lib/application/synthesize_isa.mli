open Random_visa_domain

(** Use case: Synthesize a randomized V-ISA specification under a given profile. *)

val run :
  rng:Random.State.t ->
  ?name:string ->
  ?config:Vector_config.t ->
  ?profile:Generation_profile.t ->
  num_instructions:int ->
  unit ->
  (Vector_isa_spec.t, Errors.t) result
