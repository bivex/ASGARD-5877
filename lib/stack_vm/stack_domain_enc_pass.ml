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

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  (s, logxor z (shift_right_logical z 31))

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFFFFFFL) in
    v mod n

let apply_block_internal ~anchor (cfg : domain_config) (b : block) : block =
  if not cfg.enabled then b
  else
    let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (b.id * 0x3141 + 0x5926))) in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    List.iteri (fun idx op ->
      let flags_dead =
        if idx + 1 < Array.length live then not live.(idx + 1)
        else true
      in
      match op with
      | PushImm v when flags_dead && next_int rng 100 < 40 ->
          let alpha = Int64.logor (next_int64 rng) 1L in
          let beta = next_int64 rng in
          let v_enc = encode_val ~alpha ~beta v in
          let inv = mod_inv_64 alpha in
          let cluster = [
            PushImm v_enc;
            PopReg anchor;
            PushReg anchor;
            PushImm beta;
            Sub;
            PushImm inv;
            Mul;
          ] in
          new_ops := List.rev cluster @ !new_ops
      | other ->
          new_ops := other :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_block (cfg : domain_config) ctx (b : block) : block =
  let anchor = Context_allocator.alloc_scratch ctx in
  apply_block_internal ~anchor cfg b

let apply_program (cfg : domain_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let anchor = Context_allocator.alloc_scratch ctx in
    let sorted =
      Hashtbl.fold (fun id b acc -> (id, b) :: acc) prog.blocks []
      |> List.sort (fun (a, _) (b, _) -> compare a b)
      |> Array.of_list
    in
    let n = Array.length sorted in
    let out = Array.make n (0, { (snd sorted.(0)) with ops = [] }) in
    let pool = Random_visa_ports.Domain_pool.global_pool () in
    Random_visa_ports.Domain_pool.parallel_for ~min_n:4 pool ~n (fun i ->
      let (id, b) = sorted.(i) in
      out.(i) <- (id, apply_block_internal ~anchor cfg b)
    );
    let new_blocks = Hashtbl.create n in
    Array.iter (fun (id, b) -> Hashtbl.replace new_blocks id b) out;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }
