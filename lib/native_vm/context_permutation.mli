(** Fisher-Yates register context permutation with cycle-decomposition swap generator.
    Guarantees correct register mapping transitions across epoch rotation boundaries
    without cycle collisions or register corruption. *)

type t = {
  perm     : int array;
  inv_perm : int array;
}

val gen_permutation : rng:Random.State.t -> n:int -> t
val decompose_into_swaps : int array -> (int * int) list
val emit_epoch_rotation_cpp : t -> string
