open Register
open Flags

type alu_op =
  | Add
  | Adc
  | Sub
  | Sbb
  | And
  | Or
  | Xor
  | Shl
  | Shr
  | Sar
  | Rol
  | Ror
  | Mul
  | Imul
  | Div
  | Idiv

type unary_op =
  | Not
  | Neg
  | Inc
  | Dec

type mem_ref = {
  base : Register.t option;
  index : (Register.t * int) option; (** (index_reg, scale 1|2|4|8) *)
  disp : int64;
  width : width;
}

type operand =
  | Reg of Register.t
  | Imm of int64
  | Mem of mem_ref

type target =
  | Label of string
  | BlockId of int
  | TargetImm of int64

type instr =
  | Nop
  | Mov of { dst : operand; src : operand }
  | Lea of { dst : Register.t; addr : mem_ref }
  | Push of operand
  | Pop of operand
  | Xchg of operand * operand
  | Alu of { op : alu_op; dst : Register.t; src1 : operand; src2 : operand; set_flags : bool }
  | Unary of { op : unary_op; dst : Register.t; src : operand; set_flags : bool }
  | Cmp of { src1 : operand; src2 : operand }
  | Test of { src1 : operand; src2 : operand }
  | Jmp of target
  | Jcc of { cond : condition; target_true : target; target_false : target }
  | Call of target
  | Ret
  | Setcc of { cond : condition; dst : operand }
  | Cmov of { cond : condition; dst : Register.t; src : operand }
  | Vm_enter
  | Vm_exit
  | Trap of string

type basic_block = {
  id : int;
  label : string;
  instrs : instr list;
}

type cfg = {
  entry_id : int;
  blocks : (int, basic_block) Hashtbl.t;
}

type func = {
  name : string;
  cfg : cfg;
}

val alu_op_to_string : alu_op -> string
val unary_op_to_string : unary_op -> string
val mem_ref_to_string : mem_ref -> string
val operand_to_string : operand -> string
val target_to_string : target -> string
val instr_to_string : instr -> string
val block_to_string : basic_block -> string
val func_to_string : func -> string

val make_block : id:int -> label:string -> instrs:instr list -> basic_block
val make_func : name:string -> entry_id:int -> blocks:basic_block list -> func
val get_block : cfg -> int -> basic_block option
val successors : basic_block -> target list
