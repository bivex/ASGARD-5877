(** GPU-Verified Affine MBA Substitution Matrix Generator.

    Uses Apple Metal GPU compute kernels to generate and statistically verify
    cryptographically strong affine register substitution matrices over Z_{2^64}.
    Each candidate matrix is evaluated against the Strict Avalanche Criterion (SAC)
    across 65,536 parallel GPU threads. *)

type substitution_matrix = {
  forward : int64 array array;
  inverse : int64 array array;
  dim : int;
  sac : float;
}

(** [generate ?dim ?target_sac_min ?target_sac_max ?max_attempts ~rng ()]
    generates an invertible affine substitution matrix over Z_{2^64}
    verified on Apple Silicon GPU to have optimal diffusion
    (default: 40.0% <= SAC <= 60.0%). *)
val generate :
  ?dim:int ->
  ?target_sac_min:float ->
  ?target_sac_max:float ->
  ?max_attempts:int ->
  rng:Random.State.t ->
  unit ->
  substitution_matrix

(** Apply forward matrix transformation: v' = M * v mod 2^64. *)
val transform_vector : substitution_matrix -> int64 array -> int64 array

(** Apply inverse matrix transformation: v = M^{-1} * v' mod 2^64. *)
val inverse_transform_vector : substitution_matrix -> int64 array -> int64 array

(** Render forward and inverse substitution matrices as C++ constexpr arrays. *)
val emit_cpp_constants : substitution_matrix -> string
