(** E-Graph data structures, hash-consing, and union-find operations. *)

val mask_even : int64
val mask_odd : int64

type enode =
  | EVar of string
  | EConst of int64
  | EAdd of int * int
  | ESub of int * int
  | EMul of int * int
  | EAnd of int * int
  | EOr of int * int
  | EXor of int * int
  | ENot of int
  | ENeg of int

type t = {
  mutable next_id : int;
  parent : (int, int) Hashtbl.t;
  classes : (int, enode list ref) Hashtbl.t;
  mutable hashcons : (enode, int) Hashtbl.t;
  mutable unions : int;
}

val create : unit -> t

val find : t -> int -> int

val class_ids : t -> int list

val node_count : t -> int

val add_node : t -> enode -> int

val add_expr : t -> Mba.expr -> int

val canonicalize : t -> enode -> enode

val merge : t -> int -> int -> int

val rebuild : t -> unit
