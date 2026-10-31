(** Intermediate AST for parsed Sail specification files. *)

type type_desc =
  | TBits of int
  | TInt
  | TNat
  | TBool
  | TUnit
  | TVector of int * type_desc
  | TCustom of string

type expr =
  | EInt of int
  | EHex of int
  | EBits of int * int (** value, width *)
  | EBool of bool
  | EVar of string
  | EBinOp of string * expr * expr
  | EUnOp of string * expr
  | ECall of string * expr list

type stmt =
  | SLet of string * type_desc option * expr
  | SAssign of string * expr
  | SIf of expr * stmt list * stmt list
  | SForeach of string * expr * expr * stmt list (** var, start, end, body *)
  | SCall of string * expr list

type toplevel_item =
  | TDefaultOrder
  | TInclude of string
  | TLetConst of string * type_desc * expr
  | TTypeDecl of string
  | TRegisterDecl of string * type_desc
  | TValDecl of string * type_desc list * type_desc
  | TFunctionDef of string * (string * type_desc) list * stmt list
  | TMappingClause of string * int * int (** mnemonic, funct6, funct3 *)
  | TEncodingComment of string * string * int * int (** mnemonic, format, funct6, funct3 *)

type parsed_spec = toplevel_item list
