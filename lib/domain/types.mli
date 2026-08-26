(** Common Domain Types and Enums for Vector ISA Specification. *)

module Sew : sig
  type t = E8 | E16 | E32 | E64

  val to_bits : t -> int
  val byte_width : t -> int
  val c_type : t -> string
  val c_utype : t -> string
  val of_bits : int -> (t, Errors.t) result
  val to_string : t -> string
  val all : t list
end

module Lmul : sig
  type t = MF8 | MF4 | MF2 | M1 | M2 | M4 | M8

  val multiplier_val : t -> float
  val num_registers : t -> int
  val to_string : t -> string
  val all : t list
end

module Element_kind : sig
  type t = Int | Uint | Float | Bits

  val to_string : t -> string
  val of_string : string -> (t, Errors.t) result
end

module Instruction_format : sig
  type t =
    | OP_VV
    | OP_VX
    | OP_VI
    | OP_MVV
    | OP_RED
    | OP_WIDENING
    | OP_MEM_LOAD
    | OP_MEM_STORE

  val to_string : t -> string
  val to_suffix : t -> string
  val to_funct3 : t -> int
  val of_string : string -> (t, Errors.t) result
  val all : t list
  val equal : t -> t -> bool
end

module Binary_op : sig
  type t =
    | ADD
    | SUB
    | MUL
    | DIV
    | REM
    | AND
    | OR
    | XOR
    | SLL
    | SRL
    | SRA
    | MIN
    | MAX
    | SADD
    | SSUB
    | CMPEQ
    | CMPNE
    | CMPLT
    | CMPGE

  val name : t -> string
  val symbol : t -> string
  val is_compare : t -> bool
  val of_name : string -> t option
  val all : t list
end

module Unary_op : sig
  type t =
    | NEG
    | NOT
    | ABS
    | CLZ
    | CTZ
    | CPOP

  val name : t -> string
  val symbol : t -> string
  val of_name : string -> t option
  val all : t list
end

module Tail_policy : sig
  type t = Undisturbed | Agnostic

  val to_string : t -> string
end

module Mask_policy : sig
  type t = Undisturbed | Agnostic

  val to_string : t -> string
end
