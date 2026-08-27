(* Pairwise coprime primes such that M = m1 * m2 * m3 * m4 > 2^64 *)
let m1 = 65537L (* 2^16 + 1 *)
let m2 = 65521L (* Largest prime < 2^16 *)
let m3 = 65519L (* Second largest prime < 2^16 *)
let m4 = 65497L (* Third largest prime < 2^16 *)

type rns_val = {
  r1 : int64;
  r2 : int64;
  r3 : int64;
  r4 : int64;
}

let mod_pos (a : int64) (m : int64) : int64 =
  let rem = Int64.rem a m in
  if rem < 0L then Int64.add rem m else rem

(* Extended Euclidean Algorithm for Modular Inverse *)
let ext_gcd a b =
  let rec loop r0 r1 s0 s1 =
    if r1 = 0L then (r0, s0)
    else
      let q = Int64.div r0 r1 in
      let r2 = Int64.sub r0 (Int64.mul q r1) in
      let s2 = Int64.sub s0 (Int64.mul q s1) in
      loop r1 r2 s1 s2
  in
  loop a b 1L 0L

let inv_mod a m =
  let (_, s) = ext_gcd a m in
  mod_pos s m

(* Compute 2^63 mod m accurately *)
let two_pow_63_mod m =
  let rec pow2 exp =
    if exp = 0 then 1L
    else
      let half = pow2 (exp / 2) in
      let half_sq = mod_pos (Int64.mul half half) m in
      if exp mod 2 = 0 then half_sq
      else mod_pos (Int64.mul half_sq 2L) m
  in
  pow2 63

let two_63_m1 = two_pow_63_mod m1
let two_63_m2 = two_pow_63_mod m2
let two_63_m3 = two_pow_63_mod m3
let two_63_m4 = two_pow_63_mod m4

(** Computes unsigned 64-bit integer modulo m *)
let u64_mod (x : int64) (m : int64) (two_63_m : int64) : int64 =
  let low_63 = Int64.logand x 0x7FFFFFFFFFFFFFFFL in
  let rem_low = Int64.rem low_63 m in
  if x >= 0L then rem_low
  else mod_pos (Int64.add rem_low two_63_m) m

(* Precomputed modular inverses for Garner's Mixed Radix Algorithm *)
let inv_m1_mod_m2 = inv_mod m1 m2
let inv_m1_mod_m3 = inv_mod m1 m3
let inv_m1_mod_m4 = inv_mod m1 m4

let inv_m2_mod_m3 = inv_mod m2 m3
let inv_m2_mod_m4 = inv_mod m2 m4

let inv_m3_mod_m4 = inv_mod m3 m4

let encode (x : int64) : rns_val =
  {
    r1 = u64_mod x m1 two_63_m1;
    r2 = u64_mod x m2 two_63_m2;
    r3 = u64_mod x m3 two_63_m3;
    r4 = u64_mod x m4 two_63_m4;
  }

let add (a : rns_val) (b : rns_val) : rns_val =
  {
    r1 = mod_pos (Int64.add a.r1 b.r1) m1;
    r2 = mod_pos (Int64.add a.r2 b.r2) m2;
    r3 = mod_pos (Int64.add a.r3 b.r3) m3;
    r4 = mod_pos (Int64.add a.r4 b.r4) m4;
  }

let sub (a : rns_val) (b : rns_val) : rns_val =
  {
    r1 = mod_pos (Int64.sub a.r1 b.r1) m1;
    r2 = mod_pos (Int64.sub a.r2 b.r2) m2;
    r3 = mod_pos (Int64.sub a.r3 b.r3) m3;
    r4 = mod_pos (Int64.sub a.r4 b.r4) m4;
  }

let mul (a : rns_val) (b : rns_val) : rns_val =
  {
    r1 = mod_pos (Int64.mul a.r1 b.r1) m1;
    r2 = mod_pos (Int64.mul a.r2 b.r2) m2;
    r3 = mod_pos (Int64.mul a.r3 b.r3) m3;
    r4 = mod_pos (Int64.mul a.r4 b.r4) m4;
  }

(** Decodes an RNS 4-tuple back to 64-bit integer using Garner's Mixed-Radix Conversion *)
let decode (r : rns_val) : int64 =
  let v1 = r.r1 in
  
  let v2 =
    let diff = mod_pos (Int64.sub r.r2 v1) m2 in
    mod_pos (Int64.mul diff inv_m1_mod_m2) m2
  in
  
  let v3 =
    let diff1 = mod_pos (Int64.sub r.r3 v1) m3 in
    let term1 = mod_pos (Int64.mul diff1 inv_m1_mod_m3) m3 in
    let diff2 = mod_pos (Int64.sub term1 v2) m3 in
    mod_pos (Int64.mul diff2 inv_m2_mod_m3) m3
  in
  
  let v4 =
    let diff1 = mod_pos (Int64.sub r.r4 v1) m4 in
    let term1 = mod_pos (Int64.mul diff1 inv_m1_mod_m4) m4 in
    let diff2 = mod_pos (Int64.sub term1 v2) m4 in
    let term2 = mod_pos (Int64.mul diff2 inv_m2_mod_m4) m4 in
    let diff3 = mod_pos (Int64.sub term2 v3) m4 in
    mod_pos (Int64.mul diff3 inv_m3_mod_m4) m4
  in
  
  (* X = v1 + v2 * m1 + v3 * (m1 * m2) + v4 * (m1 * m2 * m3) mod 2^64 *)
  let term_v2 = Int64.mul v2 m1 in
  let term_v3 = Int64.mul v3 (Int64.mul m1 m2) in
  let term_v4 = Int64.mul v4 (Int64.mul (Int64.mul m1 m2) m3) in
  
  Int64.add (Int64.add v1 term_v2) (Int64.add term_v3 term_v4)
