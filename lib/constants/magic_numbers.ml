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

(* --- FNV-1a --------------------------------------------------------- *)

(* The 64-bit FNV-1a prime: 2^40 + 2^8 + 0xB3.  Multiplies the hashed word. *)
let fnv1a_64_prime = 0x100000001B3L

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
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "sqrt2_fraction_64";
    value = sqrt2_fraction_64;
    source = "frac(sqrt(2)) * 2^64";
    used_in = [ "lib/vm_ir/rolling_key.ml"; "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "cbrt3_fraction_64";
    value = cbrt3_fraction_64;
    source = "frac(cbrt(3)) * 2^64 - first word of the SHA-256 initial hash";
    used_in = [ "lib/native_vm/vm_context_emitter.ml" ] };
  { name = "splitmix64_gamma";
    value = splitmix64_gamma;
    source = "SplitMix64 finalizer increment 1 (Steele, Lea and Flood, OOPSLA 2014)";
    used_in = [ "lib/vm_ir/rolling_key.ml" ] };
  { name = "splitmix64_mix";
    value = splitmix64_mix;
    source = "SplitMix64 finalizer increment 2 (Steele, Lea and Flood, OOPSLA 2014)";
    used_in = [ "lib/vm_ir/rolling_key.ml" ] };
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
]

let entry_by_name (name : string) : entry option =
  List.find_opt (fun e -> e.name = name) registry

(* ["0x9E3779B97F4A7C15ULL"] - the C spelling of a 64-bit constant. *)
let to_c_literal (v : int64) : string = Printf.sprintf "0x%016LxULL" v

(* ["0x9E3779B97F4A7C15L"] - the OCaml spelling of a 64-bit constant. *)
let to_ocaml_literal (v : int64) : string = Printf.sprintf "0x%016LxL" v
