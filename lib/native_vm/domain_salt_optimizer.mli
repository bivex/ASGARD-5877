(* lib/native_vm/domain_salt_optimizer.mli
   ASGARD-5877: Dispatch Table Domain Salt & Permutation Optimizer *)

(** Dispatch Table Domain Salt & Permutation Optimizer:
    Finds domain salt tuples (s_0, ..., s_{K-1}) that minimize opcode
    frequency correlation across dispatch slots, flattening the memory
    access pattern to defeat side-channel and frequency analysis attacks. *)

val default_opcode_frequencies : unit -> float array
(** [default_opcode_frequencies ()] returns standard empirical execution frequencies
    for the 256 opcode byte space (derived from typical x86/ARM code). *)

val calculate_frequency_variance :
  domain_salts:int array ->
  ?frequencies:float array ->
  unit ->
  float
(** [calculate_frequency_variance ~domain_salts ?frequencies ()] evaluates the
    variance of the composite slot access distribution across the 256 dispatch slots.
    Lower variance implies greater resistance to frequency analysis. *)

val optimize_domain_salts :
  rng:Random.State.t ->
  num_domains:int ->
  ?frequencies:float array ->
  ?iterations:int ->
  unit ->
  int array
(** [optimize_domain_salts ~rng ~num_domains ?frequencies ?iterations ()]
    performs simulated annealing / hill climbing over domain salt configurations
    to maximize spectral flatness and pairwise Hamming distance between domains. *)
