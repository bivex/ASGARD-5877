(** Homomorphic data encoding in the ring Z_{2^64} and nonlinear involutions against SiMBA/MBA-Blast *)

type ring_codec = {
  a     : int64;
  a_inv : int64;
  b     : int64;
}

val inv_mod_2_64 : int64 -> int64
val gen_ring_codec : Random.State.t -> ring_codec
val encode_val : ring_codec -> int64 -> int64
val decode_val : ring_codec -> int64 -> int64

(** Precomputation of the coefficients (C1, C2, C3) for homomorphic addition:
    \hat{z} = C1 * \hat{x} + C2 * \hat{y} + C3 (mod 2^64) *)
val compile_homomorphic_add :
  ring_codec -> ring_codec -> ring_codec -> int64 * int64 * int64

(** Precomputation of the coefficients (K_xy, K_x, K_y, K_0) for homomorphic multiplication:
    \hat{z} = K_xy * (\hat{x} * \hat{y}) + K_x * \hat{x} + K_y * \hat{y} + K_0 (mod 2^64) *)
val compile_homomorphic_mul :
  ring_codec -> ring_codec -> ring_codec -> int64 * int64 * int64 * int64

(** Nonlinear bijective involution F(x) = x ^ (((x & 0x7FFFFFFF) * odd_c) lsl 33),
    destroying the 2^k-dimensional linear space of the table-based solvers SiMBA / MBA-Blast.
    It has the property of strict self-invertibility: F(F(x)) == x for all 64-bit inputs! *)
val eval_xorshift33_involution : c_odd:int64 -> int64 -> int64
