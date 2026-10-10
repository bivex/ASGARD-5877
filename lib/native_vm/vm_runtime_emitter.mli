(** Vm_runtime_emitter — Emission of Native Threaded VM C++ runtime and runners using Jingoo templates. *)

val generate_wbox_seed_derivation :
  rng:Random.State.t ->
  int32 ->
  string

val emit_cpp_threaded_header :
  rng:Random.State.t ->
  key_seed:int32 ->
  reg_perm:int array ->
  expected_hash:int64 ->
  ?expected_hashes:int64 list ->
  ?runtime_profile:Random_visa_domain.Vm_runtime_profile.t ->
  ?config:Protection_config.t ->
  ?external_symbols:string list ->
  ?constants:(string * string) list ->
  ?block_spans:(int * int) list ->
  ?gpu_matrix:Gpu_synth.Gpu_matrix.substitution_matrix ->
  string array ->
  string

val emit_runner_cpp :
  ?key_seed:int64 ->
  reg_perm:int array ->
  int64 list ->
  string
