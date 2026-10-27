(** Phase 5e: Non-Linear PolyMBA Pass (E-Graph & Equality Saturation Breaker) *)

open Stack_ir

type polymba_config = {
  enabled : bool;
  rate : int; (** percentage of candidate sites to inject PolyMBA knots (0..100) *)
  seed : int64;
}

val default_polymba_config : int64 -> polymba_config

(** Emits a degree-2 quadratic cross-term zero knot:
    ((s + 1)^2) - (s^2 + 2s + 1) == 0 *)
val emit_quadratic_knot : scratch_slot:int -> stack_op list

(** Emits a non-linear dynamic-shift zero knot:
    ((s * 5 + 3) << (s & 15)) - ((s * 5 + 3) << (s & 15)) == 0 *)
val emit_dyn_shift_knot : scratch_slot:int -> stack_op list

val apply_block :
  polymba_config ->
  scratch_ring:int array ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  ?scratch_ring:int array ->
  polymba_config ->
  Context_allocator.t ->
  program ->
  program

val polymba_stats : program -> program -> string
