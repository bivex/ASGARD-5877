open Ir

(** Data-keyed dynamic decoys pass:
    Inserts data-dependent dynamic branching diamonds (2-way and 4-way) at
    safe control-flow transitions.
    
    The branch direction at each diamond is decided at RUNTIME by computing
    bits from an in-flight live register (e.g. `(r >> shift) & mask`).
    Each branch arm executes a distinct sequence and length of dead-write
    ALU/Mov instructions targeting scratch register [Register.vx26], then
    re-converges on the original target.
    
    Because the path taken depends on runtime input data and each arm has a
    different length and handler-class sequence, the dynamic trace seen by an
    attacker/fuzzer/ML model is no longer deterministic across inputs, and
    phases are shifted, destroying sequence prediction without affecting
    program semantics. *)

val transform :
  ?density:float ->
  ?split_blocks:bool ->
  rng:Random.State.t ->
  func ->
  func
