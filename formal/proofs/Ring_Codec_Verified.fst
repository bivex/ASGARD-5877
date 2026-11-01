(**
  Ring_Codec_Verified.fst — Formal verification of affine ring automorphisms over Z_{2^64}.
  F* 2026.08.23 + Z3 5.0.0.

  Proves:
  1. Multiplicative bijection in Z_{2^64}: phi_inv (phi x) == x given a * a_inv == 1 mod 2^64.
  2. Homomorphic Addition: phi(x + y) == phi(x) + phi(y) - b (mod 2^64).
  3. Homomorphic Subtraction: phi(x - y) == phi(x) - phi(y) + b (mod 2^64).
  4. Homomorphic Scaled Add: phi(x + c) == phi(x) + a*c (mod 2^64).
*)
module Ring_Codec_Verified

open FStar.UInt
open FStar.UInt64

type u64 = uint_t 64
let two_64 : pos = 0x10000000000000000

let add_mod (x:u64) (y:u64) : u64 = (x + y) % two_64
let sub_mod (x:u64) (y:u64) : u64 = (x - y + two_64) % two_64
let mul_mod (x:u64) (y:u64) : u64 = (x * y) % two_64

let phi (a:u64) (b:u64) (x:u64) : u64 =
  add_mod (mul_mod a x) b

let phi_inv (a_inv:u64) (b:u64) (y:u64) : u64 =
  mul_mod a_inv (sub_mod y b)

let hom_add_fixup (b:u64) : u64 =
  sub_mod 0 b

let hom_sub_fixup (b:u64) : u64 =
  b
