(** Formal Invariants for ASGARD-5877 Stack-VM Transformations (P2)
    ─────────────────────────────────────────────────────────────────
    Formally defines and checks the three core machine-state invariants:
      1. Stack Invariant: Non-negative stack depth at EVERY instruction,
         zero exit delta, and consistent entry depth across all CFG edges.
      2. Control-Flow Invariant: Valid entry block, all targets exist,
         well-formed block terminators, context slots within bounds.
      3. Key-State Invariant: Rolling key and decoder state consistency
         across CFG edges and join points.
*)

open Stack_ir

type stack_violation =
  | Underflow of { block_id : int; op_index : int; op : stack_op; depth : int }
  | NonZeroExit of { block_id : int; final_delta : int }
  | DepthMismatchAtMerge of { block_id : int; pred1 : int; depth1 : int; pred2 : int; depth2 : int }

type cfg_violation =
  | MissingEntryBlock of int
  | MissingTargetBlock of { from_block : int; target_block : int }
  | InvalidContextSlot of { block_id : int; op_index : int; slot : int; max_slots : int }
  | MissingTerminator of { block_id : int }

type key_violation =
  | KeyMismatchAtMerge of { block_id : int; pred1 : int; key1 : int64; pred2 : int; key2 : int64 }

type invariant_violation =
  | StackViolation of stack_violation
  | CfgViolation of cfg_violation
  | KeyViolation of key_violation

val violation_to_string : invariant_violation -> string

val check_stack_invariants : program -> (unit, stack_violation list) result
val check_cfg_invariants : program -> (unit, cfg_violation list) result
val check_key_invariants : ?initial_key:int64 -> program -> (unit, key_violation list) result
val verify_all_invariants : ?initial_key:int64 -> program -> (unit, invariant_violation list) result
