(** Opaque Invariant Predicate Generator.
    Generates provable mathematical invariants over Z/2^64Z and Boolean lattices
    to construct opaque branch diamonds that are undecidable for static analyzers. *)

type opaque_kind =
  | BitmaskDisjoint
  | AdditiveIdentity
  | ParityNilpotent

val generate_zero_predicate :
  rng:Random.State.t ->
  scratch:Register.t ->
  target_true:Ir.target ->
  target_decoy:Ir.target ->
  Ir.instr list
