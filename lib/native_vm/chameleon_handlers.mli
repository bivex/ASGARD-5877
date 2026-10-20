(** Next-Gen Chameleon & Delayed-Commit Handler Synthesizer for ASGARD-5877:
    Destroys the concept of '1 Handler = 1 ALU Operation' and protects the handlers
    from isolated fuzzing in Unicorn/Qiling/Syntia:
    1. Chameleon ALU Kernel: a single parametric handler computes ADD, SUB, XOR, AND, OR
       depending on the dynamic weight vector (w_xor, w_and, w_or, w_bias)
    2. Delayed-Commit Writeback Queue: handler T commits the result of step T-1
       to the registers, and keeps its own result in the encrypted deferred-write buffer *)

type chameleon_weights = {
  w_xor  : int64;  (** Weight of the (x ^ y) component *)
  w_and  : int64;  (** Weight of the (x & y) component *)
  w_or   : int64;  (** Weight of the (x | y) component *)
  w_bias : int64;  (** Masking shift in Z_{2^64} *)
}

type target_alu_sem =
  | SemAdd
  | SemSub
  | SemXor
  | SemAnd
  | SemOr

(** State of the deferred-write pipeline (Delayed-Commit Pipeline State) *)
type delayed_pipeline_state = {
  mutable pending_reg  : int;
  mutable pending_val  : int64;
  mutable pending_mask : int64;
  mutable has_pending  : bool;
}

val create_pipeline_state : unit -> delayed_pipeline_state

val rand_u64 : Random.State.t -> int64

(** Synthesis of a random but mathematically exact set of weights (w_xor, w_and, w_or, w_bias)
    for computing the given semantics via the identity (x | y) == (x ^ y) + (x & y).
    For the same operation (e.g. SemAdd) every call generates
    a NEW unique quadruple of 64-bit weights! *)
val synth_chameleon_weights :
  Random.State.t -> target_alu_sem -> chameleon_weights

(** Evaluation of the chameleon-handler kernel in the ring Z_{2^64} (including the compensating shift -w_bias) *)
val eval_chameleon_kernel :
  chameleon_weights -> int64 -> int64 -> int64

(** Simulation of a handler step with deferred commit (Delayed-Commit Execution):
    writes the result of the PREVIOUS instruction (T-1) into regs, while the result
    of the current one (T) is placed into the encrypted pipeline slot *)
val step_delayed_commit_handler :
  delayed_pipeline_state -> int64 array ->
  dst_reg:int -> new_result:int64 -> next_mask:int64 -> unit

(** Forced flush of the last deferred value before exiting the VM *)
val flush_delayed_commit :
  delayed_pipeline_state -> int64 array -> unit

(** Generation of C++20 code of the Chameleon + Delayed-Commit dispatcher via the typed Cpp_codegen EDSL *)
val emit_chameleon_handlers_hpp : Random.State.t -> string
