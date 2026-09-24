(** Protection_config — Unified JSON / Preset configuration for ASGARD-5877 Obfuscator.
    Controls what transformations (CFF, MBA/E-graph, Anti-Pushan, SMC, MEM-SBOM,
    Junk code, Dispatch Domains) are enabled or disabled for a target binary. *)

type mba_engine = [ `Egraph | `Poly | `Ncfg ]

type mba_config = {
  enabled : bool;
  depth : int;
  engine : mba_engine;
}

type crypto_config = {
  rounds : int;
  key_bits : int;
}

type bloat_mode = [ `Compact | `Balanced | `Heavy | `Insane ]

type bloat_config = {
  mode : bloat_mode;
  target_size_budget_kb : int option;
  junk_density : float;
}

type cff_config = {
  enabled : bool;
  obfuscate_states : bool;
  inject_opaque_predicates : bool;
}

type anti_pushan_config = {
  enabled : bool;
  running_key : bool;
  address_bound : bool;
}

type anti_tamper_config = {
  enabled : bool;
  smc : bool;
  smc_strict : bool;
  hardware_timing_probes : bool;
  memory_integrity_scanner : bool;
  anti_emulation : bool;
  nanomites : bool;
  direct_syscalls : bool;
}

type vm_runtime_config = {
  num_dispatch_domains : int;
  enable_junk_instructions : bool;
  enable_super_operators : bool;
  stack_scrambling : bool;
  memory_sanitization : bool;
  vector_isa : bool;
  egraph_expansion : bool;
  ephemeral_jit : bool;
}

type c_macro_config = {
  enabled : bool;
  macro_prefix : string;
  obfuscate_strings : bool;
  obfuscate_constants : bool;
  obfuscate_arithmetic : bool;
  opaque_predicates : bool;
  api_hashing : bool;
  anti_debug : bool;
  signal_dispatch : bool;
  nanomites : bool;
  timing_guard : bool;
  timing_threshold_ticks : int64;
}

type t = {
  seed : int option;
  crypto : crypto_config;
  bloat : bloat_config;
  cff : cff_config;
  mba : mba_config;
  anti_pushan : anti_pushan_config;
  anti_tamper : anti_tamper_config;
  vm_runtime : vm_runtime_config;
  c_macro : c_macro_config;
}

val minimal : t
val lightweight : t
val default : t
val high : t
val max_security : t
val stealth : t

val from_preset : string -> (t, string) result

val from_json_string : string -> (t, string) result

val from_file : string -> (t, string) result

val to_json_string : ?pretty:bool -> t -> string

val save_to_file : string -> t -> unit

val rolling_key_enabled : t option -> bool
(** Anti-Pushan block-chained rolling key gate: [true] unless a config explicitly
    disables it.  Re-exported from [Protection_types] so the encoder and the C++
    runtime emitter share one source of truth for the keystream. *)

val address_bound_enabled : t option -> bool
(** Anti-VMPredator address-bound bytecode gate: [true] when running_key and address_bound
    are both enabled. Binds bytecode decryption to runtime handler addresses. *)

val ephemeral_jit_enabled : t option -> bool
(** Ephemeral polymorphic JIT gate: [true] when runtime ephemeral JIT code synthesis
    is enabled in vm_runtime. *)

type builder
(** Mutable builder for [Protection_config.t]. *)

val create_builder : ?base:t -> unit -> builder
val with_cff : bool -> builder -> builder
val with_mba : ?depth:int -> bool -> builder -> builder
val with_seed : int option -> builder -> builder
val build : builder -> t
