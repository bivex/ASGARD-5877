(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    ABI-Compliant Exception Handling Metadata Model and Shadowing Specification.
    Formalizes global unwinding opcodes, language-specific data (LSData),
    and ABI conformance constraints for placeholder unwinding records. *)

type unwind_op =
  | AllocStack of int
  | PushReg of string
  | SetFramePointer of string * int
  | SaveReg of string * int

type abi_constraint_error =
  | UnalignedStackAllocation of int
  | ClobberedNonVolatileReg of string
  | InvalidFrameOffset of int
  | EmptyUnwindOps

val validate_abi_shadow_rules : unwind_op list -> (unit, abi_constraint_error) result
(** Validates that a set of shadow unwind codes complies strictly with ABI constraints:
    1. Total stack allocation is a positive multiple of 16 bytes.
    2. Does NOT clobber or restore critical non-volatile frame registers (e.g., RBP).
    3. Contains only safe placeholder unwinding primitives. *)

type try_scope = {
  scope_id : int;
  start_pc : int64;
  end_pc : int64;
  landing_pad_pc : int64;
  catch_type_tag : int32;
}

type destructor_entry = {
  obj_id : int;
  live_start_pc : int64;
  live_end_pc : int64;
  dtor_pc : int64;
}

type lsdata_record = {
  scopes : try_scope list;
  dtors : destructor_entry list;
}

type original_metadata = {
  func_name : string;
  code_start_pc : int64;
  code_size : int;
  unwind_ops : unwind_op list;
  lsdata : lsdata_record;
}

type shadow_unwind_record = {
  shadow_alloc_size : int;
  shadow_ops : unwind_op list;
  interceptor_symbol : string;
}

type protected_container = {
  func_name : string;
  code_start_pc : int64;
  code_size : int;
  shadow : shadow_unwind_record;
  encrypted_metadata_blob : bytes;
  auth_tag : bytes;
}

type tech_2601_error =
  | TamperDetected
  | DeserializationError of string
  | AbiConstraintViolation of string
  | ScopeNotFound of int64

val error_to_string : tech_2601_error -> string
