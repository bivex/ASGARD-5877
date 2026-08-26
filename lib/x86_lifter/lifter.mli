open Vm_ir

(** Lifter configuration options *)
type options = {
  function_name : string;
}

val default_options : options

(** Lift an Intel-syntax x86_64 assembly string into a Turing-complete VM-IR function. *)
val lift_function : ?options:options -> string -> (Ir.func, string) result

(** Lift a list of parsed raw lines into basic blocks with CFG construction. *)
val lift_lines : ?options:options -> X86_parser.raw_line list -> (Ir.func, string) result

(** Resolve label references in targets to explicit BlockId references. *)
val resolve_cfg_labels : Ir.cfg -> (Ir.cfg, string) result
