open Protection_types
open Protection_presets

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

let json_get_int64 key default json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Int i) -> Int64.of_int i
      | Some (`String s) -> (
          match Int64.of_string_opt s with
          | Some v -> v
          | None -> default)
      | _ -> default)
  | _ -> default

let json_get_int_opt key json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Int i) -> Some i
      | _ -> None)
  | _ -> None

let parse_bloat_mode str =
  match String.lowercase_ascii (String.trim str) with
  | "compact" | "min" | "low" -> `Compact
  | "heavy" | "high" -> `Heavy
  | "insane" | "max" -> `Insane
  | "balanced" | _ -> `Balanced

let string_of_bloat_mode = function
  | `Compact -> "compact"
  | `Balanced -> "balanced"
  | `Heavy -> "heavy"
  | `Insane -> "insane"

let json_get_float key default json =
  match json with
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`Float f) -> f
      | Some (`Int i) -> float_of_int i
      | _ -> default)
  | _ -> default

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

    let crypto =
      match json_get_obj "crypto" json with
      | None -> base.crypto
      | Some obj ->
          {
            rounds = json_get_int "rounds" base.crypto.rounds obj;
            key_bits = json_get_int "key_bits" base.crypto.key_bits obj;
          }
    in

    let bloat =
      match json_get_obj "bloat" json with
      | None -> base.bloat
      | Some obj ->
          let mode_str = json_get_string "mode" (string_of_bloat_mode base.bloat.mode) obj in
          {
            mode = parse_bloat_mode mode_str;
            target_size_budget_kb = json_get_int_opt "target_size_budget_kb" obj;
            junk_density = json_get_float "junk_density" base.bloat.junk_density obj;
          }
    in

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
            nanomites = json_get_bool "nanomites" base.anti_tamper.nanomites obj;
            direct_syscalls = json_get_bool "direct_syscalls" base.anti_tamper.direct_syscalls obj;
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
            vector_isa = json_get_bool "vector_isa" base.vm_runtime.vector_isa obj;
          }
    in

    let c_macro =
      match json_get_obj "c_macro" json with
      | None -> base.c_macro
      | Some obj ->
          {
            enabled = json_get_bool "enabled" base.c_macro.enabled obj;
            macro_prefix = json_get_string "macro_prefix" base.c_macro.macro_prefix obj;
            obfuscate_strings = json_get_bool "obfuscate_strings" base.c_macro.obfuscate_strings obj;
            obfuscate_constants = json_get_bool "obfuscate_constants" base.c_macro.obfuscate_constants obj;
            obfuscate_arithmetic = json_get_bool "obfuscate_arithmetic" base.c_macro.obfuscate_arithmetic obj;
            opaque_predicates = json_get_bool "opaque_predicates" base.c_macro.opaque_predicates obj;
            api_hashing = json_get_bool "api_hashing" base.c_macro.api_hashing obj;
            anti_debug = json_get_bool "anti_debug" base.c_macro.anti_debug obj;
            signal_dispatch = json_get_bool "signal_dispatch" base.c_macro.signal_dispatch obj;
            nanomites = json_get_bool "nanomites" base.c_macro.nanomites obj;
            timing_guard = json_get_bool "timing_guard" base.c_macro.timing_guard obj;
            timing_threshold_ticks = json_get_int64 "timing_threshold_ticks" base.c_macro.timing_threshold_ticks obj;
          }
    in

    Ok { seed; crypto; bloat; cff; mba; anti_pushan; anti_tamper; vm_runtime; c_macro }
  with exn ->
    Error (Printf.sprintf "JSON configuration parsing failed: %s" (Printexc.to_string exn))

let to_yojson (cfg : t) : Yojson.Basic.t =
  let seed_field =
    match cfg.seed with
    | Some s -> [ ("seed", `Int s) ]
    | None -> []
  in
  let kvs = seed_field @ [
    ("crypto", `Assoc [
      ("rounds", `Int cfg.crypto.rounds);
      ("key_bits", `Int cfg.crypto.key_bits);
    ]);
    ("bloat", `Assoc ([
      ("mode", `String (string_of_bloat_mode cfg.bloat.mode));
      ("junk_density", `Float cfg.bloat.junk_density);
    ] @ (match cfg.bloat.target_size_budget_kb with Some b -> [ ("target_size_budget_kb", `Int b) ] | None -> [])));
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
      ("nanomites", `Bool cfg.anti_tamper.nanomites);
      ("direct_syscalls", `Bool cfg.anti_tamper.direct_syscalls);
    ]);
    ("vm_runtime", `Assoc [
      ("num_dispatch_domains", `Int cfg.vm_runtime.num_dispatch_domains);
      ("enable_junk_instructions", `Bool cfg.vm_runtime.enable_junk_instructions);
      ("enable_super_operators", `Bool cfg.vm_runtime.enable_super_operators);
      ("stack_scrambling", `Bool cfg.vm_runtime.stack_scrambling);
      ("memory_sanitization", `Bool cfg.vm_runtime.memory_sanitization);
      ("vector_isa", `Bool cfg.vm_runtime.vector_isa);
    ]);
    ("c_macro", `Assoc [
      ("enabled", `Bool cfg.c_macro.enabled);
      ("macro_prefix", `String cfg.c_macro.macro_prefix);
      ("obfuscate_strings", `Bool cfg.c_macro.obfuscate_strings);
      ("obfuscate_constants", `Bool cfg.c_macro.obfuscate_constants);
      ("obfuscate_arithmetic", `Bool cfg.c_macro.obfuscate_arithmetic);
      ("opaque_predicates", `Bool cfg.c_macro.opaque_predicates);
      ("api_hashing", `Bool cfg.c_macro.api_hashing);
      ("anti_debug", `Bool cfg.c_macro.anti_debug);
      ("signal_dispatch", `Bool cfg.c_macro.signal_dispatch);
      ("nanomites", `Bool cfg.c_macro.nanomites);
      ("timing_guard", `Bool cfg.c_macro.timing_guard);
      ("timing_threshold_ticks", `String (Int64.to_string cfg.c_macro.timing_threshold_ticks));
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
