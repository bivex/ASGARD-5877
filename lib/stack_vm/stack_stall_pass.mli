(** ASGARD-5877: Stack-VM Bytecode Computational Stalling Pass.
    Injects a non-linear dynamical stall loop directly into the program
    bytecode (Stack-IR), ensuring computational stalling runs exclusively
    within the interpreted VM rather than in native host prologue code. *)

open Stack_ir

type stall_config = {
  n_iterations : int;
  seed : int64;
  variant : string;
}

val default_config : stall_config

val apply_stall : ?ctx:Context_allocator.t -> ?config:stall_config -> program -> program
(** Synthesizes stall entry blocks implementing an ergodic cubic permutation
    polynomial ($x_{n+1} = x_n + 2x_n^2 + 4x_n^3 + c \pmod{2^{64}}$), connects
    the secret termination state to live register ctx[0], and routes control flow
    to the original program entry. Scratch slots are allocated through [ctx]
    to prevent collision with subsequent passes (amplifier, ghost padding). *)
