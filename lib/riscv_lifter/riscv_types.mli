open Vm_ir

type raw_mem = {
  base : Register.t option;
  disp : int64;
  width : Register.width;
  is_signed : bool;
}

type raw_op =
  | OpReg of Register.t
  | OpImm of int64
  | OpMem of raw_mem
  | OpLabel of string

type marker_mode =
  | ModeVirtualize of string
  | ModeMutation of string
  | ModeUltra of string

type raw_line =
  | LineLabel of string
  | LineInstr of string * raw_op list
  | LineDirective of string
  | LineMarkerBegin of marker_mode
  | LineMarkerEnd
  | LineEmpty

val marker_mode_to_string : marker_mode -> string
