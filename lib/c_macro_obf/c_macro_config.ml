type config = {
  seed : int;
  mba_depth : int;
  obfuscate_strings : bool;
  obfuscate_constants : bool;
  obfuscate_arithmetic : bool;
  inject_opaque_predicates : bool;
  api_hashing : bool;
  anti_debug : bool;
  signal_dispatch : bool;
  nanomites : bool;
  timing_guard : bool;
  timing_threshold_ticks : int64;
  macro_prefix : string;
}

let default_config = {
  seed = 42;
  mba_depth = 2;
  obfuscate_strings = true;
  obfuscate_constants = true;
  obfuscate_arithmetic = true;
  inject_opaque_predicates = true;
  api_hashing = true;
  anti_debug = true;
  signal_dispatch = false;
  nanomites = false;
  timing_guard = true;
  timing_threshold_ticks = 50000000L;
  macro_prefix = "ASG_";
}

let xorshift32 seed =
  let x = ref (if seed = 0 then 0x1337BEEF else seed land 0x7FFFFFFF) in
  x := !x lxor (!x lsl 13);
  x := !x lxor (!x lsr 17);
  x := !x lxor (!x lsl 5);
  let res = !x land 0x7FFFFFFF in
  if res = 0 then 0x5A5A5A5A else res

let rand_u64 rng =
  let hi = Random.State.int64 rng 0x100000000L in
  let lo = Random.State.int64 rng 0x100000000L in
  Int64.logor (Int64.shift_left hi 32) lo
