(** ASGARD-5877: Computational Stalling Engine.
    CPU-bound anti-emulation pass: RSW Time-Lock Puzzle + PoW Hash Puzzle.

    Mathematical basis
    ──────────────────
    Timing gap inequality:   T_real ≤ τ_UX  ∧  T_emu = T_real·Ω > τ_AV
    Existence criterion:     Ω > τ_AV / τ_UX

    RSW sequential squarings:  x_N ≡ a^(2^N) mod M,  N steps, depth Θ(N).
    PoW evasion probability:   P(Evasion) ≈ exp(-Q_max / (I_hash · 2^d)) → 1. *)

open Comp_stall_types

val validate_timing_gap :
  config:stall_config ->
  f_real_ghz:float ->
  ipc_real:float ->
  i_iter:int ->
  omega:float ->
  tau_av_sec:float ->
  (timing_gap_result, comp_stall_error) result
(** Analytically verifies that the chosen [n_iterations] satisfies the
    timing-gap system of inequalities for the given hardware and emulator
    parameters.  Returns a [timing_gap_result] on success. *)

val compute_rsw_key :
  seed:int64 ->
  n_iterations:int ->
  rsw_key_material
(** Offline (compile-time) O(log N) RSW key computation.
    Generates a synthetic 128-bit modulus M = p·q from [seed] using a
    deterministic LCG, then computes x_N = a^(2^N) mod M via
    e = 2^N mod φ(M) and fast modular exponentiation.
    Only M, a, n_iterations are public; x_N is the secret decryption key. *)

val simulate_runtime_unlock :
  key:rsw_key_material ->
  (int64 * int64)
(** Simulates the strictly sequential O(N) runtime unlock by running the
    N squarings.  Returns the (lo, hi) pair of x_N for verification. *)

val compute_pow_difficulty_for_quota :
  emu_quota_instrs:int ->
  i_hash:int ->
  target_evasion_prob:float ->
  int
(** Solves for d such that P(Evasion) ≥ target_evasion_prob:
    d = ceil(log2(-Q_max / (I_hash · ln(1 - p_target)))). *)

val emit_comp_stall_cpp_header : unit -> string
(** Emits the standalone C++20 header <asg_comp_stall.hpp> as a rendered
    string using the typed EDSL (Cpp_dsl / Cpp_printer).
    The header provides:
      - [RswTimeLock<N>]        – template struct with [run()] and [verify()]
      - [PowHashPuzzle<D>]      – template struct with [solve(seed, tag)]
      - [CompStallGuard<N,D>]   – composite guard that runs both *)
