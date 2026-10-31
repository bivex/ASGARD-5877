(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    Implementation of EH metadata structures and ABI conformance validation. *)

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

let is_non_volatile_reg reg =
  let r = String.lowercase_ascii reg in
  match r with
  | "rbp" | "ebp" | "rsp" | "esp" | "rbx" | "r12" | "r13" | "r14" | "r15" -> true
  | _ -> false

let validate_abi_shadow_rules (ops : unwind_op list) : (unit, abi_constraint_error) result =
  if ops = [] then Error EmptyUnwindOps
  else
    let rec check_ops total_alloc = function
      | [] ->
          if total_alloc <= 0 || total_alloc mod 16 <> 0 then
            Error (UnalignedStackAllocation total_alloc)
          else
            Ok ()
      | AllocStack sz :: rest ->
          if sz <= 0 || sz mod 16 <> 0 then
            Error (UnalignedStackAllocation sz)
          else
            check_ops (total_alloc + sz) rest
      | PushReg reg :: rest ->
          (* Disallow pushing frame pointer / stack pointer in synthetic shadow codes *)
          if is_non_volatile_reg reg then
            Error (ClobberedNonVolatileReg reg)
          else
            check_ops (total_alloc + 8) rest
      | SetFramePointer (reg, off) :: _ ->
          if is_non_volatile_reg reg then
            Error (ClobberedNonVolatileReg reg)
          else if off mod 16 <> 0 then
            Error (InvalidFrameOffset off)
          else
            Error (ClobberedNonVolatileReg reg) (* Shadow codes must avoid setting frame pointers *)
      | SaveReg (reg, off) :: _ ->
          if is_non_volatile_reg reg then
            Error (ClobberedNonVolatileReg reg)
          else if off mod 8 <> 0 then
            Error (InvalidFrameOffset off)
          else
            Error (ClobberedNonVolatileReg reg)
    in
    check_ops 0 ops

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

let error_to_string = function
  | TamperDetected -> "TamperDetected: Authentication tag verification failed"
  | DeserializationError msg -> "DeserializationError: " ^ msg
  | AbiConstraintViolation msg -> "AbiConstraintViolation: " ^ msg
  | ScopeNotFound pc -> Printf.sprintf "ScopeNotFound: No catch handler for PC 0x%LX" pc
