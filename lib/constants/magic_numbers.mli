(** Central registry of the magic numbers of the engine.

    A magic number is a numeric literal whose value cannot be guessed from the
    code that uses it: a hash or PRNG constant, a key-derivation salt, a bit
    mask, a sentinel.  Such a literal does not belong at the call site; it is
    declared once in this module, under a name that states where the number
    comes from, and every call site refers to the name.

    The registry keeps the OCaml implementation and the emitted C++ runtime in
    step: both read the same declaration, so a constant cannot be edited on one
    side only.

    {1 AGENTS.md} (section 3) makes this the only way to introduce a magic
    number. *)

(** Provenance of a registered constant. *)
type entry = {
  name : string;          (** the identifier used at the call sites *)
  value : int64;          (** the value, as a signed 64-bit integer *)
  source : string;        (** where the number comes from *)
  used_in : string list;  (** the modules that refer to it *)
}

(** frac(phi^-1) * 2^64: Knuth's multiplicative hashing constant, xxHash's
    PRIME64_1. *)
val golden_ratio_64 : int64

(** frac(phi^-1) * 2^32: the 32-bit golden ratio. *)
val golden_ratio_32 : int64

(** frac(sqrt(2)) * 2^64. *)
val sqrt2_fraction_64 : int64

(** frac(cbrt(3)) * 2^64: the first word of the SHA-256 initial hash. *)
val cbrt3_fraction_64 : int64

(** The two increments of the SplitMix64 finalizer, and the modular inverse of
    the first one. *)
val splitmix64_gamma : int64
val splitmix64_mix : int64
val splitmix64_gamma_inverse : int64

(** The FNV-1a prime and the two offset bases. *)
val fnv1a_64_prime : int64
val fnv1a_32_offset_basis : int64
val fnv1a_64_offset_basis : int64

(** The initial hash and the round constants of SHA-256 (FIPS 180-4), and the
    first word of each: the engine uses them as well-distributed 32-bit
    mixers. *)
val sha256_iv : int32 array
val sha256_k : int32 array
val sha256_iv_h0 : int64
val sha256_k0 : int64

(** MurmurHash3 for x86, 32-bit: the mixing multiplier. *)
val murmur3_32_c1 : int32

(** MurmurHash3 for 64-bit: the two multipliers of the fmix finalizer. *)
val murmur3_64_fmix_c1 : int64
val murmur3_64_fmix_c2 : int64

(** The disjoint 1-bit partition of the semi-linear MBA encoding: [even_bit_mask]
    selects the even bits, [odd_bit_mask] the odd bits. *)
val even_bit_mask : int64
val odd_bit_mask : int64

(** The engine's salt palette, written in hex-speak so that the values read as
    words in a disassembly.  They are salts, not derived values. *)
val salt_xwcafe : int64
val salt_xwcafe_leetbeef : int64
val salt_xwcafe_cafebabe1337 : int64
val salt_xwcafe_beef : int64
val salt_leetbeef : int64
val salt_cafebabe_leet : int64
val salt_leet_13375877 : int64
val salt_regmask : int64
val salt_canary_mid : int64
val salt_canary_stack : int64
val salt_poison_penalty : int64
val salt_deadbeef : int64
val salt_deadbeef_5a5a5a5a : int64
val salt_deadbeef_cafebabe : int64
val salt_deadbeef_5877cafe : int64
val salt_deadbeef_cafe1337 : int64

(** Every registered constant, with its provenance and its users. *)
val registry : entry list

(** The registry entry named [name], if there is one. *)
val entry_by_name : string -> entry option

(** ["0x9E3779B97F4A7C15ULL"] - the C spelling of a 64-bit constant. *)
val to_c_literal : int64 -> string

(** ["0x811C9DC5U"] - the C spelling of a 32-bit constant. *)
val to_c_literal32 : int64 -> string

(** ["0x5877CAFE"] - the hexadecimal spelling of a 32-bit constant, without the
    C type suffix. *)
val to_hex_literal32 : int64 -> string

(** ["0x9E3779B97F4A7C15L"] - the OCaml spelling of a 64-bit constant. *)
val to_ocaml_literal : int64 -> string
