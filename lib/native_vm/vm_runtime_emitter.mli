(** Vm_runtime_emitter — Emission of Native Threaded VM C++ runtime and runners using Jingoo templates. *)

module Runtime_policy : sig
  type t = {
    num_domains : int;
    enable_smc : bool;
    enable_smc_strict : bool;
    enable_anti_emu : bool;
    enable_mem_scan : bool;
    enable_timing_probes : bool;
    enable_nanomites : bool;
    enable_direct_syscalls : bool;
    enable_running_key : bool;
    enable_address_bound : bool;
    enable_stack_scramble : bool;
    enable_mem_sanitize : bool;
    enable_vector_isa : bool;
    enable_egraph_expansion : bool;
    enable_ephemeral_jit : bool;
  }

  val of_config : ?runtime_profile:Random_visa_domain.Vm_runtime_profile.t -> Protection_config.t option -> t
  val to_models : t -> (string * Jingoo.Jg_types.tvalue) list
end

val generate_wbox_seed_derivation :
  rng:Random.State.t ->
  int32 ->
  string

val emit_external_symbols_table_ast :
  string list ->
  Cpp_codegen.Cpp_ast.top_decl

val emit_constants_tables_ast :
  rng:Random.State.t ->
  (string * string) list ->
  Cpp_codegen.Cpp_ast.top_decl list

val emit_block_spans_tables_ast :
  (int * int) list ->
  Cpp_codegen.Cpp_ast.top_decl list

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

val emit_native_runner_main_def : unit -> Cpp_codegen.Cpp_ast.top_decl

val emit_runner_cpp :
  ?key_seed:int64 ->
  reg_perm:int array ->
  int64 list ->
  string
