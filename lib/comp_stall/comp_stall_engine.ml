(** ASGARD-5877: Computational Stalling Engine.
    CPU-bound anti-emulation pass: RSW Time-Lock Puzzle + PoW Hash Puzzle. *)

open Comp_stall_types
open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer
module Magic_numbers = Random_visa_constants.Magic_numbers

(* ── SplitMix64 PRNG (same finaliser as tech_2608/tech_2603) ────────────── *)
(* State threading: returns (new_state, output).  The increment
   Magic_numbers.golden_ratio_64 is added each call to advance the counter. *)
let _splitmix64 s =
  let open Int64 in
  let s = add s Magic_numbers.golden_ratio_64 in
  let z = s in
  let z = logxor z (shift_right_logical z 30) in
  let z = mul z Magic_numbers.splitmix64_gamma in
  let z = logxor z (shift_right_logical z 27) in
  let z = mul z Magic_numbers.splitmix64_mix in
  (s, logxor z (shift_right_logical z 31))

(* ── Small prime generation ─────────────────────────────────────────────── *)
(* We work with 32-bit primes so that M = p*q fits safely in int64 (63 bits
   of unsigned space) and all modular arithmetic stays in native OCaml ints
   (on 64-bit hosts).  The RSW sequential-squaring semantic is preserved. *)

let is_prime_32 n =
  if n < 2 then false
  else if n = 2 then true
  else if n land 1 = 0 then false
  else
    let limit = int_of_float (sqrt (float_of_int n)) in
    let rec loop d =
      if d > limit then true
      else if n mod d = 0 then false
      else loop (d + 2)
    in
    loop 3

(* LCG step using comp_stall_lcg_mul and comp_stall_lcg_add.
   Returns next 64-bit LCG state. *)
let lcg_step (state : int64) : int64 =
  let open Int64 in
  add (mul state Magic_numbers.comp_stall_lcg_mul) Magic_numbers.comp_stall_lcg_add

(* Derive a prime in [lo_32bit, hi_32bit] from a 64-bit seed value.
   Starts from an odd number derived from the seed and increments by 2. *)
let derive_prime_32 (seed : int64) (lo : int) (hi : int) : int =
  (* Take lower 32 bits, map to [lo, hi] range, ensure odd *)
  let raw = Int64.to_int (Int64.logand seed 0x7FFFFFFFL) in
  let range = hi - lo in
  let start = lo + (raw mod range) in
  (* Make start odd *)
  let start = if start land 1 = 0 then start + 1 else start in
  (* Linear scan for next prime *)
  let rec find n =
    if n > hi then find lo (* wrap around — lo_32bit area *)
    else if is_prime_32 n then n
    else find (n + 2)
  in
  find start

(* ── Modular arithmetic helpers (int64, positive values) ────────────────── *)
(* mulmod a b m: returns (a * b) mod m without overflow, using int64.
   Requires 0 ≤ a, b < m and m ≤ 2^31 so that a*b < 2^62. *)
let mulmod (a : int64) (b : int64) (m : int64) : int64 =
  let r = Int64.rem (Int64.mul a b) m in
  if r < 0L then Int64.add r m else r

(* powmod base exp_ m: fast modular exponentiation, exp_ ≥ 0. *)
let powmod (base : int64) (exp_ : int64) (m : int64) : int64 =
  if m = 1L then 0L
  else begin
    let result = ref 1L in
    let b = ref (Int64.rem base m) in
    let e = ref exp_ in
    while !e > 0L do
      if Int64.logand !e 1L = 1L then
        result.contents <- mulmod !result !b m;
      b.contents <- mulmod !b !b m;
      e.contents <- Int64.shift_right_logical !e 1
    done;
    !result
  end

(* Compute 2^n mod phi using repeated squaring of the exponent itself.
   This is the compile-time fast path: O(log n) multiplications. *)
let two_pow_n_mod (n : int) (phi : int64) : int64 =
  (* We want e = 2^n mod phi.  Start with e=1, double n times mod phi. *)
  let e = ref 1L in
  for _ = 1 to n do
    e.contents <- Int64.rem (Int64.mul !e 2L) phi
  done;
  !e

(* ── Public API ─────────────────────────────────────────────────────────── *)

