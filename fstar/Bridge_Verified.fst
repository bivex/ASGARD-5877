(**
  Bridge_Verified.fst — Формальная верификация Multi-VM Invertible Affine Bridge в ASGARD-5877.
  F* 2026.08.23 + Z3 5.0.0.

  Доказывает:
  1. Корректность квадратичной сходимости метода Ньютона-Рафсона (Hensel lifting)
     для вычисления модульного обратного по модулю 2^64:
     квадрат погрешности (1 - a * x') = (1 - a * x)^2 mod 2^64.
  2. Инволюцию маскировки дескриптора трассировки (Trace Digest XOR Involution):
     (X ^ Mask) ^ Mask == X.
  3. Биективность и обратимость обновления хэша трассировки (Trace Digest Bijectivity):
     invert_trace_digest (update_trace_digest prev op vip) op vip == prev.
  4. Точную обратимость аффинного моста (Affine Bridge Roundtrip Fidelity):
     Для обратимой матрицы M и маски D:
     inverse_morph M_inv (forward_morph M_fwd V D) D == V.
*)
module Bridge_Verified

open FStar.UInt
open FStar.UInt64
open FStar.List.Tot

type u64 = uint_t 64

let add64 (a:u64) (b:u64) : u64 = add_mod #64 a b
let sub64 (a:u64) (b:u64) : u64 = sub_mod #64 a b
let mul64 (a:u64) (b:u64) : u64 = mul_mod #64 a b
let xor64 (a:u64) (b:u64) : u64 = logxor #64 a b
let rol64 (a:u64) (s:nat{s <= 64}) : u64 = rotate_left #64 a s
let ror64 (a:u64) (s:nat{s <= 64}) : u64 = rotate_right #64 a s

(* ------------------------------------------------------------------ *)
(* 1. Ньютон-Рафсон модульного обратного в Z/(2^64)Z                 *)
(* ------------------------------------------------------------------ *)

let nr_step (a:u64) (x:u64) : u64 =
  mul64 x (sub64 2 (mul64 a x))

(** Главная алгебраическая лемма: Квадратичное сжатие ошибки y * (2 - y) *)
val lemma_nr_formula : y:u64 ->
  Lemma (sub64 1 (mul64 y (sub64 2 y)) == mul64 (sub64 1 y) (sub64 1 y))
let lemma_nr_formula y = ()

let mod_inverse_64_iter (a:u64) : u64 =
  let x0 = 1 in
  let x1 = nr_step a x0 in
  let x2 = nr_step a x1 in
  let x3 = nr_step a x2 in
  let x4 = nr_step a x3 in
  let x5 = nr_step a x4 in
  let x6 = nr_step a x5 in
  x6

(** Теорема 1: Конкретная корректность обратного элемента для нечетных констант *)
val theorem_mod_inv_odd_constant : a:u64 ->
  Lemma (requires (a == 0xBF58476D1CE4E5B9 \/ a == 0x9E3779B97F4A7C15 \/ a == 0x94D049BB133111EB))
        (ensures (mul64 a (mod_inverse_64_iter a) == 1))
let theorem_mod_inv_odd_constant a =
  if a = 0xBF58476D1CE4E5B9 then
    assert_norm (mul64 0xBF58476D1CE4E5B9 (mod_inverse_64_iter 0xBF58476D1CE4E5B9) == 1)
  else if a = 0x9E3779B97F4A7C15 then
    assert_norm (mul64 0x9E3779B97F4A7C15 (mod_inverse_64_iter 0x9E3779B97F4A7C15) == 1)
  else if a = 0x94D049BB133111EB then
    assert_norm (mul64 0x94D049BB133111EB (mod_inverse_64_iter 0x94D049BB133111EB) == 1)

(* ------------------------------------------------------------------ *)
(* 2. Инволюция маскировки Cross-VM Trace Digest                      *)
(* ------------------------------------------------------------------ *)

let golden_ratio : u64 = 0x9E3779B97F4A7C15

let update_trace_digest (prev:u64) (opcode:u64) (vip:u64) : u64 =
  let k1 = rol64 prev 13 in
  let term = add64 opcode (mul64 vip golden_ratio) in
  xor64 k1 term

let invert_trace_digest (next_d:u64) (opcode:u64) (vip:u64) : u64 =
  let term = add64 opcode (mul64 vip golden_ratio) in
  let k1 = xor64 next_d term in
  ror64 k1 13

val lemma_xor_involution : a:u64 -> b:u64 ->
  Lemma (xor64 (xor64 a b) b == a)
let lemma_xor_involution a b =
  let nth_check (i:nat{i < 64}) : Lemma (nth (xor64 (xor64 a b) b) i == nth a i) = () in
  nth_lemma (xor64 (xor64 a b) b) a

(** Теорема 2: Обратимость и биективность шага обновления хэша трассировки *)
val theorem_trace_digest_invertible : prev:u64 -> opcode:u64 -> vip:u64 ->
  Lemma (invert_trace_digest (update_trace_digest prev opcode vip) opcode vip == prev)
let theorem_trace_digest_invertible prev opcode vip =
  let term = add64 opcode (mul64 vip golden_ratio) in
  let k1 = rol64 prev 13 in
  lemma_xor_involution k1 term;
  rotate_left_right_inverse #64 prev 13

(* ------------------------------------------------------------------ *)
(* 3. Преобразование Аффинного моста (Affine Bridge Morphing)        *)
(* ------------------------------------------------------------------ *)

type vec4 = {
  v0 : u64;
  v1 : u64;
  v2 : u64;
  v3 : u64;
}

let mask_for_channel (digest:u64) (ch:nat{ch < 4}) : u64 =
  let shift = (ch * 3 + 7) % 64 in
  rol64 digest shift

let apply_mask (v:vec4) (digest:u64) : vec4 =
  {
    v0 = xor64 v.v0 (mask_for_channel digest 0);
    v1 = xor64 v.v1 (mask_for_channel digest 1);
    v2 = xor64 v.v2 (mask_for_channel digest 2);
    v3 = xor64 v.v3 (mask_for_channel digest 3);
  }

(** Теорема 3: Инволюция маскировки каналов регистра *)
val theorem_apply_mask_involution : v:vec4 -> digest:u64 ->
  Lemma (apply_mask (apply_mask v digest) digest == v)
let theorem_apply_mask_involution v digest =
  lemma_xor_involution v.v0 (mask_for_channel digest 0);
  lemma_xor_involution v.v1 (mask_for_channel digest 1);
  lemma_xor_involution v.v2 (mask_for_channel digest 2);
  lemma_xor_involution v.v3 (mask_for_channel digest 3)

noeq type mat4 = {
  m00:u64; m01:u64; m02:u64; m03:u64;
  m10:u64; m11:u64; m12:u64; m13:u64;
  m20:u64; m21:u64; m22:u64; m23:u64;
  m30:u64; m31:u64; m32:u64; m33:u64;
}

let mat4_mul_vec (m:mat4) (v:vec4) : vec4 =
  {
    v0 = add64 (mul64 m.m00 v.v0) (add64 (mul64 m.m01 v.v1) (add64 (mul64 m.m02 v.v2) (mul64 m.m03 v.v3)));
    v1 = add64 (mul64 m.m10 v.v0) (add64 (mul64 m.m11 v.v1) (add64 (mul64 m.m12 v.v2) (mul64 m.m13 v.v3)));
    v2 = add64 (mul64 m.m20 v.v0) (add64 (mul64 m.m21 v.v1) (add64 (mul64 m.m22 v.v2) (mul64 m.m23 v.v3)));
    v3 = add64 (mul64 m.m30 v.v0) (add64 (mul64 m.m31 v.v1) (add64 (mul64 m.m32 v.v2) (mul64 m.m33 v.v3)));
  }

noeq type affine_bridge = {
  fwd_mat : mat4;
  inv_mat : mat4;
}

let is_valid_inverse_pair (fwd:mat4) (inv:mat4) : prop =
  forall (v:vec4). mat4_mul_vec inv (mat4_mul_vec fwd v) == v

let forward_morph (b:affine_bridge) (v:vec4) (digest:u64) : vec4 =
  let transformed = mat4_mul_vec b.fwd_mat v in
  apply_mask transformed digest

let inverse_morph (b:affine_bridge) (v_morph:vec4) (digest:u64) : vec4 =
  let unmasked = apply_mask v_morph digest in
  mat4_mul_vec b.inv_mat unmasked

(** Главная теорема 4: Полный раундтрип Аффинного Моста Multi-VM *)
val theorem_affine_bridge_roundtrip : b:affine_bridge -> v:vec4 -> digest:u64 ->
  Lemma (requires (is_valid_inverse_pair b.fwd_mat b.inv_mat))
        (ensures (inverse_morph b (forward_morph b v digest) digest == v))
let theorem_affine_bridge_roundtrip b v digest =
  let transformed = mat4_mul_vec b.fwd_mat v in
  theorem_apply_mask_involution transformed digest;
  assert (apply_mask (forward_morph b v digest) digest == transformed);
  assert (mat4_mul_vec b.inv_mat transformed == v)
