open Random_visa_ports
open Protect_ports
open Native_vm

let transform_source ~(config : protection_config) ~(in_file : string) ~(out_c_file : string) ~(out_header_file : string) ~(rng : Random.State.t) : (unit, error) result =
  let raw_cfg : Protection_config.t = unwrap_config config in
  let seed_val = Random.State.int rng 0x3FFFFFFF in
  let c_cfg : C_macro_obf.config = {
    seed = seed_val;
    mba_depth = raw_cfg.mba.depth;
    macro_prefix = raw_cfg.c_macro.macro_prefix;
    obfuscate_strings = raw_cfg.c_macro.obfuscate_strings;
    obfuscate_constants = raw_cfg.c_macro.obfuscate_constants;
    obfuscate_arithmetic = raw_cfg.c_macro.obfuscate_arithmetic;
    inject_opaque_predicates = raw_cfg.c_macro.opaque_predicates;
    api_hashing = raw_cfg.c_macro.api_hashing;
    anti_debug = raw_cfg.c_macro.anti_debug;
    signal_dispatch = raw_cfg.c_macro.signal_dispatch;
    nanomites = raw_cfg.c_macro.nanomites;
    timing_guard = raw_cfg.c_macro.timing_guard;
    timing_threshold_ticks = raw_cfg.c_macro.timing_threshold_ticks;
  } in
  Logger.infof ~section:"C_MACRO" "Applying polymorphic macro obfuscation: in='%s', out='%s'" in_file out_c_file;
  if c_cfg.obfuscate_strings then
    Logger.infof ~section:"C_MACRO" "  ├─ Stack String Encryption: converting string literals to ASG_STR variadic static byte arrays";
  if c_cfg.obfuscate_constants then
    Logger.infof ~section:"C_MACRO" "  ├─ Constant Blinding: ASG_BLIND additive & XOR splitting active";
  if c_cfg.obfuscate_arithmetic then
    Logger.infof ~section:"C_MACRO" "  ├─ Mixed Boolean-Arithmetic: AST algebraic rewriting (depth=%d)" c_cfg.mba_depth;
  if c_cfg.inject_opaque_predicates then
    Logger.infof ~section:"C_MACRO" "  ├─ Opaque Predicates: non-linear polynomial invariant guards injected";
  if c_cfg.api_hashing then
    Logger.infof ~section:"C_MACRO" "  ├─ API Hashing: compile-time FNV-1a import elimination active";
  if c_cfg.timing_guard then
    Logger.infof ~section:"C_MACRO" "  ├─ Hardware Timing Probes: cycle delta threshold guard active (%Ld ticks)" c_cfg.timing_threshold_ticks;
  if c_cfg.nanomites then
    Logger.infof ~section:"C_MACRO" "  ├─ Dynamic Nanomites: signal-driven exception state machine active";
  Logger.infof ~section:"C_MACRO" "  └─ Companion header emitted: '%s'" out_header_file;
  C_macro_obf.transform_file
    ~config:c_cfg
    ~in_file
    ~out_file:out_c_file
    ~header_file:(Some out_header_file)
    ()

let run_c_obfuscation ~input ~out_file ~out_header ~seed ~strings ~consts ~mba_depth ~compile : (unit, error) result =
  let seed_val = match seed with Some s -> s | None -> Random.self_init (); Random.int 0x3FFFFFFF in
  let config : C_macro_obf.config = {
    seed = seed_val;
    mba_depth;
    obfuscate_strings = strings;
    obfuscate_constants = consts;
    obfuscate_arithmetic = true;
    inject_opaque_predicates = true;
    api_hashing = true;
    anti_debug = true;
    signal_dispatch = false;
    nanomites = false;
    timing_guard = true;
    timing_threshold_ticks = 50000000L;
    macro_prefix = "ASG_";
  } in
  let header_path = match out_header with
    | Some p -> p
    | None ->
        let dir = Filename.dirname out_file in
        Filename.concat (if dir = "" then "." else dir) "asgard_obf.h"
  in
  match C_macro_obf.transform_file ~config ~in_file:input ~out_file ~header_file:(Some header_path) () with
  | Error msg -> Error msg
  | Ok () ->
      Printf.printf "=== C MACRO OBFUSCATION COMPLETE ===\n";
      Printf.printf "  Input C Source:       %s\n" input;
      Printf.printf "  Obfuscated Output:    %s\n" out_file;
      Printf.printf "  Generated Header:     %s\n" header_path;
      Printf.printf "  Random Seed:          0x%X\n" seed_val;
      Printf.printf "  String Encryption:    %s\n" (if strings then "ENABLED" else "DISABLED");
      Printf.printf "  Constant Blinding:    %s\n" (if consts then "ENABLED" else "DISABLED");
      Printf.printf "  MBA Depth:            %d\n" mba_depth;
      Printf.printf "====================================\n\n";
      if compile then begin
        let bin_path = (try Filename.chop_extension out_file with _ -> out_file) ^ "_bin" in
        let comp_cmd = Printf.sprintf "clang -O2 -I%s %s -o %s" (Filename.dirname header_path) out_file bin_path in
        Printf.printf "[1/2] Compiling obfuscated C source with clang -O2...\n";
        let status = Sys.command comp_cmd in
        if status <> 0 then
          Error "Clang compilation failed"
        else begin
          Printf.printf "[2/2] Running Obfuscated Binary (%s):\n" bin_path;
          Printf.printf "--------------------------------------------------------\n";
          let run_code = Sys.command bin_path in
          Printf.printf "--------------------------------------------------------\n";
          Printf.printf "--- Execution Complete (Return Code: %d) ---\n" run_code;
          Ok ()
        end
      end else Ok ()
