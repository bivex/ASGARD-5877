(** Phase 6f (Pass 27): Native Micro-Handler Interleaving Pass *)

open Stack_ir

type native_interleave_config = {
  enabled : bool;
  rate : int;
  seed : int64;
  arch : Stack_native_stub.arch;
}

val default_native_interleave_config :
  ?arch:Stack_native_stub.arch -> int64 -> native_interleave_config

val apply_block :
  native_interleave_config ->
  block ->
  block

val apply_program :
  native_interleave_config ->
  Context_allocator.t ->
  program ->
  program

val native_interleave_stats : program -> program -> string
