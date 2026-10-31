(** Branchless VIP Arithmetic & Flag Elimination (Step 1 Tier-4+):
    Turns conditional jumps (JZ, JNZ, JB, JAE, JL, JGE) into pure arithmetic
    over the Virtual Instruction Pointer (VIP) without a single CMP/TEST/JCC instruction. *)

type branch_cond =
  | CondEq   (** x == y (ZF == 1) *)
  | CondNe   (** x != y (ZF == 0) *)
  | CondUlt  (** x < y unsigned (CF == 1) *)
  | CondUge  (** x >= y unsigned (CF == 0) *)
  | CondSlt  (** x < y signed (SF != OF) *)
  | CondSge  (** x >= y signed (SF == OF) *)

(** Arithmetic indicator is_zero(d) \in {0, 1} without branching.
    Supports 5 algebraically equivalent metamorphic formulations to defeat static n-gram scanners:
      • v0: 1 - ((d | -d) lsr 63)   (two's complement sign-bit)
      • v1: ((~d) & (d - 1)) lsr 63 (Warren borrow from zero)
      • v2: 1 - (((d ^ -d) + (d & -d)) lsr 63) (MBA OR decomposition)
      • v3: (~(d | -d) lsr 63) & 1  (De Morgan sign extraction)
      • v4: ((d | -d) lsr 63) ^ 1   (Boolean XOR inversion) *)
val eval_is_zero_branchless : ?variant:int -> int64 -> int64

(** Evaluation of the boolean jump condition (returns 1L if the condition is true, 0L if false)
    exclusively via bit shifts and arithmetic in the ring Z_{2^64} *)
val eval_cond_branchless : branch_cond -> int64 -> int64 -> int64

(** Computation of the next VIP without branching:
    next_vip = fallthrough_vip + cond_bit * (target_vip - fallthrough_vip) *)
val compute_next_vip_branchless :
  cond:branch_cond -> lhs:int64 -> rhs:int64 ->
  target_vip:int64 -> fallthrough_vip:int64 -> int64

(** Simultaneous update of the VIP and the rolling key (Rolling Key) without branching:
    on the taken branch key_delta_taken is added, on the false one — key_delta_fallthrough *)
val compute_vip_and_key_branchless :
  cond:branch_cond -> lhs:int64 -> rhs:int64 ->
  target_vip:int64 -> fallthrough_vip:int64 ->
  base_key:int64 -> key_delta_taken:int64 -> key_delta_fallthrough:int64 ->
  int64 * int64

(** Construction of a typed C++20 AST for the Branchless VIP dispatcher *)
val build_branchless_vip_ast : ?default_variant:int -> unit -> Cpp_codegen.Cpp_ast.top_decl list

(** Generation of a C++20 header for the Branchless VIP dispatcher *)
val emit_branchless_vip_cpp_header : unit -> string
