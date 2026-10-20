(** The x86 SHA extensions (SHA-NI).

    Every instruction works on the four 32-bit words of a 128-bit vector
    register.  The words are little-endian: word 0 is the low half of lane 0,
    word 1 the high half of lane 0, word 2 the low half of lane 1 and word 3
    the high half of lane 1. *)

val mask32 : int64

val w32 : int64 -> int64
(** Truncate to 32 bits. *)

val add32 : int64 -> int64 -> int64
(** Add two 32-bit words modulo 2^32. *)

val rol32 : int64 -> int -> int64
(** Rotate a 32-bit word left. *)

val ror32 : int64 -> int -> int64
(** Rotate a 32-bit word right. *)

val sha1_f : int -> int64 -> int64 -> int64 -> int64
(** The SHA-1 round function of the given round group (0..3). *)

val sha1_k : int -> int64
(** The SHA-1 round constant of the given round group (0..3). *)

val sha256_ch : int64 -> int64 -> int64 -> int64
(** The SHA-256 [Ch] function. *)

val sha256_maj : int64 -> int64 -> int64 -> int64
(** The SHA-256 [Maj] function. *)

val sha256_sigma0 : int64 -> int64
(** The SHA-256 [sigma0] function. *)

val sha256_sigma1 : int64 -> int64
(** The SHA-256 [sigma1] function. *)

val sha1rnds4 : int -> int64 array -> int64 array -> int64 array
(** Four SHA-1 rounds.  The immediate selects the round function and its
    constant, the destination holds the state (A, B, C, D) and the source the
    four pre-computed message words. *)

val sha1nexte : int64 array -> int64 array -> int64 array
(** The SHA-1 state variable E after four rounds, added to the scheduled
    message words. *)

val sha1msg1 : int64 array -> int64 array -> int64 array
(** The intermediate calculation of the next four SHA-1 message words. *)

val sha1msg2 : int64 array -> int64 array -> int64 array
(** The final calculation of the next four SHA-1 message words. *)

val sha256rnds2 : int64 array -> int64 array -> int64 array -> int64 array
(** Two SHA-256 rounds.  The destination holds the state (C, D, G, H), the
    source the state (A, B, E, F) and the third argument the two round
    constants of the implicit XMM0. *)

val sha256msg1 : int64 array -> int64 array -> int64 array
(** The intermediate calculation of the next four SHA-256 message words. *)

val sha256msg2 : int64 array -> int64 array -> int64 array
(** The final calculation of the next four SHA-256 message words. *)

val words_of_lanes : int64 * int64 -> int64 array
(** The four 32-bit words of a 128-bit vector register. *)

val lanes_of_words : int64 array -> int64 * int64
(** The two 64-bit lanes of a 128-bit vector register. *)
