open Vm_ir
open Flags

type stack_op =
  | PushImm of int64
  | PushReg of int
  | PopReg of int
  | ReadMem of int
  | WriteMem of int
  | Add
  | Sub
  | Mul
  | Nor
  | Nand
  | Shl
  | Shr
  | Dup
  | Swap
  | PushFlags
  | PopFlags
  | JmpRel of int
  | JccRel of int * condition
  | KeyAdjust of int64
  | Exit

type block = {
  id : int;
  label : string;
  ops : stack_op list;
}

type program = {
  entry_id : int;
  blocks : (int, block) Hashtbl.t;
  context_slots : int;
}

val op_to_string : stack_op -> string
val block_to_string : block -> string
val program_to_string : program -> string

val make_block : int -> string -> stack_op list -> block
val make_program : int -> block list -> int -> program

val push_weight : stack_op -> int
val pop_weight : stack_op -> int
val stack_delta : stack_op -> int
