(** Decoy VM Manifold — Believable Decoy Logic Synthesizer.
    ─────────────────────────────────────────────────────────────────
    Synthesizes semantically believable, structurally complex decoy
    validation routines (ARX / Feistel rounds, bitwise permutations,
    polynomial accumulators) to serve as the executable payload for
    the Decoy VM under analysis pressure. *)

open Vm_ir

val synth_decoy_validator_func :
  seed:int64 ->
  name:string ->
  Ir.func

val synth_decoy_bytecode :
  rng:Random.State.t ->
  seed:int64 ->
  name:string ->
  int64 list
