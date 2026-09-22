open Random_visa_ports
open Protect_ports
open Native_vm

let transform_source ~(config : Protection_config.t) ~(in_file : string) ~(out_c_file : string) ~(out_header_file : string) ~(rng : Random.State.t) : (unit, error) result =
  let seed_val = Random.State.int rng 0x3FFFFFFF in
  let c_cfg : C_macro_obf.config = {
    seed = seed_val;
    mba_depth = config.mba.depth;
    macro_prefix = config.c_macro.macro_prefix;
    obfuscate_strings = config.c_macro.obfuscate_strings;
    obfuscate_constants = config.c_macro.obfuscate_constants;
    obfuscate_arithmetic = config.c_macro.obfuscate_arithmetic;
    inject_opaque_predicates = config.c_macro.opaque_predicates;
    api_hashing = config.c_macro.api_hashing;
    anti_debug = config.c_macro.anti_debug;
    signal_dispatch = config.c_macro.signal_dispatch;
    nanomites = config.c_macro.nanomites;
    timing_guard = config.c_macro.timing_guard;
    timing_threshold_ticks = config.c_macro.timing_threshold_ticks;
  } in
  C_macro_obf.transform_file
    ~config:c_cfg
    ~in_file
    ~out_file:out_c_file
    ~header_file:(Some out_header_file)
    ()
