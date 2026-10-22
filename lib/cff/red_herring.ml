open Random_visa_constants.Magic_numbers

(** Red Herring Complexity — Effort Asymmetry & Cognitive Deception Engine.
    ────────────────────────────────────────────────────────────────────────
    Decorrelates structural CFG complexity (block counts, edge density,
    MBA depth, state aliasing) from code semantic importance.
    Applies asymmetric pseudo-random noise fields across basic blocks,
    ensuring critical security logic appears structurally plain and uniform
    while harmless or decoy checks are amplified into high-entropy labyrinths. *)

type effort_tier =
  | StealthPlain
  | Modulated
  | RedHerringMonster

let splitmix64 s =
  let s = Int64.add s golden_ratio_64 in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z splitmix64_gamma in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z splitmix64_mix in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  z

let hash_block_noise ~(seed : int64) ~(block_id : int) ~(salt : int) : int64 =
  let bid_mix = Int64.mul (Int64.of_int (block_id + 1)) salt_xwcafe_beef in
  let salt_mix = Int64.mul (Int64.of_int (salt + 1)) salt_deadbeef_5a5a5a5a in
  let combined = Int64.logxor (Int64.logxor seed bid_mix) salt_mix in
  splitmix64 combined

let positive_mod (v : int64) (m : int) : int =
  if m <= 0 then 0
  else
    let u = Int64.logand v 0x7FFFFFFF_FFFFFFFFL in
    let r = Int64.to_int (Int64.rem u (Int64.of_int m)) in
    (r + m) mod m

let block_effort_tier ~(seed : int64) ~(block_id : int) : effort_tier =
  let noise_val = hash_block_noise ~seed ~block_id ~salt:0x1337 in
  let score = positive_mod noise_val 100 in
  if score < 30 then StealthPlain
  else if score >= 80 then RedHerringMonster
  else Modulated

let modulate_split_rate ~(base_rate : int) ~(seed : int64) ~(block_id : int) : int =
  match block_effort_tier ~seed ~block_id with
  | StealthPlain -> 0
  | RedHerringMonster -> 100
  | Modulated ->
      let noise_val = hash_block_noise ~seed ~block_id ~salt:0x42 in
      let delta = (positive_mod noise_val 41) - 20 in (* -20..+20 *)
      Stdlib.max 10 (Stdlib.min 95 (base_rate + delta))

let modulate_mba_depth ~(base_depth : int) ~(seed : int64) ~(block_id : int) : int =
  match block_effort_tier ~seed ~block_id with
  | StealthPlain -> 1
  | RedHerringMonster -> Stdlib.min 5 (base_depth + 2)
  | Modulated ->
      let noise_val = hash_block_noise ~seed ~block_id ~salt:0x77 in
      let delta = (positive_mod noise_val 3) - 1 in (* -1..+1 *)
      Stdlib.max 1 (Stdlib.min 5 (base_depth + delta))

let modulate_ghost_count ~(max_ghosts : int) ~(seed : int64) ~(block_id : int) : int =
  if max_ghosts <= 0 then 0
  else
    match block_effort_tier ~seed ~block_id with
    | StealthPlain -> 0
    | RedHerringMonster -> max_ghosts
    | Modulated ->
        let noise_val = hash_block_noise ~seed ~block_id ~salt:0x99 in
        positive_mod noise_val (max_ghosts + 1)
