type t = {
  vlen : int;
  elen : int;
  default_sew : Types.Sew.t;
  default_lmul : Types.Lmul.t;
  tail_policy : Types.Tail_policy.t;
  mask_policy : Types.Mask_policy.t;
  num_vregs : int;
}

let is_power_of_2 n = n > 0 && (n land (n - 1)) = 0

let make
    ?(vlen = 128)
    ?(elen = 64)
    ?(default_sew = Types.Sew.E32)
    ?(default_lmul = Types.Lmul.M1)
    ?(tail_policy = Types.Tail_policy.Agnostic)
    ?(mask_policy = Types.Mask_policy.Agnostic)
    ?(num_vregs = 32)
    () =
  if vlen <= 0 || not (is_power_of_2 vlen) then
    Error (Errors.Invalid_config (Printf.sprintf "VLEN must be a power of 2, got %d" vlen))
  else if elen > vlen then
    Error (Errors.Invalid_config (Printf.sprintf "ELEN (%d) cannot exceed VLEN (%d)" elen vlen))
  else if num_vregs < 8 || not (is_power_of_2 num_vregs) then
    Error (Errors.Invalid_config (Printf.sprintf "num_vregs must be a power of 2 >= 8, got %d" num_vregs))
  else
    Ok { vlen; elen; default_sew; default_lmul; tail_policy; mask_policy; num_vregs }

let default = {
  vlen = 128;
  elen = 64;
  default_sew = Types.Sew.E32;
  default_lmul = Types.Lmul.M1;
  tail_policy = Types.Tail_policy.Agnostic;
  mask_policy = Types.Mask_policy.Agnostic;
  num_vregs = 32;
}


let vlen_bytes t = t.vlen / 8

let calculate_vlmax t sew lmul =
  let sew_bits = Types.Sew.to_bits sew in
  let mult = Types.Lmul.multiplier_val lmul in
  int_of_float ((float_of_int t.vlen /. float_of_int sew_bits) *. mult)
