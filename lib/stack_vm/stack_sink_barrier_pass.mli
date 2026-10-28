(** Phase 5i (Pass 18): I/O Sink Entanglement & Slicing Barrier Pass
    ───────────────────────────────────────────────────────────────
    Defeats Tier 4 backward program slicing (Triton / LLVM DSE / IDA Hex-Rays)
    by mathematically binding intermediate state registers and accumulator
    chains directly into observable sinks:
      1. Memory Sinks (WriteMem): entangles memory address and value operands
         with intermediate scratch registers via zero-knots.
      2. External Sinks (CallExtern): entangles live FFI argument registers
         (ctx[0]..ctx[5]) with scratch registers before invocation.
      3. Termination Sinks (Exit): entangles exit return register ctx[0]
         with scratch registers.
      4. Branch Sinks (JccRel): entangles comparison operands prior to Cmp/Test.

    Soundness Invariants:
    1. Zero Net Stack Delta: All injected barrier operations maintain exact stack depth.
    2. Exact Value Preservation: All transformations add/subtract zero-knots (V + 0 == V).
    3. Flag Preservation: Wraps barrier clusters in PushFlags ... PopFlags when downstream
       condition codes are live.
*)

open Stack_ir

type sink_barrier_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_sink_barrier_config : int64 -> sink_barrier_config

(** Emits an algebraic sink barrier zero-knot using scratch slot [s]:
    Knot = (s + C) - (s & C) - (s | C) == 0 (mod 2^64).
    Net stack delta = +1 (pushes 0L onto stack). *)
val emit_algebraic_barrier_knot : scratch_slot:int -> stack_op list

(** Emits a Mersenne prime field M31 barrier zero-knot using scratch slot [s]:
    Net stack delta = +1 (pushes 0L onto stack). *)
val emit_mersenne_barrier_knot : scratch_slot:int -> stack_op list

val apply_block :
  sink_barrier_config ->
  ?scratch_ring:int array ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  ?scratch_ring:int array ->
  sink_barrier_config ->
  Context_allocator.t ->
  program ->
  program

val sink_barrier_stats : program -> program -> string
