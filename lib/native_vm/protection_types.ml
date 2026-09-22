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

(* Single source of truth for the Anti-Pushan rolling-key gate: the encoder
   (vm_emitter) and the C++ runtime emitter (vm_runtime_emitter) must agree on
   it, or the predicted keystream diverges from the runtime one. *)
let rolling_key_enabled (config : t option) : bool =
  match config with
  | Some c -> c.anti_pushan.enabled && c.anti_pushan.running_key
  | None -> true
