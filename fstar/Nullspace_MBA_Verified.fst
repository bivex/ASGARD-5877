(**
  Nullspace_MBA_Verified.fst — Verified Noise MBA Identity Engine for ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.
*)
module Nullspace_MBA_Verified

open FStar.UInt
module C = FStar.Classical

let w : pos = 64
type u64 = uint_t w

val xor_self_zero : a:u64 ->
  Lemma (logxor #w a a == 0)
let xor_self_zero a =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logxor #w a a) i = nth #w 0 i) =
    logxor_definition #w a a i;
    nth_zero #w i
  in
  C.forall_intro per_bit;
  nth_lemma #w (logxor #w a a) 0

val xor_pair_cancel : acc:u64 -> f_val:u64 ->
  Lemma (logxor #w (logxor #w acc f_val) f_val == acc)
let xor_pair_cancel acc f_val =
  let per_bit (i:nat{i < w}) : Lemma (nth #w (logxor #w (logxor #w acc f_val) f_val) i = nth #w acc i) =
    logxor_definition #w (logxor #w acc f_val) f_val i;
    logxor_definition #w acc f_val i
  in
  C.forall_intro per_bit;
  nth_lemma #w (logxor #w (logxor #w acc f_val) f_val) acc
