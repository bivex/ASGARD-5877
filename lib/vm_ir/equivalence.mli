(** Differential Semantic Equivalence Verifier.
    Asserts bit-exact semantic equivalence between original and transformed IR
    across randomized fuzzing vectors. *)

type discrepancy = {
  trial_index : int;
  initial_regs : (Register.t * int64) list;
  expected_rax : int64;
  actual_rax : int64;
  details : string;
}

val assert_equivalent :
  ?trials:int ->
  ?seed:int64 ->
  Ir.func ->
  Ir.func ->
  (unit, discrepancy) result
