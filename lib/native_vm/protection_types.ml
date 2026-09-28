let int64_of_yojson = function
  | `Int i -> Ok (Int64.of_int i)
  | `Intlit s -> (match Int64.of_string_opt s with Some v -> Ok v | None -> Error "invalid int64 literal")
  | `String s -> (match Int64.of_string_opt s with Some v -> Ok v | None -> Error "invalid int64 string")
  | _ -> Error "Expected int or string for int64"

let int64_to_yojson i = `String (Int64.to_string i)

let float_of_yojson = function
  | `Float f -> Ok f
  | `Int i -> Ok (float_of_int i)
  | `Intlit s -> (match float_of_string_opt s with Some v -> Ok v | None -> Error "invalid float literal")
  | `String s -> (match float_of_string_opt s with Some v -> Ok v | None -> Error "invalid float string")
  | _ -> Error "Expected float"

let float_to_yojson f = `Float f

type mba_engine = [ `Egraph | `Poly | `Ncfg | `Gpu_metal ]

let mba_engine_of_yojson = function
  | `String s -> (
      match String.lowercase_ascii (String.trim s) with
      | "egraph" | "e-graph" | "scrambler" -> Ok `Egraph
      | "ncfg" -> Ok `Ncfg
      | "gpu" | "gpu_metal" | "metal" -> Ok `Gpu_metal
      | "poly" | "polynomial" | _ -> Ok `Poly)
  | _ -> Error "Expected string for mba_engine"

let mba_engine_to_yojson = function
  | `Egraph -> `String "egraph"
  | `Poly -> `String "poly"
  | `Ncfg -> `String "ncfg"
  | `Gpu_metal -> `String "gpu_metal"

