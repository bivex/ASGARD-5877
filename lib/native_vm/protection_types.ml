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

type mba_engine = [ `Egraph | `Poly | `Ncfg | `Gpu_metal | `Nullspace ]

let mba_engine_of_yojson = function
  | `String s -> (
      match String.lowercase_ascii (String.trim s) with
      | "egraph" | "e-graph" | "scrambler" -> Ok `Egraph
      | "ncfg" -> Ok `Ncfg
      | "gpu" | "gpu_metal" | "metal" -> Ok `Gpu_metal
      | "nullspace" | "null" | "kernel" -> Ok `Nullspace
      | "poly" | "polynomial" | _ -> Ok `Poly)
  | _ -> Error "Expected string for mba_engine"

let mba_engine_to_yojson = function
  | `Egraph -> `String "egraph"
  | `Poly -> `String "poly"
  | `Ncfg -> `String "ncfg"
  | `Gpu_metal -> `String "gpu_metal"
  | `Nullspace -> `String "nullspace"

type mba_config = {
  enabled : bool [@default true];
  depth : int [@default 2];
  engine : (mba_engine [@of_yojson mba_engine_of_yojson] [@to_yojson mba_engine_to_yojson]) [@default `Egraph];
} [@@deriving yojson]

(* Target architecture of the lifted program.  The VM stores flags in the
   x86 convention (CF = borrow after SUB); ARM64 ADC/SBC read a carry in the
   ARM64 convention (C = NOT borrow), so the emitter tags those words with
   the architecture's carry dialect.  See todo item 8. *)
type arch = [ `X86_64 | `AArch64 | `RISCV ]

let arch_of_yojson = function
  | `String s -> (
      match String.lowercase_ascii (String.trim s) with
      | "arm64" | "aarch64" | "a64" -> Ok `AArch64
      | "riscv" | "risc-v" | "rv64" -> Ok `RISCV
      | _ -> Ok `X86_64)
  | _ -> Error "Expected string for arch"

let arch_to_yojson = function
  | `AArch64 -> `String "aarch64"
  | `RISCV -> `String "riscv"
  | `X86_64 -> `String "x86_64"

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
  input_tainted_transitions : bool [@default true];
  split_rate : int [@default 30];
  hub_count : int [@default 1];
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
  chameleon_handlers : bool [@default true];
  oblivious_memory : bool [@default true];
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
let default_cff = { enabled = true; obfuscate_states = true; inject_opaque_predicates = false; input_tainted_transitions = true; split_rate = 30; hub_count = 1 }

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
  chameleon_handlers = true;
  oblivious_memory = true;
}
let default_c_macro = {
  enabled = true; macro_prefix = "ASG_"; obfuscate_strings = true;
  obfuscate_constants = true; obfuscate_arithmetic = true;
  opaque_predicates = true; api_hashing = true; anti_debug = true;
  signal_dispatch = false; nanomites = false; timing_guard = true;
  timing_threshold_ticks = 50000000L;
}
type eh_shadowing_config = {
  enabled : bool [@default true];
  shadow_alloc_size : int [@default 32];
  interceptor_symbol : string [@default "tech_2601_interceptor"];
} [@@deriving yojson]

let default_eh_shadowing = {
  enabled = true;
  shadow_alloc_size = 32;
  interceptor_symbol = "tech_2601_interceptor";
}

type anti_vpc_config = {
  enabled : bool [@default true];
  scramble_vpc : bool [@default true];
  split_vpc : bool [@default true];
  entropy_whitening : bool [@default true];
} [@@deriving yojson]

let default_anti_vpc = {
  enabled = true;
  scramble_vpc = true;
  split_vpc = true;
  entropy_whitening = true;
}

type memory_chaffing_config = {
  enabled : bool [@default true];
  pool_size : int [@default 4096];
  chaff_ratio : float [@default 2.0];
} [@@deriving yojson]

let default_memory_chaffing = {
  enabled = true;
  pool_size = 4096;
  chaff_ratio = 2.0;
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
  arch : (arch [@of_yojson arch_of_yojson] [@to_yojson arch_to_yojson]) [@default `X86_64];
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
  eh_shadowing : eh_shadowing_config [@default default_eh_shadowing];
  anti_vpc : anti_vpc_config [@default default_anti_vpc];
  memory_chaffing : memory_chaffing_config [@default default_memory_chaffing];
} [@@deriving yojson]

(* ADC/SBC carry dialect: true when the lifted program reads the carry in the
   ARM64 convention (C = NOT borrow after SUB-family flag writers). *)
let arm64_carry_enabled (config : t option) : bool =
  match config with
  | Some c -> c.arch = `AArch64
  | None -> false

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

let eh_shadowing_enabled (config : t option) : bool =
  match config with
  | Some c -> c.eh_shadowing.enabled
  | None -> true

let chameleon_handlers_enabled (config : t option) : bool =
  match config with
  | Some c -> c.vm_runtime.chameleon_handlers
  | None -> true

let anti_vpc_enabled (config : t option) : bool =
  match config with
  | Some c -> c.anti_vpc.enabled
  | None -> true

let memory_chaffing_enabled (config : t option) : bool =
  match config with
  | Some c -> c.memory_chaffing.enabled
  | None -> true

let oblivious_memory_enabled (config : t option) : bool =
  match config with
  | Some c -> c.vm_runtime.oblivious_memory
  | None -> true

