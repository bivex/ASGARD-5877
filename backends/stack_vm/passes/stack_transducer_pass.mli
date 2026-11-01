(** Phase 5d: Stateful Transducer Pass (Key-Coupled Micro-Ops) *)

open Stack_ir

type transducer_config = {
  enabled : bool;
  rate : int; (** percentage of eligible ALU ops to couple (0..100) *)
  seed : int64;
}

val default_transducer_config : int64 -> transducer_config

(** Transforms an Add operation into a stateful transducer-coupled cluster:
    [B, A] -> (B - S) + (A + S) == A + B *)
val transform_add : state_slot:int -> stack_op list

(** Transforms a Sub operation into a stateful transducer-coupled cluster:
    [B, A] -> (A + S) - (B + S) == A - B *)
val transform_sub : state_slot:int -> stack_op list

(** Advances the transducer state: S := S * transducer_step_mul + transducer_step_add *)
val emit_step : state_slot:int -> stack_op list

val apply_block :
  transducer_config ->
  state_slot:int ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  ?state_slot:int ->
  transducer_config ->
  Context_allocator.t ->
  program ->
  program

val transducer_stats : program -> program -> string
