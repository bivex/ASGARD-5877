open Vm_ir

type expr =
  | Var of string
  | Const of int64
  | Add of expr * expr
  | Sub of expr * expr
  | Mul of expr * expr
  | And of expr * expr
  | Or of expr * expr
  | Xor of expr * expr
  | Not of expr
  | Neg of expr

val to_string : expr -> string
val eval : (string -> int64) -> expr -> int64

(** Rewrites an expression into a Mixed Boolean-Arithmetic (MBA) polynomial of given recursion depth. *)
val rewrite : rng:Random.State.t -> depth:int -> expr -> expr

(** Lowers an MBA expression AST into a sequence of VM-IR instructions writing the result to [dst]. *)
val lower_to_ir : dst:Register.t -> env:(string * Ir.operand) list -> expr -> Ir.instr list

(** Obfuscate a single ALU operation (Add, Sub, Xor, And, Or) using MBA transformation. *)
val obfuscate_alu :
  rng:Random.State.t ->
  depth:int ->
  dst:Register.t ->
  src1:Ir.operand ->
  src2:Ir.operand ->
  Ir.alu_op ->
  Ir.instr list
