(**
  Poly_Verified.fst — Формальная верификация непрозрачных нуль-полиномов степени 5 над Z_{2^64} в ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Доказывает:
  1. Произведение двух последовательных чисел k*(k-1) всегда четно: k*(k-1) = 2*m.
  2. Для любого x произведение x*(x-2) или (x-1)*(x-3) делится на 8.
  3. Произведение 5 последовательных чисел poly5(x) делится на 8 для ВСЕХ x.
  4. Симметричный полином poly5_sym(x) делится на 8 для ВСЕХ x.
  5. Главная теорема 1: 2^61 * poly5(x) == 0 mod 2^64 (Opaque Polynomial Invariant).
  6. Главная теорема 2: 2^61 * poly5_sym(x) == 0 mod 2^64 (Symmetric Opaque Polynomial Invariant).
  7. Главная теорема 3: Нелинейный инвариант zero_inv5_nl(a, b) == 0 mod 2^64.
*)
module Poly_Verified

module M = FStar.Math.Lemmas

(* ------------------------------------------------------------------ *)
(* 1. Базовые леммы четности и делимости на 8                         *)
(* ------------------------------------------------------------------ *)

val lemma_consecutive_even : k:int ->
  Lemma ((k * (k - 1)) % 2 == 0)
let lemma_consecutive_even k =
  let rem = (k % 2 + 2) % 2 in
  let q = (k - rem) / 2 in
  assert (k == 2 * q + rem);
  assert (k * (k - 1) == 2 * (2 * q * q + q * (2 * rem - 1) + rem * (rem - 1) / 2))

val lemma_consecutive_plus_even : k:int ->
  Lemma ((k * (k + 1)) % 2 == 0)
let lemma_consecutive_plus_even k =
  lemma_consecutive_even (k + 1)

(** Лемма: Если x четный, то x*(x-2) делится на 8 *)
val lemma_even_step2_div8 : x:int ->
  Lemma (requires (x % 2 == 0))
        (ensures ((x * (x - 2)) % 8 == 0))
let lemma_even_step2_div8 x =
  let k = x / 2 in
  assert (x == 2 * k);
  assert (x - 2 == 2 * (k - 1));
  assert (x * (x - 2) == 4 * (k * (k - 1)));
  lemma_consecutive_even k;
  let m = (k * (k - 1)) / 2 in
  assert (k * (k - 1) == 2 * m);
  assert (x * (x - 2) == 8 * m)

(** Лемма: Если x нечетный, то (x-1)*(x-3) делится на 8 *)
val lemma_odd_step2_div8 : x:int ->
  Lemma (requires (x % 2 <> 0))
        (ensures (((x - 1) * (x - 3)) % 8 == 0))
let lemma_odd_step2_div8 x =
  let k = (x - 1) / 2 in
  assert (x - 1 == 2 * k);
  assert (x - 3 == 2 * (k - 1));
  assert ((x - 1) * (x - 3) == 4 * (k * (k - 1)));
  lemma_consecutive_even k;
  let m = (k * (k - 1)) / 2 in
  assert (k * (k - 1) == 2 * m);
  assert ((x - 1) * (x - 3) == 8 * m)

(* ------------------------------------------------------------------ *)
(* 2. Полиномы 5-й степени                                            *)
(* ------------------------------------------------------------------ *)

let poly5 (x:int) : int =
  x * (x - 1) * (x - 2) * (x - 3) * (x - 4)

let poly5_sym (x:int) : int =
  (x - 2) * (x - 1) * x * (x + 1) * (x + 2)

(** Теорема 1: poly5(x) делится на 8 для любого целого x *)
val theorem_poly5_divisible_by_8 : x:int ->
  Lemma ((poly5 x) % 8 == 0)
