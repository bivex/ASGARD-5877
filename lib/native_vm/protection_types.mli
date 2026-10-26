(** Types defining multi-layer VM protection and hardening configurations. *)

type mba_engine = [ `Egraph | `Poly | `Ncfg | `Gpu_metal | `Nullspace ]

type mba_config = {
  enabled : bool;
  depth : int;
  engine : mba_engine;
  stack_synthesis_rate : int;
  egraph_rate : int;
  egraph_node_limit : int;
  egraph_time_budget_ms : int;
  egraph_iter_limit : int;
  ir_max_depth : int;
  ir_egraph_node_limit : int;
  ir_egraph_time_budget_ms : int;
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
  density_cap_threshold1_kb : int;
  density_cap_threshold2_kb : int;
}

type cff_config = {
  enabled : bool;
  obfuscate_states : bool;
  inject_opaque_predicates : bool;
  input_tainted_transitions : bool;
  split_rate : int;
  hub_count : int;
  pop_digest : bool;
  red_herring : bool;
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
  chameleon_handlers : bool;
  oblivious_memory : bool;
  context_epochs : int;
  oblivious_decoys : int;
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

type stack_vm_config = {
  enabled : bool;
  superoperators : bool;
  state_feedback : bool;
  layout_randomization : bool;
  runtime_hardening : bool;
  compact_imm : bool;
  feedback_rate : int;
  cff_couple_key : bool;
  opcode_polymorphism : bool;
  permute_registers : bool;
  host_stack_size_kb : int;
}

type eh_shadowing_config = {
  enabled : bool;
  shadow_alloc_size : int;
  interceptor_symbol : string;
}

type anti_vpc_config = {
  enabled : bool;
  scramble_vpc : bool;
  split_vpc : bool;
  entropy_whitening : bool;
}

type memory_chaffing_config = {
  enabled : bool;
  pool_size : int;
  chaff_ratio : float;
}

type comp_stall_config = {
  enabled          : bool;
  variant          : string;
  n_iterations     : int;
  pow_difficulty   : int;
  tau_ux_sec       : float;
  emu_quota_instrs : int;
  seed             : int64;
}

type spaghetti_config = {
  enabled           : bool;
  split_rate        : int;
  max_extra_blocks  : int;
  max_splits_factor : int;
  min_chunk         : int;
}

type amplifier_config = {
  enabled             : bool;
  profile             : string;
  horner_degree       : int;
  bit_slice_lanes     : int;
  expander_chord_len  : int;
  expander_chord_rate : int;
}

type superop_config = {
  enabled            : bool;
  fusion_rate        : int;
  enable_add_imm     : bool;
  enable_sub_imm     : bool;
  enable_add_ii      : bool;
  enable_sub_ii      : bool;
  enable_set_reg_imm : bool;
  enable_add_reg_imm : bool;
}

type ghost_config = {
  enabled    : bool;
  ghost_rate : int;
  max_ghosts : int;
  entangle   : bool;
}
type avid_config = {
  enabled  : bool;
  rate     : int;
  max_avid : int;
}

val default_avid : avid_config
type multiplicity_config = {
  enabled : bool;
  rate    : int;
}

val default_multiplicity : multiplicity_config
type pipelined_dispatch_config = {
  enabled     : bool;
  chaff_slots : int;
}

val default_pipelined_dispatch : pipelined_dispatch_config



type trampoline_config = {
  chunk_size : int;
}

type watermark_config = {
  payload_bits : int;
  redundancy   : int;
}

val default_watermark : watermark_config

type toolchain_config = {
  opt_level   : string;
  extra_flags : string list;
}

val default_toolchain : toolchain_config

type arch = [ `X86_64 | `AArch64 | `RISCV ]

type t = {
  arch : arch;
  seed : int option;
  crypto : crypto_config;
  bloat : bloat_config;
  cff : cff_config;
  mba : mba_config;
  anti_pushan : anti_pushan_config;
  anti_tamper : anti_tamper_config;
  vm_runtime : vm_runtime_config;
  c_macro : c_macro_config;
  stack_vm : stack_vm_config;
  eh_shadowing : eh_shadowing_config;
  anti_vpc : anti_vpc_config;
  memory_chaffing : memory_chaffing_config;
  comp_stall : comp_stall_config;
  spaghetti : spaghetti_config;
  amplifier : amplifier_config;
  superop : superop_config;
  ghost : ghost_config;
  avid : avid_config;
  multiplicity : multiplicity_config;
  pipelined_dispatch : pipelined_dispatch_config;
  trampoline : trampoline_config;
  watermark : watermark_config;
  toolchain : toolchain_config;
}

val default_stack_vm : stack_vm_config
val default_eh_shadowing : eh_shadowing_config
val default_anti_vpc : anti_vpc_config
val default_memory_chaffing : memory_chaffing_config
val default_comp_stall : comp_stall_config
val default_spaghetti : spaghetti_config
val default_amplifier : amplifier_config
val default_superop : superop_config
val default_ghost : ghost_config
val default_trampoline : trampoline_config

val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (t, string) result

val rolling_key_enabled : t option -> bool
(** Anti-Pushan block-chained rolling key gate: [true] unless a config explicitly
    disables it.  Shared by the encoder and the C++ runtime emitter so both sides
    derive the same keystream. *)

val arm64_carry_enabled : t option -> bool
(** ADC/SBC carry dialect: [true] when the lifted program reads the carry in
    the ARM64 convention (C = NOT borrow after SUB-family flag writers).
    Selects the ARM64-view carry for ADC/SBC words in the emitted bytecode. *)

val address_bound_enabled : t option -> bool
(** Anti-VMPredator address-bound bytecode gate: [true] when running_key and address_bound
    are both enabled. Binds bytecode decryption to runtime handler addresses. *)

val ephemeral_jit_enabled : t option -> bool
(** Ephemeral polymorphic JIT gate: [true] when runtime ephemeral JIT code synthesis
    is enabled in vm_runtime. *)

val eh_shadowing_enabled : t option -> bool
(** Tech-2601 Exception Handling Shadowing gate: [true] when enabled in eh_shadowing config. *)

val chameleon_handlers_enabled : t option -> bool
(** Chameleon ALU polymorphic handlers gate: [true] when enabled in vm_runtime. *)

val anti_vpc_enabled : t option -> bool
(** Tech-2603 Anti-VPC-Tracking gate: [true] when enabled in anti_vpc config. *)

val memory_chaffing_enabled : t option -> bool
(** Tech-2608 Anti-Trace-Synthesis gate: [true] when enabled in memory_chaffing config. *)

val comp_stall_enabled : t option -> bool
(** Computational Stalling (anti-emulation) gate: [true] when enabled in comp_stall config. *)

val oblivious_memory_enabled : t option -> bool
(** Oblivious Memory & Decoy Access gate: [true] when enabled in vm_runtime. *)

