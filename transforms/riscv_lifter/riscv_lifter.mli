open Vm_ir

type options = {
  function_name : string;
}

val default_options : options

val lift_function : ?options:options -> string -> (Ir.func, string) result
val lift_lines : ?options:options -> Riscv_parser.raw_line list -> (Ir.func, string) result

val extract_marked_regions :
  ?require_markers:bool ->
  Riscv_parser.raw_line list ->
  (Riscv_parser.marker_mode * Riscv_parser.raw_line list) list

module Riscv_parser : module type of Riscv_parser
