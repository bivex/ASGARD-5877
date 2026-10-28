(** Phase 5k (Pass 22): DRCC Top-Of-Stack Physical Register Window & A003022 Golomb Spilling *)

open Stack_ir

type drcc_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_drcc_config : int64 -> drcc_config

val golomb_diffs : int64 array

val emit_golomb_zero_knot : slot:int -> delta:int64 -> stack_op list

val emit_drcc_binary_cluster :
  tos0:int ->
  tos1:int ->
  delta:int64 ->
  op:stack_op ->
  flags_live:bool ->
  stack_op list

val emit_drcc_push_imm :
  tos0:int ->
  delta:int64 ->
  v:int64 ->
  flags_live:bool ->
  stack_op list

val apply_block :
  drcc_config ->
  tos0:int ->
  tos1:int ->
  block ->
  block

val apply_program :
  drcc_config ->
  Context_allocator.t ->
  program ->
  program

val drcc_stats : program -> program -> string
