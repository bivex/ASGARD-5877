(** ASGARD-5877: Computational Stalling pass (CPU-bound anti-emulation).
    Implements three complementary mechanisms that raise the emulation
    slowdown factor Ω to force sandbox timeout or quota exhaustion while
    staying below the user-facing latency threshold τ_UX:
      1. RSW Time-Lock Puzzle  – strictly sequential squarings mod M = p·q;
         the compile-time key is computed via φ(M) in O(log N), the runtime
         path requires exactly N multiplications.
      2. PoW Hash Puzzle       – geometric search with d leading-zero bits,
         using hardware-expensive inner loop instructions (GF(2^64) multiply,
         carry-chain, Soft-TLB scatter).
      3. Timing Gap Validator  – analytical range check that verifies the
         chosen N satisfies T_real ≤ τ_UX and T_emu > τ_AV. *)

type stall_variant =
  | TimeLockPuzzle   (** Rivest–Shamir–Wagner sequential squaring mod M *)
  | HashPow          (** Proof-of-Work hash puzzle with d leading-zero bits *)
  | Combined         (** TimeLockPuzzle followed by HashPow *)

type hw_bound_primitive =
  | GF2Mul64          (** PCLMULQDQ / PMULL — carry-less GF(2^64) multiply *)
  | AesRound          (** AESENC / AESE + AESMC — AES round *)
  | Crc32Folding      (** CRC32 instruction chain *)
  | AdcChain          (** Dense ADC/SBB carry-chain (flag-intensive) *)

type stall_config = {
  variant           : stall_variant;
  (** Number of sequential squarings N for TimeLockPuzzle.
      Must satisfy the timing-gap inequality (see [validate_timing_gap]). *)
  n_iterations      : int;
  (** Leading-zero-bit difficulty d for HashPow; expected work = 2^d hashes. *)
  pow_difficulty    : int;
  (** Target real-CPU latency budget in seconds (τ_UX).  Default 0.05 s. *)
  tau_ux_sec        : float;
  (** Emulator instruction quota Q_max used for the evasion-probability model. *)
  emu_quota_instrs  : int;
  (** Hardware-expensive primitives to use in the PoW inner loop. *)
  hw_primitives     : hw_bound_primitive list;
  (** Seed for the PRNG that generates the RSW modulus halves and PoW seed. *)
  seed              : int64;
}

type timing_gap_result = {
  t_real_sec          : float;   (** T_real = N·I_iter / (f_real · IPC_real) *)
  t_emu_sec           : float;   (** T_emu  = T_real · Ω *)
  omega               : float;   (** Slowdown factor Ω *)
  evasion_probability : float;   (** P(Evasion) ≈ exp(-Q_max / (I_hash · 2^d)) *)
  gap_satisfied       : bool;    (** T_real ≤ τ_UX  ∧  T_emu > τ_AV *)
}

(** RSW Time-Lock compile-time key material (generated offline; only the
    public parameters M, a, n_iterations survive into the binary). *)
type rsw_key_material = {
  modulus_lo          : int64;   (** lower 64 bits of M (128-bit product p·q) *)
  modulus_hi          : int64;   (** upper 64 bits of M *)
  base_a              : int64;   (** random base a, 2 ≤ a < M *)
  n_iterations        : int;
  (** x_N = a^(2^N) mod M — the correct decryption key. *)
  x_n_lo              : int64;
  x_n_hi              : int64;
}

type comp_stall_error =
  | TimingGapNotSatisfied of { t_real: float; tau_ux: float }
  | OmegaTooSmall of { omega: float; required: float }
  | InvalidIterationCount of int
  | InvalidDifficulty of int
  | InvalidSeed

let error_to_string = function
  | TimingGapNotSatisfied { t_real; tau_ux } ->
      Printf.sprintf
        "CompStall: T_real=%.4fs exceeds τ_UX=%.4fs; reduce n_iterations" t_real tau_ux
  | OmegaTooSmall { omega; required } ->
      Printf.sprintf
        "CompStall: Ω=%.1f < τ_AV/τ_UX=%.1f; emulator too fast for this configuration" omega required
  | InvalidIterationCount n ->
      Printf.sprintf "CompStall: n_iterations=%d must be in [1, 1_000_000_000]" n
  | InvalidDifficulty d ->
      Printf.sprintf "CompStall: pow_difficulty=%d must be in [8, 40]" d
  | InvalidSeed ->
      "CompStall: seed must be non-zero"
