(** Pass B: Path-Sensitive Semantic Encoding Pass
    ─────────────────────────────────────────────
    Applies path-sensitive state encodings across CFG edges.
    For each block B_i, virtual state is encoded via:
      E_i(x) = alpha_i * x + beta_i (mod 2^64)

    For edge B_i -> B_j, the transition operator transforms the
    encoded state without decoding into plaintext:
      y_j = E_j(E_i^{-1}(y_i)) = A_{ij} * y_i + B_{ij} (mod 2^64)
    where:
      A_{ij} = alpha_j * alpha_i^{-1} (mod 2^64)
      B_{ij} = beta_j - A_{ij} * beta_i (mod 2^64)

    Guarantees consistent PHI merges across converging CFG paths
    and breaks global taint continuity.
*)

open Stack_ir

type block_encoding = {
  alpha     : int64;
  beta      : int64;
  inv_alpha : int64;
}

type path_config = {
  enabled : bool;
  seed    : int64;
}

val default_path_config : int64 -> path_config

val compute_block_encoding : seed:int64 -> block_id:int -> block_encoding

(** Computes transition coefficients (A, B) such that y_dst = A * y_src + B (mod 2^64) *)
val compute_edge_transition :
  src_enc:block_encoding ->
  dst_enc:block_encoding ->
  int64 * int64

(** Emits Stack-IR sequence applying transition: slot := A * slot + B *)
val emit_edge_transition : slot:int -> a:int64 -> b:int64 -> stack_op list

val apply_block :
  path_config ->
  Context_allocator.t ->
  block ->
  block

val apply_program :
  path_config ->
  Context_allocator.t ->
  program ->
  program
