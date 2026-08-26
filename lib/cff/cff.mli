open Vm_ir

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
}

val default_cff_options : cff_options

(** Flattens the control flow graph of a function into a centralized state dispatcher. *)
val flatten_func :
  ?options:cff_options ->
  rng:Random.State.t ->
  Ir.func ->
  (Ir.func, string) result

(** Injects an opaque predicate into a basic block, creating an invariant conditional branch. *)
val inject_opaque_predicate :
  rng:Random.State.t ->
  trap_block_id:int ->
  Ir.basic_block ->
  Ir.basic_block
