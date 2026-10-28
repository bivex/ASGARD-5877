(** Stack JIT VM chunker (SJIT tier-1 lowering, docs/STACK_JIT_VM_PROTOTYPE.md).

    Translates a straight-line Stack-IR trace into JIT chunks executed by
    the RD-JIT sealed native tier: window layout (context slots [0..7],
    stack positions [8..15]), Kolakoski fission (OEIS A000002) and
    Thue-Morse dummy padding (OEIS A010060), with a result epilogue that
    moves the final stack top to window slot 0.

    Translatable subset (semantics per the handlers of
    [stack_handlers_emitter.ml]): [PushImm], [PushReg], [PopReg], [Add],
    [Sub], [Mul], [Nand], [Nor], [Dup], [Swap], [AddImm], [SubImm],
    [AddImmImm], [SubImmImm].  [Sub] pops [b] (top) then [a] (deeper) and
    pushes [a - b]; [Nand]/[Nor] lower to AND/OR followed by NOT.  Shifts,
    division, flags, branches, memory and escapes are rejected with a
    reason so the caller can fall back to another engine. *)

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
}

val ctx_slots : int
val stack_base : int
val max_stack_depth : int

(** Translate a straight-line stack trace.  [scale] multiplies the
    Kolakoski run lengths (default [Nano_jit_slot.nano_kolakoski_scale]). *)
val translate_trace :
  ?scale:int -> ?allow_branches:bool -> unit -> stack_op list -> (translation, string) result
(* Translate an entire multi-block Stack-IR program (with loops, jumps, and
   conditional branches) into Kolakoski chunks with dynamic JMP and JCC
   transfer resolution. *)
val translate_program :
  ?scale:int -> unit -> program -> (translation, string) result


(** Reference interpreter of the translatable subset over context
    registers and an int64 stack; returns the final stack (top first).
    Mutates [regs] for [PopReg]. *)
val reference_eval : int64 array -> stack_op list -> int64 list

(** Run translated chunks over a 16-slot window model (zero-initialized
    before execution); mutates [gprs]. *)
val simulate_chunks : jit_item list list -> int64 array -> unit
