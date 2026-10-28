(** Pass B: Path-Sensitive Semantic Encoding Pass
    ─────────────────────────────────────────────
    Applies path-sensitive state encodings across CFG edges.
*)

open Stack_ir

type block_encoding = {
  alpha     : int64;
  beta      : int64;
  inv_alpha : int64;
}

type path_config = {
  enabled : bool;
  seed    : int64;
}

let default_path_config seed = {
  enabled = true;
  seed;
}

(** Newton-Raphson 64-bit modular inverse of odd integer modulo 2^64. *)
let mod_inv_64 a =
  let open Int64 in
  let a = logor a 1L in
  let x = logxor (mul 3L a) 2L in
  let step x = mul x (sub 2L (mul a x)) in
  let x = step x in
  let x = step x in
  let x = step x in
  let x = step x in
  step x

let splitmix64 s =
  let open Int64 in
  let s = add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  (s, logxor z (shift_right_logical z 31))

let compute_block_encoding ~seed ~block_id =
  let open Int64 in
  let s0 = logxor seed (of_int (block_id * 0x5877 + 0x1337)) in
  let s1, z1 = splitmix64 s0 in
  let _, z2 = splitmix64 s1 in
  let alpha = logor z1 1L in (* Ensure odd *)
  let beta = z2 in
  let inv_alpha = mod_inv_64 alpha in
  { alpha; beta; inv_alpha }

let compute_edge_transition ~src_enc ~dst_enc =
  let open Int64 in
  let a = mul dst_enc.alpha src_enc.inv_alpha in
  let b = sub dst_enc.beta (mul a src_enc.beta) in
  (a, b)

let emit_edge_transition ~slot ~a ~b =
  [
    PushReg slot;
    PushImm a;
    Mul;
    PushImm b;
    Add;
    PopReg slot;
  ]

let apply_block (cfg : path_config) _ctx (b : block) : block =
  if not cfg.enabled then b
  else
    b

let apply_program (cfg : path_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ctx b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks }
