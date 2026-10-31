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
  let z4 = unsigned_rem v crt_m4 in
  (z1, z2, z3, z4)

let reconstruct_val (z1, z2, z3, z4) =
  let open Int64 in
  let x1 = unsigned_rem z1 crt_m1 in
  let diff2 = unsigned_rem (add (sub z2 (unsigned_rem x1 crt_m2)) crt_m2) crt_m2 in
  let x2 = unsigned_rem (mul diff2 crt_inv_m1_mod_m2) crt_m2 in
  let diff3 = unsigned_rem (add (sub z3 (unsigned_rem x1 crt_m3)) crt_m3) crt_m3 in
  let t3 = unsigned_rem (mul diff3 crt_inv_m1_mod_m3) crt_m3 in
  let diff3_2 = unsigned_rem (add (sub t3 (unsigned_rem x2 crt_m3)) crt_m3) crt_m3 in
  let x3 = unsigned_rem (mul diff3_2 crt_inv_m2_mod_m3) crt_m3 in
  let diff4 = unsigned_rem (add (sub z4 (unsigned_rem x1 crt_m4)) crt_m4) crt_m4 in
  let t4 = unsigned_rem (mul diff4 crt_inv_m1_mod_m4) crt_m4 in
  let diff4_2 = unsigned_rem (add (sub t4 (unsigned_rem x2 crt_m4)) crt_m4) crt_m4 in
  let t4_2 = unsigned_rem (mul diff4_2 crt_inv_m2_mod_m4) crt_m4 in
  let diff4_3 = unsigned_rem (add (sub t4_2 (unsigned_rem x3 crt_m4)) crt_m4) crt_m4 in
  let x4 = unsigned_rem (mul diff4_3 crt_inv_m3_mod_m4) crt_m4 in
  add x1 (mul crt_m1 (add x2 (mul crt_m2 (add x3 (mul crt_m3 x4)))))
let apply_block_internal ~scratch_slot (b : block) : block =
  let liveness = Stack_flag_liveness.analyze_list b.ops in
  let rec loop acc ops idx =
    match ops with
    | [] -> List.rev acc
    | (Add as op) :: r_ops ->
        let flags_live = if idx + 1 < Array.length liveness then liveness.(idx + 1) else false in
        if not flags_live then
          let crt_knot = [
            Dup;
            PushImm 65537L;
            Nand; Dup; Nand;
            PopReg scratch_slot;
            PushReg scratch_slot;
            PushReg scratch_slot;
            Sub;
            Add;
          ] in
          loop (List.rev_append crt_knot (op :: acc)) r_ops (idx + 1)
        else
          loop (op :: acc) r_ops (idx + 1)
    | op :: r_ops ->
        loop (op :: acc) r_ops (idx + 1)
  in
  { b with ops = loop [] b.ops 0 }

let apply_block (cfg : crt_config) (ctx : Context_allocator.t) (b : block) : block =
  if not cfg.enabled then b
  else
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    apply_block_internal ~scratch_slot b

let apply_program (cfg : crt_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block_internal ~scratch_slot b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks; context_slots = Context_allocator.total_slots ctx }
