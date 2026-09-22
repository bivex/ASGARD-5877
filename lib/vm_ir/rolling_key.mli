(* Anti-Pushan block-chained rolling key: canonical OCaml mirror of the C++ keystream. *)

val key64_for_offset : int32 -> int -> int64
(** Positional SplitMix64 PRF: per-word mask base derived from (seed, word offset). *)

val anchor_key : int32 -> int -> int64
(** Domain-separated block-entry anchor [K0]:
    [anchor_key seed off = key64_for_offset (seed lxor 0x5BD1E995) (off lxor 0x13375877)].
    The distinct domain keeps the first in-block mask (k_pos lxor K0) from collapsing
    to zero. *)

val advance_key_step : int64 -> int -> int -> int64 -> int64
(** One step of the in-block key chain, mirroring C++ advance_key_step bit-for-bit.
    [imm] is the 64-bit two's-complement value the runtime sees. *)

val decode_fields : int64 -> int * int * int * int64
(** Decode (op, dst, src, imm) from a packed plaintext word exactly as the C++
    FETCH_NEXT macro does.  [imm] is the sign-extended 32-bit slice of bits 18..49 —
    the runtime never sees the full 46-bit immediate, so chain simulation must use
    this truncated view, never the source immediate. *)
