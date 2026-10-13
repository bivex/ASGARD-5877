module Metamorphic_Isa_Verified

(** Доказательство биективности смешанной системы счисления (Mixed-Radix Packing)
    для непересекающихся диапазонов произвольных (нестепенных) баз N_op, N_reg, N_rt *)

let pack_pair (x : nat) (y : nat) (base_x : pos{x < base_x}) : Tot nat =
  x + base_x * y

let unpack_x (u : nat) (base_x : pos) : Tot nat =
  u % base_x

let unpack_y (u : nat) (base_x : pos) : Tot nat =
  u / base_x

val lemma_mixed_radix_step_bijective :
  x:nat -> y:nat -> base_x:pos{x < base_x} ->
  Lemma (ensures (
    let u = pack_pair x y base_x in
    unpack_x u base_x == x /\ unpack_y u base_x == y
  ))
let lemma_mixed_radix_step_bijective x y base_x =
  FStar.Math.Lemmas.lemma_mod_plus x y base_x;
  FStar.Math.Lemmas.small_mod x base_x;
  FStar.Math.Lemmas.lemma_div_plus x y base_x;
  FStar.Math.Lemmas.small_div x base_x

(** Спецификация обратимости определителя матрицы базиса GL(2, Z_{2^64}):
    при нечетных (a, d) и четных (b, c) определитель det = a*d - b*c всегда нечетен *)
val lemma_gl2_odd_determinant :
  a:int -> b:int -> c:int -> d:int ->
  Lemma
    (requires (a % 2 <> 0 /\ d % 2 <> 0 /\ b % 2 == 0 /\ c % 2 == 0))
    (ensures  ((a * d - b * c) % 2 <> 0))
let lemma_gl2_odd_determinant a b c d =
  let qa = a / 2 in let ra = a % 2 in
  let qd = d / 2 in let rd = d % 2 in
  let qb = b / 2 in
  let qc = c / 2 in
  assert (a == 2 * qa + ra);
  assert (d == 2 * qd + rd);
  assert (b == 2 * qb);
  assert (c == 2 * qc);
  assert (a * d - b * c == 2 * (2 * qa * qd + qa * rd + qd * ra - 2 * qb * qc) + ra * rd);
  FStar.Math.Lemmas.lemma_mod_plus (ra * rd) (2 * qa * qd + qa * rd + qd * ra - 2 * qb * qc) 2
