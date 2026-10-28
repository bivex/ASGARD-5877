(* lib/constants/magic_numbers.ml
   Central registry of the magic numbers of the engine.

   A magic number is a numeric literal whose value cannot be guessed from the
   code that uses it: a hash or PRNG constant, a key-derivation salt, a bit
   mask, a sentinel.  Such a literal must not be written inline at the call
   site.  It is declared here, once, under a name that states where the number
   comes from; every call site refers to the name.

   Why a registry instead of a local constant in each module: the same literal
   is used by the OCaml implementation and by the emitted C++ runtime, and the
   two sides must agree bit for bit.  A single declaration removes the chance
   that one side is edited and the other is not.

   How to add an entry:
     1. declare the constant below, with a comment naming its provenance;
     2. add it to [registry], naming the modules that use it;
     3. replace the literal at the call sites with the name. *)

(* --- Fractional-power mixing constants ------------------------------- *)

(* frac(phi^-1) * 2^64, phi = (1+sqrt(5))/2.  Knuth's multiplicative hashing
   constant, and xxHash's PRIME64_1.  The engine uses it as the odd multiplier
   of the key stream and of the position mixing in the MBA noise. *)
let golden_ratio_64 = 0x9E3779B97F4A7C15L

(* frac(phi^-1) * 2^32, the 32-bit counterpart of [golden_ratio_64].  The
   engine uses it as the 32-bit mixer of the key derivation and of the
   Vanguard-9292 scrambler. *)
let golden_ratio_32 = 0x9E3779B9L

(* frac(sqrt(2)) * 2^64.  Multiplier of the positional term of the rolling
   key; also the seed scrambler of the emitted VM context. *)
let sqrt2_fraction_64 = 0x517CC1B727220A95L

(* frac(cbrt(3)) * 2^64.  The first word of the SHA-256 initial hash, reused
   here as a well-distributed 64-bit mixer for the key slots. *)
let cbrt3_fraction_64 = 0x6A09E667F3BCC908L

(* --- SplitMix64 ----------------------------------------------------- *)

(* The two increments of the SplitMix64 finalizer (Steele, Lea and Flood,
   "Fast splittable pseudorandom number generators", OOPSLA 2014).  They turn a
   64-bit counter into a well-mixed key word. *)
let splitmix64_gamma = 0xBF58476D1CE4E5B9L
let splitmix64_mix = 0x94D049BB133111EBL

(* The modular inverse of [splitmix64_gamma] modulo 2^64: undoing the
   finalizer of the polynomial key update needs it.  The inverse relation is
   verified in fstar/Rolling_Key_Verified.fst. *)
let splitmix64_gamma_inverse = 0x96DE1B173F119089L

(* --- FNV-1a --------------------------------------------------------- *)

(* The 64-bit FNV-1a prime: 2^40 + 2^8 + 0xB3.  Multiplies the hashed word. *)
let fnv1a_64_prime = 0x100000001B3L

(* The 32-bit FNV-1a prime: 2^24 + 2^8 + 0x93 = 16777619. *)
let fnv1a_32_prime = 0x01000193L

(* The two FNV-1a offset bases: the initial value of the hash before the first
   word is mixed in.  The 32-bit one starts the symbol-name hash of the
   emitted runtime, the 64-bit one the polynomial key initialisation. *)
let fnv1a_32_offset_basis = 0x811C9DC5L
let fnv1a_64_offset_basis = 0x811C9DC5C9DC5119L

(* --- SHA-256 (FIPS 180-4) -------------------------------------------- *)

(* The initial hash and the round constants of SHA-256, as published in
   FIPS 180-4.  The engine keeps the two tables in one place, so that the
   OCaml core and the emitted C++ core read the same values. *)
let sha256_iv : int32 array = [|
  0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
  0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l;
|]

let sha256_k : int32 array = [|
  0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l;
  0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
  0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l;
  0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
  0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl;
  0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
  0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l;
  0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
  0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l;
  0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
  0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l;
  0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
  0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l;
  0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
  0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
  0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l;
|]

(* The first word of the initial hash and the first round constant.  The
   engine uses them as well-distributed 32-bit mixers. *)
let sha256_iv_h0 = Int64.of_int32 sha256_iv.(0)
let sha256_k0 = Int64.of_int32 sha256_k.(0)

(* --- MurmurHash3 ---------------------------------------------------- *)

(* MurmurHash3 for x86, 32-bit: the multiplier of the mixing step.  The
   engine uses it as the domain separator of the block-entry anchor key. *)
let murmur3_32_c1 = 0x5BD1E995l

(* MurmurHash3 for 64-bit: the two multipliers of the fmix finalizer.  The
   engine uses the same finalizer for the feedback hash of the register file
   (see [Stack_encoder.feedback_hash]). *)
let murmur3_64_fmix_c1 = 0xFF51AFD7ED558CCDL
let murmur3_64_fmix_c2 = 0xC4CEB9FE1A85EC53L

(* --- Semi-linear bit masks ------------------------------------------ *)

(* The disjoint 1-bit partition of the semi-linear (Zhou-Eyrolles) MBA
   encoding: 0x5555.. selects the even bits, 0xAAAA.. the odd bits.  The two
   masks are exact complements, so the odd one is derived from the even one. *)
let even_bit_mask = 0x5555555555555555L
let odd_bit_mask = Int64.lognot even_bit_mask

(* --- Engine salt palette --------------------------------------------- *)

