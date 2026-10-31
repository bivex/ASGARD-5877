(** Stack JIT VM chunker (SJIT tier-1 lowering, docs/STACK_JIT_VM_PROTOTYPE.md).

    Translates Stack-IR traces and programs into JIT chunks executed by
    the RD-JIT sealed native tier: window layout (context slots
    [0..ctx_slots-1], stack positions [stack_base..stack_base+3] with
    spilling through the reserved spill-pointer slot), Kolakoski fission
    (OEIS A000002) and Thue-Morse dummy padding (OEIS A010060), with a
    result epilogue that moves the final stack top to window slot 0.

    The translatable subset covers the arithmetic, logical, shift,
    memory, call and flag operations of Stack-IR; [Cmp]/[Test] materialise
    NZCV in the JIT code, [PushFlags]/[PopFlags] move the condition word
    through a real stack slot, and branches lower to chunk-hopping
    [JIT_OP_JMP]/[JIT_OP_JCC] patched to chunk indices.  Unsupported ops
    are rejected with a reason so the caller can fall back to another
    engine. *)

open Stack_ir

type jit_item = string * int * int * int64
(** (JIT_OP_* symbol, dst slot, src slot, immediate) consumed by
    [Rd_jit_emitter.compile_and_package_chunked]. *)

type translation = {
  chunks : jit_item list list; (** Kolakoski-fissioned, Thue-Morse padded *)
  final_depth : int;           (** net stack effect of the trace *)
  max_depth : int;             (** live-depth high-water mark *)
  real_instrs : int;           (** emitted instructions, dummies excluded *)
  dummy_instrs : int;          (** Thue-Morse dummy count *)
  invalidation_schedule : int array;
  (** OEIS A001511 fractal tiered invalidation schedule: entry [k] = 1 + ctz(k+1),
      the wipe level threshold applied by the arena after executing chunk k. *)
}

val ctx_slots : int
val stack_base : int
val max_stack_depth : int
(* OEIS A001511: ruler function A001511(t) = 1 + ctz(t) for t >= 1.
   Gives the fractal wipe level for execution step [t] in the RD-JIT
   arena: all slots of level <= A001511(t) are re-wiped after chunk t. *)
val ruler_a001511 : int -> int

(** Translate a straight-line stack trace.  [scale] multiplies the
    Kolakoski run lengths (default [Nano_jit_slot.nano_kolakoski_scale]).
    [entry_depth] models stack values inherited from predecessors (the
    successor sees the top of the physical window); [epilogue=false]
    suppresses the result move to slot 0 for multi-block callers. *)
val translate_trace :
  ?scale:int -> ?allow_branches:bool -> ?allow_spill:bool -> ?entry_depth:int ->
  ?epilogue:bool -> ?ctx_map:(int, int) Hashtbl.t -> ?used_slots:(int, unit) Hashtbl.t ->
  unit -> stack_op list -> (translation, string) result
(* Translate an entire multi-block Stack-IR program (with loops, jumps, and
   conditional branches) into Kolakoski chunks with dynamic JMP and JCC
   transfer resolution.  Cross-block stack state is honoured: each block's
   model starts at the entry depth its predecessors leave behind. *)
val translate_program :
  ?scale:int -> ?allow_spill:bool -> unit -> program -> (translation, string) result


(** Reference interpreter of the translatable subset over context
    registers and an int64 stack; returns the final stack (top first).
    Mutates [regs] for [PopReg]. *)
val reference_eval : int64 array -> stack_op list -> int64 list

(** Run translated chunks over a 16-slot window model (zero-initialized
    before execution); mutates [gprs]. *)
val simulate_chunks : jit_item list list -> int64 array -> unit
