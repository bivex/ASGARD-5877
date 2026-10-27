(** Pass 12: Chinese Remainder Theorem (CRT) Split-Path Execution Pass
    ─────────────────────────────────────────────────────────────────
    Splits computations across pairwise coprime moduli (m1, m2, m3, m4)
    where M = m1 * m2 * m3 * m4 > 2^65:
      m1 = 2^17      = 131072
      m2 = 2^17 - 1  = 131071
      m3 = 2^16 + 1  = 65537
      m4 = 2^16 - 1  = 65535
    with Garner reconstruction over M > 2^65 and exact 64-bit overflow truncation.
*)

open Stack_ir

type crt_config = {
  enabled : bool;
  seed    : int64;
}

val default_crt_config : int64 -> crt_config

val split_val : int64 -> int64 * int64 * int64 * int64

val reconstruct_val : int64 * int64 * int64 * int64 -> int64

val apply_block :
  crt_config ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  crt_config ->
  Context_allocator.t ->
  program ->
  program
