(** Pass 10: Branchless Bit-Blasted Flag Materialization Pass
    ─────────────────────────────────────────────────────────────
    Eliminates reliance on host RFLAGS/NZCV by expressing condition
    flags (CF, OF, SF, ZF, AF, PF) entirely as branchless algebraic
    bit-vector expressions in Z_{2^64}.

    Mathematical Invariants:
      1. Carry Flag (CF in {0, 1}):
           CF_add(x, y, r) = ((x & y) | ((x | y) & ~r)) >> 63
           CF_sub(x, y, r) = ((~x & y) | ((~x | y) & r)) >> 63
      2. Signed Overflow Flag (OF in {0, 1}):
           OF_add(x, y, r) = (~(x ^ y) & (x ^ r)) >> 63
           OF_sub(x, y, r) = ((x ^ y) & (x ^ r)) >> 63
      3. Zero Flag (ZF in {0, 1}):
           ZF(r) = ((r - 1) & ~r) >> 63
      4. Sign Flag (SF in {0, 1}):
           SF(r) = r >> 63
      5. Auxiliary Carry Flag (AF in {0, 1}):
           AF(x, y, r) = ((x ^ y ^ r) >> 4) & 1
      6. Parity Flag (PF in {0, 1}):
           PF(r) = (((((r ^ (r >> 4)) & 0xF) * 0x6996) >> ((r ^ (r >> 4)) & 0xF)) & 1) ^ 1
*)

open Stack_ir
open Vm_ir.Flags

type algebraic_flags_config = {
  enabled : bool;
}

val default_algebraic_flags_config : algebraic_flags_config

(** Emits branchless Stack-IR sequence evaluating ZF(r) = ((r - 1) & ~r) >> 63 *)
val emit_bit_blasted_zf : stack_op list

(** Emits branchless Stack-IR sequence evaluating SF(r) = r >> 63 *)
val emit_bit_blasted_sf : stack_op list

(** Emits branchless Stack-IR sequence evaluating CF_sub(x, y, r) *)
val emit_bit_blasted_cf_sub : stack_op list

(** Emits branchless Stack-IR sequence evaluating OF_sub(x, y, r) *)
val emit_bit_blasted_of_sub : stack_op list

(** Evaluates a condition algebraically using materialized flag slots *)
val emit_eval_condition_algebraic :
  condition ->
  cf_slot:int ->
  zf_slot:int ->
  sf_slot:int ->
  of_slot:int ->
  stack_op list

val apply_block :
  algebraic_flags_config ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  algebraic_flags_config ->
  Context_allocator.t ->
  program ->
  program
