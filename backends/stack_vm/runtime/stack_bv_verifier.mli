(** Pass C: Bit-Vector Semantic Normalization & Automated SMT Verifier
    ─────────────────────────────────────────────────────────────────
    Formally proves semantics preservation between original and transformed
    Stack-IR sequences via SMT-LIB2 bit-vector (QF_BV) verification.

    For any transformation T over program P:
      forall x in BV_{64}^n: Obs(P, x) = Obs(T(P), x)

    Constructs SMT difference formulas:
      (assert (distinct orig_obs trans_obs))
      (check-sat)

    If result is `unsat`: mathematically proven equivalent across all 2^64 inputs.
    If result is `sat`: extracts counterexample input triggering divergence.
*)

open Stack_ir

type verification_result =
  | Equivalent
  | Divergent of { counterexample : string }
  | Solver_timeout
  | Solver_error of string
  | Stack_depth_mismatch of { orig_depth : int; trans_depth : int }

val string_of_result : verification_result -> string

(** Formally checks equivalence between two instruction clusters in QF_BV *)
val verify_ops_equivalence :
  ?timeout_sec:int ->
  orig_ops:stack_op list ->
  trans_ops:stack_op list ->
  unit ->
  verification_result

(** Formally checks equivalence between original and transformed basic blocks *)
val verify_block_equivalence :
  ?timeout_sec:int ->
  orig_block:block ->
  trans_block:block ->
  unit ->
  verification_result

(** Formally checks equivalence between all blocks of two programs *)
val verify_program_equivalence :
  ?timeout_sec:int ->
  orig_prog:program ->
  trans_prog:program ->
  unit ->
  (int * verification_result) list
