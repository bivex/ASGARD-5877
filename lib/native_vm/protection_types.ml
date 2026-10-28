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
  (** Stack-VM Phase 2b (MBA Constant Synthesis) rewrite rate, 0-100:
      probability each PushImm is replaced by a NOR/NAND/ADD sequence.
      The IR-level MBA engine (depth/engine) is independent of this. *)
  stack_synthesis_rate : int [@default 100];
  (** Probability 0-100 of choosing the L5 e-graph strategy inside the
      synthesis (default 30 = historical distribution; the value 30 also
      preserves the RNG stream bit-for-bit). *)
  egraph_rate : int [@default 30];
  (** E-graph saturation budget for constant synthesis. *)
  egraph_node_limit : int [@default 120];
  egraph_time_budget_ms : int [@default 80];
  egraph_iter_limit : int [@default 5];
  (** Ceiling for the per-block IR-level MBA depth (with the built-in ±1
      jitter); mba.depth values above this are clamped. *)
  ir_max_depth : int [@default 4];
  (** E-graph node cap and wall-clock budget (ms) for the IR-level ALU
      obfuscation loop in the native/threaded/jit engines (the iteration
      limit there is the jittered mba.depth itself). *)
  ir_egraph_node_limit : int [@default 80];
  ir_egraph_time_budget_ms : int [@default 50];
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
  (** Junk-density safety caps by budget tier: when the budget is below
      threshold1 the density is capped at 0.1, below threshold2 at 0.5.
      A threshold of 0 disables that tier. *)
  density_cap_threshold1_kb : int [@default 200];
  density_cap_threshold2_kb : int [@default 500];
} [@@deriving yojson]

type cff_config = {
  enabled : bool [@default true];
  obfuscate_states : bool [@default true];
  inject_opaque_predicates : bool [@default false];
  input_tainted_transitions : bool [@default true];
  split_rate : int [@default 30];
  hub_count : int [@default 1];
  (** Path-Oriented Protection: couple an ARX path digest register into the
      CFF state encoding and dispatcher decoding, making the digest
      load-bearing and immune to dead-code elimination. Uses the shared
      [Cff.Pop_coupler.default_pop_config] register and seed. *)
  pop_digest : bool [@default false];
  (** Insert red-herring (never-taken) state aliases when splitting hot
      states, inflating static state-count analysis. *)
  red_herring : bool [@default true];
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
  context_epochs : int [@default 4];
  oblivious_decoys : int [@default 3];
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
  (** Phase 6 (State-Feedback Rolling Key) injection rate, 0-100:
      probability a register-coupled cipher checkpoint is injected. *)
  feedback_rate : int [@default 100];
  (** Phase 3 stack-level CFF: couple the rolling key to the VPC write on every CFF edge. *)
  cff_couple_key : bool [@default true];
  opcode_polymorphism : bool [@default true];
  permute_registers : bool [@default false];
  host_stack_size_kb : int [@default 1024];
} [@@deriving yojson]