(* The engine writes its salts in hex-speak, so that they read as words in a
   disassembly: "XWCAFE", "LEETBEEF", "CAFEBABE", "DEADBEEF".  They are salts,
   not derived values: their only requirement is to be unguessable and to
   differ from one another. *)

(* "XWCAFE": the magic of the encrypted bytecode payload and the 32-bit salt
   of the key derivation. *)
let salt_xwcafe = 0x5877CAFEL

(* "XWCAFE" + "LEETBEEF": the tail salt of the rolling key, the last XOR of
   the key chain. *)
let salt_xwcafe_leetbeef = 0x5877CAFE1337BEEFL

(* "XWCAFE" + "CAFEBABE1337": the salt of the integrity hash of the handler
   table. *)
let salt_xwcafe_cafebabe1337 = 0x5877CAFEBABE1337L

(* "XWCAFE" + "BEEF": the salt of the register-mask hash. *)
let salt_xwcafe_beef = 0x5877CAFEBEEFL

(* "LEETBEEF": the salt of the handler-domain scrambler. *)
let salt_leetbeef = 0x1337BEEFL

(* "CAFEBABE" + "13375877": the canary value of the VM context and the salt of
   the running key. *)
let salt_cafebabe_leet = 0xCAFEBABE13375877L

(* "13375877": the leet tag that separates the key-derivation domains. *)
let salt_leet_13375877 = 0x13375877L

(* "ZZZZ" + "13375877": the initial value of the register mask. *)
let salt_regmask = 0x5A5A5A5A13375877L

(* "AAAA" + "LEETBEEF": the salt of the mid-frame canaries. *)
let salt_canary_mid = 0xA5A5A5A51337BEEFL

(* "A5A5A5A5" + "5A5A5A5A": the mask that encrypts the shadow stack. *)
let salt_canary_stack = 0xA5A5A5A55A5A5A5AL

(* Per-block seed domain separation for the Stack-VM junk passes: the
   per-block RNG stream is seeded with `pass_seed xor (block_id * mul + add)`
   so one pass seed yields independent streams per basic block.  "LEET" and
   "XW" for avid (Phase 5b), pi digits for multiplicity (Phase 2a). *)
let salt_avid_block_mul = 0x1337L
let salt_avid_block_add = 0x5877L
let salt_multiplicity_block_mul = 0x3141L
let salt_multiplicity_block_add = 0x5926L

(* The salt of the poison penalty that is applied when a canary check fails. *)
let salt_poison_penalty = 0xCAA7E1D8718BF877L

(* "DEADBEEF": the scrub pattern that overwrites the bytecode when a memory
   sanitisation pass runs, and the marker of an invalid entry. *)
let salt_deadbeef = 0xDEADBEEFL

(* "DEADBEEF" + "5A5A5A5A": the scrub pattern of the domain handler table. *)
let salt_deadbeef_5a5a5a5a = 0xDEADBEEF5A5A5A5AL

(* "DEADBEEF" + "CAFEBABE": the scrub pattern of the constant pool. *)
let salt_deadbeef_cafebabe = 0xDEADBEEFCAFEBABEL

(* "DEADBEEF" + "5877CAFE": the scrub pattern of the bytecode heap. *)
let salt_deadbeef_5877cafe = 0xDEADBEEF5877CAFEL

(* "DEADBEEF" + "CAFE1337": the scrub pattern of the shadow stack. *)
let salt_deadbeef_cafe1337 = 0xDEADBEEFCAFE1337L

(* "XWCAFE" + "A56A" + "11223344": the dynamic chunk key seed in the C trampoline. *)
let salt_chunk_kdyn_seed = 0x5877A56A11223344L

(* "XWCAFE" + "A564D00F": the Stack-VM rolling state initialization salt. *)
let salt_stack_vm_state = 0x5877A564D00FL

(* "13375877" + "AABBCCDD": the Multi-VM bridge morphing test seed. *)
let salt_bridge_vector_seed = 0x13375877AABBCCDDL
(* "5877A564" + "CAFEBEEF": the Stack-VM dispatch table blinding salt. *)
let salt_stack_dispatch_blind = 0x5877A564CAFEBEEFL

(* "DEAD" + "C0DE": the mask that diversifies block IDs before token derivation. *)
let salt_deadcode = 0xDEADC0DEL

(* "C0FFEE" + 1: the sentinel token replacing zero so no block token is zero. *)
let sentinel_c0ffee_1 = 0xC0FFEE00000001L

(* Alternating-nibble scrambler seed for E-graph expansion in Stack-MBA. *)
let salt_egraph_scrambler = 0xECA8642013579BDFL

(* Multiplier for per-block PRNG diversification in Stack-MBA pass. *)
let block_id_multiplier = 0xB7E15163L

(* "CAFE" + "5877": salt for deterministic decoy edge generation in Stack-IR dumps. *)
let salt_dump_phase = 0x5CAFE5877L

(* --- Computational Stalling (comp_stall) --------------------------------- *)

(* LCG multiplier used to derive synthetic RSW prime candidates from a seed.
   Standard POSIX / java.util.Random LCG constant: a = 25214903917 = 0x5DEECE66D. *)
let comp_stall_lcg_mul = 0x5DEECE66DL

(* LCG addend used together with [comp_stall_lcg_mul]:
   c = 11 = 0xB.  Pair (a, c) satisfies the Hull-Dobell theorem for mod 2^k. *)
let comp_stall_lcg_add = 0xBL

(* GF(2^64) carry-less multiplication inner-loop constant for the PoW puzzle.
   MurmurHash3 64-bit finalizer mix1 constant; also functions as the GF(2^64)
   reduction polynomial mask in the software PCLMULQDQ emulation loop. *)
let comp_stall_pow_gf_poly = 0xC4CEB9FE1A85EC53L

(* Non-linear mathematical stalling constants *)
let comp_stall_chebyshev_salt = 0x5877C4E051C11337L
let comp_stall_ergodic_c = 0x58771337CAFEBEEFL
let comp_stall_two_adic_c3 = 0x13375877DEADBEEFL
let comp_stall_two_adic_c2 = 0xCAFEBABE01000002L

(* Memory-Address Entanglement constants: 8-byte aligned scratch offset window within 64B cache line *)
let mem_webbing_offset_mask = 0x38L
let mem_webbing_base_offset = 65L
let mem_webbing_base_align_mask = 0xFFFFFFFFFFFFFFC0L
let mem_webbing_alias_diff = 0x18L
let mem_webbing_decoy_salt = 0x58771337CAFEL
let mem_webbing_feistel_k_perm = 0x5053F3L
(* Stateful Transducer constants: LCG full-period generator over Z_{2^64} *)
let transducer_step_mul = 0x58771337CAFEBEEDL
let transducer_step_add = 0x9E3779B97F4A7C15L

(* Non-Linear PolyMBA constants: dynamic variable shift parameters *)
let polymba_dyn_shift_mul = 5L
let polymba_dyn_shift_add = 3L
let polymba_dyn_shift_mask = 15L

(* Chinese Remainder Theorem (CRT) constants *)
let crt_m1 = 0x20000L
let crt_m2 = 0x1FFFFL
let crt_m3 = 0x10001L
let crt_m4 = 0xFFFFL
let crt_inv_m1_mod_m2 = 0x1L
let crt_inv_m1_mod_m3 = 0x8000L
let crt_inv_m1_mod_m4 = 0x8000L
let crt_inv_m2_mod_m3 = 0xAAABL
let crt_inv_m2_mod_m4 = 0x1L
let crt_inv_m3_mod_m4 = 0x8000L

(* Mixed-Characteristic Finite Field Arithmetic (Phase 5h / Pass 17) constants *)
let finite_field_m31 = 0x7FFFFFFFL
let finite_field_m31_mask = 0x7FFFFFFEL
let finite_field_m31_mul = 0x58771337L
let finite_field_m31_inv = 0x1484AA6DL
let finite_field_gf64_poly = 0x1BL
let finite_field_gf64_const = 0x5877CAFE1337BEEFL

(* Cross-Block Execution Path Integrity & Anti-DBI Traps (Phase 6b / Pass 19) constants *)
let trap_step_mul = 0x5877A55ACA1337B9L
let trap_step_add = 0x1337CAFEBEEF5877L
let trap_token_mul = 0x9E3779B97F4A7C15L
let trap_salt_init = 0xCAFE58771337BABEL

(* Dual-Rail Complement Arithmetic (Phase 5j / Pass 21) constants *)
let dual_rail_salt = 0x5877DEADBEEFCAFEL

(* Homomorphic Ciphertext Operand Blinding (Phase 2d / Pass 20) constants *)
let homomorphic_salt = 0x5877CAFE58771337L

(* DRCC Top-Of-Stack Window & A003022 Golomb Spilling (Phase 5k / Pass 22) constants *)
let drcc_salt = 0x5877A0030221337BL
let golomb_ruler_g0 = 0L
let golomb_ruler_g1 = 1L
let golomb_ruler_g2 = 4L
let golomb_ruler_g3 = 6L

(* Galois LFSR Memory Whitening (Phase 5l / Pass 23) constants *)
let whitening_salt = 0x5877A0112601337AL
let whitening_init_key = 0x9E3779B97F4A7C15L
let whitening_lfsr_poly = 0x1BL

(* Costas Array Field Permutation (Phase 8b / Pass 26) constants — OEIS A008404 *)
let costas_field_layout_salt = 0xC057A51337B00F0L

(* Wolfram Rule 30 Non-Linear Keystream (Phase 6e / Pass 24) constants — OEIS A269160 *)
let rule30_salt = 0x5877A2691601337BL
let rule30_init_key = 0x1337C0DE5877A269L

(* Native Micro-Handler Interleaving (Phase 6f / Pass 27) constants *)
let native_interleave_salt = 0x5877A17A1E5C0DE7L
(* --- Registry -------------------------------------------------------- *)

type entry = {
  name : string;          (* the identifier used at the call sites *)
  value : int64;          (* the value, as a signed 64-bit integer *)
  source : string;        (* where the number comes from *)
  used_in : string list;  (* the modules that refer to it *)
}

let registry : entry list = [
  { name = "golden_ratio_64";
    value = golden_ratio_64;
    source = "frac(phi^-1) * 2^64 - Knuth multiplicative hashing, xxHash PRIME64_1";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml";
                "lib/stack_vm/stack_cff_pass.ml"; "lib/stack_vm/stack_mba_pass.ml";
                "lib/stack_vm/stack_avid_pass.ml"; "lib/stack_vm/stack_multiplicity_pass.ml";
                "lib/stack_vm/pipelined_dispatch_pass.ml" ] };
  { name = "sqrt2_fraction_64";
    value = sqrt2_fraction_64;
    source = "frac(sqrt(2)) * 2^64";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "cbrt3_fraction_64";
    value = cbrt3_fraction_64;
    source = "frac(cbrt(3)) * 2^64 - first word of the SHA-256 initial hash";
    used_in = [ "lib/native_vm/vm_context_emitter.ml"; "lib/stack_vm/stack_runtime.ml" ] };
  { name = "splitmix64_gamma";
    value = splitmix64_gamma;
    source = "SplitMix64 finalizer increment 1 (Steele, Lea and Flood, OOPSLA 2014)";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/stack_vm/stack_cff_pass.ml"; "lib/stack_vm/stack_mba_pass.ml";
                "lib/stack_vm/stack_avid_pass.ml"; "lib/stack_vm/stack_multiplicity_pass.ml" ] };
  { name = "splitmix64_mix";
    value = splitmix64_mix;
    source = "SplitMix64 finalizer increment 2 (Steele, Lea and Flood, OOPSLA 2014)";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/stack_vm/stack_cff_pass.ml"; "lib/stack_vm/stack_mba_pass.ml";
                "lib/stack_vm/stack_avid_pass.ml"; "lib/stack_vm/stack_multiplicity_pass.ml" ] };
  { name = "fnv1a_64_prime";
    value = fnv1a_64_prime;
    source = "FNV-1a 64-bit prime, 2^40 + 2^8 + 0xB3";
    used_in = [ "lib/vm_ir/rolling_key.ml" ] };
  { name = "murmur3_32_c1";
    value = Int64.of_int32 murmur3_32_c1;
    source = "MurmurHash3 x86 32-bit mixing multiplier";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "murmur3_64_fmix_c1";
    value = murmur3_64_fmix_c1;
    source = "MurmurHash3 64-bit fmix multiplier 1";
    used_in = [ "lib/stack_vm/stack_encoder.ml" ] };
  { name = "murmur3_64_fmix_c2";
    value = murmur3_64_fmix_c2;
    source = "MurmurHash3 64-bit fmix multiplier 2";
    used_in = [ "lib/stack_vm/stack_encoder.ml" ] };
  { name = "even_bit_mask";
    value = even_bit_mask;
    source = "semi-linear MBA even-bit mask, 0x5555555555555555";
    used_in = [ "lib/mba_engine/mba.ml"; "lib/mba_engine/egraph_types.ml";
                "lib/vm_ir/opaque_predicates.ml"; "lib/vm_ir/equivalence.ml";
                "lib/domain/mutation_profile.ml" ] };
  { name = "golden_ratio_32";
    value = golden_ratio_32;
    source = "frac(phi^-1) * 2^32 - the 32-bit golden ratio";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml";
                "lib/stack_vm/context_allocator.ml"; "lib/vanguard_9292/vanguard_types.ml";
                "lib/vanguard_9292/vanguard_decoder.ml" ] };
  { name = "splitmix64_gamma_inverse";
    value = splitmix64_gamma_inverse;
    source = "modular inverse of splitmix64_gamma modulo 2^64 (fstar/Rolling_Key_Verified.fst)";
    used_in = [ "lib/vm_ir/rolling_key.ml" ] };
  { name = "fnv1a_32_offset_basis";
    value = fnv1a_32_offset_basis;
    source = "FNV-1a 32-bit offset basis";
    used_in = [ "lib/native_vm/vm_runtime_emitter.ml"; "lib/c_macro_obf/c_macro_templates.ml";
                "lib/native_vm/native_vm_templates.ml"; "lib/native_vm/runtime_dual_map.ml";
                "lib/native_vm/runtime_ephemeral_jit.ml"; "lib/stack_vm/stack_runtime.ml" ] };
  { name = "fnv1a_64_offset_basis";
    value = fnv1a_64_offset_basis;
    source = "FNV-1a 64-bit offset basis";
    used_in = [ "lib/vm_ir/rolling_key.ml" ] };
  { name = "sha256_iv_h0";
    value = sha256_iv_h0;
    source = "the initial hash of SHA-256 (FIPS 180-4); the value shown is its first word";
    used_in = [ "lib/bytecode_crypto/sha256.ml"; "lib/tech_2601/tech_2601_emitter.ml" ] };
  { name = "sha256_k0";
    value = sha256_k0;
    source = "the round constants of SHA-256 (FIPS 180-4); the value shown is the first one";
    used_in = [ "lib/bytecode_crypto/sha256.ml"; "lib/tech_2601/tech_2601_emitter.ml" ] };
  { name = "salt_xwcafe";
    value = salt_xwcafe;
    source = "hex-speak salt 'XWCAFE' - the bytecode payload magic";
    used_in = [ "lib/native_vm/vm_handlers_emitter.ml"; "lib/native_vm/vm_runtime_emitter.ml";
                "lib/native_vm/vm_context_emitter.ml"; "lib/bytecode_crypto/bytecode_payload.ml" ] };
  { name = "salt_xwcafe_leetbeef";
    value = salt_xwcafe_leetbeef;
    source = "hex-speak salt 'XWCAFE'+'LEETBEEF' - the tail salt of the rolling key";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml";
                "lib/native_vm/vm_runtime_emitter.ml"; "lib/native_vm/vm_mem_handlers.ml";
                "lib/native_vm/oblivious_mem.ml"; "lib/native_vm/decoy_synth.ml";
                "lib/cff/cff.ml"; "lib/adapters/protect_adapters/c_trampoline_adapter.ml";
                "lib/native_vm/native_vm_templates.ml"; "lib/native_vm/runtime_ephemeral_jit.ml" ] };
  { name = "salt_xwcafe_cafebabe1337";
    value = salt_xwcafe_cafebabe1337;
    source = "hex-speak salt 'XWCAFE'+'CAFEBABE1337' - the handler-table integrity hash";
    used_in = [ "lib/native_vm/vm_context_emitter.ml"; "lib/cff/pop_coupler.ml" ] };
  { name = "salt_xwcafe_beef";
    value = salt_xwcafe_beef;
    source = "hex-speak salt 'XWCAFE'+'BEEF' - the register-mask hash";
    used_in = [ "lib/native_vm/vm_mem_handlers.ml"; "lib/native_vm/vm_runtime_emitter.ml";
                "lib/cff/red_herring.ml" ] };
  { name = "salt_leetbeef";
    value = salt_leetbeef;
    source = "hex-speak salt 'LEETBEEF' - the handler-domain scrambler";
    used_in = [ "lib/native_vm/vm_alu_handlers.ml"; "lib/native_vm/vm_control_handlers.ml";
                "lib/native_vm/vm_emitter.ml"; "lib/vanguard_9292/vanguard_types.ml";
                "lib/vanguard_9292/vanguard_decoder.ml"; "lib/c_macro_obf/c_macro_config.ml" ] };
  { name = "salt_cafebabe_leet";
    value = salt_cafebabe_leet;
    source = "hex-speak salt 'CAFEBABE'+'13375877' - the VM context canary value";
    used_in = [ "lib/native_vm/vm_context_emitter.ml"; "lib/native_vm/vm_mem_handlers.ml";
                "lib/native_vm/vm_runtime_emitter.ml"; "lib/vm_ir/vm_eval.ml" ] };
  { name = "salt_leet_13375877";
    value = salt_leet_13375877;
    source = "hex-speak tag '13375877' - the key-derivation domain separator";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml";
                "lib/native_vm/vm_alu_handlers.ml" ] };
  { name = "salt_regmask";
    value = salt_regmask;
    source = "hex-speak salt 'ZZZZ'+'13375877' - the initial register mask";
    used_in = [ "lib/native_vm/vm_context_emitter.ml"; "lib/native_vm/vm_runtime_emitter.ml" ] };
  { name = "salt_canary_mid";
    value = salt_canary_mid;
    source = "hex-speak salt 'AAAA'+'LEETBEEF' - the mid-frame canaries";
    used_in = [ "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "salt_canary_stack";
    value = salt_canary_stack;
    source = "hex-speak salt 'A5A5A5A5'+'5A5A5A5A' - the shadow-stack encryption mask";
    used_in = [ "lib/native_vm/vm_context_emitter.ml"; "lib/native_vm/vm_mem_handlers.ml" ] };
  { name = "salt_poison_penalty";
    value = salt_poison_penalty;
    source = "the salt of the poison penalty applied when a canary check fails";
    used_in = [ "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "salt_deadbeef";
    value = salt_deadbeef;
    source = "hex-speak scrub pattern 'DEADBEEF'";
    used_in = [ "lib/native_vm/vm_mem_handlers.ml"; "lib/native_vm/vm_alu_handlers.ml";
                "lib/stack_vm/bytecode_amplifier.ml"; "lib/native_vm/vm_runtime_emitter.ml" ] };
  { name = "salt_deadbeef_5a5a5a5a";
    value = salt_deadbeef_5a5a5a5a;
    source = "hex-speak scrub pattern 'DEADBEEF'+'5A5A5A5A'";
    used_in = [ "lib/native_vm/vm_mem_handlers.ml"; "lib/native_vm/vm_runtime_emitter.ml";
                "lib/cff/red_herring.ml"; "lib/native_vm/decoy_synth.ml" ] };
  { name = "salt_deadbeef_cafebabe";
    value = salt_deadbeef_cafebabe;
    source = "hex-speak scrub pattern 'DEADBEEF'+'CAFEBABE'";
    used_in = [ "lib/native_vm/vm_mem_handlers.ml"; "lib/native_vm/vm_runtime_emitter.ml";
                "lib/adapters/protect_adapters/c_trampoline_adapter.ml" ] };
  { name = "salt_deadbeef_5877cafe";
    value = salt_deadbeef_5877cafe;
    source = "hex-speak scrub pattern 'DEADBEEF'+'5877CAFE'";
    used_in = [ "lib/native_vm/vm_runtime_emitter.ml" ] };
  { name = "salt_deadbeef_cafe1337";
    value = salt_deadbeef_cafe1337;
    source = "hex-speak scrub pattern 'DEADBEEF'+'CAFE1337'";
    used_in = [ "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "fnv1a_32_prime";
    value = fnv1a_32_prime;
    source = "FNV-1a 32-bit prime, 2^24 + 2^8 + 0x93 = 16777619";
    used_in = [ "lib/c_macro_obf/c_macro_templates.ml"; "lib/native_vm/native_vm_templates.ml";
                "lib/stack_vm/stack_runtime.ml" ] };
  { name = "salt_chunk_kdyn_seed";
    value = salt_chunk_kdyn_seed;
    source = "hex-speak salt 'XWCAFE'+'A56A'+'11223344' - chunk table key derivation";
    used_in = [ "lib/adapters/protect_adapters/c_trampoline_adapter.ml" ] };
  { name = "salt_stack_vm_state";
    value = salt_stack_vm_state;
    source = "hex-speak salt 'XWCAFE'+'A564D00F' - Stack-VM state initialization";
    used_in = [ "lib/cff/cff.ml"; "lib/stack_vm/stack_encoder.ml"; "lib/stack_vm/stack_runtime.ml" ] };
  { name = "salt_bridge_vector_seed";
    value = salt_bridge_vector_seed;
    source = "hex-speak salt '13375877'+'AABBCCDD' - Multi-VM bridge morphing seed";
    used_in = [ "bin/profile_bottlenecks.ml"; "test/test_multi_vm.ml" ] };
  { name = "salt_avid_block_mul";
    value = salt_avid_block_mul;
    source = "hex-speak 'LEET' - avid pass per-block seed multiplier";
    used_in = [ "lib/stack_vm/stack_avid_pass.ml" ] };
  { name = "salt_avid_block_add";
    value = salt_avid_block_add;
    source = "hex-speak 'XW' - avid pass per-block seed additive salt";
    used_in = [ "lib/stack_vm/stack_avid_pass.ml" ] };
  { name = "salt_multiplicity_block_mul";
    value = salt_multiplicity_block_mul;
    source = "digits of pi (3.141...) - multiplicity pass per-block seed multiplier";
    used_in = [ "lib/stack_vm/stack_multiplicity_pass.ml" ] };
  { name = "salt_multiplicity_block_add";
    value = salt_multiplicity_block_add;
    source = "digits of pi (...5926) - multiplicity pass per-block seed additive salt";
    used_in = [ "lib/stack_vm/stack_multiplicity_pass.ml" ] };
  { name = "salt_stack_dispatch_blind";
    value = salt_stack_dispatch_blind;
    source = "hex-speak salt '5877A564'+'CAFEBEEF' - Stack-VM dispatch table blinding";
    used_in = [ "lib/stack_vm/stack_runtime.ml" ] };
  { name = "salt_deadcode";
    value = salt_deadcode;
    source = "hex-speak salt 'DEAD'+'C0DE' - block ID token diversification";
    used_in = [ "lib/stack_vm/stack_cff_pass.ml" ] };
  { name = "sentinel_c0ffee_1";
    value = sentinel_c0ffee_1;
    source = "hex-speak sentinel 'C0FFEE'+1 - non-zero token replacement";
    used_in = [ "lib/stack_vm/stack_cff_pass.ml" ] };
  { name = "salt_egraph_scrambler";
    value = salt_egraph_scrambler;
    source = "alternating-nibble scrambler seed for E-graph expansion in Stack-MBA";
    used_in = [ "lib/stack_vm/stack_mba_pass.ml" ] };
  { name = "block_id_multiplier";
    value = block_id_multiplier;
    source = "multiplier for per-block PRNG diversification in Stack-MBA";
    used_in = [ "lib/stack_vm/stack_mba_pass.ml" ] };
  { name = "salt_dump_phase";
    value = salt_dump_phase;
    source = "hex-speak salt 'CAFE'+'5877' - deterministic decoy edge seed";
    used_in = [ "lib/stack_vm/stack_ir_json.ml" ] };
  { name = "comp_stall_lcg_mul";
    value = comp_stall_lcg_mul;
    source = "POSIX/java.util.Random LCG multiplier a=25214903917; prime candidate generation in CompStall";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml" ] };
  { name = "comp_stall_lcg_add";
    value = comp_stall_lcg_add;
    source = "POSIX LCG addend c=11; pair (a,c) satisfies Hull-Dobell theorem mod 2^k";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml" ] };
  { name = "comp_stall_pow_gf_poly";
    value = comp_stall_pow_gf_poly;
    source = "MurmurHash3 64-bit mix1 / GF(2^64) reduction polynomial for PoW inner loop";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml"; "lib/comp_stall/asg_comp_stall.hpp" ] };
  { name = "comp_stall_chebyshev_salt";
    value = comp_stall_chebyshev_salt;
    source = "hex-speak 5877 + CHAOS + LEET: state seed salt for Chebyshev discrete chaotic map";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml"; "lib/comp_stall/asg_comp_stall.hpp" ] };
  { name = "comp_stall_ergodic_c";
    value = comp_stall_ergodic_c;
    source = "hex-speak 5877 + 1337 + CAFE + BEEF: odd constant for Rivest-Knuth ergodic cubic polynomial";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml"; "lib/comp_stall/asg_comp_stall.hpp" ] };
  { name = "comp_stall_two_adic_c3";
    value = comp_stall_two_adic_c3;
    source = "hex-speak 1337 + 5877 + DEAD + BEEF: degree 3 coefficient for 2-adic Hensel-Newton solver";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml"; "lib/comp_stall/asg_comp_stall.hpp" ] };
  { name = "comp_stall_two_adic_c2";
    value = comp_stall_two_adic_c2;
    source = "hex-speak CAFE + BABE + 01000002: degree 2 even coefficient for 2-adic Hensel-Newton solver";
    used_in = [ "lib/comp_stall/comp_stall_engine.ml"; "lib/comp_stall/asg_comp_stall.hpp" ] };
  { name = "mem_webbing_offset_mask";
    value = mem_webbing_offset_mask;
    source = "bitmask 0x38 (00111000b): bounds scratch offset to 0..56, strictly within one 64B L1D cache line";
    used_in = [ "lib/stack_vm/stack_mem_webbing_pass.ml" ] };
  { name = "mem_webbing_base_offset";
    value = mem_webbing_base_offset;
    source = "base offset 65 bytes: round up base calculation ensuring [Base..Base+56] lies strictly in [SP-128..SP-1]";
    used_in = [ "lib/stack_vm/stack_mem_webbing_pass.ml" ] };
  { name = "mem_webbing_base_align_mask";
    value = mem_webbing_base_align_mask;
    source = "0xFFFFFFFFFFFFFFC0 (~0x3F): aligns base pointer to 64-byte L1D cache line boundary";
    used_in = [ "lib/stack_vm/stack_mem_webbing_pass.ml" ] };
  { name = "mem_webbing_alias_diff";
    value = mem_webbing_alias_diff;
    source = "0x18: bitwise difference ensuring a1 != a2 in dual-store aliasing";
    used_in = [ "lib/stack_vm/stack_mem_webbing_pass.ml" ] };
  { name = "mem_webbing_decoy_salt";
    value = mem_webbing_decoy_salt;
    source = "0x58771337CAFE: decoy value salt stored to a2 in dual-store aliasing";
    used_in = [ "lib/stack_vm/stack_mem_webbing_pass.ml" ] };
  { name = "mem_webbing_feistel_k_perm";
    value = mem_webbing_feistel_k_perm;
    source = "0x5053F3 (024051763_8): non-affine derangement permutation in F_{2^3} with maximum boolean non-linearity";
    used_in = [ "lib/stack_vm/stack_mem_webbing_pass.ml" ] };
  { name = "transducer_step_mul";
    value = transducer_step_mul;
    source = "0x58771337CAFEBEED: Hull-Dobell mod 8 multiplier for stateful transducer";
    used_in = [ "lib/stack_vm/stack_transducer_pass.ml" ] };
  { name = "transducer_step_add";
    value = transducer_step_add;
    source = "0x9E3779B97F4A7C15: golden ratio odd addend for stateful transducer";
    used_in = [ "lib/stack_vm/stack_transducer_pass.ml" ] };
  { name = "polymba_dyn_shift_mul";
    value = polymba_dyn_shift_mul;
    source = "5: multiplier for non-linear dynamic-shift PolyMBA knot";
    used_in = [ "lib/stack_vm/stack_polymba_pass.ml" ] };
  { name = "polymba_dyn_shift_add";
    value = polymba_dyn_shift_add;
    source = "3: addend for non-linear dynamic-shift PolyMBA knot";
    used_in = [ "lib/stack_vm/stack_polymba_pass.ml" ] };
  { name = "polymba_dyn_shift_mask";
    value = polymba_dyn_shift_mask;
    source = "15: 4-bit mask (0..15) for non-linear dynamic variable shift";
    used_in = [ "lib/stack_vm/stack_polymba_pass.ml" ] };
  { name = "crt_m1";
    value = crt_m1;
    source = "2^17 (131072): first pairwise coprime modulus for 4-moduli Garner CRT";
    used_in = [ "lib/stack_vm/stack_crt_pass.ml" ] };
  { name = "crt_m2";
    value = crt_m2;
    source = "2^17 - 1 (131071): second coprime Mersenne modulus for 4-moduli Garner CRT";
    used_in = [ "lib/stack_vm/stack_crt_pass.ml" ] };
  { name = "crt_m3";
    value = crt_m3;
    source = "2^16 + 1 (65537): third Fermat coprime modulus for 4-moduli Garner CRT";
    used_in = [ "lib/stack_vm/stack_crt_pass.ml" ] };
  { name = "crt_m4";
    value = crt_m4;
    source = "2^16 - 1 (65535): fourth coprime modulus for 4-moduli Garner CRT (M > 2^65)";
    used_in = [ "lib/stack_vm/stack_crt_pass.ml" ] };
  { name = "finite_field_m31";
    value = finite_field_m31;
    source = "2^31 - 1 (2147483647): 8th Mersenne prime field modulus F_M31";
    used_in = [ "lib/stack_vm/stack_finite_field_pass.ml" ] };
  { name = "finite_field_m31_mask";
    value = finite_field_m31_mask;
    source = "0x7FFFFFFE: 31-bit even input mask strictly < 2^31 - 1";
    used_in = [ "lib/stack_vm/stack_finite_field_pass.ml" ] };
  { name = "finite_field_m31_mul";
    value = finite_field_m31_mul;
    source = "0x58771337: non-zero multiplier in F_M31";
    used_in = [ "lib/stack_vm/stack_finite_field_pass.ml" ] };
  { name = "finite_field_m31_inv";
    value = finite_field_m31_inv;
    source = "0x1484AA6D: modular inverse of finite_field_m31_mul modulo 2^31 - 1";
    used_in = [ "lib/stack_vm/stack_finite_field_pass.ml" ] };
  { name = "finite_field_gf64_poly";
    value = finite_field_gf64_poly;
    source = "0x1B: x^4 + x^3 + x + 1 irreducible polynomial low-bits for GF(2^64)";
    used_in = [ "lib/stack_vm/stack_finite_field_pass.ml" ] };
  { name = "finite_field_gf64_const";
    value = finite_field_gf64_const;
    source = "0x5877CAFE1337BEEF: linear polynomial expansion constant in GF(2^64)";
    used_in = [ "lib/stack_vm/stack_finite_field_pass.ml" ] };
  { name = "trap_step_mul";
    value = trap_step_mul;
    source = "0x5877A55ACA1337B9: odd prime multiplier for cross-block path digest LCG permutation";
    used_in = [ "lib/stack_vm/stack_trap_pass.ml" ] };
  { name = "trap_step_add";
    value = trap_step_add;
    source = "0x1337CAFEBEEF5877: odd addend for cross-block path digest accumulator";
    used_in = [ "lib/stack_vm/stack_trap_pass.ml" ] };
  { name = "trap_token_mul";
    value = trap_token_mul;
    source = "0x9E3779B97F4A7C15: golden ratio multiplier for basic block token derivation";
    used_in = [ "lib/stack_vm/stack_trap_pass.ml" ] };
  { name = "trap_salt_init";
    value = trap_salt_init;
    source = "0xCAFE58771337BABE: initial salt for execution path digest register";
    used_in = [ "lib/stack_vm/stack_trap_pass.ml" ] };
  { name = "dual_rail_salt";
    value = dual_rail_salt;
    source = "0x5877DEADBEEFCAFE: PRNG diversification salt for dual-rail complement pass";
    used_in = [ "lib/stack_vm/stack_dual_rail_pass.ml" ] };
  { name = "homomorphic_salt";
    value = homomorphic_salt;
    source = "0x5877CAFE58771337: diversification salt for homomorphic operand blinding pass";
    used_in = [ "lib/stack_vm/stack_homomorphic_pass.ml" ] };
  { name = "drcc_salt";
    value = drcc_salt;
    source = "0x5877A0030221337B: PRNG diversification salt for DRCC register window pass";
    used_in = [ "lib/stack_vm/stack_drcc_pass.ml" ] };
  { name = "golomb_ruler_g0";
    value = golomb_ruler_g0;
    source = "OEIS A003022: mark 0 of optimal 4-mark Golomb ruler {0, 1, 4, 6}";
    used_in = [ "lib/stack_vm/stack_drcc_pass.ml" ] };
  { name = "golomb_ruler_g1";
    value = golomb_ruler_g1;
    source = "OEIS A003022: mark 1 of optimal 4-mark Golomb ruler {0, 1, 4, 6}";
    used_in = [ "lib/stack_vm/stack_drcc_pass.ml" ] };
  { name = "golomb_ruler_g2";
    value = golomb_ruler_g2;
    source = "OEIS A003022: mark 2 of optimal 4-mark Golomb ruler {0, 1, 4, 6}";
    used_in = [ "lib/stack_vm/stack_drcc_pass.ml" ] };
  { name = "golomb_ruler_g3";
    value = golomb_ruler_g3;
    source = "OEIS A003022: mark 3 of optimal 4-mark Golomb ruler {0, 1, 4, 6}";
    used_in = [ "lib/stack_vm/stack_drcc_pass.ml" ] };
  { name = "whitening_salt";
    value = whitening_salt;
    source = "0x5877A0112601337A: PRNG diversification salt for Galois LFSR memory whitening pass";
    used_in = [ "lib/stack_vm/stack_whitening_pass.ml" ] };
  { name = "whitening_init_key";
    value = whitening_init_key;
    source = "0x9E3779B97F4A7C15: golden ratio fractional part initial seed for whitening stream";
    used_in = [ "lib/stack_vm/stack_whitening_pass.ml" ] };
  { name = "whitening_lfsr_poly";
    value = whitening_lfsr_poly;
    source = "OEIS A011260: primitive polynomial x^64 + x^4 + x^3 + x + 1 mod 2^64 over GF(2)";
    used_in = [ "lib/stack_vm/stack_whitening_pass.ml" ] };
  { name = "costas_field_layout_salt";
    value = costas_field_layout_salt;
    source = "0x0C057A51337B00F0: OEIS A008404 Costas array field permutation PRNG salt for Pass 26 bytecode field layout";
    used_in = [ "lib/stack_vm/stack_encoder.ml" ] };
  { name = "rule30_salt";
    value = rule30_salt;
    source = "0x5877A2691601337B: OEIS A269160 Wolfram Rule 30 cellular automaton PRNG salt";
    used_in = [ "lib/stack_vm/stack_rule30_pass.ml" ] };
  { name = "rule30_init_key";
    value = rule30_init_key;
    source = "0x1337C0DE5877A269: initial seed for Wolfram Rule 30 keystream state slot";
    used_in = [ "lib/stack_vm/stack_rule30_pass.ml" ] };
  { name = "native_interleave_salt";
    value = native_interleave_salt;
    source = "0x5877A17A1E5C0DE7: PRNG diversification salt for native micro-handler interleaving pass";
    used_in = [ "lib/stack_vm/stack_native_interleave_pass.ml" ] };
]

let entry_by_name (name : string) : entry option =
  List.find_opt (fun e -> e.name = name) registry

(* ["0x9E3779B97F4A7C15ULL"] - the C spelling of a 64-bit constant. *)
let to_c_literal (v : int64) : string = Printf.sprintf "0x%LXULL" v

(* ["0x811C9DC5U"] - the C spelling of a 32-bit constant. *)
let to_c_literal32 (v : int64) : string =
  Printf.sprintf "0x%LXU" (Int64.logand v 0xFFFFFFFFL)

(* ["0x5877CAFE"] - the hexadecimal spelling of a 32-bit constant, without the
   C type suffix. *)
let to_hex_literal32 (v : int64) : string =
  Printf.sprintf "0x%08LX" (Int64.logand v 0xFFFFFFFFL)

(* ["0x9E3779B97F4A7C15L"] - the OCaml spelling of a 64-bit constant. *)
let to_ocaml_literal (v : int64) : string = Printf.sprintf "0x%016LxL" v
