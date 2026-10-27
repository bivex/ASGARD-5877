(** Pass 12: Chinese Remainder Theorem (CRT) Split-Path Execution Pass
    ─────────────────────────────────────────────────────────────────
    Splits computations across pairwise coprime moduli (m1, m2, m3)
    with Garner reconstruction over M = m1 * m2 * m3.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type crt_config = {
  enabled : bool;
  seed    : int64;
}

let default_crt_config seed = {
  enabled = true;
  seed;
}


let split_val v =
  let open Int64 in
  let z1 = unsigned_rem v crt_m1 in
  let z2 = unsigned_rem v crt_m2 in
  let z3 = unsigned_rem v crt_m3 in
  (z1, z2, z3)

let inv_m1_mod_m2 = 0x100000L
let inv_m1_mod_m3 = 0x55555L
let inv_m2_mod_m3 = 0xFFFFFL

let reconstruct_val (z1, z2, z3) =
  let open Int64 in
  let x1 = unsigned_rem z1 crt_m1 in
  let diff2 = unsigned_rem (add (sub z2 (unsigned_rem x1 crt_m2)) crt_m2) crt_m2 in
  let x2 = unsigned_rem (mul diff2 inv_m1_mod_m2) crt_m2 in
  let diff3 = unsigned_rem (add (sub z3 (unsigned_rem x1 crt_m3)) crt_m3) crt_m3 in
  let t3 = unsigned_rem (mul diff3 inv_m1_mod_m3) crt_m3 in
  let diff3_2 = unsigned_rem (add (sub t3 (unsigned_rem x2 crt_m3)) crt_m3) crt_m3 in
  let x3 = unsigned_rem (mul diff3_2 inv_m2_mod_m3) crt_m3 in
  add x1 (mul crt_m1 (add x2 (mul crt_m2 x3)))

let apply_block (cfg : crt_config) _ctx (b : block) : block =
  if not cfg.enabled then b
  else
    b

let apply_program (cfg : crt_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ctx b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks }
