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

let default : t = {
  seed = None;
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
  };
  vm_runtime = {
    num_dispatch_domains = 4;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
  };
  c_macro = {
    enabled = true;
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    nanomites = true;
  };
}

let max_security : t = {
  seed = None;
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
  };
  vm_runtime = {
    num_dispatch_domains = 8;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
  };
  c_macro = {
    enabled = true;
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    nanomites = true;
  };
}

let lightweight : t = {
  seed = None;
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
  };
  vm_runtime = {
    num_dispatch_domains = 2;
    enable_junk_instructions = false;
    enable_super_operators = true;
    stack_scrambling = false;
    memory_sanitization = false;
  };
  c_macro = {
    enabled = false;
    obfuscate_strings = false;
    obfuscate_constants = false;
    obfuscate_arithmetic = false;
    nanomites = false;
  };
}

let stealth : t = {
  seed = None;
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
  };
  vm_runtime = {
    num_dispatch_domains = 4;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
  };
  c_macro = {
    enabled = true;
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    nanomites = false;
  };
}

let minimal : t = {
  seed = None;
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
  };
  vm_runtime = {
    num_dispatch_domains = 1;
    enable_junk_instructions = false;
    enable_super_operators = false;
    stack_scrambling = false;
    memory_sanitization = false;
  };
  c_macro = {
    enabled = false;
    obfuscate_strings = false;
    obfuscate_constants = false;
    obfuscate_arithmetic = false;
    nanomites = false;
  };
}

let high : t = {
  seed = None;
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
  };
  vm_runtime = {
    num_dispatch_domains = 8;
    enable_junk_instructions = true;
    enable_super_operators = true;
    stack_scrambling = true;
    memory_sanitization = true;
  };
  c_macro = {
    enabled = true;
    obfuscate_strings = true;
    obfuscate_constants = true;
    obfuscate_arithmetic = true;
    nanomites = true;
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

let json_get_obj key json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Assoc _ as obj) -> Some obj
      | _ -> None)
  | _ -> None

let json_get_bool key default json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Bool b) -> b
      | _ -> default)
  | _ -> default

let json_get_int key default json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Int i) -> i
      | _ -> default)
  | _ -> default

let json_get_string key default json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`String s) -> s
      | _ -> default)
  | _ -> default

let json_get_int_opt key json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Int i) -> Some i
      | _ -> None)
  | _ -> None

let parse_mba_engine str =
  match String.lowercase_ascii (String.trim str) with
  | "egraph" | "e-graph" | "scrambler" -> `Egraph
  | "ncfg" -> `Ncfg
  | "poly" | "polynomial" | _ -> `Poly

