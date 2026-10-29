(** Pass Verification & Provenance Engine for ASGARD-5877
    ─────────────────────────────────────────────────────
    Provides multi-level compilation reporting, pass provenance tracking,
    independent semantic verification, and honest pass lifecycle classification
    aligned with industrial VM-protector and verification pipeline standards.
*)

open Stack_ir
open Native_vm

type pass_status =
  | Verified
  | Applied
  | Partial of string
  | Skipped of string
  | Disabled of string

val status_to_string : pass_status -> string
val status_tag : pass_status -> string
val is_active : pass_status -> bool

type legality_checks = {
  bit_width_preservation : bool;
  signedness_preservation : bool;
  overflow_semantics : bool;
  flag_semantics : bool;
}

val default_legality : legality_checks

type pass_record = {
  name : string;
  phase : string;
  status : pass_status;
  seed : int64 option;
  input_ops : int;
  output_ops : int;
  input_blocks : int;
  output_blocks : int;
  input_hash : int64;
  output_hash : int64;
  candidates : int;
  rewritten : int;
  rejected : int;
  legality : legality_checks;
  invariants_passed : bool;
  duration_ms : float;
  details : string;
}

type provenance_tracker

val create_tracker : unit -> provenance_tracker

val record_pass :
  provenance_tracker ->
  name:string ->
  phase:string ->
  status:pass_status ->
  ?seed:int64 ->
  ?prog_before:program ->
  ?prog_after:program ->
  ?candidates:int ->
  ?rewritten:int ->
  ?rejected:int ->
  ?legality:legality_checks ->
  ?invariants_passed:bool ->
  ?duration_ms:float ->
  ?details:string ->
  unit ->
  unit

val get_records : provenance_tracker -> pass_record list

val hash_program : program -> int64
val count_ops : program -> int
val count_blocks : program -> int

type semantic_check = {
  name : string;
  passed : bool;
  details : string;
}

type semantic_verification_report = {
  checks : semantic_check list;
  all_passed : bool;
  differential_trials : int;
  differential_mismatches : int;
  overall_status : string;
}

val run_semantic_verification :
  ?initial_ir:Vm_ir.Ir.func ->
  ?differential_trials:int ->
  ?differential_mismatches:int ->
  program ->
  semantic_verification_report

type drs_breakdown = {
  cfg_score : float;
  arith_score : float;
  isa_score : float;
  integrity_score : float;
  total_score : float;
}

val calculate_drs_breakdown :
  native_cfg:Protection_config.t ->
  prog:program ->
  enc:Stack_encoder.encrypted_bytecode ->
  real_ops:int ->
  real_blocks:int ->
  drs_breakdown

type pipeline_summary = {
  target_arch : string;
  backend : string;
  host_os : string;
  output_format : string;
  build_mode : string;
  source_funcs : int;
  lifted_funcs : int;
  vm_ir_blocks : int;
  unsupported_instructions : int;
  semantic_coverage_pct : float;
  passes_configured : int;
  passes_applied : int;
  passes_verified : int;
  passes_partial : int;
  passes_skipped : int;
  passes_disabled : int;
  ir_blocks : int;
  lowered_stack_blocks : int;
  final_cfg_blocks : int;
  real_ops : int;
  total_ops : int;
  exact_bytecode_bytes : int;
  aligned_bytecode_bytes : int;
  bytecode_words : int;
  padding_bytes : int;
  shannon_entropy : float;
  drs : drs_breakdown;
  pass_records : pass_record list;
  verification : semantic_verification_report;
  unwind_audit : string option;
  watermark_info : string option;
  functional_tests : (string * bool) list;
  compile_time_ms : float;
}

val format_compiler_report : pipeline_summary -> string

val finalize_report :
  ?unwind_audit:string ->
  ?watermark:string ->
  ?functional_tests:(string * bool) list ->
  ?output_target:string ->
  string ->
  string
