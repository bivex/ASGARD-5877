(** Phase 5c: Stack-VM Memory-Address Entanglement Pass *)

open Stack_ir

type mem_webbing_config = {
  enabled : bool;
  rate : int; (** percentage of candidate sites to entangle (0..100) *)
  seed : int64;
}

val default_mem_webbing_config : int64 -> mem_webbing_config

(** Generates a memory-address entanglement cluster on slot [scratch_slot]
    using stack pointer slot [sp_slot].
    Net stack delta = 0; value of [scratch_slot] is preserved. *)
val generate_mem_web_cluster :
  sp_slot:int ->
  scratch_slot:int ->
  bool ->
  stack_op list

(** Applies memory-address entanglement to a basic block. *)
val apply_block :
  mem_webbing_config ->
  sp_slot:int ->
  scratch_ring:int array ->
  Context_allocator.t ->
  block ->
  block

(** Applies memory-address entanglement across all basic blocks in [prog].
    If [scratch_ring] is omitted, allocates a fresh 4-slot ring in [ctx].
    If [sp_slot] is omitted, derives it from [Register.rsp] via [ctx]. *)
val apply_program :
  ?scratch_ring:int array ->
  ?sp_slot:int ->
  mem_webbing_config ->
  Context_allocator.t ->
  program ->
  program

val mem_webbing_stats : program -> program -> string
