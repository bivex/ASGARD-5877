(** Phase 4b: Stack-VM Avid Junk Operands Pass *)

open Stack_ir

type avid_config = {
  enabled  : bool;
  rate     : int;
  max_avid : int;
  seed     : int64;
}

val default_avid_config : int64 -> avid_config

val apply_block : avid_config -> Context_allocator.t -> block -> block

val apply_program : avid_config -> Context_allocator.t -> program -> program

val avid_stats : program -> program -> string
