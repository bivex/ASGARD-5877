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

let apply_block_internal ~scratch_slot (cfg : path_config) (b : block) : block =
  let rec inject acc = function
    | [] -> List.rev acc
    | (JmpRel target as term) :: rest ->
        let src_enc = compute_block_encoding ~seed:cfg.seed ~block_id:b.id in
        let dst_enc = compute_block_encoding ~seed:cfg.seed ~block_id:target in
        let (a, b_imm) = compute_edge_transition ~src_enc ~dst_enc in
        let trans_ops = emit_edge_transition ~slot:scratch_slot ~a ~b:b_imm in
        inject (term :: List.rev_append trans_ops acc) rest
    | (JccRel (target, _cond) as term) :: rest ->
        let src_enc = compute_block_encoding ~seed:cfg.seed ~block_id:b.id in
        let dst_enc = compute_block_encoding ~seed:cfg.seed ~block_id:target in
        let (a, b_imm) = compute_edge_transition ~src_enc ~dst_enc in
        let trans_ops = emit_edge_transition ~slot:scratch_slot ~a ~b:b_imm in
        inject (term :: List.rev_append trans_ops acc) rest
    | op :: rest ->
        inject (op :: acc) rest
  in
  { b with ops = inject [] b.ops }

let apply_block (cfg : path_config) (ctx : Context_allocator.t) (b : block) : block =
  if not cfg.enabled then b
  else
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    apply_block_internal ~scratch_slot cfg b

let apply_program (cfg : path_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled then prog
  else
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block_internal ~scratch_slot cfg b in
      Hashtbl.replace new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks; context_slots = Context_allocator.total_slots ctx }
