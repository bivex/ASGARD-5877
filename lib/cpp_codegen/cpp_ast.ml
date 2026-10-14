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
  | LitU8 of int                       (* 0x12 *)
  | LitBool of bool
  | LitStr of string
  | LitNull
  | SizeOfType of ctype
  | InitList of expr list              (* { a, b, c } *)
  | Var of string
  | Member of expr * string            (* obj.field *)
  | PtrMember of expr * string         (* ptr->field *)
  | Index of expr * expr               (* arr[idx] *)
  | Unary of unop * expr
  | Binary of binop * expr * expr
  | Ternary of expr * expr * expr      (* cond ? tr : fl *)
  | Cast of ctype * expr               (* static_cast<T>(e) *)
  | CCast of ctype * expr              (* (T)(e) C-style cast *)
  | BitCast of ctype * expr            (* std::bit_cast<T>(e) *)
  | ReinterpretCast of ctype * expr    (* reinterpret_cast<T>(e) *)
  | Call of string * expr list         (* fn(a, b, ...) *)
  | LabelAddr of string                (* &&label (GNU C computed goto label address) *)
  | DesignatedIndex of expr * expr     (* [idx] = value *)
  | DesignatedRange of expr * expr * expr (* [start ... limit] = value *)

type assign_op =
  | AssignPlain | AssignAdd | AssignSub | AssignMul | AssignXor | AssignOr | AssignAnd | AssignDiv

type stmt =
  | DeclVar of {
      align_as        : int option;
      is_static       : bool;
      is_thread_local : bool;
      is_const        : bool;
      is_constexpr    : bool;
      is_volatile     : bool;
      ty              : ctype;
      name            : string;
      init            : expr option;
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
  | DoWhile of expr * stmt list        (* do { ... } while (cond); *)
  | Switch of {
      cond    : expr;
      cases   : (expr * string option * stmt list) list;
      default : stmt list option;
    }
  | Break
  | Continue
  | Goto of string                     (* goto EXIT_VM; *)
  | ComputedGoto of expr               (* goto *target; (computed goto) *)
  | Label of string                    (* label: *)
  | PreprocIfStmt of string * stmt list * stmt list (* #if cond ... #else ... #endif *)
  | MacroUndefStmt of string           (* #undef NAME *)
  | Raw of string                      (* raw C++ line *)
  | FenceSeqCst                        (* std::atomic_signal_fence(std::memory_order_seq_cst); *)
  | Comment of string

type func_attr =
  | AlwaysInline
  | NoInline
  | InlineFn
  | Nodiscard
  | NoExcept
  | ConstexprFn
  | StaticFn
  | Constructor

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

type visibility =
  | Public
  | Private
  | Protected

type struct_member =
  | MemberField of {
      is_volatile : bool;
      ty          : ctype;
      name        : string;
      init        : expr option;
    }
  | MemberMethod of {
      attrs           : func_attr list;
      is_static       : bool;
      is_const        : bool;
      template_params : string list;
      ret_type        : ctype;
      name            : string;
      params          : (ctype * string) list;
      body            : stmt list;
    }
  | MemberMethodDecl of {
      attrs           : func_attr list;
      is_static       : bool;
      is_const        : bool;
      template_params : string list;
      ret_type        : ctype;
      name            : string;
      params          : (ctype * string) list;
    }
  | MemberConstructor of {
      attrs       : func_attr list;
      is_explicit : bool;
      name        : string;
      params      : (ctype * string) list;
      init_list   : (string * expr) list;
      body        : stmt list;
    }
  | MemberStaticConstexpr of { ty : ctype; name : string; init : expr }
  | MemberVisibility of visibility
  | MemberStaticAssert of expr * string
  | MemberRaw of string
  | MemberComment of string

type struct_def = {
  align_as : int option;
  name     : string;
  members  : struct_member list;
}

type top_decl =
  | Pragma of string                   (* #pragma once *)
  | MacroDef of string * expr option   (* #define NAME [VALUE] *)
  | MacroUndef of string               (* #undef NAME *)
  | PreprocIf of string * top_decl list * top_decl list (* #if cond ... #else ... #endif *)
  | PreprocIfdef of string * top_decl list * top_decl list (* #ifdef MACRO ... #else ... #endif *)
  | PreprocIfndef of string * top_decl list * top_decl list (* #ifndef MACRO ... #else ... #endif *)
  | IncludeSys of string               (* #include <cstdint> *)
  | IncludeLocal of string             (* #include "asg_crypto.hpp" *)
  | Namespace of string * top_decl list
  | ConstexprGlobal of ctype * string * expr
  | GlobalVar of {
      align_as        : int option;
      is_extern_c     : bool;
      is_weak         : bool;
      is_static       : bool;
      is_thread_local : bool;
      is_const        : bool;
      is_constexpr    : bool;
      is_volatile     : bool;
      ty              : ctype;
      name            : string;
      init            : expr option;
    }
  | StructDecl of struct_decl
  | StructDef of struct_def
  | ClassDef of struct_def
  | TemplateStructDef of { template_params : string list; def : struct_def }
  | TemplateClassDef of { template_params : string list; def : struct_def }
  | UnionDecl of struct_decl
  | UnionDef of struct_def
  | EnumDecl of { name : string; underlying_ty : ctype option; items : (string * expr option) list }
  | FuncDecl of func_decl
  | FuncProto of func_decl
  | Typedef of ctype * string
  | RawTop of string
  | CommentTop of string
