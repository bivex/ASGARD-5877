open Int64

type ring_codec = {
  a     : int64;
  a_inv : int64;
  b     : int64;
}

let inv_mod_2_64 (a : int64) : int64 =
  if logand a 1L = 0L then
    invalid_arg "Metamorphic_ring.inv_mod_2_64: even number has no inverse in Z_{2^64}";
  let step x = mul x (sub 2L (mul a x)) in
  step (step (step (step (step a))))

let rand_u64 (rng : Random.State.t) : int64 =
  let hi = Random.State.bits rng |> of_int in
  let mid = Random.State.bits rng |> of_int in
  let lo = Random.State.bits rng |> of_int in
  logor (shift_left hi 34) (logor (shift_left mid 4) (logand lo 0xFL))

let gen_ring_codec (rng : Random.State.t) : ring_codec =
  let a = logor (rand_u64 rng) 1L in
  let b = rand_u64 rng in
  { a; a_inv = inv_mod_2_64 a; b }

let encode_val (c : ring_codec) (x : int64) : int64 =
  add (mul c.a x) c.b

let decode_val (c : ring_codec) (x_hat : int64) : int64 =
  mul (sub x_hat c.b) c.a_inv

let compile_homomorphic_add (cx : ring_codec) (cy : ring_codec) (cz : ring_codec)
    : int64 * int64 * int64 =
  let c1 = mul cz.a cx.a_inv in
  let c2 = mul cz.a cy.a_inv in
  let term_bx = mul c1 cx.b in
  let term_by = mul c2 cy.b in
  let c3 = sub (sub cz.b term_bx) term_by in
  (c1, c2, c3)

let compile_homomorphic_mul (cx : ring_codec) (cy : ring_codec) (cz : ring_codec)
    : int64 * int64 * int64 * int64 =
  let inv_xy = mul cx.a_inv cy.a_inv in
  let k_xy = mul cz.a inv_xy in
  let k_x  = neg (mul k_xy cy.b) in
  let k_y  = neg (mul k_xy cx.b) in
  let k_0  = add cz.b (mul k_xy (mul cx.b cy.b)) in
  (k_xy, k_x, k_y, k_0)

let eval_xorshift33_involution ~(c_odd : int64) (x : int64) : int64 =
  let c = logor c_odd 1L in
  (* Since the left shift by 33 >= 32 (half the bit width), the low 33 bits of x
     are unchanged on the first application and yield an identical shifted pattern on the second! *)
  let shifted = shift_left (mul (logand x 0x7FFFFFFFL) c) 33 in
  logxor x shifted
