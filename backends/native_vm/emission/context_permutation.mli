(** Dynamic permutation of the VMContext layout at epoch boundaries (P0-Fixed).
    Includes Cycle Decomposition for the exact decomposition of permutations into transpositions
    without cycle collisions and context corruption. *)

type t = {
  perm     : int array;
  inv_perm : int array;
}

val gen_permutation : rng:Random.State.t -> n:int -> t
val emit_epoch_rotation_cpp : t -> string

type epoch_schedule = {
  n_regs       : int;
  epoch_perms  : int array array;  (** epoch_id -> reg_id -> physical_slot *)
  inv_perms    : int array array;  (** epoch_id -> physical_slot -> reg_id *)
  epoch_masks  : int64 array;      (** Epoch index masking keys *)
}

(** Generation of the context permutation schedule for a given number of epochs *)
val gen_epoch_schedule : Random.State.t -> n_regs:int -> n_epochs:int -> epoch_schedule

(** Obtaining the physical slot for a virtual register in a given epoch *)
val physical_slot : epoch_schedule -> epoch:int -> reg_id:int -> int

(** Decomposition of an arbitrary permutation target (where new_arr[target[i]] = old_arr[i])
    into an exact sequence of index pairs (u, v) for in-place swap *)
val decompose_into_swaps : int array -> (int * int) list

(** Simulation of the register array rotation between epochs in OCaml (for verification) *)
val apply_swaps_in_place : int64 array -> (int * int) list -> unit

(** Construction of the C++20 AST of the epoch-to-epoch register rotation function according to the schedule *)
val build_schedule_epoch_rotation_ast :
  epoch_schedule -> from_epoch:int -> to_epoch:int -> Cpp_codegen.Cpp_ast.top_decl

(** Generation of the C++20 in-place epoch-to-epoch register rotation function according to the schedule *)
val emit_schedule_epoch_rotation_cpp : epoch_schedule -> from_epoch:int -> to_epoch:int -> string
