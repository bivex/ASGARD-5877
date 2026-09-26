open Stack_ir

type logic_basis =
  | Basis_NOR
  | Basis_NAND
  | Basis_Random

val transform_block : ?basis:logic_basis -> ?seed:int -> Context_allocator.t -> block -> block

val transform_program : ?basis:logic_basis -> ?seed:int -> Context_allocator.t -> program -> program

val expand_not_nor : stack_op list
val expand_or_nor : stack_op list
val expand_and_nor : stack_op list
val expand_xor_nor : int -> int -> stack_op list

val expand_not_nand : stack_op list
val expand_and_nand : stack_op list
val expand_or_nand : stack_op list
val expand_xor_nand : int -> int -> int -> stack_op list
