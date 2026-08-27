type alu_variant =
  | LinearStandard
  | MbaZhouEyrolles of int
  | MaskedSemiLinear of { mask_even : int64; mask_odd : int64 }
  | PolynomialOpaqueZero

type timing_probe_mode =
  | ProbeDisabled
  | SilentPoisoning of { threshold_cycles : int64; poison_mask : int64 }

type handler_mutation = {
  alu_variant       : alu_variant;
  has_opaque_branch : bool;
  timing_probe      : timing_probe_mode;
}

type t = {
  op_mutations            : (int, handler_mutation) Hashtbl.t;
  global_timing_threshold : int64;
}

let generate ~rng ~total_opcodes ?(enable_silent_poisoning = true) ?(max_mba_depth = 3) () =
  let tbl = Hashtbl.create total_opcodes in
  let threshold_cycles = 15000L in
  
  for op = 0 to total_opcodes - 1 do
    let alu_variant =
      match Random.State.int rng 4 with
      | 0 -> LinearStandard
      | 1 -> MbaZhouEyrolles (1 + Random.State.int rng max_mba_depth)
      | 2 ->
          MaskedSemiLinear {
            mask_even = 0x5555555555555555L;
            mask_odd  = -0x5555555555555556L;
          }
      | _ -> PolynomialOpaqueZero
    in
    
    let has_opaque_branch = Random.State.bool rng in
    
    let timing_probe =
      if enable_silent_poisoning && Random.State.int rng 100 < 30 then
        let poison_mask = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
        SilentPoisoning { threshold_cycles; poison_mask }
      else
        ProbeDisabled
    in
    
    Hashtbl.replace tbl op { alu_variant; has_opaque_branch; timing_probe }
  done;
  
  { op_mutations = tbl; global_timing_threshold = threshold_cycles }

let get_mutation profile op =
  match Hashtbl.find_opt profile.op_mutations op with
  | Some m -> m
  | None -> { alu_variant = LinearStandard; has_opaque_branch = false; timing_probe = ProbeDisabled }
