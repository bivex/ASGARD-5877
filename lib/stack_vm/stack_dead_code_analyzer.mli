(** Stack-VM Dead Code Causality Analyzer
    ──────────────────────────────────────
    Diagnoses, classifies, and pinpoints exactly *why* dead code emerges
    or is eliminated across the ASGARD virtualization pipeline.

    Root Cause Taxonomy:
    1. Dead Register Writes (unreferenced or overwritten before read)
    2. Stack-to-Dead-Slot Drains (Push followed by Pop into dead slot)
    3. Structural Identities (Swap; Swap, Rot^4, etc.)
    4. Algebraic Zero-Knots & Redundant Arithmetic (x - x, + 0, * 1)
    5. CFF Sub-Zero Redundancy (Sub; PushImm 0; Cmp)
    6. Stack Balance Discard Drains (PopReg inserted by Stack_balance_pass)
    7. Unreachable CFG Blocks (orphaned decoy blocks or dead branches)
    8. Dead Flag Production (Cmp/Test whose flags are never consumed)
    9. Slicing Unobservable (ops with no dataflow path to observable sinks)
*)

open Stack_ir

(** The precise causal reason why an instruction or sequence is dead *)
type dead_reason =
  | Dead_write_unreferenced of { slot : int }
      (** Context slot is written but never read anywhere in the program *)
  | Dead_write_overwritten of { slot : int; next_write_pos : int }
      (** Context slot is overwritten within the block before any intervening read *)
  | Stack_pop_to_dead_slot of { slot : int; push_op : string }
      (** A value pushed to the stack is immediately popped into a dead slot *)
  | Structural_identity of { pattern : string; length : int }
      (** Self-canceling structural identity sequence (e.g. Swap; Swap, Rot*4) *)
  | Algebraic_zero_knot of { formula : string }
      (** Arithmetic zero or identity element with no net effect on stack value *)
  | Redundant_sub_zero_cmp
      (** CFF comparison idiom: Sub followed by PushImm 0L; Cmp *)
  | Balance_drain_orphan of { slot : int }
      (** Stack-draining PopReg inserted by Stack_balance_pass with no downstream consumer *)
  | Unreachable_block of { block_id : int; label : string }
      (** Block has zero CFG predecessors and is not the entry block *)
  | Dead_flag_production of { op_name : string }
      (** Cmp/Test or flag producer whose flags are never tested before overwrite *)
  | Slicing_unobservable of { op_name : string }
      (** Instruction has no transitive dependency reaching an observable I/O or control sink *)

(** A classified dead instruction with exact location and remediation advice *)
type dead_instruction = {
  block_id : int;
  pos : int;
  op : stack_op;
  reason : dead_reason;
  category : string;
  culprit_phase_hint : string;
  remediation_hint : string;
}

(** Summary statistics of dead code causality *)
type causality_summary = {
  total_ops : int;
  dead_ops_count : int;
  dead_ops_ratio : float;
  by_category : (string * int) list;
  by_phase_hint : (string * int) list;
  top_dead_slots : (int * int) list;
  unreachable_blocks : int list;
}

(** Complete diagnostic report for a single program *)
type program_diagnosis = {
  dead_instructions : dead_instruction list;
  summary : causality_summary;
}

(** Phase-by-phase causality progression *)
type phase_diff = {
  phase_name : string;
  total_ops : int;
  dead_count : int;
  dead_ratio : float;
  new_dead_ops : dead_instruction list;
  culprit_distribution : (string * int) list;
}

(** Analyzes a single program and diagnoses all dead code and its root causes *)
val analyze_program : ?trace_slicing:bool -> program -> program_diagnosis

(** Analyzes an individual block given the set of globally read context slots *)
val analyze_block : global_reads:(int, unit) Hashtbl.t -> block -> dead_instruction list

(** Traces the emergence of dead code across pipeline phases *)
val diagnose_pipeline : (string * program) list -> phase_diff list

(** Returns a human-readable formatted report with causality breakdown *)
val format_diagnosis_report : ?verbose:bool -> program_diagnosis -> string

(** Returns a human-readable diff report showing which phase introduced dead code *)
val format_pipeline_diff : (string * program) list -> string