let theorem_poly5_divisible_by_8 x =
  if x % 2 = 0 then begin
    lemma_even_step2_div8 x;
    let m = (x * (x - 2)) / 8 in
    assert (x * (x - 2) == 8 * m);
    let other = (x - 1) * (x - 3) * (x - 4) in
    assert (poly5 x == (x * (x - 2)) * other);
    assert (poly5 x == 8 * (m * other))
  end else begin
    lemma_odd_step2_div8 x;
    let m = ((x - 1) * (x - 3)) / 8 in
    assert ((x - 1) * (x - 3) == 8 * m);
    let other = x * (x - 2) * (x - 4) in
    assert (poly5 x == ((x - 1) * (x - 3)) * other);
    assert (poly5 x == 8 * (m * other))
  end

(** Теорема 2: Симметричный poly5_sym(x) делится на 8 для любого x *)
val theorem_poly5_sym_divisible_by_8 : x:int ->
  Lemma ((poly5_sym x) % 8 == 0)
let theorem_poly5_sym_divisible_by_8 x =
  if x % 2 = 0 then begin
    lemma_even_step2_div8 x;
    let m = (x * (x - 2)) / 8 in
    assert (x * (x - 2) == 8 * m);
    let other = (x - 1) * (x + 1) * (x + 2) in
    assert (poly5_sym x == (x * (x - 2)) * other);
    assert (poly5_sym x == 8 * (m * other))
  end else begin
    let k = (x - 1) / 2 in
    assert (x - 1 == 2 * k);
    assert (x + 1 == 2 * (k + 1));
    assert ((x - 1) * (x + 1) == 4 * (k * (k + 1)));
    lemma_consecutive_plus_even k;
    let m = (k * (k + 1)) / 2 in
    assert (k * (k + 1) == 2 * m);
    assert ((x - 1) * (x + 1) == 8 * m);
    let other = (x - 2) * x * (x + 2) in
    assert (poly5_sym x == ((x - 1) * (x + 1)) * other);
    assert (poly5_sym x == 8 * (m * other))
  end

(* ------------------------------------------------------------------ *)
(* 3. Главные теоремы в кольце Z_{2^64}                                *)
(* ------------------------------------------------------------------ *)

let two_61 : pos = 0x2000000000000000 (* 2^61 *)
let two_64 : pos = 0x10000000000000000 (* 2^64 *)

(** Главная теорема 3: 2^61 * poly5(x) тождественно равен 0 mod 2^64 *)
val theorem_zero_inv5_poly : x:int ->
  Lemma ((two_61 * poly5 x) % two_64 == 0)
let theorem_zero_inv5_poly x =
  theorem_poly5_divisible_by_8 x;
  let p = poly5 x in
  let k = p / 8 in
  assert (p == 8 * k);
  assert (two_61 * p == two_61 * (8 * k));
  assert (two_61 * (8 * k) == (two_61 * 8) * k);
  assert (two_61 * 8 == two_64);
  assert (two_61 * p == two_64 * k);
  M.lemma_mod_mul_distr_l two_64 k two_64;
  assert ((two_64 * k) % two_64 == 0)

(** Главная теорема 4: Симметричный 2^61 * poly5_sym(x) == 0 mod 2^64 *)
val theorem_zero_inv5_sym_poly : x:int ->
  Lemma ((two_61 * poly5_sym x) % two_64 == 0)
let theorem_zero_inv5_sym_poly x =
  theorem_poly5_sym_divisible_by_8 x;
  let p = poly5_sym x in
  let k = p / 8 in
  assert (p == 8 * k);
  assert (two_61 * p == (two_61 * 8) * k);
  assert (two_61 * 8 == two_64);
  assert (two_61 * p == two_64 * k);
  M.lemma_mod_mul_distr_l two_64 k two_64;
  assert ((two_64 * k) % two_64 == 0)

(** Главная теорема 5: Нелинейный перекрестный инвариант zero_inv5_nl *)
val theorem_zero_inv5_nl : zero_factor:int -> other_factors:int ->
  Lemma (requires (zero_factor % two_64 == 0))
        (ensures ((zero_factor * other_factors) % two_64 == 0))
let theorem_zero_inv5_nl zero_factor other_factors =
  M.lemma_mod_mul_distr_l zero_factor other_factors two_64
