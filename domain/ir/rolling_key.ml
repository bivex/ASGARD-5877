(* Anti-Pushan block-chained rolling key: canonical OCaml mirror of the C++ keystream.
   The C++ side lives in the emitted VM context (key64_for_offset / anchor_key /
   advance_key_step) and the FETCH_NEXT dispatch macro. Both sides must agree
   bit-for-bit; test/test_anti_pushan.ml pins the correspondence. *)

open Random_visa_constants.Magic_numbers

(* SplitMix64-style positional PRF, mirrored from the emitted key64_for_offset. *)
let key64_for_offset (seed : int32) (offset : int) : int64 =
  let s64 = Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL in
  let x0 = Int64.logxor (Int64.logor (Int64.shift_left s64 32) (Int64.logxor s64 golden_ratio_32))
                        (Int64.mul (Int64.of_int offset) sqrt2_fraction_64) in
  let x1 = Int64.mul (Int64.logxor x0 (Int64.shift_right_logical x0 30)) splitmix64_gamma in
  let x2 = Int64.mul (Int64.logxor x1 (Int64.shift_right_logical x1 27)) splitmix64_mix in
  Int64.logxor x2 (Int64.shift_right_logical x2 31)

(* Domain-separated block-entry anchor. Must NOT equal key64_for_offset itself,
   otherwise the first in-block mask (k_pos lxor anchor) collapses to zero. *)
let anchor_key (seed : int32) (offset : int) : int64 =
  key64_for_offset (Int32.logxor seed murmur3_32_c1) (offset lxor (Int64.to_int salt_leet_13375877))

(* Anti-DSE branch-invariant polynomial key updates (P2-01):
   Eliminates static key ^= fixup_const at CFG merge points.
   K_{new} = H(K_{old} ^ (C * Delta)) where H is SplitMix64 non-linear permutation. *)

let poly_hash64 (x : int64) : int64 =
  let x1 = Int64.mul (Int64.logxor x (Int64.shift_right_logical x 30)) splitmix64_gamma in
  let x2 = Int64.mul (Int64.logxor x1 (Int64.shift_right_logical x1 27)) splitmix64_mix in
  Int64.logxor x2 (Int64.shift_right_logical x2 31)

(* One step of the in-block chain, mirroring C++ advance_key_step exactly:
   x = k ^ (op*0x9E3779B97F4A7C15 + (dst<<24) + imm); xh = poly_hash64(x);
   rot = ROR23(xh); (rot * 0xBF58476D1CE4E5B9) ^ 0x5877CAFE1337BEEF.
   The poly_hash64 (SplitMix64 finalizer) inside the step breaks the F2 /
   Z/2^64 affine structure of the old chain (rot/xor/odd-mul only): carries
   from its two odd multiplications defeat linear key recovery via Gaussian
   elimination and linear SMT.  Int64 arithmetic is modulo 2^64, matching
   uint64_t wraparound. *)
let advance_key_step (k : int64) (op : int) (dst : int) (imm : int64) : int64 =
  let x = Int64.logxor k
      (Int64.add
         (Int64.add
            (Int64.mul (Int64.of_int op) golden_ratio_64)
            (Int64.shift_left (Int64.of_int dst) 24))
         imm) in
  let xh = poly_hash64 x in
  let rot = Int64.logor (Int64.shift_right_logical xh 23) (Int64.shift_left xh 41) in
  Int64.logxor (Int64.mul rot splitmix64_gamma) salt_xwcafe_leetbeef

let sign_extend_32 (v : int64) : int64 =
  if Int64.logand v 0x80000000L <> 0L then Int64.logor v 0xFFFFFFFF00000000L else v

type word_layout = {
  op_shift : int;
  dst_shift : int;
  src_shift : int;
}

let default_word_layout = {
  op_shift = 0;
  dst_shift = 8;
  src_shift = 13;
}

let layouts = [|
  { op_shift = 0; dst_shift = 8; src_shift = 13 };
  { op_shift = 0; dst_shift = 13; src_shift = 8 };
  { op_shift = 5; dst_shift = 0; src_shift = 13 };
  { op_shift = 5; dst_shift = 13; src_shift = 0 };
  { op_shift = 10; dst_shift = 0; src_shift = 5 };
  { op_shift = 10; dst_shift = 5; src_shift = 0 };
|]

