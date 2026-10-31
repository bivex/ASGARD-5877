(** Phase 5j (Pass 21): Dual-Rail Complement Arithmetic & Invariant Checkpoints
    ───────────────────────────────────────────────────────────────────────────
    Provides fault injection resistance (EMFI, clock glitching) and dynamic
    tamper detection by shadowing context registers with bitwise complements
    r_bar = NOT(r) = -1 - r (mod 2^64).

    Mechanisms:
      1. Dual-Rail Pairing: Context registers are paired with dedicated shadow slots
         r_bar maintained through dual-rail updates (SetRegImm/PopReg).
      2. Fundamental Invariants:
         - Sum Invariant: r + r_bar + 1 == 0 (mod 2^64)
         - Orthogonality: r & r_bar == 0
         - Span Invariant: r | r_bar == -1
      3. Dynamic Fault Checkpoints:
         Evaluates invariant zero-knots (r + r_bar + 1) directly into stack operands.
         Any fault injection (bit-flip, glitch) breaks the invariant, silently
         destroying computation without obvious detection branches.

    Soundness Invariants:
    1. Zero Net Stack Delta: All checkpoint clusters maintain exact stack depth.
    2. Exact Value Preservation: Legitimate execution adds 0 to operands (V + 0 == V).
    3. Flag Preservation: Wraps updates in PushFlags ... PopFlags when downstream
       condition codes are live.
*)

open Stack_ir

type dual_rail_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_dual_rail_config : int64 -> dual_rail_config

(** Emits complement update for register [reg] into [dual_slot]:
    PushReg reg; Dup; Nand; PopReg dual_slot;
    Net stack delta = 0. *)
val emit_dual_update : reg:int -> dual_slot:int -> stack_op list

(** Emits sum invariant zero-knot:
    PushReg reg; PushReg dual_slot; Add; PushImm 1L; Add;
    Evaluates to 0L on stack top. Net stack delta = +1. *)
val emit_sum_invariant_knot : reg:int -> dual_slot:int -> stack_op list

(** Emits orthogonality invariant zero-knot:
    PushReg reg; PushReg dual_slot; Nand; Dup; Nand;
    Evaluates to 0L on stack top. Net stack delta = +1. *)
val emit_ortho_invariant_knot : reg:int -> dual_slot:int -> stack_op list

val apply_block :
  dual_rail_config ->
  ?pairs:(int * int) array ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  dual_rail_config ->
  Context_allocator.t ->
  program ->
  program

val dual_rail_stats : program -> program -> string
