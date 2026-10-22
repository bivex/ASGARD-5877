open Protection_types

let default : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Balanced; target_size_budget_kb = Some 1000; junk_density = 0.5; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = false;
    input_tainted_transitions = true;
    split_rate = 30;
    hub_count = 1;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = true;
    depth = 2;
    engine = `Egraph;
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
    address_bound = false;
  };
  anti_tamper = {
    enabled = true;
    smc = true;
    smc_strict = false;
    hardware_timing_probes = true;
    memory_integrity_scanner = true;
    anti_emulation = true;
    nanomites = true;
    direct_syscalls = true;
  };
  vm_runtime = {
    num_dispatch_domains = 4;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
    vector_isa = true;
    egraph_expansion = true;
    ephemeral_jit = false;
    chameleon_handlers = true;
    oblivious_memory = true;
  };
  c_macro = {
    enabled = true;
    macro_prefix = "ASG_";
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    opaque_predicates = true;
    api_hashing = true;
    anti_debug = true;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = true;
    timing_threshold_ticks = 50000000L;
  };
  stack_vm = default_stack_vm;
  eh_shadowing = default_eh_shadowing;
  anti_vpc = default_anti_vpc;
  memory_chaffing = default_memory_chaffing;
  spaghetti = default_spaghetti;
  amplifier = default_amplifier;
  superop = default_superop;
  ghost = default_ghost;
  trampoline = default_trampoline;
}

let max_security : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 64; key_bits = 128 };
  bloat = { mode = `Insane; target_size_budget_kb = Some 5000; junk_density = 2.0; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = true;
    input_tainted_transitions = true;
    split_rate = 50;
    hub_count = 2;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = true;
    depth = 4;
    engine = (if Gpu_synth.is_gpu_available () then `Gpu_metal else `Egraph);
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
    address_bound = true;
  };
  anti_tamper = {
    enabled = true;
    smc = true;
    smc_strict = true;
    hardware_timing_probes = true;
    memory_integrity_scanner = true;
    anti_emulation = true;
    nanomites = true;
    direct_syscalls = true;
  };
  vm_runtime = {
    num_dispatch_domains = 8;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
    vector_isa = true;
    egraph_expansion = true;
    ephemeral_jit = true;
    chameleon_handlers = true;
    oblivious_memory = true;
  };
  c_macro = {
    enabled = true;
    macro_prefix = "ASG_";
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    opaque_predicates = true;
    api_hashing = true;
    anti_debug = true;
    signal_dispatch = true;
    nanomites = true;
    timing_guard = true;
    timing_threshold_ticks = 25000000L;
  };
  stack_vm = {
    enabled = true;
    superoperators = true;
    state_feedback = true;
    layout_randomization = true;
    runtime_hardening = true;
    compact_imm = true;
    feedback_rate = 100;
    cff_couple_key = true;
  };
  eh_shadowing = {
    enabled = true;
    shadow_alloc_size = 64;
    interceptor_symbol = "tech_2601_interceptor";
  };
  anti_vpc = {
    enabled = true;
    scramble_vpc = true;
    split_vpc = true;
    entropy_whitening = true;
  };
  memory_chaffing = {
    enabled = true;
    pool_size = 16384;
    chaff_ratio = 4.0;
  };
  spaghetti = { default_spaghetti with max_splits_factor = 2 };
  amplifier = default_amplifier;
  superop = default_superop;
  ghost = { default_ghost with ghost_rate = 100 };
  trampoline = default_trampoline;
}

