(** RFC 6234 Standard SHA-256 Cryptographic Hash Implementation.
    Pure OCaml, zero external dependencies. *)

val digest_bytes : bytes -> bytes
(** Computes 32-byte raw binary SHA-256 digest of input bytes. *)

val digest_string : string -> bytes
(** Computes 32-byte raw binary SHA-256 digest of input string. *)

val hexdigest : bytes -> string
(** Formats 32-byte raw digest as 64-character lowercase hexadecimal string. *)

val constant_time_equal : bytes -> bytes -> bool
(** Constant-time byte-array equality check to defeat timing side-channel attacks. *)
