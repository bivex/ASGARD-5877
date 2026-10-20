(** The x86 AES extensions (AES-NI).

    All instructions operate on 128-bit vector states (represented as 16-byte
    arrays or two 64-bit lanes) according to NIST FIPS-197 and the Intel SDM. *)

val bytes_of_lanes : int64 * int64 -> int array
val lanes_of_bytes : int array -> int64 * int64

val aesenc : int array -> int array -> int array
val aesenclast : int array -> int array -> int array
val aesdec : int array -> int array -> int array
val aesdeclast : int array -> int array -> int array
val aesimc : int array -> int array
val aeskeygenassist : int array -> int -> int array