let lightweight : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Compact; target_size_budget_kb = Some 250; junk_density = 0.2; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = false;
    obfuscate_states = false;
    inject_opaque_predicates = false;
    input_tainted_transitions = false;
    split_rate = 0;
    hub_count = 1;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = true;
    depth = 1;
    engine = `Poly;
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
    address_bound = false;
  };
  anti_tamper = {
    enabled = false;
    smc = false;
    smc_strict = false;
    hardware_timing_probes = false;
    memory_integrity_scanner = false;
    anti_emulation = false;
    nanomites = false;
    direct_syscalls = false;
  };
  vm_runtime = {
    num_dispatch_domains = 2;
    enable_junk_instructions = false;
    enable_super_operators = true;
    stack_scrambling = false;
    memory_sanitization = false;
    vector_isa = false;
    egraph_expansion = false;
    ephemeral_jit = true;
    chameleon_handlers = false;
    oblivious_memory = false;
  };
  c_macro = {
    enabled = true;
    macro_prefix = "ASG_";
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    opaque_predicates = false;
    api_hashing = true;
    anti_debug = false;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = false;
    timing_threshold_ticks = 100000000L;
  };
  stack_vm = {
    enabled = true;
    superoperators = true;
    state_feedback = false;
    layout_randomization = false;
    runtime_hardening = false;
    compact_imm = true;
    feedback_rate = 100;
    cff_couple_key = true;
  };
  eh_shadowing = {
    enabled = false;
    shadow_alloc_size = 32;
    interceptor_symbol = "tech_2601_interceptor";
  };
  anti_vpc = {
    enabled = true;
    scramble_vpc = true;
    split_vpc = false;
    entropy_whitening = false;
  };
  memory_chaffing = {
    enabled = false;
    pool_size = 1024;
    chaff_ratio = 0.5;
  };
  spaghetti = default_spaghetti;
  amplifier = { default_amplifier with profile = "light" };
  superop = { default_superop with fusion_rate = 80 };
  ghost = { default_ghost with ghost_rate = 40 };
  trampoline = default_trampoline;
}

let stealth : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Balanced; target_size_budget_kb = Some 500; junk_density = 0.3; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = true;
    input_tainted_transitions = true;
    split_rate = 30;
    hub_count = 1;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = true;
    depth = 2;
    engine = `Ncfg;
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
    address_bound = false;
  };
  anti_tamper = {
    enabled = true;
    smc = false;
    smc_strict = false;
    hardware_timing_probes = true;
    memory_integrity_scanner = false;
    anti_emulation = true;
    nanomites = false;
    direct_syscalls = true;
  };
  vm_runtime = {
    num_dispatch_domains = 4;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
    vector_isa = true;
    egraph_expansion = true;
    ephemeral_jit = false;
    chameleon_handlers = true;
    oblivious_memory = true;
  };
  c_macro = {
    enabled = true;
    macro_prefix = "ASG_";
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    opaque_predicates = true;
    api_hashing = true;
    anti_debug = false;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = true;
    timing_threshold_ticks = 50000000L;
  };
  stack_vm = {
    enabled = true;
    superoperators = true;
    state_feedback = true;
    layout_randomization = true;
    runtime_hardening = true;
    compact_imm = true;
    feedback_rate = 100;
    cff_couple_key = true;
  };
  eh_shadowing = {
    enabled = true;
    shadow_alloc_size = 32;
    interceptor_symbol = "tech_2601_interceptor";
  };
  anti_vpc = default_anti_vpc;
  memory_chaffing = {
    enabled = true;
    pool_size = 8192;
    chaff_ratio = 3.0;
  };
  spaghetti = default_spaghetti;
  amplifier = default_amplifier;
  superop = default_superop;
  ghost = default_ghost;
  trampoline = default_trampoline;
}

