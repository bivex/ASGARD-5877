(**
  Rolling_Key_Verified.fst — Формальная верификация Anti-Pushan криптографического генератора ключей.
  F* 2026.08.23 + Z3 5.0.0.

  Доказывает:
  1. Корректность мультипликативного обратного элемента M^{-1} mod 2^64.
  2. Обратимость циклического сдвига: ROL23(ROR23(x)) == x.
  3. Полную биективность шага эволюции ключа (advance_key_step):
     invert_key_step (advance_key_step k delta) delta == k.
  4. Отсутствие коллизий (Collision-Free / Key Space Preservation):
     k1 <> k2 ==> advance_key_step k1 delta <> advance_key_step k2 delta.
  5. Нечетность полиномиального множителя (Odd-Multiplier Bijectivity):
     poly_mult | 1L всегда взаимно просто с 2^64.
*)
module Rolling_Key_Verified

module M = FStar.Math.Lemmas
open FStar.UInt
open FStar.UInt64

type u64 = uint_t 64

let two_64 : pos = 0x10000000000000000

let mul_mod (a:u64) (b:u64) : u64 =
  (a * b) % two_64

let add_mod (a:u64) (b:u64) : u64 =
  (a + b) % two_64

let xor64 (a:u64) (b:u64) : u64 =
  logxor #64 a b

let or64 (a:u64) (b:u64) : u64 =
  logor #64 a b

let shl64 (a:u64) (s:nat{s < 64}) : u64 =
  shift_left #64 a s

let shr64 (a:u64) (s:nat{s < 64}) : u64 =
  shift_right #64 a s

(* ------------------------------------------------------------------ *)
(* 1. Мультипликативный обратный элемент константы M                  *)
(* ------------------------------------------------------------------ *)

let const_M     : u64 = 0xBF58476D1CE4E5B9
let const_M_inv : u64 = 0x96DE1B173F119089
let const_C     : u64 = 0x5877CAFE1337BEEF

(** Теорема 1: Формальное доказательство обратного элемента Безу mod 2^64 *)
val theorem_multiplier_inverse : unit ->
  Lemma ((const_M * const_M_inv) % two_64 == 1)
let theorem_multiplier_inverse () = ()

val lemma_mul_inverse_cancel : x:u64 ->
  Lemma (mul_mod (mul_mod x const_M) const_M_inv == x)
let lemma_mul_inverse_cancel x =
  theorem_multiplier_inverse ();
  M.lemma_mod_mul_distr_l (x * const_M) const_M_inv two_64;
  assert (((x * const_M) * const_M_inv) == x * (const_M * const_M_inv));
  M.lemma_mod_mul_distr_r x (const_M * const_M_inv) two_64;
  M.small_mod x two_64

(* ------------------------------------------------------------------ *)
(* 2. Циклический сдвиг ROR23 и ROL23                                 *)
(* ------------------------------------------------------------------ *)

let ror23 (x:u64) : u64 =
  rotate_right #64 x 23

let rol23 (x:u64) : u64 =
  rotate_left #64 x 23

(** Лемма: ROL23 и ROR23 взаимно обратны *)
val lemma_rot_cancel : x:u64 ->
  Lemma (rol23 (ror23 x) == x)
let lemma_rot_cancel x =
  rotate_right_left_inverse #64 x 23

(* ------------------------------------------------------------------ *)
(* 3. Шаг эволюции ключа и его точное обращение                        *)
(* ------------------------------------------------------------------ *)

let advance_key_step (k:u64) (delta:u64) : u64 =
  let x = xor64 k delta in
  let rot = ror23 x in
  xor64 (mul_mod rot const_M) const_C

let invert_key_step (k_next:u64) (delta:u64) : u64 =
  let temp1 = xor64 k_next const_C in
  let rot = mul_mod temp1 const_M_inv in
  let x = rol23 rot in
  xor64 x delta

val lemma_xor_involution : a:u64 -> b:u64 ->
  Lemma (xor64 (xor64 a b) b == a)
let lemma_xor_involution a b =
  nth_lemma (xor64 (xor64 a b) b) a

(** Главная теорема 2: Биективность эволюции ключа (Roundtrip Invertibility) *)
val theorem_key_step_invertible : k:u64 -> delta:u64 ->
  Lemma (invert_key_step (advance_key_step k delta) delta == k)
let theorem_key_step_invertible k delta =
  let x = xor64 k delta in
  let rot = ror23 x in
  let stepped = advance_key_step k delta in
  (* 1. Снимаем XOR C *)
  lemma_xor_involution (mul_mod rot const_M) const_C;
  assert (xor64 stepped const_C == mul_mod rot const_M);
  (* 2. Снимаем умножение на M *)
  lemma_mul_inverse_cancel rot;
  assert (mul_mod (xor64 stepped const_C) const_M_inv == rot);
  (* 3. Снимаем ROR23 *)
  lemma_rot_cancel x;
  assert (rol23 rot == x);
  (* 4. Снимаем XOR delta *)
  lemma_xor_involution k delta

(** Главная теорема 3: Отсутствие коллизий ключей (Injective / Collision-Free) *)
val theorem_key_step_injective : k1:u64 -> k2:u64 -> delta:u64 ->
  Lemma (requires (k1 <> k2))
        (ensures (advance_key_step k1 delta <> advance_key_step k2 delta))
let theorem_key_step_injective k1 k2 delta =
  if advance_key_step k1 delta = advance_key_step k2 delta then begin
    theorem_key_step_invertible k1 delta;
    theorem_key_step_invertible k2 delta;
    assert (k1 == k2)
  end else ()

(* ------------------------------------------------------------------ *)
(* 4. Нечетность полиномиального множителя (Odd-Multiplier Bijectivity)*)
(* ------------------------------------------------------------------ *)

let ensure_odd (mixed:u64) : u64 =
  or64 mixed 1

(** Теорема 4: ensure_odd всегда возвращает нечетное число *)
val theorem_odd_multiplier : mixed:u64 ->
  Lemma ((ensure_odd mixed) % 2 == 1)
let theorem_odd_multiplier mixed =
  logand_mask #64 (ensure_odd mixed) 1;
  assert (logand (ensure_odd mixed) 1 == (ensure_odd mixed) % 2);
  ()