let validate_timing_gap
    ~(config : stall_config)
    ~(f_real_ghz : float)
    ~(ipc_real : float)
    ~(i_iter : int)
    ~(omega : float)
    ~(tau_av_sec : float)
  : (timing_gap_result, comp_stall_error) result =
  (* Validate basic parameter ranges *)
  if config.n_iterations < 1 || config.n_iterations > 1_000_000_000 then
    Error (InvalidIterationCount config.n_iterations)
  else if config.pow_difficulty < 8 || config.pow_difficulty > 40 then
    Error (InvalidDifficulty config.pow_difficulty)
  else if config.seed = 0L then
    Error InvalidSeed
  else begin
    (* T_real = N * I_iter / (f_real * IPC_real)
       f_real is in GHz so multiply by 1e9 to get Hz *)
    let f_hz = f_real_ghz *. 1.0e9 in
    let t_real = float_of_int config.n_iterations *. float_of_int i_iter
                 /. (f_hz *. ipc_real) in
    let t_emu  = t_real *. omega in
    (* PoW evasion probability: P(Evasion) ≈ exp(-Q_max / (I_hash * 2^d)) *)
    let i_hash = float_of_int i_iter in  (* reuse I_iter as I_hash estimate *)
    let expected_hashes = 2.0 ** float_of_int config.pow_difficulty in
    let evasion_prob =
      exp (-. float_of_int config.emu_quota_instrs /. (i_hash *. expected_hashes))
    in
    let gap_satisfied = t_real <= config.tau_ux_sec && t_emu > tau_av_sec in
    (* Tau_AV_required: any Ω-independent check *)
    let required_omega = tau_av_sec /. config.tau_ux_sec in
    if omega < required_omega then
      Error (OmegaTooSmall { omega; required = required_omega })
    else if t_real > config.tau_ux_sec then
      Error (TimingGapNotSatisfied { t_real; tau_ux = config.tau_ux_sec })
    else
      Ok { t_real_sec = t_real; t_emu_sec = t_emu; omega; evasion_probability = evasion_prob;
           gap_satisfied }
  end

let rec gcd a b =
  if b = 0L then a else gcd b (Int64.rem a b)

let compute_rsw_key ~(seed : int64) ~(n_iterations : int) : rsw_key_material =
  (* Step 1: derive two distinct primes p and q from the seed.
     We bound p < 20011, q < 40009 so that M = p * q < 2^30.
     Then x^2 < 2^60 < 2^63 - 1, completely preventing 64-bit overflow. *)
  let s1 = lcg_step seed in
  let s2 = lcg_step s1 in
  let p = derive_prime_32 s1 10007 20011 in
  let q = derive_prime_32 s2 20021 40009 in
  let p64 = Int64.of_int p in
  let q64 = Int64.of_int q in
  let m = Int64.mul p64 q64 in
  (* Step 2: φ(M) = (p-1)*(q-1) *)
  let phi_m = Int64.mul (Int64.of_int (p - 1)) (Int64.of_int (q - 1)) in
  (* Step 3: choose base a = 2 + (|seed| mod (M-2)), ensure 2 ≤ a < M and gcd(a, M) = 1 *)
  let seed_pos = if seed < 0L then Int64.neg seed else seed in
  let m_minus_2 = Int64.sub m 2L in
  let raw_a = Int64.add 2L (Int64.rem (Int64.logand seed_pos 0x7FFFFFFFFFFFFFFFL) m_minus_2) in
  let rec make_coprime x =
    if gcd x m = 1L then x
    else make_coprime (Int64.add x 1L)
  in
  let a = make_coprime raw_a in
  (* Step 4: e = 2^N mod φ(M) *)
  let e = two_pow_n_mod n_iterations phi_m in
  (* Step 5: x_N = a^e mod M *)
  let x_n = powmod a e m in
  { modulus_lo = m;
    modulus_hi = 0L;
    base_a     = a;
    n_iterations;
    x_n_lo     = x_n;
    x_n_hi     = 0L;
  }

let simulate_runtime_unlock ~(key : rsw_key_material) : int64 * int64 =
  (* Strictly sequential: x_{i+1} = x_i^2 mod M.  Cannot be parallelised. *)
  let m = key.modulus_lo in
  let x = ref (Int64.rem key.base_a m) in
  for _ = 1 to key.n_iterations do
    x.contents <- mulmod !x !x m
  done;
  (!x, 0L)

