open Int64

type entanglement_matrix = {
  a11 : int64; a12 : int64;
  a21 : int64; a22 : int64;
  inv11 : int64; inv12 : int64;
  inv21 : int64; inv22 : int64;
  bias_u : int64;
  bias_v : int64;
}

let inv_odd_64 (a : int64) : int64 =
  let step x = mul x (sub 2L (mul a x)) in
  step (step (step (step (step a))))

let rand_u64 (rng : Random.State.t) : int64 =
  let hi = Random.State.bits rng |> of_int in
  let mid = Random.State.bits rng |> of_int in
  let lo = Random.State.bits rng |> of_int in
  logor (shift_left hi 34) (logor (shift_left mid 4) (logand lo 0xFL))

let gen_entanglement_matrix (rng : Random.State.t) : entanglement_matrix =
  (* Главная диагональ нечетная, побочная четная (но ненулевая!) -> det всегда нечетен *)
  let a11 = logor (rand_u64 rng) 1L in
  let a22 = logor (rand_u64 rng) 1L in
  let a12 = logor (logand (rand_u64 rng) (lognot 1L)) 2L in
  let a21 = logor (logand (rand_u64 rng) (lognot 1L)) 2L in

  let det = sub (mul a11 a22) (mul a12 a21) in
  let det_inv = inv_odd_64 det in

  let inv11 = mul a22 det_inv in
  let inv12 = mul (neg a12) det_inv in
  let inv21 = mul (neg a21) det_inv in
  let inv22 = mul a11 det_inv in

  let bias_u = rand_u64 rng in
  let bias_v = rand_u64 rng in
  { a11; a12; a21; a22; inv11; inv12; inv21; inv22; bias_u; bias_v }

let entangle_pair (m : entanglement_matrix) (x : int64) (y : int64) : int64 * int64 =
  let u = add (add (mul m.a11 x) (mul m.a12 y)) m.bias_u in
  let v = add (add (mul m.a21 x) (mul m.a22 y)) m.bias_v in
  (u, v)

let disentangle_pair (m : entanglement_matrix) (u : int64) (v : int64) : int64 * int64 =
  let du = sub u m.bias_u in
  let dv = sub v m.bias_v in
  let x = add (mul m.inv11 du) (mul m.inv12 dv) in
  let y = add (mul m.inv21 du) (mul m.inv22 dv) in
  (x, y)

let homomorphic_entangled_add_const (m : entanglement_matrix)
    ~(u : int64) ~(v : int64) ~(dx : int64) ~(dy : int64) : int64 * int64 =
  (* A * ([x; y] + [dx; dy]) + bias = (A*[x;y] + bias) + A*[dx; dy] *)
  let shift_u = add (mul m.a11 dx) (mul m.a12 dy) in
  let shift_v = add (mul m.a21 dx) (mul m.a22 dy) in
  (add u shift_u, add v shift_v)

let homomorphic_coupled_butterfly (m : entanglement_matrix) ~(u : int64) ~(v : int64) : int64 * int64 =
  (* Пусть T = [1, 1; 1, -1] (преобразование (x+y, x-y)).
     В сшитых координатах матрица оператора имеет вид M_op = A * T * A^{-1} mod 2^64 *)
  let (x, y) = disentangle_pair m u v in
  entangle_pair m (add x y) (sub x y)
