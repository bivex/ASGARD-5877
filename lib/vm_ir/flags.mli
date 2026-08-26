open Register

type flag =
  | CF  (** Carry Flag *)
  | ZF  (** Zero Flag *)
  | SF  (** Sign Flag *)
  | OF  (** Overflow Flag *)
  | PF  (** Parity Flag *)
  | AF  (** Auxiliary Carry Flag *)

type condition =
  | E      (** Equal / Zero (ZF = 1) *)
  | NE     (** Not Equal / Not Zero (ZF = 0) *)
  | B      (** Below / Carry (CF = 1) *)
  | AE     (** Above or Equal / No Carry (CF = 0) *)
  | BE     (** Below or Equal (CF = 1 or ZF = 1) *)
  | A      (** Above (CF = 0 and ZF = 0) *)
  | S      (** Sign / Negative (SF = 1) *)
  | NS     (** No Sign / Positive (SF = 0) *)
  | P      (** Parity / Parity Even (PF = 1) *)
  | NP     (** No Parity / Parity Odd (PF = 0) *)
  | L      (** Less (SF != OF) *)
  | GE     (** Greater or Equal (SF == OF) *)
  | LE     (** Less or Equal (ZF = 1 or SF != OF) *)
  | G      (** Greater (ZF = 0 and SF == OF) *)
  | O      (** Overflow (OF = 1) *)
  | NO     (** No Overflow (OF = 0) *)
  | ALWAYS (** Unconditional *)

type cc_op =
  | CC_OP_RAW of int64
  | CC_OP_ADD of { src1 : int64; src2 : int64; dst : int64; width : width }
  | CC_OP_ADC of { src1 : int64; src2 : int64; carry_in : bool; dst : int64; width : width }
  | CC_OP_SUB of { src1 : int64; src2 : int64; dst : int64; width : width }
  | CC_OP_SBB of { src1 : int64; src2 : int64; borrow_in : bool; dst : int64; width : width }
  | CC_OP_LOGIC of { dst : int64; width : width }
  | CC_OP_INC of { old_dst : int64; new_dst : int64; prev_cf : bool; width : width }
  | CC_OP_DEC of { old_dst : int64; new_dst : int64; prev_cf : bool; width : width }

val empty_flags : cc_op

val compute_cf : cc_op -> bool
val compute_zf : cc_op -> bool
val compute_sf : cc_op -> bool
val compute_of : cc_op -> bool
val compute_pf : cc_op -> bool
val compute_af : cc_op -> bool

val compute_flag : cc_op -> flag -> bool
val evaluate_condition : cc_op -> condition -> bool

val materialize_rflags : cc_op -> int64
val of_rflags : int64 -> cc_op

val condition_to_string : condition -> string
val condition_of_string : string -> (condition, string) result
val condition_negate : condition -> condition
