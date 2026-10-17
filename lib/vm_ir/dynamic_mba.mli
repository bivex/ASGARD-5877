open Ir

(** Dynamic MBA Diamonds pass:
    Transforms integer ALU operations (Add, Sub, Xor, And, Or) into dynamic
    dual-variant execution diamonds.
    
    At runtime, a data bit from an in-flight register decides whether
    Variant 1 or Variant 2 executes. Both variants compute the exact same
    mathematical result using different Boolean arithmetic identities and
    different instruction counts/sequences.
    
    This injects data-dependent control flow and trace entropy deep inside
    basic blocks, destroying sequence-prediction learnability while guaranteeing
    100% semantic equivalence. *)

val transform :
  ?density:float ->
  rng:Random.State.t ->
  func ->
  func
