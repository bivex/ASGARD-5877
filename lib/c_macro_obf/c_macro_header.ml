open C_macro_config

type feature_usage = {
  has_api_hashing : bool;
  has_anti_debug : bool;
  has_signal_dispatch : bool;
  has_timing_guard : bool;
  has_nanomites : bool;
}

let contains_sub s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  if len_sub > len_s then false
  else
    let found = ref false in
    for i = 0 to len_s - len_sub do
      if not !found && String.sub s i len_sub = sub then found := true
    done;
    !found

let detect_features ~prefix (source : string) : feature_usage =
  let p = prefix in
  {
    has_api_hashing = contains_sub source (p ^ "hash_api_str") || contains_sub source (p ^ "resolve_api_by_hash");
    has_anti_debug = contains_sub source (p ^ "ANTI_DEBUG") || contains_sub source (p ^ "is_debugger_present")
                     || contains_sub source (p ^ "check_ptrace") || contains_sub source (p ^ "check_hw_breakpoints");
    has_signal_dispatch = contains_sub source (p ^ "SIG_DISPATCH") || contains_sub source (p ^ "SIG_JUMP");
    has_timing_guard = contains_sub source (p ^ "TIMING_GUARD") || contains_sub source (p ^ "read_cpu_ticks");
    has_nanomites = contains_sub source (p ^ "NANOMITE_") || contains_sub source (p ^ "register_nanomite");
  }

let generate_header ?(config = default_config) ?source () =
  let p = config.macro_prefix in
  let b = Buffer.create 4096 in
  let (emit_api_hash, emit_timing, emit_anti_debug, emit_signal, emit_nanomites) =
    match source with
    | Some src ->
        let u = detect_features ~prefix:p src in
        ( config.api_hashing && u.has_api_hashing,
          config.timing_guard && u.has_timing_guard,
          config.anti_debug && u.has_anti_debug,
          config.signal_dispatch && u.has_signal_dispatch,
          u.has_nanomites )
    | None ->
        ( config.api_hashing,
          config.timing_guard,
          config.anti_debug,
          config.signal_dispatch,
          true )
  in
  C_macro_templates.emit_base_macros ~emit_api_hash b ~p;
  C_macro_guards.emit_guards_macros ~emit_timing ~emit_anti_debug ~emit_signal ~emit_nanomites b ~p;
  Buffer.contents b
