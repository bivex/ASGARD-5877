open Int64

type frame_scrambler = {
  n_slots   : int;
  coprime_p : int;
  inv_p     : int;
  offset_q  : int;
  frame_key : int64;
}

let rec gcd a b = if b = 0 then a else gcd b (a mod b)

let mod_inv (a : int) (m : int) : int =
  let rec ext_gcd a b =
    if b = 0 then (1, 0)
    else
      let (q, r) = (a / b, a mod b) in
      let (x, y) = ext_gcd b r in
      (y, x - q * y)
  in
  let (x, _) = ext_gcd a m in
  ((x mod m) + m) mod m

let gen_frame_scrambler (rng : Random.State.t) ~(n_slots : int) : frame_scrambler =
  assert (n_slots >= 4);
  let rec pick_coprime () =
    let cand = 1 + Random.State.int rng (n_slots - 1) in
    if gcd cand n_slots = 1 then cand else pick_coprime ()
  in
  let coprime_p = pick_coprime () in
  let inv_p = mod_inv coprime_p n_slots in
  let offset_q = Random.State.int rng n_slots in
  let frame_key = Random.State.int64 rng max_int in
  { n_slots; coprime_p; inv_p; offset_q; frame_key }

let logical_to_physical_slot (s : frame_scrambler) (logical_idx : int) : int =
  ((s.coprime_p * logical_idx + s.offset_q) mod s.n_slots + s.n_slots) mod s.n_slots

let physical_to_logical_slot (s : frame_scrambler) (phys_idx : int) : int =
  let diff = ((phys_idx - s.offset_q) mod s.n_slots + s.n_slots) mod s.n_slots in
  (diff * s.inv_p) mod s.n_slots

let slot_tweak_mask (s : frame_scrambler) ~(logical_idx : int) : int64 =
  let z = add s.frame_key (mul (of_int logical_idx) 0x9E3779B97F4A7C15L) in
  let z = mul (logxor z (shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  logxor z (shift_right_logical z 31)

let oblivious_store (s : frame_scrambler) (mem : int64 array) ~(logical_idx : int) (v : int64) : unit =
  let p_idx = logical_to_physical_slot s logical_idx in
  let mask  = slot_tweak_mask s ~logical_idx in
  mem.(p_idx) <- logxor v mask

let oblivious_load_with_decoys (s : frame_scrambler) (mem : int64 array)
    ~(logical_idx : int) ~(noise_seed : int64) : int64 * int list =
  let real_phys = logical_to_physical_slot s logical_idx in
  let base_rot  = (to_int (logand noise_seed 3L)) in
  (* Строим 4 физических индекса: 1 настоящий (в позиции base_rot) и 3 ложных *)
  let accessed_indices = List.init 4 (fun k ->
    if k = base_rot then real_phys
    else
      let fake_step = ((k * 7 + to_int (logand (shift_right_logical noise_seed (k * 5)) 0xFL)) mod (s.n_slots - 1)) + 1 in
      (real_phys + fake_step) mod s.n_slots
  ) in
  (* Арифметический выбор без ветвлений из 4 прочитанных ячеек *)
  let acc = ref 0L in
  List.iteri (fun k p_idx ->
    let raw_val = mem.(p_idx) in
    (* is_target = 1L если k == base_rot, иначе 0L *)
    let d = of_int (k lxor base_rot) in
    let is_target = sub 1L (shift_right_logical (logor d (neg d)) 63) in
    let bit_mask = neg is_target in
    acc := logor !acc (logand raw_val bit_mask)
  ) accessed_indices;
  let unmasked = logxor !acc (slot_tweak_mask s ~logical_idx) in
  (unmasked, accessed_indices)
