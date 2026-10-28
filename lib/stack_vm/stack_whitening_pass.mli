(** Phase 5l (Pass 23): Galois LFSR Non-Linear Whitening & Memory Diffing Resistance *)

open Stack_ir

type whitening_config = {
  enabled : bool;
  rate : int;
  seed : int64;
}

val default_whitening_config : int64 -> whitening_config

val emit_xor : unit -> stack_op list

val emit_xtime : unit -> stack_op list

val emit_galois_zero_knot : whitening_slot:int -> s_val:int64 -> stack_op list

val emit_advance_whitening : whitening_slot:int -> salt:int64 -> stack_op list

val apply_block :
  whitening_config ->
  whitening_slot:int ->
  block ->
  block

val apply_program :
  whitening_config ->
  Context_allocator.t ->
  program ->
  program

val whitening_stats : program -> program -> string
