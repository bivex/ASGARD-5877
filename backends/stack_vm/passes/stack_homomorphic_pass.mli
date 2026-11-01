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

type homomorphic_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_homomorphic_config : int64 -> homomorphic_config

(** Computes Newton-Raphson 64-bit modular inverse of odd integer [a] modulo 2^64. *)
val mod_inv_64 : int64 -> int64

(** Computes affine encryption of scalar [v] with key (alpha, beta). *)
val encrypt_scalar : alpha:int64 -> beta:int64 -> int64 -> int64

(** Emits blinded PushImm sequence reconstructing [v] with scratch slot [scratch_slot].
    Net stack delta = +1. *)
val emit_blinded_push_imm :
  alpha:int64 ->
  beta:int64 ->
  v:int64 ->
  scratch_slot:int ->
  flags_live:bool ->
  stack_op list

(** Emits blinded SetRegImm sequence setting register [reg] to [v].
    Net stack delta = 0. *)
val emit_blinded_set_reg_imm :
  alpha:int64 ->
  beta:int64 ->
  reg:int ->
  v:int64 ->
  flags_live:bool ->
  stack_op list

val apply_block :
  homomorphic_config ->
  scratch_slot:int ->
  block ->
  block

val apply_program :
  homomorphic_config ->
  Context_allocator.t ->
  program ->
  program

val homomorphic_stats : program -> program -> string