type spaghetti_config = {
  enabled   : bool  [@default true];
  (** Probability 0–100 of splitting each eligible block. 100 = always split
      when a valid cut-point exists and the block-count ceiling permits. *)
  split_rate : int  [@default 100];
  (** Maximum additional blocks allowed beyond the post-CFF count.
      Priority: [max_extra_blocks > 0] wins; otherwise
      [cur_blocks * max_splits_factor]; when both are 0 the legacy
      hard-coded heuristic (min 512 (cur/2)) applies. *)
  max_extra_blocks : int  [@default 0];
  (** Multiplier applied to the current block count to derive max_splits
      (used only when [max_extra_blocks = 0]).  Default 1 means "at most
      1× extra blocks"; 2 means 2× extra; etc. *)
  max_splits_factor : int  [@default 1];
  (** Minimum number of ops required on each side of a cut point.
      Lower = more candidate splits; minimum useful value is 1. *)
  min_chunk : int  [@default 2];
} [@@deriving yojson]

let default_spaghetti = {
  enabled           = true;
  split_rate        = 100;
  max_extra_blocks  = 0;
  max_splits_factor = 1;
  min_chunk         = 2;
}
type braid_config = {
  enabled : bool [@default true];
  rate    : int  [@default 25];
} [@@deriving yojson]

let default_braid = {
  enabled = true;
  rate    = 25;
}

type amplifier_config = {
  enabled : bool [@default true];
  (** Base profile: "heavy" (Horner 6, +281% ops), "balanced" (Horner 3),
      "light" (Horner 2). Individual numeric overrides below with value 0
      inherit from the profile. *)
  profile : string [@default "heavy"];
  (** Degree of the Horner polynomial expansion for PushImm constants. *)
  horner_degree : int [@default 0];
  (** Carry-chain bit-slice lanes for Add/Sub (0-2). *)
  bit_slice_lanes : int [@default 0];
  (** Number of ops between def-use web "knots" (expander chords). *)
  expander_chord_len : int [@default 0];
  (** Probability 0-100 of emitting an expander knot. *)
  expander_chord_rate : int [@default 0];
} [@@deriving yojson]

let default_amplifier = {
  enabled             = true;
  profile             = "heavy";
  horner_degree       = 0;
  bit_slice_lanes     = 0;
  expander_chord_len  = 0;
  expander_chord_rate = 0;
}

type superop_config = {
  enabled : bool [@default true];
  (** Probability 0-100 of fusing an eligible op pair into a superoperator.
      Effective gate is [stack_vm.superoperators && superop.enabled]. *)
  fusion_rate : int [@default 100];
  enable_add_imm : bool [@default true];
  enable_sub_imm : bool [@default true];
  enable_add_ii : bool [@default true];
  enable_sub_ii : bool [@default true];
  enable_set_reg_imm : bool [@default true];
  enable_add_reg_imm : bool [@default true];
} [@@deriving yojson]

let default_superop = {
  enabled            = true;
  fusion_rate        = 100;
  enable_add_imm     = true;
  enable_sub_imm     = true;
  enable_add_ii      = true;
  enable_sub_ii      = true;
  enable_set_reg_imm = true;
  enable_add_reg_imm = true;
}

type ghost_config = {
  enabled : bool [@default true];
  (** Probability 0-100 of inserting a ghost op after each real op. *)
  ghost_rate : int [@default 80];
  (** Maximum ghost ops per block (0 = unlimited). *)
  max_ghosts : int [@default 0];
  (** Data-flow entanglement of ghost checksums with memory ops (P1-02). *)
  entangle : bool [@default true];
} [@@deriving yojson]

let default_ghost = {
  enabled    = true;
  ghost_rate = 80;
  max_ghosts = 0;
  entangle   = true;
}
type avid_config = {
  enabled  : bool [@default true];
  rate     : int  [@default 40];
  max_avid : int  [@default 0];
} [@@deriving yojson]

let default_avid = {
  enabled  = true;
  rate     = 40;
  max_avid = 0;
}
type multiplicity_config = {
  enabled : bool [@default true];
  rate    : int  [@default 30];
} [@@deriving yojson]

let default_multiplicity = {
  enabled = true;
  rate    = 30;
}
type mem_webbing_config = {
  enabled : bool [@default true];
  rate    : int  [@default 40];
} [@@deriving yojson]

let default_mem_webbing = {
  enabled = true;
  rate    = 40;
}
type transducer_config = {
  enabled : bool [@default true];
  rate    : int  [@default 50];
} [@@deriving yojson]

let default_transducer = {
  enabled = true;
  rate    = 50;
}
type trace_closure_config = {
  enabled : bool [@default true];
  rate    : int  [@default 25];
} [@@deriving yojson]

let default_trace_closure = {
  enabled = true;
  rate    = 25;
}
type polymba_config = {
  enabled : bool [@default true];
  rate    : int  [@default 40];
} [@@deriving yojson]

let default_polymba = {
  enabled = true;
  rate    = 40;
}
type finite_field_config = {
  enabled : bool [@default true];
  rate    : int  [@default 35];
} [@@deriving yojson]

let default_finite_field = {
  enabled = true;
  rate    = 35;
}
type sink_barrier_config = {
  enabled : bool [@default true];
  rate    : int  [@default 40];
} [@@deriving yojson]

let default_sink_barrier = {
  enabled = true;
  rate    = 40;
}
type pipelined_dispatch_config = {
  enabled     : bool [@default true];
  (** Stage-2 dead-slot chaff region size; normalized to a power of two. *)
  chaff_slots : int  [@default 4];
} [@@deriving yojson]

let default_pipelined_dispatch = {
  enabled     = true;
  chaff_slots = 4;
}



type trampoline_config = {
  (** Number of 64-bit words per fragmented bytecode chunk. Default 64. *)
  chunk_size : int [@default 64];
} [@@deriving yojson]

let default_trampoline = {
  chunk_size = 64;
}

type watermark_config = {
  payload_bits : int [@default 48];
  redundancy   : int [@default 7];
} [@@deriving yojson]

let default_watermark = {
  payload_bits = 48;
  redundancy   = 7;
}

type toolchain_config = {
  opt_level   : string      [@default "-O3"];
  extra_flags : string list [@default []];
} [@@deriving yojson]

let default_toolchain = {
  opt_level   = "-O3";
  extra_flags = [];
}


let default_crypto = { rounds = 16; key_bits = 128 }
let default_bloat = { mode = `Balanced; target_size_budget_kb = Some 1000; junk_density = 0.5; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 }
let default_cff = { enabled = true; obfuscate_states = true; inject_opaque_predicates = false; input_tainted_transitions = true; split_rate = 30; hub_count = 1; pop_digest = false; red_herring = true }

let default_mba = { enabled = true; depth = 2; engine = `Egraph; stack_synthesis_rate = 100; egraph_rate = 30; egraph_node_limit = 120; egraph_time_budget_ms = 80; egraph_iter_limit = 5; ir_max_depth = 4; ir_egraph_node_limit = 80; ir_egraph_time_budget_ms = 50 }
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
  context_epochs = 4;
  oblivious_decoys = 3;
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

type comp_stall_config = {
  enabled          : bool   [@default false];
  variant          : string [@default "ergodic"];  (* "ergodic" | "time_lock" | "pow" *)
  n_iterations     : int    [@default 50_000];
  pow_difficulty   : int    [@default 20];
  tau_ux_sec       : (float [@of_yojson float_of_yojson] [@to_yojson float_to_yojson]) [@default 0.5];
  emu_quota_instrs : int    [@default 10_000_000];
  seed             : int64  [@default 0L];
} [@@deriving yojson]

let default_comp_stall = {
  enabled = false;
  variant = "ergodic";
  n_iterations = 50_000;
  pow_difficulty = 20;
  tau_ux_sec = 0.5;
  emu_quota_instrs = 10_000_000;
  seed = 0L;
}

let default_stack_vm = {
  enabled = true;
  superoperators = true;
  state_feedback = true;
  layout_randomization = true;
  runtime_hardening = true;
  compact_imm = true;
  feedback_rate = 100;
  cff_couple_key = true;
  opcode_polymorphism = true;
  permute_registers = false;
  host_stack_size_kb = 1024;
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
  comp_stall : comp_stall_config [@default default_comp_stall];
  spaghetti : spaghetti_config [@default default_spaghetti];
  braid : braid_config [@default default_braid];
  amplifier : amplifier_config [@default default_amplifier];
  superop : superop_config [@default default_superop];
  ghost : ghost_config [@default default_ghost];
  avid : avid_config [@default default_avid];
  mem_webbing : mem_webbing_config [@default default_mem_webbing];
  trace_closure : trace_closure_config [@default default_trace_closure];
  transducer : transducer_config [@default default_transducer];
  polymba : polymba_config [@default default_polymba];
  finite_field : finite_field_config [@default default_finite_field];
  sink_barrier : sink_barrier_config [@default default_sink_barrier];
  multiplicity : multiplicity_config [@default default_multiplicity];
  pipelined_dispatch : pipelined_dispatch_config [@default default_pipelined_dispatch];
  trampoline : trampoline_config [@default default_trampoline];
  watermark : watermark_config [@default default_watermark];
  toolchain : toolchain_config [@default default_toolchain];
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

let comp_stall_enabled (config : t option) : bool =
  match config with
  | Some c -> c.comp_stall.enabled
  | None -> false

let oblivious_memory_enabled (config : t option) : bool =
  match config with
  | Some c -> c.vm_runtime.oblivious_memory
  | None -> true