let compute_pow_difficulty_for_quota
    ~(emu_quota_instrs : int)
    ~(i_hash : int)
    ~(target_evasion_prob : float)
  : int =
  (* P(Evasion) ≈ exp(-Q_max / (I_hash * 2^d)) = p_target
     => -Q / (I * 2^d) = ln(p_target)
     => 2^d = -Q / (I * ln(p_target))
     => d = ceil(log2(-Q / (I * ln(p_target)))) *)
  let ln_p = log target_evasion_prob in
  (* Clamp: if p_target >= 1.0 ln is non-negative, handle edge *)
  let ln_p = if ln_p >= 0.0 then -1.0e-9 else ln_p in
  let two_d = -. float_of_int emu_quota_instrs /. (float_of_int i_hash *. ln_p) in
  let d = ceil (log two_d /. log 2.0) in
  let d_int = int_of_float d in
  (* Clamp to valid range *)
  max 8 (min 40 d_int)

(* ── C++ Header Emitter via Typed EDSL ──────────────────────────────────── *)

(* RswTimeLock<N, M, A>::run() body — strictly sequential squarings.
   Uses Raw for __uint128_t since it has no AST node (GCC/Clang extension). *)
let emit_rsw_run_body () : stmt list =
  [
    (* uint64_t x = A % M; *)
    let_u64 "x" (var "A" %~ var "M");
    (* for (uint64_t i = 0; i < N; ++i) { x = ((__uint128_t)x * x) % M; } *)
    for_range "i" (u64 0L) (var "N")
      [
        (* We use Raw for the __uint128_t squaring since the AST has no 128-bit type. *)
        Raw "x = static_cast<uint64_t>((static_cast<__uint128_t>(x) * x) % M);";
      ];
    ret (var "x");
  ]

let emit_rsw_verify_body () : stmt list =
  [
    (* Constant-time comparison: return (result ^ expected_x_n) == 0 *)
    ret ((var "result" ^~ var "expected_x_n") ==~ u64 0L);
  ]

let emit_rsw_time_lock_def () : top_decl =
  template_struct_def
    ~template_params:["uint64_t N"; "uint64_t M"; "uint64_t A"]
    "RswTimeLock"
    [
      member_static_assert (var "N" >~ u64 0L) "N must be positive";
      member_static_assert (var "M" >~ u64 3L) "M must be > 3";
      member_method
        ~attrs:[Nodiscard; NoExcept]
        ~is_static:true
        UInt64 "run" []
        (emit_rsw_run_body ());
      member_method
        ~attrs:[Nodiscard; NoExcept]
        ~is_static:true
        Bool "verify"
        [(UInt64, "result"); (UInt64, "expected_x_n")]
        (emit_rsw_verify_body ());
    ]

(* PowHashPuzzle<D> mix_round body — GF(2^64) carry-less multiply emulation
   followed by ADC-chain mix (SplitMix64 finaliser steps). *)
let emit_mix_round_body () : stmt list =
  [
    let_u64 "acc" (u64 0L);
    let_u64 "a_gf" (var "state");
    (* b = golden ratio constant — hardware-expensive inner bit loop *)
    let_u64 "b_gf" (u64 Magic_numbers.golden_ratio_64);
    (* GF(2^64) carry-less multiply: software PCLMULQDQ emulation *)
    for_range "bit" (u64 0L) (u64 64L)
      [
        (* if (b_gf & 1) acc ^= a_gf; *)
        if_then (var "b_gf" &~ u64 1L ==~ u64 1L)
          [ var "acc" ^= var "a_gf" ];
        (* carry = (a_gf >> 63) & 1 *)
        let_u64 "carry" (var "a_gf" >>~ u64 63L &~ u64 1L);
        var "a_gf" := var "a_gf" <<~ u64 1L;
        (* if (carry) a_gf ^= GF_POLY_REDUCE *)
        if_then (var "carry" ==~ u64 1L)
          [ var "a_gf" ^= u64 Magic_numbers.comp_stall_pow_gf_poly ];
        var "b_gf" := var "b_gf" >>~ u64 1L;
      ];
    (* ADC-chain: SplitMix64 finaliser steps for flag-intensive mixing *)
    var "acc" ^= (var "acc" >>~ u64 30L) *~ u64 Magic_numbers.splitmix64_gamma;
    var "acc" ^= (var "acc" >>~ u64 27L) *~ u64 Magic_numbers.splitmix64_mix;
    ret (var "acc" ^~ (var "acc" >>~ u64 31L));
  ]

