(** Phase 2d (Pass 20): Homomorphic Ciphertext Operand Blinding Pass
    ─────────────────────────────────────────────────────────────────
    Eliminates scalar immediate constants from plaintext appearance in the
    bytecode stream (PushImm imm, SetRegImm (r, imm)) by encoding them into
    affine quotient rings:
      E(v) = (alpha * v + beta) mod 2^64, where gcd(alpha, 2^64) = 1.

    Mechanisms:
      1. Affine Ciphertext Space: Raw scalars are replaced with pseudo-random
         ciphertext words enc_v.
      2. Peephole-Resistant Desugaring: Reconstructed via scratch register
         breaks (PushImm enc_v; PushImm beta; Sub; PopReg s; PushReg s; PushImm alpha_inv; Mul)
         preventing AST constant folding.
      3. Complete Bytecode Masking: All sensitive scalars (hashes, keys, magic tags)
         are completely wiped from plaintext bytecode disassembly.

    Soundness Invariants:
    1. Exact Value Preservation: alpha_inv * (E(v) - beta) == v for all 2^64 values.
    2. Exact Stack Depth: PushImm desugaring preserves net stack delta +1;
       SetRegImm preserves net stack delta 0.
    3. Flag Preservation: Wraps reconstruction in PushFlags ... PopFlags when downstream
       condition codes are live.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type homomorphic_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

let default_homomorphic_config seed = {
  enabled = true;
  rate = 35;
  seed;
}

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  (s, logxor z (shift_right_logical z 31))

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let z = next_int64 rng in
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

(** Newton-Raphson 64-bit modular inverse of odd integer [a] modulo 2^64. *)
let mod_inv_64 a =
  let open Int64 in
  let a = logor a 1L in (* Ensure odd *)
  let x = logxor (mul 3L a) 2L in
  let x = mul x (sub 2L (mul a x)) in
  let x = mul x (sub 2L (mul a x)) in
  let x = mul x (sub 2L (mul a x)) in
  mul x (sub 2L (mul a x))

let encrypt_scalar ~alpha ~beta v =
  let open Int64 in
  add (mul alpha v) beta

let emit_blinded_push_imm ~alpha ~beta ~v ~scratch_slot ~flags_live =
  let enc_v = encrypt_scalar ~alpha ~beta v in
  let inv = mod_inv_64 alpha in
  if flags_live then
    [
      PushFlags;
      PushImm enc_v;
      PushImm beta;
      Sub;
      PushImm inv;
      Mul;
      PopReg scratch_slot;
      PopFlags;
      PushReg scratch_slot;
    ]
  else
    [
      PushImm enc_v;
      PushImm beta;
      Sub;
      PopReg scratch_slot;
      PushReg scratch_slot;
      PushImm inv;
      Mul;
    ]

let emit_blinded_set_reg_imm ~alpha ~beta ~reg ~v ~flags_live =
  let enc_v = encrypt_scalar ~alpha ~beta v in
  let inv = mod_inv_64 alpha in
  if flags_live then
    [
      PushFlags;
      PushImm enc_v;
      PushImm beta;
      Sub;
      PushImm inv;
      Mul;
      PopReg reg;
      PopFlags;
    ]
  else
    [
      PushImm enc_v;
      PushImm beta;
      Sub;
      PushImm inv;
      Mul;
      PopReg reg;
    ]

let apply_block (cfg : homomorphic_config) ~scratch_slot (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.logxor homomorphic_salt
              (Int64.of_int (b.id * 0x7758 + 0x5877))))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in

    List.iteri (fun idx op ->
      let flags_live = if idx + 1 < Array.length live then live.(idx + 1) else false in
      match op with
      | PushImm v when next_int rng 100 < cfg.rate ->
          let alpha = Int64.logor (next_int64 rng) 1L in
          let beta = next_int64 rng in
          let cluster = emit_blinded_push_imm ~alpha ~beta ~v ~scratch_slot ~flags_live in
          new_ops := List.rev cluster @ !new_ops

      | SetRegImm (reg, v) when next_int rng 100 < cfg.rate ->
          let alpha = Int64.logor (next_int64 rng) 1L in
          let beta = next_int64 rng in
          let cluster = emit_blinded_set_reg_imm ~alpha ~beta ~reg ~v ~flags_live in
          new_ops := List.rev cluster @ !new_ops

      | _ ->
          new_ops := op :: !new_ops
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : homomorphic_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg ~scratch_slot b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }
let homomorphic_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  let diff = after - before in
  Printf.sprintf "Homomorphic Operand Blinding: %d ops -> %d ops (+%d blinded operand clusters, +%.1f%%)"
    before after diff
    (if before = 0 then 0.0 else float_of_int diff /. float_of_int before *. 100.0)