let edr_stealth : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Balanced; target_size_budget_kb = Some 250; junk_density = 0.2; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = false;
    input_tainted_transitions = true;
    split_rate = 30;
    hub_count = 2;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = true;
    depth = 2;
    engine = `Egraph;
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
    address_bound = false;
  };
  anti_tamper = {
    enabled = true;
    smc = false;
    smc_strict = false;
    hardware_timing_probes = true;
    memory_integrity_scanner = false;
    anti_emulation = false;
    nanomites = false;
    direct_syscalls = false;
  };
  vm_runtime = {
    num_dispatch_domains = 4;
    enable_junk_instructions = false;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = false;
    vector_isa = true;
    egraph_expansion = true;
    ephemeral_jit = false;
    chameleon_handlers = true;
    oblivious_memory = false;
  };
  c_macro = {
    enabled = true;
    macro_prefix = "ASG_";
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    opaque_predicates = false;
    api_hashing = false;
    anti_debug = false;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = false;
    timing_threshold_ticks = 50000000L;
  };
  stack_vm = {
    enabled = true;
    superoperators = true;
    state_feedback = true;
    layout_randomization = true;
    runtime_hardening = true;
    compact_imm = true;
    feedback_rate = 100;
    cff_couple_key = true;
  };
  eh_shadowing = {
    enabled = false;
    shadow_alloc_size = 64;
    interceptor_symbol = "tech_2601_interceptor";
  };
  anti_vpc = {
    enabled = true;
    scramble_vpc = true;
    split_vpc = false;
    entropy_whitening = true;
  };
  memory_chaffing = {
    enabled = false;
    pool_size = 4096;
    chaff_ratio = 1.0;
  };
  spaghetti = default_spaghetti;
  amplifier = default_amplifier;
  superop = default_superop;
  ghost = default_ghost;
  trampoline = default_trampoline;
}

let minimal : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 8; key_bits = 128 };
  bloat = { mode = `Compact; target_size_budget_kb = Some 100; junk_density = 0.0; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = false;
    obfuscate_states = false;
    inject_opaque_predicates = false;
    input_tainted_transitions = false;
    split_rate = 0;
    hub_count = 1;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = false;
    depth = 0;
    engine = `Poly;
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = false;
    running_key = false;
    address_bound = false;
  };
  anti_tamper = {
    enabled = false;
    smc = false;
    smc_strict = false;
    hardware_timing_probes = false;
    memory_integrity_scanner = false;
    anti_emulation = false;
    nanomites = false;
    direct_syscalls = false;
  };
  vm_runtime = {
    num_dispatch_domains = 1;
    enable_junk_instructions = false;
    enable_super_operators = false;
    stack_scrambling = false;
    memory_sanitization = false;
    vector_isa = false;
    egraph_expansion = false;
    ephemeral_jit = false;
    chameleon_handlers = false;
    oblivious_memory = false;
  };
  c_macro = {
    enabled = false;
    macro_prefix = "ASG_";
    obfuscate_strings = false;
    obfuscate_constants = false;
    obfuscate_arithmetic = false;
    opaque_predicates = false;
    api_hashing = false;
    anti_debug = false;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = false;
    timing_threshold_ticks = 500000000L;
  };
  stack_vm = {
    enabled = false;
    superoperators = false;
    state_feedback = false;
    layout_randomization = false;
    runtime_hardening = false;
    compact_imm = false;
    feedback_rate = 100;
    cff_couple_key = true;
  };
  eh_shadowing = {
    enabled = false;
    shadow_alloc_size = 32;
    interceptor_symbol = "tech_2601_interceptor";
  };
  anti_vpc = {
    enabled = false;
    scramble_vpc = false;
    split_vpc = false;
    entropy_whitening = false;
  };
  memory_chaffing = {
    enabled = false;
    pool_size = 1024;
    chaff_ratio = 0.0;
  };
  spaghetti = default_spaghetti;
  amplifier = { default_amplifier with enabled = false };
  superop = default_superop;
  ghost = { default_ghost with enabled = false };
  trampoline = default_trampoline;
}

let high : t = {
  arch = `X86_64;
  seed = None;
  crypto = { rounds = 32; key_bits = 128 };
  bloat = { mode = `Heavy; target_size_budget_kb = Some 2500; junk_density = 1.0; density_cap_threshold1_kb = 200; density_cap_threshold2_kb = 500 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = true;
    input_tainted_transitions = true;
    split_rate = 40;
    hub_count = 1;
    pop_digest = false;
    red_herring = true;
  };
  mba = {
    enabled = true;
    depth = 3;
    engine = `Egraph;
    stack_synthesis_rate = 100;
    egraph_rate = 30;
    egraph_node_limit = 120;
    egraph_time_budget_ms = 80;
    egraph_iter_limit = 5;
    ir_max_depth = 4;
    ir_egraph_node_limit = 80;
    ir_egraph_time_budget_ms = 50;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
    address_bound = false;
  };
  anti_tamper = {
    enabled = true;
    smc = true;
    smc_strict = false;
    hardware_timing_probes = true;
    memory_integrity_scanner = true;
    anti_emulation = true;
    nanomites = true;
    direct_syscalls = true;
  };
  vm_runtime = {
    num_dispatch_domains = 8;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
    vector_isa = true;
    egraph_expansion = true;
    ephemeral_jit = false;
    chameleon_handlers = true;
    oblivious_memory = true;
  };
  c_macro = {
    enabled = true;
    macro_prefix = "ASG_";
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    opaque_predicates = true;
    api_hashing = true;
    anti_debug = true;
    signal_dispatch = true;
    nanomites = true;
    timing_guard = true;
    timing_threshold_ticks = 50000000L;
  };
  stack_vm = {
    enabled = true;
    superoperators = true;
    state_feedback = true;
    layout_randomization = true;
    runtime_hardening = true;
    compact_imm = true;
    feedback_rate = 100;
    cff_couple_key = true;
  };
  eh_shadowing = {
    enabled = true;
    shadow_alloc_size = 48;
    interceptor_symbol = "tech_2601_interceptor";
  };
  anti_vpc = default_anti_vpc;
  memory_chaffing = default_memory_chaffing;
  spaghetti = default_spaghetti;
  amplifier = default_amplifier;
  superop = default_superop;
  ghost = { default_ghost with ghost_rate = 90 };
  trampoline = default_trampoline;
}

let from_preset name =
  match String.lowercase_ascii (String.trim name) with
  | "min" | "minimal" | "none" | "zero" | "0" -> Ok minimal
  | "light" | "lightweight" | "fast" | "low" | "1" -> Ok lightweight
  | "default" | "std" | "standard" | "medium" | "med" | "2" -> Ok default
  | "high" | "hardened" | "strong" | "3" -> Ok high
  | "max" | "max_security" | "paranoid" | "military" | "insane" | "4" -> Ok max_security
  | "stealth" | "covert" -> Ok stealth
  | "edr" | "edr_stealth" | "av_clean" | "whitelist" -> Ok edr_stealth
  | other -> Error (Printf.sprintf "Unknown protection preset '%s'. Available: min (0), lightweight (1), default/medium (2), high (3), max (4), stealth, edr_stealth" other)
