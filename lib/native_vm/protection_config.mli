(** Protection_config — Unified JSON / Preset configuration for ASGARD-5877 Obfuscator.
    Controls what transformations (CFF, MBA/E-graph, Anti-Pushan, SMC, MEM-SBOM,
    Junk code, Dispatch Domains) are enabled or disabled for a target binary. *)

type mba_engine = [ `Egraph | `Poly | `Ncfg ]

type mba_config = {
  enabled : bool;
  depth : int;
  engine : mba_engine;
}

type cff_config = {
  enabled : bool;
  obfuscate_states : bool;
  inject_opaque_predicates : bool;
}

type anti_pushan_config = {
  enabled : bool;
  running_key : bool;
}

type anti_tamper_config = {
  enabled : bool;
  smc : bool;
  hardware_timing_probes : bool;
  memory_integrity_scanner : bool;
  anti_emulation : bool;
}

type vm_runtime_config = {
  num_dispatch_domains : int;
  enable_junk_instructions : bool;
  enable_super_operators : bool;
  stack_scrambling : bool;
  memory_sanitization : bool;
}

type c_macro_config = {
  enabled : bool;
  obfuscate_strings : bool;
  obfuscate_constants : bool;
  obfuscate_arithmetic : bool;
  nanomites : bool;
}

type t = {
  seed : int option;
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
