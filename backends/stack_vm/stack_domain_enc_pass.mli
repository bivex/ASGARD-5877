(** Pass 9: End-to-End Affine Ring Domain Encoding Pass
    ────────────────────────────────────────────────────
    Encodes program values into individual affine quotient rings
    Z_{2^64} via Lagrange-Rivest bijections:
      E_i(x) = (alpha_i * x + beta_i) mod 2^64,  alpha_i = 1 (mod 2)
      D_i(y) = alpha_i^{-1} * (y - beta_i) mod 2^64

    Homomorphic Operations:
      1. Addition:
           z_enc = (C1 * x_enc + C2 * y_enc + C0) mod 2^64
      2. Multiplication:
           z_enc = (M_xy * x_enc * y_enc + M_x * x_enc + M_y * y_enc + M0) mod 2^64
*)

open Stack_ir

type domain_config = {
  enabled : bool;
  seed    : int64;
}

val default_domain_config : int64 -> domain_config

val mod_inv_64 : int64 -> int64

val encode_val : alpha:int64 -> beta:int64 -> int64 -> int64

val decode_val : alpha:int64 -> beta:int64 -> int64 -> int64

val homomorphic_add_coeffs :
  alpha1:int64 -> beta1:int64 ->
  alpha2:int64 -> beta2:int64 ->
  alpha3:int64 -> beta3:int64 ->
  int64 * int64 * int64

val homomorphic_mul_coeffs :
  alpha1:int64 -> beta1:int64 ->
  alpha2:int64 -> beta2:int64 ->
  alpha3:int64 -> beta3:int64 ->
  int64 * int64 * int64 * int64

val apply_block :
  domain_config ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  domain_config ->
  Context_allocator.t ->
  program ->
  program
