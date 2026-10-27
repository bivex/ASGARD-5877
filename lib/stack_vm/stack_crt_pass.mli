(** Pass 12: Chinese Remainder Theorem (CRT) Split-Path Execution Pass
    ─────────────────────────────────────────────────────────────────
    Splits computations across pairwise coprime moduli (m1, m2, m3)
    where:
      m1 = 2^22      = 4194304
      m2 = 2^21 - 1  = 2097151
      m3 = 2^21 - 3  = 2097149
    with Garner reconstruction over M = m1 * m2 * m3:
      z = (z1 * c1 + z2 * c2 + z3 * c3) mod M
*)

open Stack_ir

type crt_config = {
  enabled : bool;
  seed    : int64;
}

val default_crt_config : int64 -> crt_config

val split_val : int64 -> int64 * int64 * int64

val reconstruct_val : int64 * int64 * int64 -> int64

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
