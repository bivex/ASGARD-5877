(** Phase 6b (Pass 19): Cross-Block Execution Path Integrity & Anti-DBI Traps
    ────────────────────────────────────────────────────────────────────────
    Cryptographically couples the runtime execution path to dynamic trap
    assertions, defeating dynamic binary instrumentation (Frida, QBDI, GDB/LLDB).

    Mechanisms:
      1. Path Digest Accumulator: Maintains an evolving cryptographic digest
         H_{k+1} = (H_k * C_mul + Token(B_i)) mod 2^64 across every executed basic block.
      2. Dynamic Anti-DBI Zero-Knots:
         Evaluates algebraic path assertions (H + C) - (H & C) - (H | C) == 0 (mod 2^64),
         entangled directly into stack operands and context writes.
      3. Silent Desynchronization: If an adversary hooks a handler or bypasses
         a security check block, H is corrupted, causing silent algebraic distortion
         and invalid opcode aborts downstream.

    Soundness Invariants:
    1. Zero Net Stack Delta: Digest updates and knot evaluations preserve stack balance.
    2. Exact Value Preservation: All transformations add 0 to operands under legitimate paths.
    3. Flag Preservation: Wraps updates in PushFlags ... PopFlags when condition codes are live.
*)

open Stack_ir

type trap_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_trap_config : int64 -> trap_config

(** Computes a deterministic 64-bit token for block [bid]. *)
val block_token : int -> int64

(** Emits the path digest update cluster for block [bid] into slot [digest_slot]:
    H = (H * C_mul + Token(bid)) mod 2^64.
    Net stack delta = 0. *)
val emit_digest_update : digest_slot:int -> bid:int -> stack_op list

(** Emits an anti-DBI path zero-knot using [digest_slot]:
    Knot = (H + C) - (H & C) - (H | C) == 0 (mod 2^64).
    Net stack delta = +1 (pushes 0L onto stack). *)
val emit_trap_knot : digest_slot:int -> stack_op list

val apply_block :
  trap_config ->
  digest_slot:int ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  trap_config ->
  Context_allocator.t ->
  program ->
  program

val trap_stats : program -> program -> string
