open Stack_ir

type balance_result = {
  block_id : int;
  max_depth : int;
  final_delta : int;
  is_balanced : bool;
}

val is_terminator : stack_op -> bool

val analyze_block : block -> balance_result

val verify_program : program -> (int * string) list

val repair_block : Context_allocator.t -> block -> block

val repair_program : Context_allocator.t -> program -> program
