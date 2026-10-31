(** ASGARD-5877: Path-Oriented Protections (POP)
    Based on research from arXiv:1908.01549:
    "How to Kill Symbolic Deobfuscation for Free; or Unleashing the Potential of Path-Oriented Protections"
    (Bardin, Marion, Ollivier et al.) *)

open Vm_ir

type pop_config = {
  digest_reg : Register.t;
  scratch_reg1 : Register.t;
  scratch_reg2 : Register.t;
  initial_seed : int64;
}

val default_pop_config : pop_config

(** Compute expected feasible path digest after transitioning through block [bid] with condition [cond_tag]. *)
val advance_digest : int64 -> int -> int64 -> int64

(** Injects Path-Oriented Protections into an IR function, coupling all basic block
    transitions to a cumulative trace digest and adding DSE-resistant infeasible constraints. *)
val apply_pop_transform : ?config:pop_config -> rng:Random.State.t -> Ir.func -> Ir.func