let layout_of_seed (seed : int32) : word_layout =
  let idx = (Int32.to_int (Int32.logand seed 0x7FFFFFFFl)) mod 6 in
  layouts.(idx)

(* Field extraction from a packed plaintext word, exactly as the C++ FETCH_NEXT
   macro does it.  The runtime immediate is the SIGN-EXTENDED 32-bit slice of
   bits 18..49, not the 46-bit immediate the encoder packed — chain simulation
   must use this truncated view, never the source immediate. *)
let decode_fields ?(layout = default_word_layout) (w : int64) : int * int * int * int64 =
  let op = Int64.to_int (Int64.logand (Int64.shift_right_logical w layout.op_shift) 0xFFL) in
  let dst = Int64.to_int (Int64.logand (Int64.shift_right_logical w layout.dst_shift) 0x1FL) in
  let src = Int64.to_int (Int64.logand (Int64.shift_right_logical w layout.src_shift) 0x1FL) in
  let imm = sign_extend_32 (Int64.logand (Int64.shift_right_logical w 18) 0xFFFFFFFFL) in
  (op, dst, src, imm)

let poly_multiplier_of_seed (seed : int32) : int64 =
  let s64 = Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL in
  let mixed = Int64.logxor fnv1a_64_prime (Int64.mul s64 sqrt2_fraction_64) in
  Int64.logor mixed 1L

let poly_init_of_seed (seed : int32) : int64 =
  let s64 = Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL in
  Int64.logxor fnv1a_64_offset_basis (Int64.mul s64 golden_ratio_64)


let unshift_xor_right (y : int64) (shift : int) : int64 =
  let rec loop acc s =
    if s >= 64 then acc
    else loop (Int64.logxor acc (Int64.shift_right_logical y s)) (s + shift)
  in
  loop y shift

let mod_inverse_64 (a : int64) : int64 =
  let rec iter x i =
    if i >= 6 then x
    else
      let next_x = Int64.mul x (Int64.sub 2L (Int64.mul a x)) in
      iter next_x (i + 1)
  in
  iter a 0

let poly_unhash64 (y : int64) : int64 =
  let x2 = unshift_xor_right y 31 in
  let inv2 = mod_inverse_64 splitmix64_mix in
  let w1 = Int64.mul x2 inv2 in
  let x1 = unshift_xor_right w1 27 in
  let inv1 = mod_inverse_64 splitmix64_gamma in
  let w0 = Int64.mul x1 inv1 in
  unshift_xor_right w0 30

let branch_invariant_poly_update ~(key : int64) ~(path_delta : int64) ~(poly_const : int64) : int64 =
  let c = Int64.logor poly_const 1L in
  let term = Int64.mul c path_delta in
  poly_hash64 (Int64.logxor key term)

let solve_path_delta ~(k_old : int64) ~(k_target : int64) ~(poly_const : int64) : int64 =
  let c = Int64.logor poly_const 1L in
  let c_inv = mod_inverse_64 c in
  let target_pre = poly_unhash64 k_target in
  let term = Int64.logxor k_old target_pre in
  Int64.mul term c_inv

let _m_const = splitmix64_gamma
let m_inv   = splitmix64_gamma_inverse (* Formally verified in fstar/Rolling_Key_Verified.fst *)
let c_const = salt_xwcafe_leetbeef
let phi_op  = golden_ratio_64

let rol64 x n =
  Int64.logor (Int64.shift_left x n) (Int64.shift_right_logical x (64 - n))

(** Solves for 64-bit delta_imm such that advance_key_step(k_in, op, dst, delta_imm) == k_target.
    Inverts the non-linear step via poly_unhash64 (exact SplitMix64 inverse):
    k_target = ((ROR23(poly_hash64(x)) * gamma) ^ C)  =>  x recovered by
    un-C, un-mul, un-rot, poly_unhash64.  The step is still bijective —
    only its LINEAR structure is gone. *)
let solve_join_compensation ~(k_in : int64) ~(k_target : int64) ~(op : int) ~(dst : int) : int64 =
  let step1 = Int64.logxor k_target c_const in
  let unmul = Int64.mul step1 m_inv in
  let unrot = rol64 unmul 23 in
  let x_req = poly_unhash64 unrot in
  let op_part = Int64.mul (Int64.of_int op) phi_op in
  let dst_part = Int64.shift_left (Int64.of_int dst) 24 in
  Int64.sub x_req (Int64.add (Int64.add k_in op_part) dst_part)


