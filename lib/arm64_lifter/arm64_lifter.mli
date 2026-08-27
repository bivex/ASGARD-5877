open Vm_ir

type options = {
  function_name : string;
}

val default_options : options

val lift_function : ?options:options -> string -> (Ir.func, string) result
val lift_lines : ?options:options -> Arm64_parser.raw_line list -> (Ir.func, string) result
