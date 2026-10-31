(**
  Flags_Verified.fst — Processor Flag Semantics Verification (Lazy Flags) for ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Proves:
  1. Correctness of Carry (CF), Zero (ZF), Sign (SF), and Overflow (OF) flag calculation.
  2. Equivalence of lazy bitwise expressions to x86_64 / ARM64 hardware semantics.
  3. Fundamental branch condition theorems (Jcc):
     - L (Less): SF <> OF <=> to_signed a < to_signed b
     - GE (Greater or Equal): SF == OF <=> to_signed a >= to_signed b
     - LE (Less or Equal): ZF || (SF <> OF) <=> to_signed a <= to_signed b
     - G (Greater): ~ZF && (SF == OF) <=> to_signed a > to_signed b
     - B (Below): CF <=> a < b (unsigned)
     - AE (Above or Equal): ~CF <=> a >= b (unsigned)
     - BE (Below or Equal): CF || ZF <=> a <= b (unsigned)
     - A (Above): ~CF && ~ZF <=> a > b (unsigned)
*)
module Flags_Verified

open FStar.UInt
module C = FStar.Classical
module M = FStar.Math.Lemmas

let w : pos = 64
type u64 = uint_t w

(* Signed interpretation of 64-bit integer (Two's complement) *)
let to_signed (x:u64) : int =
  if x >= pow2 63 then x - pow2 64 else x

let min_int64 : int = - (pow2 63)
let max_int64 : int = pow2 63 - 1

(* ------------------------------------------------------------------ *)
(* 1. Modular Arithmetic Helper Lemmas                                *)
(* ------------------------------------------------------------------ *)

let lemma_add_mod_val (a:u64) (b:u64) : Lemma
  (add_mod #w a b == (if a + b < pow2 64 then a + b else a + b - pow2 64)) =
  if a + b < pow2 64 then
    M.small_mod (a + b) (pow2 64)
  else begin
    M.small_mod (a + b - pow2 64) (pow2 64);
    M.modulo_addition_lemma (a + b - pow2 64) (pow2 64) 1
  end

let lemma_sub_mod_val (a:u64) (b:u64) : Lemma
  (sub_mod #w a b == (if a >= b then a - b else a - b + pow2 64)) =
  if a >= b then
    M.small_mod (a - b) (pow2 64)
  else begin
    M.small_mod (a - b + pow2 64) (pow2 64);
    M.modulo_addition_lemma (a - b + pow2 64) (pow2 64) (-1)
  end

(* ------------------------------------------------------------------ *)
(* 2. Carry Flag (CF)                                                 *)
(* ------------------------------------------------------------------ *)

(** Hardware definition of CF for ADD: unsigned overflow occurred *)
let hw_cf_add (a:u64) (b:u64) : bool =
  a + b >= pow2 64

(** Lazy CF evaluation in VM-IR: dst < a *)
let lazy_cf_add (a:u64) (b:u64) : bool =
  add_mod #w a b < a

val theorem_cf_add : a:u64 -> b:u64 ->
  Lemma (hw_cf_add a b == lazy_cf_add a b)
let theorem_cf_add a b =
  lemma_add_mod_val a b

(** Hardware definition of CF (Borrow) for SUB: a < b *)
let hw_cf_sub (a:u64) (b:u64) : bool =
  a < b

let lazy_cf_sub (a:u64) (b:u64) : bool =
  a < b

val theorem_cf_sub : a:u64 -> b:u64 ->
  Lemma (hw_cf_sub a b == lazy_cf_sub a b)
let theorem_cf_sub a b = ()

(* ------------------------------------------------------------------ *)
(* 3. Zero Flag (ZF) & Sign Flag (SF)                                 *)
(* ------------------------------------------------------------------ *)

let compute_zf (res:u64) : bool =
  res = 0

let compute_sf (res:u64) : bool =
  msb #w res

val theorem_zf : res:u64 ->
  Lemma (compute_zf res == (res = 0))
let theorem_zf res = ()

val theorem_sf : res:u64 ->
  Lemma (compute_sf res == (to_signed res < 0))
let theorem_sf res =
  lemma_msb_pow2 #w res

(* ------------------------------------------------------------------ *)
(* 4. Overflow Flag (OF)                                              *)
(* ------------------------------------------------------------------ *)

(** Hardware definition of OF for ADD: signed overflow *)
let hw_of_add (a:u64) (b:u64) : bool =
  let sa = to_signed a in
  let sb = to_signed b in
  let sum = sa + sb in
  sum < min_int64 || sum > max_int64

(** Lazy OF evaluation for ADD: sign_bit ((a ^ dst) & (b ^ dst)) *)
let lazy_of_add (a:u64) (b:u64) : bool =
  let dst = add_mod #w a b in
  msb #w (logand #w (logxor #w a dst) (logxor #w b dst))

val theorem_of_add : a:u64 -> b:u64 ->
  Lemma (hw_of_add a b == lazy_of_add a b)
let theorem_of_add a b =
  let dst = add_mod #w a b in
  logand_definition #w (logxor #w a dst) (logxor #w b dst) 0;
  logxor_definition #w a dst 0;
  logxor_definition #w b dst 0;
  lemma_msb_pow2 #w a;
  lemma_msb_pow2 #w b;
  lemma_msb_pow2 #w dst;
  lemma_add_mod_val a b

(** Hardware definition of OF for SUB: signed overflow *)
let hw_of_sub (a:u64) (b:u64) : bool =
  let sa = to_signed a in
  let sb = to_signed b in
  let diff = sa - sb in
  diff < min_int64 || diff > max_int64

(** Lazy OF evaluation for SUB: sign_bit ((a ^ b) & (a ^ dst)) *)
let lazy_of_sub (a:u64) (b:u64) : bool =
  let dst = sub_mod #w a b in
  msb #w (logand #w (logxor #w a b) (logxor #w a dst))

val theorem_of_sub : a:u64 -> b:u64 ->
  Lemma (hw_of_sub a b == lazy_of_sub a b)
let theorem_of_sub a b =
  let dst = sub_mod #w a b in
  logand_definition #w (logxor #w a b) (logxor #w a dst) 0;
  logxor_definition #w a b 0;
  logxor_definition #w a dst 0;
  lemma_msb_pow2 #w a;
  lemma_msb_pow2 #w b;
  lemma_msb_pow2 #w dst;
  lemma_sub_mod_val a b

(* ------------------------------------------------------------------ *)
(* 5. Branch Condition Theorems (Jcc / Branch Conditions)             *)
(* ------------------------------------------------------------------ *)

let cond_l (sf:bool) (of_:bool) : bool =
  sf <> of_

let cond_ge (sf:bool) (of_:bool) : bool =
  sf = of_

let cond_le (zf:bool) (sf:bool) (of_:bool) : bool =
  zf || (sf <> of_)

let cond_g (zf:bool) (sf:bool) (of_:bool) : bool =
  (not zf) && (sf = of_)

let cond_b (cf:bool) : bool =
  cf

let cond_ae (cf:bool) : bool =
  not cf

let cond_be (cf:bool) (zf:bool) : bool =
  cf || zf

let cond_a (cf:bool) (zf:bool) : bool =
  (not cf) && (not zf)

(** Fundamental x86 theorem: Less (L) equivalent to to_signed a < to_signed b *)
val theorem_cond_l : a:u64 -> b:u64 ->
  Lemma (cond_l (compute_sf (sub_mod #w a b)) (lazy_of_sub a b) == (to_signed a < to_signed b))
let theorem_cond_l a b =
  theorem_sf (sub_mod #w a b);
  theorem_of_sub a b;
  lemma_sub_mod_val a b

(** Greater or Equal (GE) *)
val theorem_cond_ge : a:u64 -> b:u64 ->
  Lemma (cond_ge (compute_sf (sub_mod #w a b)) (lazy_of_sub a b) == (to_signed a >= to_signed b))
let theorem_cond_ge a b =
  theorem_sf (sub_mod #w a b);
  theorem_of_sub a b;
  lemma_sub_mod_val a b

(** Less or Equal (LE) *)
val theorem_cond_le : a:u64 -> b:u64 ->
  Lemma (cond_le (compute_zf (sub_mod #w a b)) (compute_sf (sub_mod #w a b)) (lazy_of_sub a b) ==
         (to_signed a <= to_signed b))
let theorem_cond_le a b =
  theorem_zf (sub_mod #w a b);
  theorem_sf (sub_mod #w a b);
  theorem_of_sub a b;
  lemma_sub_mod_val a b

(** Greater (G) *)
val theorem_cond_g : a:u64 -> b:u64 ->
  Lemma (cond_g (compute_zf (sub_mod #w a b)) (compute_sf (sub_mod #w a b)) (lazy_of_sub a b) ==
         (to_signed a > to_signed b))
let theorem_cond_g a b =
  theorem_zf (sub_mod #w a b);
  theorem_sf (sub_mod #w a b);
  theorem_of_sub a b;
  lemma_sub_mod_val a b

(** Below (B / Unsigned Less) *)
val theorem_cond_b : a:u64 -> b:u64 ->
  Lemma (cond_b (lazy_cf_sub a b) == (a < b))
let theorem_cond_b a b = ()

(** Above or Equal (AE / Unsigned Greater or Equal) *)
val theorem_cond_ae : a:u64 -> b:u64 ->
  Lemma (cond_ae (lazy_cf_sub a b) == (a >= b))
let theorem_cond_ae a b = ()

(** Below or Equal (BE / Unsigned Less or Equal) *)
val theorem_cond_be : a:u64 -> b:u64 ->
  Lemma (cond_be (lazy_cf_sub a b) (compute_zf (sub_mod #w a b)) == (a <= b))
let theorem_cond_be a b =
  lemma_sub_mod_val a b

(** Above (A / Unsigned Greater) *)
val theorem_cond_a : a:u64 -> b:u64 ->
  Lemma (cond_a (lazy_cf_sub a b) (compute_zf (sub_mod #w a b)) == (a > b))
let theorem_cond_a a b =
  lemma_sub_mod_val a b
