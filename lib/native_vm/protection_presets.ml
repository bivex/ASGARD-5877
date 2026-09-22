open Protection_types

let default : t = {
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Balanced; target_size_budget_kb = Some 1000; junk_density = 0.5 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = false;
  };
  mba = {
    enabled = true;
    depth = 2;
    engine = `Egraph;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
  };
  anti_tamper = {
    enabled = true;
    smc = true;
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
}

let max_security : t = {
  seed = None;
  crypto = { rounds = 64; key_bits = 128 };
  bloat = { mode = `Insane; target_size_budget_kb = Some 5000; junk_density = 2.0 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = false;
  };
  mba = {
    enabled = true;
    depth = 4;
    engine = `Egraph;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
  };
  anti_tamper = {
    enabled = true;
    smc = true;
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
}

let lightweight : t = {
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Compact; target_size_budget_kb = Some 250; junk_density = 0.2 };
  cff = {
    enabled = false;
    obfuscate_states = false;
    inject_opaque_predicates = false;
  };
  mba = {
    enabled = true;
    depth = 1;
    engine = `Poly;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
  };
  anti_tamper = {
    enabled = false;
    smc = false;
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
    timing_threshold_ticks = 100000000L;
  };
}

let stealth : t = {
  seed = None;
  crypto = { rounds = 16; key_bits = 128 };
  bloat = { mode = `Balanced; target_size_budget_kb = Some 500; junk_density = 0.3 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = false;
  };
  mba = {
    enabled = true;
    depth = 2;
    engine = `Ncfg;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
  };
  anti_tamper = {
    enabled = true;
    smc = false;
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
}

let minimal : t = {
  seed = None;
  crypto = { rounds = 8; key_bits = 128 };
  bloat = { mode = `Compact; target_size_budget_kb = Some 100; junk_density = 0.0 };
  cff = {
    enabled = false;
    obfuscate_states = false;
    inject_opaque_predicates = false;
  };
  mba = {
    enabled = false;
    depth = 0;
    engine = `Poly;
  };
  anti_pushan = {
    enabled = false;
    running_key = false;
  };
  anti_tamper = {
    enabled = false;
    smc = false;
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
}

let high : t = {
  seed = None;
  crypto = { rounds = 32; key_bits = 128 };
  bloat = { mode = `Heavy; target_size_budget_kb = Some 2500; junk_density = 1.0 };
  cff = {
    enabled = true;
    obfuscate_states = true;
    inject_opaque_predicates = false;
  };
  mba = {
    enabled = true;
    depth = 3;
    engine = `Egraph;
  };
  anti_pushan = {
    enabled = true;
    running_key = true;
  };
  anti_tamper = {
    enabled = true;
    smc = true;
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
}

let from_preset name =
  match String.lowercase_ascii (String.trim name) with
  | "min" | "minimal" | "none" | "zero" | "0" -> Ok minimal
  | "light" | "lightweight" | "fast" | "low" | "1" -> Ok lightweight
  | "default" | "std" | "standard" | "medium" | "med" | "2" -> Ok default
  | "high" | "hardened" | "strong" | "3" -> Ok high
  | "max" | "max_security" | "paranoid" | "military" | "insane" | "4" -> Ok max_security
  | "stealth" | "covert" -> Ok stealth
  | other -> Error (Printf.sprintf "Unknown protection preset '%s'. Available: min (0), lightweight (1), default/medium (2), high (3), max (4), stealth" other)
