(** Differential Semantic Equivalence Verifier.
    Asserts bit-exact semantic equivalence between original and transformed IR
    across randomized fuzzing vectors and corner cases. *)

type discrepancy_kind =
  | RegMismatch of { reg : Register.t; expected : int64; actual : int64 }
  | CalleeSavedClobbered of { reg : Register.t; initial : int64; actual : int64 }
  | FlagsMismatch of { expected_flags : int64; actual_flags : int64; details : string }
  | MemoryMismatch of { addr : int64; expected_byte : int; actual_byte : int }
  | TrapMismatch of { expected_trap : string option; actual_trap : string option }
  | EvalError of string

type discrepancy = {
  trial_index : int;
  initial_regs : (Register.t * int64) list;
  expected_rax : int64;
  actual_rax : int64;
  kind : discrepancy_kind;
  details : string;
}

val assert_equivalent :
  ?trials:int ->
  ?seed:int64 ->
  ?check_callee_saved:bool ->
  ?check_flags:bool ->
  ?check_memory:bool ->
  Ir.func ->
  Ir.func ->
  (unit, discrepancy) result

