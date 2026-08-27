(** Vm_runtime_profile — Unified Domain Aggregate for polymorphic runtime configuration. *)

type t = {
  seed             : int64;
  dispatch         : Dispatch_strategy.t;
  mutation         : Mutation_profile.t;
  cff_depth        : int;
  enable_nested_vm : bool;
}

val generate :
  seed:int64 ->
  total_opcodes:int ->
  ?cff_depth:int ->
  ?enable_nested_vm:bool ->
  unit ->
  t
