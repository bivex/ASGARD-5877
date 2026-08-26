(** Sail AST Domain Model for formal ISA specification. *)

type sail_type =
  | Bits of int
  | Int of bool (** true for int, false for nat *)
  | Bool
  | Unit
  | Vector of int * sail_type
  | Var_type of string

type sail_expr =
  | Literal_int of int * int option (** value, optional bit width *)
  | Literal_bool of bool
  | Var of string
  | Binary of sail_expr * Types.Binary_op.t * sail_expr * Types.Element_kind.t
  | Unary of Types.Unary_op.t * sail_expr
  | Vector_elem of string * sail_expr * int (** reg_name, index_expr, sew *)
  | Mask_check of string * sail_expr * sail_expr (** mask_reg, index_expr, vm_unmasked_expr *)
  | Call of string * sail_expr list

type sail_stmt =
  | Let of string * sail_expr * sail_type option
  | Assign of string * sail_expr
  | Set_vector_elem of string * sail_expr * sail_expr * int (** reg, index, val, sew *)
  | If of sail_expr * sail_stmt list * sail_stmt list
  | Vector_loop of string * sail_expr * sail_stmt list (** var, bound, body *)

type function_def = {
  name : string;
  params : (string * sail_type) list;
  return_type : sail_type;
  body : sail_stmt list;
}

type encoding_clause = {
  mnemonic : string;
  funct6 : int;
  funct3 : int;
  format_name : string;
}

val type_to_sail : sail_type -> string
val expr_to_sail : sail_expr -> string
val stmt_to_sail : ?indent:int -> sail_stmt -> string
val function_to_sail : ?indent:int -> function_def -> string
val encoding_clause_to_sail : encoding_clause -> string
