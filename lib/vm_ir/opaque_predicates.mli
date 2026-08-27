(** Advanced Anti-Symbolic Opaque Predicates Generator.
    Constructs mathematical, non-linear algebraic, and memory-aliasing invariant branches
    to prevent symbolic state merging (angr/Triton) and trigger SMT array theory explosion. *)

type opaque_kind =
  | BitmaskDisjoint
  | AdditiveIdentity
  | ParityNilpotent
  | NonLinearMemoryAliasing
  | ModularExpInvariant

val generate_zero_predicate :
  rng:Random.State.t ->
  scratch:Register.t ->
  target_true:Ir.target ->
  target_decoy:Ir.target ->
  Ir.instr list
