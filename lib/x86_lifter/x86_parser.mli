open Vm_ir

type raw_mem = {
  base : Register.t option;
  index : (Register.t * int) option;
  disp : int64;
  width : Register.width;
}

type raw_op =
  | OpReg of Register.t
  | OpImm of int64
  | OpMem of raw_mem
  | OpLabel of string

type raw_line =
  | LineLabel of string
  | LineInstr of string * raw_op list
  | LineDirective of string
  | LineEmpty

val parse_line : string -> (raw_line, string) result
val parse_lines : string -> (raw_line list, string) result
val parse_mem_operand : string -> Register.width -> (raw_mem, string) result
