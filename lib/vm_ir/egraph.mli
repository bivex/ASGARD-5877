(** E-Graph Equality Saturation Engine with Inverted Cost Metric.
    Represents equivalence classes of AST expression terms and applies rewrite rules
    until saturation, extracting expressions that maximize syntactic complexity and MBA depth. *)

type expr =
  | Const of int64
  | Var of Register.t
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | Xor of expr * expr
  | And of expr * expr
  | Or of expr * expr
  | Neg of expr
  | Not of expr

type eclass_id = int

type t

val create : unit -> t
val add : t -> expr -> eclass_id
val union : t -> eclass_id -> eclass_id -> unit
val rebuild : t -> unit
val saturate : ?max_iters:int -> ?rng:Random.State.t -> t -> unit
val complexity_of_expr : expr -> int
val extract_max_complexity : t -> eclass_id -> expr
