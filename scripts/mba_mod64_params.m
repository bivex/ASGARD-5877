function mba_mod64_params()
%MBA_MOD64_PARAMS  Exact Z_{2^64} parameter generator for the ASGARD-5877
%   bytecode amplifier (lib/stack_vm/bytecode_amplifier.ml,
%   lib/mba_engine/metamorphic_ring.ml).
%
%   WHY THIS FILE EXISTS
%   --------------------
%   The runtime performs ALL of its MBA arithmetic in native OCaml int64,
%   i.e. with two's-complement WRAPAROUND over Z_{2^64}.  Both MATLAB and
%   GNU Octave SATURATE integer arithmetic instead of wrapping:
%
%       a = uint64(2^64 - 1); b = uint64(5);
%       a + b   % MATLAB  : 18446744073709551615  (intmax('uint64'))
%               % Octave  : 0xFFFFFFFFFFFFFFFF     (clamped, measured here)
%               % OCaml  : 0x0000000000000004     (wraparound, correct)
%
%   A naive "uint64(a) + uint64(b)" therefore SILENTLY breaks the
%   Z_{2^64} semantics the whole obfuscation layer relies on.  Symbolic
%   Math Toolbox / Fixed-Point Designer are not available under Octave
%   (this repo's reference engine), so the only portable and exact route
%   is an explicit carry-chain built from pure bit operations
%   (bitand/bitor/bitxor/bitshift never saturate).
%
%   WHAT IT GENERATES
%   -----------------
%   1. Randomised amplification profiles (obfuscation limits) constrained
%      to the bounds the OCaml runtime actually honours.
%   2. Horner polynomial vectors (t_0, [a_d..a_0]) that reproduce a given
%      target constant C under Z_{2^64} evaluation - byte-for-byte
%      equivalent to Bytecode_amplifier.synth_horner_polynomial.
%   3. Ring keys (k_odd, k_inv) with k_odd * k_inv == 1 (mod 2^64),
%      computed with the same Newton iteration as
%      Metamorphic_ring.inv_mod_2_64.
%   4. A mask pool for the t_0 masking identity
%      (t_0 ^ m) + 2*(t_0 & m) - m == t_0.
%
%   The generator is DETERMINISTIC: a counter-based SplitMix64 stream is
%   used instead of the host RNG, so the same seed reproduces the same
%   parameters on every engine (MATLAB, Octave, CI).
%
%   OUTPUTS
%   -------
%     scripts/bench_data/mba_mod64_params.json   full parameter set
%     scripts/bench_data/mba_mod64_params.csv    flat summary
%     test/data/mba_mod64_golden.json             golden fixture consumed
%                                                 by test/test_mba_mod64_crosscheck.ml
%
%   USAGE
%   -----
%     octave --eval "addpath('scripts'); mba_mod64_params()"
%     octave scripts/run_mba_mod64_params.m
%     matlab -batch "addpath('scripts'); mba_mod64_params()"
%
%   All int64 values are exported as SIGNED decimal strings (the format
%   accepted by OCaml's Int64.of_string, and the convention already used
%   by lib/native_vm/protection_types.ml) plus an unsigned hex mirror.

  % the shared Z_{2^64} primitives live next to this file
  addpath(fileparts(mfilename('fullpath')));
  root = fileparts(fileparts(mfilename('fullpath')));
  bench_dir = fullfile(root, "scripts", "bench_data");
  test_data_dir = fullfile(root, "test", "data");
  if exist(bench_dir, "dir") ~= 7, mkdir(bench_dir); end
  if exist(test_data_dir, "dir") ~= 7, mkdir(test_data_dir); end

  disp("=========================================================================");
  disp("   ASGARD-5877: Z_{2^64} MODULAR PARAMETER GENERATOR (MBA AMPLIFIER)   ");
  disp("=========================================================================");
  fprintf("Engine: %s\n", version);
  fprintf("Host Platform: %s\n", computer);
  fprintf("Timestamp: %s\n", datestr(now, "yyyy-mm-dd HH:MM:SS"));
  disp("Modulus: 2^64 = 18446744073709551616");
  disp("-------------------------------------------------------------------------");

  % ---------------------------------------------------------------------
  % [0] SATURATION TRAP DEMONSTRATION (measured on THIS engine)
  % ---------------------------------------------------------------------
  disp("\n[0] INTEGER-OVERFLOW SEMANTICS OF THE HOST ENGINE (MEASURED)");
  disp("-------------------------------------------------------------------------");
  a_max = asgard_mod64('from_hex', "FFFFFFFFFFFFFFFF");
  five = uint64(5);
  naive_sum = a_max + five;
  exact_sum = asgard_mod64('add', a_max, five);
  fprintf("  uint64(2^64-1) + uint64(5)  naive : %s\n", asgard_mod64('to_hex', naive_sum));
  fprintf("  uint64(2^64-1) + uint64(5)  exact : %s   (expected 0000000000000004)\n", ...
          asgard_mod64('to_hex', exact_sum));
  if naive_sum == exact_sum
    disp("  [!] Host integer arithmetic WRAPS: naive uint64 + is already exact.");
  else
    disp("  [+] Host integer arithmetic SATURATES: naive uint64 + is WRONG.");
    disp("      => every ring operation below goes through the carry chain.");
  end

  % ---------------------------------------------------------------------
  % [1] SELF-VERIFICATION BATTERY
  % ---------------------------------------------------------------------
  disp("\n[1] Z_{2^64} RING ARITHMETIC SELF-VERIFICATION");
  disp("-------------------------------------------------------------------------");

  n_checks = 0;
  n_failed = 0;

  % 1.1 carry chain vs. independent 16-bit limb reference
  seed_v = asgard_mod64('from_hex', "9E3779B97F4A7C15");
  for i = 0:299
    x = rand_u64_at(seed_v, i);
    y = rand_u64_at(seed_v, i + 1000);
    n_checks += 1;
    if asgard_mod64('add', x, y) ~= asgard_mod64('ref_add', x, y), n_failed += 1; end
    n_checks += 1;
    if asgard_mod64('mul', x, y) ~= asgard_mod64('ref_mul', x, y), n_failed += 1; end
    n_checks += 1;
    if asgard_mod64('sub', x, y) ~= asgard_mod64('ref_sub', x, y), n_failed += 1; end
  end

  % 1.2 boundary cases of the carry chain
  boundary = {uint64(0), uint64(1), uint64(4294967295), uint64(4294967296), ...
              asgard_mod64('from_hex', "7FFFFFFFFFFFFFFF"), asgard_mod64('from_hex', "8000000000000000"), ...
              asgard_mod64('from_hex', "FFFFFFFFFFFFFFFF")};
  for i = 1:numel(boundary)
    for j = 1:numel(boundary)
      x = boundary{i};
      y = boundary{j};
      n_checks += 1;
      if asgard_mod64('add', x, y) ~= asgard_mod64('ref_add', x, y), n_failed += 1; end
      n_checks += 1;
      if asgard_mod64('mul', x, y) ~= asgard_mod64('ref_mul', x, y), n_failed += 1; end
    end
  end

  % 1.3 Horner round trip: eval(synth(C)) == C over Z_{2^64}
  for i = 0:399
    target = rand_u64_at(seed_v, 5000 + i);
    degree = 1 + mod(i, 8);
    [t0, coeffs] = synth_horner(target, degree, seed_v, 9000 + i);
    n_checks += 1;
    if eval_horner(t0, coeffs) ~= target, n_failed += 1; end
    % a_0 must equal C - P_high(t_0), the very scheme of the OCaml side
    n_checks += 1;
    if coeffs(end) ~= asgard_mod64('sub', target, horner_high_partial(t0, coeffs)), n_failed += 1; end
  end

  % 1.4 modular inverse and ring twist identity
  for i = 0:399
    k = asgard_mod64('or', rand_u64_at(seed_v, 20000 + i), uint64(1));
    kinv = inv_mod_2_64(k);
    n_checks += 1;
    if asgard_mod64('mul', k, kinv) ~= uint64(1), n_failed += 1; end
    n_checks += 1;
    if bitand(kinv, uint64(1)) ~= uint64(1), n_failed += 1; end
    x = rand_u64_at(seed_v, 21000 + i);
    n_checks += 1;
    if asgard_mod64('mul', asgard_mod64('mul', x, k), kinv) ~= x, n_failed += 1; end
  end

  % 1.5 t_0 masking identity: (t_0 ^ m) + 2*(t_0 & m) - m == t_0
  for i = 0:199
    t0 = asgard_mod64('or', rand_u64_at(seed_v, 30000 + i), uint64(1));
    m = rand_u64_at(seed_v, 31000 + i);
    lhs = asgard_mod64('sub', asgard_mod64('add', bitxor(t0, m), asgard_mod64('add', asgard_mod64('and', t0, m), asgard_mod64('and', t0, m))), m);
    n_checks += 1;
    if lhs ~= t0, n_failed += 1; end
  end

  fprintf("  Ring self-checks: %d executed, %d failed\n", n_checks, n_failed);
  if n_failed > 0
    error("mba_mod64_params: %d ring self-checks FAILED - aborting", n_failed);
  end
  disp("  [+] All ring invariants hold (add/mul/sub vs 16-bit limb reference,");
  disp("      Horner round trip, modular inverse, ring twist, mask identity).");

  % ---------------------------------------------------------------------
  % [2] RANDOMISED AMPLIFICATION PROFILES (OBFUSCATION LIMITS)
  % ---------------------------------------------------------------------
  disp("\n[2] RANDOMISED AMPLIFICATION PROFILES (RUNTIME-BOUNDED)");
  disp("-------------------------------------------------------------------------");
  % Bounds are the ones the OCaml runtime actually honours:
  %   horner_degree       : synth_horner_polynomial uses max 1 d
  %   bit_slice_lanes     : 0 disables the carry chain, > 0 enables it
  %   expander_chord_len  : step of the knots; anchor ring K = clamp 1..6
  %   expander_chord_rate : percentage 0..100
  bounds.horner_degree = [1, 8];
  bounds.bit_slice_lanes = [0, 2];
  bounds.expander_chord_len = [1, 16];
  bounds.expander_chord_rate = [0, 100];
  disp("  Limits: horner_degree [1..8], bit_slice_lanes [0..2],");
  disp("          expander_chord_len [1..16] (anchor ring K = clamp 1..6),");
  disp("          expander_chord_rate [0..100]");

  n_profiles = 24;
  profiles = struct("horner_degree", {}, "bit_slice_lanes", {}, ...
                     "expander_chord_len", {}, "expander_chord_rate", {});
  for i = 1:n_profiles
    profiles(i).horner_degree = bounds.horner_degree(1) + ...
        u64_rand_below(rand_u64_at(seed_v, 40000 + i), bounds.horner_degree(2) - bounds.horner_degree(1) + 1);
    profiles(i).bit_slice_lanes = bounds.bit_slice_lanes(1) + ...
        u64_rand_below(rand_u64_at(seed_v, 41000 + i), bounds.bit_slice_lanes(2) - bounds.bit_slice_lanes(1) + 1);
    profiles(i).expander_chord_len = bounds.expander_chord_len(1) + ...
        u64_rand_below(rand_u64_at(seed_v, 42000 + i), bounds.expander_chord_len(2) - bounds.expander_chord_len(1) + 1);
    profiles(i).expander_chord_rate = bounds.expander_chord_rate(1) + ...
        u64_rand_below(rand_u64_at(seed_v, 43000 + i), bounds.expander_chord_rate(2) - bounds.expander_chord_rate(1) + 1);
  end

  % Reference profiles must mirror lib/stack_vm/bytecode_amplifier.ml exactly.
  ref_profiles.heavy.horner_degree = 6;
  ref_profiles.heavy.bit_slice_lanes = 2;
  ref_profiles.heavy.expander_chord_len = 8;
  ref_profiles.heavy.expander_chord_rate = 75;
  ref_profiles.balanced.horner_degree = 3;
  ref_profiles.balanced.bit_slice_lanes = 2;
  ref_profiles.balanced.expander_chord_len = 8;
  ref_profiles.balanced.expander_chord_rate = 50;
  ref_profiles.light.horner_degree = 2;
  ref_profiles.light.bit_slice_lanes = 1;
  ref_profiles.light.expander_chord_len = 10;
  ref_profiles.light.expander_chord_rate = 25;

  fprintf("  Generated %d randomised profiles, %d reference profiles mirrored\n", ...
          n_profiles, numel(fieldnames(ref_profiles)));
  fprintf("    heavy    : degree=%d lanes=%d chord_len=%d rate=%d%%\n", ...
          ref_profiles.heavy.horner_degree, ref_profiles.heavy.bit_slice_lanes, ...
          ref_profiles.heavy.expander_chord_len, ref_profiles.heavy.expander_chord_rate);
  fprintf("    balanced : degree=%d lanes=%d chord_len=%d rate=%d%%\n", ...
          ref_profiles.balanced.horner_degree, ref_profiles.balanced.bit_slice_lanes, ...
          ref_profiles.balanced.expander_chord_len, ref_profiles.balanced.expander_chord_rate);
  fprintf("    light    : degree=%d lanes=%d chord_len=%d rate=%d%%\n", ...
          ref_profiles.light.horner_degree, ref_profiles.light.bit_slice_lanes, ...
          ref_profiles.light.expander_chord_len, ref_profiles.light.expander_chord_rate);

  % ---------------------------------------------------------------------
  % [3] HORNER POLYNOMIAL VECTORS + RING KEYS + MASK POOL
  % ---------------------------------------------------------------------
  disp("\n[3] HORNER VECTORS, RING KEYS AND MASK POOL");
  disp("-------------------------------------------------------------------------");
  n_vectors = 64;
  horner = struct("target", {}, "t0", {}, "coeffs", {});
  for i = 1:n_vectors
    target = rand_u64_at(seed_v, 50000 + i);
    degree = profiles(1 + mod(i - 1, n_profiles)).horner_degree;
    [t0, coeffs] = synth_horner(target, degree, seed_v, 60000 + i);
    horner(i).target = target;
    horner(i).t0 = t0;
    horner(i).coeffs = coeffs;
  end

  n_keys = 64;
  keys = struct("k_odd", {}, "k_inv", {});
  for i = 1:n_keys
    k = asgard_mod64('or', rand_u64_at(seed_v, 70000 + i), uint64(1));
    keys(i).k_odd = k;
    keys(i).k_inv = inv_mod_2_64(k);
  end

  n_masks = 256;
  masks = zeros(1, n_masks, "uint64");
  for i = 1:n_masks
    masks(i) = rand_u64_at(seed_v, 80000 + i);
  end

  fprintf("  Horner vectors : %d (t_0 odd, a_0 = C - P_high(t_0) mod 2^64)\n", n_vectors);
  fprintf("  Ring keys      : %d (k_odd odd, k_odd * k_inv == 1 mod 2^64)\n", n_keys);
  fprintf("  Mask pool      : %d masks for the (t_0^m) + 2*(t_0&m) - m identity\n", n_masks);

  % ---------------------------------------------------------------------
  % [4] STATISTICAL VALIDATION OF THE RANDOMISER
  % ---------------------------------------------------------------------
  disp("\n[4] RANDOMISER UNIFORMITY OVER Z_{2^64}");
  disp("-------------------------------------------------------------------------");
  n_samples = 20000;
  samples = zeros(1, n_samples, "uint64");
  for i = 1:n_samples
    samples(i) = rand_u64_at(seed_v, 100000 + i);
  end

  % 4.1 byte-level chi-square over the 8 bytes of every sample
  byte_counts = zeros(256, 1);
  for b = 0:7
    bytes = bitand(bitshift(samples, -8 * b), uint64(255));
    byte_counts += accumarray(double(bytes(:)) + 1, 1, [256, 1]);
  end
  n_bytes = n_samples * 8;
  expected = n_bytes / 256;
  chi2 = sum((byte_counts - expected) .^ 2 ./ expected);
  df = 255;
  p_chi2 = chi2_sf_wilson_hilferty(chi2, df);
  fprintf("  Byte marginal distribution: chi2 = %8.2f (df=%d), p = %.4f\n", chi2, df, p_chi2);
  fprintf("    min/max bin count: %d / %d (expected %d)\n", ...
          min(byte_counts), max(byte_counts), round(expected));

  % 4.2 per-bit balance (binomial z-scores)
  bit_z = zeros(1, 64);
  for p = 0:63
    ones_count = double(sum(bitand(bitshift(samples, -p), uint64(1))));
    bit_z(p + 1) = (ones_count - n_samples / 2) / sqrt(n_samples / 4);
  end
  n_outliers = sum(abs(bit_z) > 3);
  fprintf("  Per-bit balance: max |z| = %.2f, positions with |z| > 3: %d / 64 (expected ~0.2)\n", ...
          max(abs(bit_z)), n_outliers);

  % 4.3 top-bit bias check: the OCaml layout puts 30 random bits in [63..34]
  top_bits = double(bitshift(samples, -34));
  fprintf("  Top-30-bit mean: %0.2f (ideal %0.2f)\n", ...
          mean(top_bits), (2^30 - 1) / 2);

  % ---------------------------------------------------------------------
  % [5] EXPORT
  % ---------------------------------------------------------------------
  disp("\n[5] EXPORT");
  disp("-------------------------------------------------------------------------");
  params_path = fullfile(bench_dir, "mba_mod64_params.json");
  write_params_json(params_path, "asgard.mba.mod64.v1", seed_v, profiles, ref_profiles, ...
                    horner, keys, masks, bounds);
  fprintf("  Parameters   : %s\n", params_path);

  csv_path = fullfile(bench_dir, "mba_mod64_params.csv");
  write_params_csv(csv_path, horner, keys);
  fprintf("  CSV summary  : %s\n", csv_path);

  golden_path = fullfile(test_data_dir, "mba_mod64_golden.json");
  write_params_json(golden_path, "asgard.mba.mod64.golden.v1", seed_v, ...
                    profiles(1:3), ref_profiles, horner(1:8), keys(1:8), ...
                    masks(1:16), bounds);
  fprintf("  Golden fixture: %s\n", golden_path);
  fprintf("    (consumed by test/test_mba_mod64_crosscheck.ml)\n");

  disp("=========================================================================");
  disp("   Z_{2^64} PARAMETER GENERATION COMPLETE - ALL INVARIANTS VERIFIED      ");
  disp("=========================================================================");
end

% =========================================================================
%  Z_{2^64} RING PRIMITIVES  (pure bit operations, no saturation)
% =========================================================================

% =========================================================================
%  MIRRORS OF THE OCAML PRIMITIVES
% =========================================================================

function v = sm64_at(seed, idx)
  % SplitMix64: the idx-th output of the stream identified by seed.
  golden = asgard_mod64('from_hex', "9E3779B97F4A7C15");
  mix1 = asgard_mod64('from_hex', "BF58476D1CE4E5B9");
  mix2 = asgard_mod64('from_hex', "94D049BB133111EB");
  st = asgard_mod64('add', seed, asgard_mod64('mul', uint64(idx), golden));
  z = st;
  z = asgard_mod64('mul', bitxor(z, bitshift(z, -30)), mix1);
  z = asgard_mod64('mul', bitxor(z, bitshift(z, -27)), mix2);
  v = bitxor(z, bitshift(z, -31));
end

function v = rand_u64_at(seed, idx)
  % Same bit layout as Bytecode_amplifier.rand_u64:
  %   (hi << 34) | (mid << 4) | (lo & 0xF) with three 30-bit chunks.
  mask30 = uint64(1073741823);
  v1 = sm64_at(seed, 2 * idx);
  v2 = sm64_at(seed, 2 * idx + 1);
  c_hi = bitshift(v1, -34);
  c_mid = bitand(bitshift(v1, -4), mask30);
  c_lo = bitand(v2, mask30);
  v = bitor(bitor(bitshift(c_hi, 34), bitshift(c_mid, 4)), bitand(c_lo, uint64(15)));
end

function k = u64_rand_below(v, n)
  % Index in [0, n-1] taken from the exact high bits of v (n <= 256).
  k = mod(double(bitshift(v, -56)), n);
end

function [t0, coeffs] = synth_horner(target, degree, seed, idx)
  % Mirror of Bytecode_amplifier.synth_horner_polynomial:
  %   t_0 odd, a_d..a_1 random, a_0 = C - P_high(t_0) (mod 2^64),
  %   P_high built by the fold  acc <- (acc + a_k) * t_0.
  d = max(1, degree);
  t0 = asgard_mod64('or', rand_u64_at(seed, idx), uint64(1));
  coeffs = zeros(1, d + 1, "uint64");
  for k = 1:d
    coeffs(k) = rand_u64_at(seed, idx + 100 * k);
  end
  coeffs(d + 1) = asgard_mod64('sub', target, horner_high_partial(t0, coeffs));
end

function p = horner_high_partial(t0, coeffs)
  % P_high(t_0) over the coefficients a_d..a_1 (the last entry is a_0).
  d = numel(coeffs) - 1;
  p = uint64(0);
  for k = 1:d
    p = asgard_mod64('mul', asgard_mod64('add', p, coeffs(k)), t0);
  end
end

function v = eval_horner(t0, coeffs)
  v = coeffs(1);
  for k = 2:numel(coeffs)
    v = asgard_mod64('add', asgard_mod64('mul', v, t0), coeffs(k));
  end
end

function inv = inv_mod_2_64(a)
  % Same Newton iteration as Metamorphic_ring.inv_mod_2_64:
  %   x <- x * (2 - a*x), applied 5 times starting from x = a.
  if bitand(a, uint64(1)) == uint64(0)
    error("inv_mod_2_64: even operand has no inverse in Z_{2^64}");
  end
  x = a;
  for _ = 1:5
    x = asgard_mod64('mul', x, asgard_mod64('sub', uint64(2), asgard_mod64('mul', a, x)));
  end
  inv = x;
end

function p = chi2_sf_wilson_hilferty(x, df)
  % Toolbox-free survival function of the chi-square distribution.
  if x <= 0
    p = 1;
    return;
  end
  z = ((x / df) ^ (1 / 3) - (1 - 2 / (9 * df))) / sqrt(2 / (9 * df));
  p = 0.5 * erfc(z / sqrt(2));
end

% =========================================================================
%  SERIALISATION
% =========================================================================

function write_params_json(path, schema, seed, profiles, ref_profiles, horner, keys, masks, bounds)
  fid = fopen(path, "w");
  if fid < 0
    error("cannot open %s for writing", path);
  end
  fprintf(fid, "{\n");
  fprintf(fid, "  \"schema\": \"%s\",\n", schema);
  fprintf(fid, "  \"generator\": \"scripts/mba_mod64_params.m\",\n");
  fprintf(fid, "  \"seed_hex\": \"%s\",\n", asgard_mod64('to_hex', seed));
  fprintf(fid, "  \"seed_dec\": \"%s\",\n", asgard_mod64('to_dec', seed));
  fprintf(fid, "  \"modulus\": \"2^64\",\n");
  fprintf(fid, "  \"modulus_decimal\": \"18446744073709551616\",\n");
  fprintf(fid, "  \"int64_encoding\": \"signed-decimal-string\",\n");

  fprintf(fid, "  \"bounds\": {\n");
  fprintf(fid, "    \"horner_degree\": [%d, %d],\n", bounds.horner_degree(1), bounds.horner_degree(2));
  fprintf(fid, "    \"bit_slice_lanes\": [%d, %d],\n", bounds.bit_slice_lanes(1), bounds.bit_slice_lanes(2));
  fprintf(fid, "    \"expander_chord_len\": [%d, %d],\n", bounds.expander_chord_len(1), bounds.expander_chord_len(2));
  fprintf(fid, "    \"expander_chord_rate\": [%d, %d]\n", bounds.expander_chord_rate(1), bounds.expander_chord_rate(2));
  fprintf(fid, "  },\n");

  fprintf(fid, "  \"reference_profiles\": {\n");
  names = fieldnames(ref_profiles);
  for i = 1:numel(names)
    p = ref_profiles.(names{i});
    fprintf(fid, "    \"%s\": {\"horner_degree\": %d, \"bit_slice_lanes\": %d, ", ...
            names{i}, p.horner_degree, p.bit_slice_lanes);
    fprintf(fid, "\"expander_chord_len\": %d, \"expander_chord_rate\": %d}%s\n", ...
            p.expander_chord_len, p.expander_chord_rate, ...
            ternary(i < numel(names), ",", ""));
  end
  fprintf(fid, "  },\n");

  fprintf(fid, "  \"profiles\": [\n");
  for i = 1:numel(profiles)
    p = profiles(i);
    fprintf(fid, "    {\"horner_degree\": %d, \"bit_slice_lanes\": %d, ", ...
            p.horner_degree, p.bit_slice_lanes);
    fprintf(fid, "\"expander_chord_len\": %d, \"expander_chord_rate\": %d}%s\n", ...
            p.expander_chord_len, p.expander_chord_rate, ...
            ternary(i < numel(profiles), ",", ""));
  end
  fprintf(fid, "  ],\n");

  fprintf(fid, "  \"horner_vectors\": [\n");
  for i = 1:numel(horner)
    v = horner(i);
    fprintf(fid, "    {\"target\": \"%s\", \"target_hex\": \"%s\", ", ...
            asgard_mod64('to_dec', v.target), asgard_mod64('to_hex', v.target));
    fprintf(fid, "\"t0\": \"%s\", \"t0_hex\": \"%s\", ", ...
            asgard_mod64('to_dec', v.t0), asgard_mod64('to_hex', v.t0));
    fprintf(fid, "\"coeffs\": [");
    for k = 1:numel(v.coeffs)
      fprintf(fid, "\"%s\"", asgard_mod64('to_dec', v.coeffs(k)));
      if k < numel(v.coeffs)
        fprintf(fid, ", ");
      end
    end
    fprintf(fid, "], \"coeffs_hex\": [");
    for k = 1:numel(v.coeffs)
      fprintf(fid, "\"%s\"", asgard_mod64('to_hex', v.coeffs(k)));
      if k < numel(v.coeffs)
        fprintf(fid, ", ");
      end
    end
    fprintf(fid, "]}%s\n", ternary(i < numel(horner), ",", ""));
  end
  fprintf(fid, "  ],\n");

  fprintf(fid, "  \"ring_keys\": [\n");
  for i = 1:numel(keys)
    k = keys(i);
    fprintf(fid, "    {\"k_odd\": \"%s\", \"k_odd_hex\": \"%s\", ", ...
            asgard_mod64('to_dec', k.k_odd), asgard_mod64('to_hex', k.k_odd));
    fprintf(fid, "\"k_inv\": \"%s\", \"k_inv_hex\": \"%s\"}%s\n", ...
            asgard_mod64('to_dec', k.k_inv), asgard_mod64('to_hex', k.k_inv), ...
            ternary(i < numel(keys), ",", ""));
  end
  fprintf(fid, "  ],\n");

  fprintf(fid, "  \"mask_pool\": [");
  for i = 1:numel(masks)
    fprintf(fid, "\"%s\"", asgard_mod64('to_dec', masks(i)));
    if i < numel(masks)
      fprintf(fid, ", ");
    end
  end
  fprintf(fid, "]\n");
  fprintf(fid, "}\n");
  fclose(fid);
end

function write_params_csv(path, horner, keys)
  fid = fopen(path, "w");
  if fid < 0
    error("cannot open %s for writing", path);
  end
  fprintf(fid, "kind,index,field0,field1,field2,field3,field4\n");
  for i = 1:numel(horner)
    v = horner(i);
    fprintf(fid, "horner,%d,%s,%s,%s,%s,\n", i, ...
            asgard_mod64('to_dec', v.target), asgard_mod64('to_dec', v.t0), ...
            asgard_mod64('to_dec', v.coeffs(1)), asgard_mod64('to_dec', v.coeffs(end)));
  end
  for i = 1:numel(keys)
    k = keys(i);
    fprintf(fid, "ring_key,%d,%s,%s,,,\n", i, asgard_mod64('to_dec', k.k_odd), asgard_mod64('to_dec', k.k_inv));
  end
  fclose(fid);
end

function r = ternary(cond, a, b)
  if cond
    r = a;
  else
    r = b;
  end
end
