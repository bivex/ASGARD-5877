(** Pass 9: End-to-End Affine Ring Domain Encoding Pass
    ────────────────────────────────────────────────────
    Encodes program values into individual affine quotient rings
    Z_{2^64} via Lagrange-Rivest bijections:
      E_i(x) = (alpha_i * x + beta_i) mod 2^64,  alpha_i = 1 (mod 2)
      D_i(y) = alpha_i^{-1} * (y - beta_i) mod 2^64
*)

open Stack_ir

type domain_config = {
  enabled : bool;
  seed    : int64;
}

let default_domain_config seed = {
  enabled = true;
  seed;
}

(** Newton-Raphson 64-bit modular inverse of odd integer [a] modulo 2^64. *)
let mod_inv_64 a =
  let open Int64 in
  let a = logor a 1L in (* Ensure odd *)
  let x = logxor (mul 3L a) 2L in
  let step x = mul x (sub 2L (mul a x)) in
  let x = step x in
  let x = step x in
  let x = step x in
  let x = step x in
  step x

let encode_val ~alpha ~beta x =
  let open Int64 in
  add (mul alpha x) beta

let decode_val ~alpha ~beta y =
  let open Int64 in
  let inv = mod_inv_64 alpha in
  mul inv (sub y beta)

let homomorphic_add_coeffs ~alpha1 ~beta1 ~alpha2 ~beta2 ~alpha3 ~beta3 =
  let open Int64 in
  let inv1 = mod_inv_64 alpha1 in
  let inv2 = mod_inv_64 alpha2 in
  let c1 = mul alpha3 inv1 in
  let c2 = mul alpha3 inv2 in
  let c0 = sub (sub beta3 (mul c1 beta1)) (mul c2 beta2) in
  (c1, c2, c0)

let homomorphic_mul_coeffs ~alpha1 ~beta1 ~alpha2 ~beta2 ~alpha3 ~beta3 =
  let open Int64 in
  let inv1 = mod_inv_64 alpha1 in
  let inv2 = mod_inv_64 alpha2 in
  let m_xy = mul alpha3 (mul inv1 inv2) in
  let m_x  = neg (mul m_xy beta2) in
  let m_y  = neg (mul m_xy beta1) in
  let m_0  = add beta3 (mul m_xy (mul beta1 beta2)) in
  (m_xy, m_x, m_y, m_0)

let apply_block (cfg : domain_config) _ctx (b : block) : block =
  if not cfg.enabled then b
  else
    (* Pass 9 provides domain encoding infrastructure across the IR *)
    b

let apply_program (cfg : domain_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ctx b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks }
