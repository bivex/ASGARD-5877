(** 2D Variable Entanglement (Step 2 Tier-4+):
    Entangles pairs of independent virtual registers (x, y) with an invertible matrix
    A \in GL(2, Z_{2^64}), making component-wise slicing and MCTS synthesis (Syntia) impossible. *)

type entanglement_matrix = {
  a11 : int64; a12 : int64;
  a21 : int64; a22 : int64;
  (* Inverse matrix A^{-1} mod 2^64 *)
  inv11 : int64; inv12 : int64;
  inv21 : int64; inv22 : int64;
  bias_u : int64;
  bias_v : int64;
}

(** Generation of a random invertible entanglement matrix in GL(2, Z_{2^64}) *)
val gen_entanglement_matrix : Random.State.t -> entanglement_matrix

(** Direct entanglement of two independent variables (x, y) -> (u, v) *)
val entangle_pair : entanglement_matrix -> int64 -> int64 -> int64 * int64

(** Inverse disentangling of an entangled pair (u, v) -> (x, y) *)
val disentangle_pair : entanglement_matrix -> int64 -> int64 -> int64 * int64

(** Homomorphic execution of independent constant additions (x + dx, y + dy)
    DIRECTLY in the entangled space (u, v) without disentangling! *)
val homomorphic_entangled_add_const :
  entanglement_matrix -> u:int64 -> v:int64 -> dx:int64 -> dy:int64 -> int64 * int64

(** Homomorphic linear transformation of a pair:
    computes the image (x + y, x - y) directly over the entangled variables (u, v),
    returning a new entangled pair (u', v') in the very same basis A! *)
val homomorphic_coupled_butterfly :
  entanglement_matrix -> u:int64 -> v:int64 -> int64 * int64
