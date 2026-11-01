(** Phase 6e (Pass 24): Wolfram Rule 30 Non-Linear Keystream & Cellular Automaton Diffusion *)

open Stack_ir

type rule30_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_rule30_config : int64 -> rule30_config

val emit_or : unit -> stack_op list

val emit_xor : unit -> stack_op list

val emit_rotl1 : unit -> stack_op list

val emit_rotr1 : unit -> stack_op list

val emit_rule30_step : unit -> stack_op list

val emit_rule30_zero_knot : rule30_slot:int -> s_val:int64 -> stack_op list

val emit_advance_rule30 : rule30_slot:int -> salt:int64 -> stack_op list

val apply_block :
  rule30_config ->
  rule30_slot:int ->
  block ->
  block

val apply_program :
  rule30_config ->
  Context_allocator.t ->
  program ->
  program

val rule30_stats : program -> program -> string
