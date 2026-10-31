(** Strict Typed IR Verification Engine.
    Validates CFG integrity, block terminators, jump targets, and operand widths. *)

type verify_error =
  | MissingEntryBlock of int
  | InvalidJumpTarget of int * string
  | MissingTerminator of int
  | EmptyBlock of int
  | InvalidRegisterWidth of Register.t * string

val error_to_string : verify_error -> string
val verify_block : Ir.cfg -> Ir.basic_block -> (unit, verify_error) result
val verify_cfg : Ir.cfg -> (unit, verify_error) result
val verify_func : Ir.func -> (unit, verify_error) result