type mba_config = {
  enabled : bool [@default true];
  depth : int [@default 2];
  engine : (mba_engine [@of_yojson mba_engine_of_yojson] [@to_yojson mba_engine_to_yojson]) [@default `Egraph];
} [@@deriving yojson]

type crypto_config = {
  rounds : int [@default 16];
  key_bits : int [@default 128];
} [@@deriving yojson]

type bloat_mode = [ `Compact | `Balanced | `Heavy | `Insane ]

let bloat_mode_of_yojson = function
  | `String s -> (
      match String.lowercase_ascii (String.trim s) with
      | "compact" | "min" | "low" -> Ok `Compact
      | "heavy" | "high" -> Ok `Heavy
      | "insane" | "max" -> Ok `Insane
      | "balanced" | _ -> Ok `Balanced)
  | _ -> Error "Expected string for bloat_mode"

let bloat_mode_to_yojson = function
  | `Compact -> `String "compact"
  | `Balanced -> `String "balanced"
  | `Heavy -> `String "heavy"
  | `Insane -> `String "insane"

type bloat_config = {
  mode : (bloat_mode [@of_yojson bloat_mode_of_yojson] [@to_yojson bloat_mode_to_yojson]) [@default `Balanced];
  target_size_budget_kb : int option [@default Some 1000];
  junk_density : (float [@of_yojson float_of_yojson] [@to_yojson float_to_yojson]) [@default 0.5];
} [@@deriving yojson]

type cff_config = {
  enabled : bool [@default true];
  obfuscate_states : bool [@default true];
  inject_opaque_predicates : bool [@default false];
} [@@deriving yojson]

type anti_pushan_config = {
  enabled : bool [@default true];
  running_key : bool [@default true];
  address_bound : bool [@default false];
} [@@deriving yojson]

type anti_tamper_config = {
  enabled : bool [@default true];
  smc : bool [@default true];
  smc_strict : bool [@default false];
  hardware_timing_probes : bool [@default true];
  memory_integrity_scanner : bool [@default true];
  anti_emulation : bool [@default true];
  nanomites : bool [@default true];
  direct_syscalls : bool [@default true];
} [@@deriving yojson]

type vm_runtime_config = {
  num_dispatch_domains : int [@default 4];
  enable_junk_instructions : bool [@default true];
  enable_super_operators : bool [@default true];
  stack_scrambling : bool [@default true];
  memory_sanitization : bool [@default true];
  vector_isa : bool [@default true];
  egraph_expansion : bool [@default true];
  ephemeral_jit : bool [@default false];
} [@@deriving yojson]

type c_macro_config = {
  enabled : bool [@default true];
  macro_prefix : string [@default "ASG_"];
  obfuscate_strings : bool [@default true];
  obfuscate_constants : bool [@default true];
  obfuscate_arithmetic : bool [@default true];
  opaque_predicates : bool [@default true];
  api_hashing : bool [@default true];
  anti_debug : bool [@default true];
  signal_dispatch : bool [@default false];
  nanomites : bool [@default false];
  timing_guard : bool [@default true];
  timing_threshold_ticks : (int64 [@of_yojson int64_of_yojson] [@to_yojson int64_to_yojson]) [@default 50000000L];
} [@@deriving yojson]

type stack_vm_config = {
  enabled : bool [@default true];
  superoperators : bool [@default true];
  state_feedback : bool [@default true];
  layout_randomization : bool [@default true];
  runtime_hardening : bool [@default true];
  compact_imm : bool [@default true];
} [@@deriving yojson]

let default_crypto = { rounds = 16; key_bits = 128 }
let default_bloat = { mode = `Balanced; target_size_budget_kb = Some 1000; junk_density = 0.5 }
let default_cff = { enabled = true; obfuscate_states = true; inject_opaque_predicates = false }
let default_mba = { enabled = true; depth = 2; engine = `Egraph }
let default_anti_pushan = { enabled = true; running_key = true; address_bound = false }
let default_anti_tamper = {
  enabled = true; smc = true; smc_strict = false;
  hardware_timing_probes = true; memory_integrity_scanner = true;
  anti_emulation = true; nanomites = true; direct_syscalls = true;
}
let default_vm_runtime = {
  num_dispatch_domains = 4; enable_junk_instructions = true;
  enable_super_operators = true; stack_scrambling = true;
  memory_sanitization = true; vector_isa = true;
  egraph_expansion = true; ephemeral_jit = false;
}
let default_c_macro = {
  enabled = true; macro_prefix = "ASG_"; obfuscate_strings = true;
  obfuscate_constants = true; obfuscate_arithmetic = true;
  opaque_predicates = true; api_hashing = true; anti_debug = true;
  signal_dispatch = false; nanomites = false; timing_guard = true;
  timing_threshold_ticks = 50000000L;
}
let default_stack_vm = {
  enabled = true;
  superoperators = true;
  state_feedback = true;
  layout_randomization = true;
  runtime_hardening = true;
  compact_imm = true;
}

type t = {
  seed : int option [@default None];
  crypto : crypto_config [@default default_crypto];
  bloat : bloat_config [@default default_bloat];
  cff : cff_config [@default default_cff];
  mba : mba_config [@default default_mba];
  anti_pushan : anti_pushan_config [@default default_anti_pushan];
  anti_tamper : anti_tamper_config [@default default_anti_tamper];
  vm_runtime : vm_runtime_config [@default default_vm_runtime];
  c_macro : c_macro_config [@default default_c_macro];
  stack_vm : stack_vm_config [@default default_stack_vm];
} [@@deriving yojson]

(* Single source of truth for the Anti-Pushan rolling-key gate: the encoder
   (vm_emitter) and the C++ runtime emitter (vm_runtime_emitter) must agree on
   it, or the predicted keystream diverges from the runtime one. *)
let rolling_key_enabled (config : t option) : bool =
  match config with
  | Some c -> c.anti_pushan.enabled && c.anti_pushan.running_key
  | None -> true

let address_bound_enabled (config : t option) : bool =
  match config with
  | Some c -> c.anti_pushan.enabled && c.anti_pushan.running_key && c.anti_pushan.address_bound
  | None -> false

let ephemeral_jit_enabled (config : t option) : bool =
  match config with
  | Some c -> c.vm_runtime.ephemeral_jit
  | None -> false