let string_of_mba_engine = function
  | `Egraph -> "egraph"
  | `Poly -> "poly"
  | `Ncfg -> "ncfg"

let from_yojson (json : Yojson.Basic.t) : (t, string) result =
  try
    let base = default in
    let seed = json_get_int_opt "seed" json in

    let cff =
      match json_get_obj "cff" json with
      | None -> base.cff
      | Some obj ->
          {
            enabled = json_get_bool "enabled" base.cff.enabled obj;
            obfuscate_states = json_get_bool "obfuscate_states" base.cff.obfuscate_states obj;
            inject_opaque_predicates = json_get_bool "inject_opaque_predicates" base.cff.inject_opaque_predicates obj;
          }
    in

    let mba =
      match json_get_obj "mba" json with
      | None -> base.mba
      | Some obj ->
          let eng_str = json_get_string "engine" (string_of_mba_engine base.mba.engine) obj in
          {
            enabled = json_get_bool "enabled" base.mba.enabled obj;
            depth = json_get_int "depth" base.mba.depth obj;
            engine = parse_mba_engine eng_str;
          }
    in

    let anti_pushan =
      match json_get_obj "anti_pushan" json with
      | None -> base.anti_pushan
      | Some obj ->
          {
            enabled = json_get_bool "enabled" base.anti_pushan.enabled obj;
            running_key = json_get_bool "running_key" base.anti_pushan.running_key obj;
          }
    in

    let anti_tamper =
      match json_get_obj "anti_tamper" json with
      | None -> base.anti_tamper
      | Some obj ->
          {
            enabled = json_get_bool "enabled" base.anti_tamper.enabled obj;
            smc = json_get_bool "smc" base.anti_tamper.smc obj;
            hardware_timing_probes = json_get_bool "hardware_timing_probes" base.anti_tamper.hardware_timing_probes obj;
            memory_integrity_scanner = json_get_bool "memory_integrity_scanner" base.anti_tamper.memory_integrity_scanner obj;
            anti_emulation = json_get_bool "anti_emulation" base.anti_tamper.anti_emulation obj;
          }
    in

    let vm_runtime =
      match json_get_obj "vm_runtime" json with
      | None -> base.vm_runtime
      | Some obj ->
          {
            num_dispatch_domains = json_get_int "num_dispatch_domains" base.vm_runtime.num_dispatch_domains obj;
            enable_junk_instructions = json_get_bool "enable_junk_instructions" base.vm_runtime.enable_junk_instructions obj;
            enable_super_operators = json_get_bool "enable_super_operators" base.vm_runtime.enable_super_operators obj;
            stack_scrambling = json_get_bool "stack_scrambling" base.vm_runtime.stack_scrambling obj;
            memory_sanitization = json_get_bool "memory_sanitization" base.vm_runtime.memory_sanitization obj;
          }
    in

    let c_macro =
      match json_get_obj "c_macro" json with
      | None -> base.c_macro
      | Some obj ->
          {
            enabled = json_get_bool "enabled" base.c_macro.enabled obj;
            obfuscate_strings = json_get_bool "obfuscate_strings" base.c_macro.obfuscate_strings obj;
            obfuscate_constants = json_get_bool "obfuscate_constants" base.c_macro.obfuscate_constants obj;
            obfuscate_arithmetic = json_get_bool "obfuscate_arithmetic" base.c_macro.obfuscate_arithmetic obj;
            nanomites = json_get_bool "nanomites" base.c_macro.nanomites obj;
          }
    in

    Ok { seed; cff; mba; anti_pushan; anti_tamper; vm_runtime; c_macro }
  with exn ->
    Error (Printf.sprintf "JSON configuration parsing failed: %s" (Printexc.to_string exn))

let to_yojson (cfg : t) : Yojson.Basic.t =
  let seed_field =
    match cfg.seed with
    | Some s -> [ ("seed", `Int s) ]
    | None -> []
  in
  let kvs = seed_field @ [
    ("cff", `Assoc [
      ("enabled", `Bool cfg.cff.enabled);
      ("obfuscate_states", `Bool cfg.cff.obfuscate_states);
      ("inject_opaque_predicates", `Bool cfg.cff.inject_opaque_predicates);
    ]);
    ("mba", `Assoc [
      ("enabled", `Bool cfg.mba.enabled);
      ("depth", `Int cfg.mba.depth);
      ("engine", `String (string_of_mba_engine cfg.mba.engine));
    ]);
    ("anti_pushan", `Assoc [
      ("enabled", `Bool cfg.anti_pushan.enabled);
      ("running_key", `Bool cfg.anti_pushan.running_key);
    ]);
    ("anti_tamper", `Assoc [
      ("enabled", `Bool cfg.anti_tamper.enabled);
      ("smc", `Bool cfg.anti_tamper.smc);
      ("hardware_timing_probes", `Bool cfg.anti_tamper.hardware_timing_probes);
      ("memory_integrity_scanner", `Bool cfg.anti_tamper.memory_integrity_scanner);
      ("anti_emulation", `Bool cfg.anti_tamper.anti_emulation);
    ]);
    ("vm_runtime", `Assoc [
      ("num_dispatch_domains", `Int cfg.vm_runtime.num_dispatch_domains);
      ("enable_junk_instructions", `Bool cfg.vm_runtime.enable_junk_instructions);
      ("enable_super_operators", `Bool cfg.vm_runtime.enable_super_operators);
      ("stack_scrambling", `Bool cfg.vm_runtime.stack_scrambling);
      ("memory_sanitization", `Bool cfg.vm_runtime.memory_sanitization);
    ]);
    ("c_macro", `Assoc [
      ("enabled", `Bool cfg.c_macro.enabled);
      ("obfuscate_strings", `Bool cfg.c_macro.obfuscate_strings);
      ("obfuscate_constants", `Bool cfg.c_macro.obfuscate_constants);
      ("obfuscate_arithmetic", `Bool cfg.c_macro.obfuscate_arithmetic);
      ("nanomites", `Bool cfg.c_macro.nanomites);
    ]);
  ] in
  `Assoc kvs

let from_json_string str =
  try
    let json = Yojson.Basic.from_string str in
    from_yojson json
  with exn ->
    Error (Printf.sprintf "JSON parse error: %s" (Printexc.to_string exn))

let from_file path =
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "Configuration file not found: %s" path)
  else
    try
      let json = Yojson.Basic.from_file path in
      from_yojson json
    with exn ->
      Error (Printf.sprintf "Failed to read configuration file %s: %s" path (Printexc.to_string exn))

let to_json_string ?(pretty = true) cfg =
  let json = to_yojson cfg in
  if pretty then Yojson.Basic.pretty_to_string json
  else Yojson.Basic.to_string json

let save_to_file path cfg =
  let str = to_json_string ~pretty:true cfg in
  let oc = open_out path in
  output_string oc str;
  output_char oc '\n';
  close_out oc