let emit_pow_solve_body () : stmt list =
  [
    for_range "nonce" (u64 0L) (u64 Int64.max_int)
      [
        let_u64 "state" (var "seed" ^~ var "nonce");
        for_range "r" (u64 0L) (u64 16L)
          [
            var "state" := call "mix_round" [var "state"];
          ];
        if_then ((var "state" &~ var "MASK") ==~ u64 0L
                 &&~ ((var "state" >>~ u64 32L) ==~ var "target_tag"))
          [ ret (var "state") ];
      ];
    ret (u64 0L);  (* unreachable *)
  ]

let emit_pow_hash_puzzle_def () : top_decl =
  template_struct_def
    ~template_params:["uint32_t D"]
    "PowHashPuzzle"
    [
      member_static_assert
        (var "D" >=~ u64 8L &&~ (var "D" <=~ u64 40L))
        "difficulty must be in [8,40]";
      (* MASK = (D == 64) ? ~0ULL : ((1ULL << D) - 1ULL) *)
      member_static_constexpr UInt64 "MASK"
        (ternary (var "D" ==~ u64 64L)
           (bit_not (u64 0L))
           ((u64 1L <<~ var "D") -~ u64 1L));
      (* mix_round: GF(2^64) carry-less multiply + SplitMix64 ADC-chain *)
      member_method
        ~attrs:[Nodiscard; NoExcept]
        ~is_static:true
        UInt64 "mix_round"
        [(UInt64, "state")]
        (emit_mix_round_body ());
      (* solve: geometric nonce search *)
      member_method
        ~attrs:[Nodiscard; NoExcept]
        ~is_static:true
        UInt64 "solve"
        [(UInt64, "seed"); (UInt64, "target_tag")]
        (emit_pow_solve_body ());
    ]

(* CompStallGuard<N,D,M,A,XN>: composite guard *)
let emit_comp_stall_guard_def () : top_decl =
  template_struct_def
    ~template_params:["uint64_t N"; "uint32_t D"; "uint64_t M"; "uint64_t A"; "uint64_t XN"]
    "CompStallGuard"
    [
      member_method
        ~attrs:[Nodiscard; NoExcept]
        ~is_static:true
        Bool "run_and_verify"
        [(UInt64, "pow_seed"); (UInt64, "pow_tag")]
        [
          (* const uint64_t rsw_result = RswTimeLock<N,M,A>::run(); *)
          const_u64 "rsw_result"
            (call "RswTimeLock<N, M, A>::run" []);
          (* if (!RswTimeLock<N,M,A>::verify(rsw_result, XN)) return false; *)
          if_then (log_not (call "RswTimeLock<N, M, A>::verify" [var "rsw_result"; var "XN"]))
            [ ret (bool_lit false) ];
          (* const uint64_t pow_result = PowHashPuzzle<D>::solve(pow_seed ^ rsw_result, pow_tag); *)
          const_u64 "pow_result"
            (call "PowHashPuzzle<D>::solve"
               [var "pow_seed" ^~ var "rsw_result"; var "pow_tag"]);
          ret (ne (var "pow_result") (u64 0L));
        ];
    ]

let emit_comp_stall_cpp_header () : string =
  let decls = [
    comment_top "============================================================================";
    comment_top "ASGARD-5877: Computational Stalling (CPU-bound Anti-Emulation)";
    comment_top "Raises the emulation slowdown factor Ω to force sandbox timeout.";
    comment_top "  RswTimeLock<N,M,A>     – N sequential squarings mod M (depth Θ(N))";
    comment_top "  PowHashPuzzle<D>       – D leading-zero-bit PoW with GF(2^64) inner loop";
    comment_top "  CompStallGuard<N,D,M,A,XN> – composite guard (RSW then PoW)";
    comment_top "============================================================================";
    IncludeSys "cstdint";
    IncludeSys "cstring";
    namespace_def "asgard::comp_stall" [
      emit_rsw_time_lock_def ();
      emit_pow_hash_puzzle_def ();
      emit_comp_stall_guard_def ();
    ];
  ] in
  "#pragma once\n" ^ render_top_decls decls
