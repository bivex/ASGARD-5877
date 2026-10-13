(* lib/cpp_codegen/cpp_ast.ml
   Типизированное представление подмножества C++20/C11 для генерации рантаймов VM *)

type ctype =
  | Void
  | Bool
  | Int8 | Int16 | Int32 | Int64
  | UInt8 | UInt16 | UInt32 | UInt64 | UIntPtr | SizeT
  | Float | Double
  | Ptr of ctype
  | ConstPtr of ctype
  | VolatilePtr of ctype
  | Ref of ctype
  | ConstRef of ctype
  | Array of ctype * int
  | StructType of string

type binop =
  | Add | Sub | Mul | Div | Rem
  | BitXor | BitAnd | BitOr | Shl | Shr
  | Eq | Ne | Lt | Le | Gt | Ge
  | LogAnd | LogOr

type unop =
  | BitNot | Neg | LogNot | Deref | AddrOf

type expr =
  | LitU64 of int64
  | LitU32 of int32
  | LitI64 of int64
  | LitInt of int
  | LitBool of bool
  | LitStr of string
  | Var of string
  | Member of expr * string            (* obj.field *)
  | PtrMember of expr * string         (* ptr->field *)
  | Index of expr * expr               (* arr[idx] *)
  | Unary of unop * expr
  | Binary of binop * expr * expr
  | Ternary of expr * expr * expr      (* cond ? tr : fl *)
  | Cast of ctype * expr               (* static_cast<T>(e) *)
  | BitCast of ctype * expr            (* std::bit_cast<T>(e) *)
  | Call of string * expr list         (* fn(a, b, ...) *)

type assign_op =
  | AssignPlain | AssignAdd | AssignSub | AssignXor | AssignOr | AssignAnd | AssignDiv

type stmt =
  | DeclVar of {
      is_const    : bool;
      is_constexpr: bool;
      is_volatile : bool;
      ty          : ctype;
      name        : string;
      init        : expr option;
    }
  | Assign of assign_op * expr * expr  (* lhs op= rhs; *)
  | ExprStmt of expr                   (* call(); *)
  | Return of expr option
  | Block of stmt list
  | If of expr * stmt list * stmt list
  | ForRange of {
      var_name : string;
      start_e  : expr;
      limit_e  : expr;
      body     : stmt list;
    }
  | While of expr * stmt list          (* while (cond) { ... } *)
  | Switch of {
      cond    : expr;
      cases   : (expr * stmt list) list;
      default : stmt list option;
    }
  | Break
  | Continue
  | Goto of string                     (* goto EXIT_VM; *)
  | Label of string                    (* label: *)
  | Raw of string                      (* raw C++ line *)
  | FenceSeqCst                        (* std::atomic_signal_fence(std::memory_order_seq_cst); *)
  | Comment of string

type func_attr =
  | AlwaysInline
  | NoInline
  | NoExcept
  | ConstexprFn
  | StaticFn

type func_decl = {
  attrs      : func_attr list;
  ret_type   : ctype;
  name       : string;
  params     : (ctype * string) list;
  body       : stmt list;
}

type struct_decl = {
  align_as : int option;
  name     : string;
  fields   : (ctype * string) list;
}

type top_decl =
  | IncludeSys of string               (* #include <cstdint> *)
  | IncludeLocal of string             (* #include "asg_crypto.hpp" *)
  | Namespace of string * top_decl list
  | ConstexprGlobal of ctype * string * expr
  | StructDecl of struct_decl
  | FuncDecl of func_decl
