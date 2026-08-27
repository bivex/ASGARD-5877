(** Golden Reference Evaluator for IR Functions.
    Executes IR functions in a controlled virtual environment and captures snapshots. *)

type execution_snapshot = {
  final_rax : int64;
  registers : (Register.t, int64) Hashtbl.t;
  memory_writes : (int64, int) Hashtbl.t;
  steps_taken : int;
  halted_cleanly : bool;
}

val evaluate :
  ?initial_regs:(Register.t * int64) list ->
  ?initial_mem:(int64 * int) list ->
  ?max_steps:int ->
  Ir.func ->
  (execution_snapshot, string) result
