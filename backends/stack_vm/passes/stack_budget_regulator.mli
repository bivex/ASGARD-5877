(* lib/stack_vm/stack_budget_regulator.mli
   ASGARD-5877: Dynamic budget regulator for Stack-VM pass pipeline *)

(** Stack-VM dynamic budget regulator: monitors AST size growth and
    dynamically throttles pass rates when the code footprint approaches
    the target size budget, preventing multiplicative pass explosion. *)

type pass_kind =
  | ExpansionPass   (** Ghost padding, avid operands, spaghetti splitting, chord expander *)
  | StructuralPass  (** CFF, finite field, dual rail, polymorphic handlers *)
  | EssentialPass   (** Stack balance, provenance anchors, ABI exits *)

type t

val create : budget_kb:int option -> t
(** [create ~budget_kb] initializes the regulator with an optional size budget in KB.
    When [budget_kb = None] or [<= 0], no throttling is applied (scale = 1.0). *)

val estimate_program_bytes : Stack_ir.program -> int
(** [estimate_program_bytes prog] calculates the approximate serialized bytecode footprint
    in bytes based on 64-bit opcode words and immediate payload extensions. *)

val throttle_rate :
  t ->
  pass_name:string ->
  kind:pass_kind ->
  nominal_rate:int ->
  prog:Stack_ir.program ->
  int * float
(** [throttle_rate reg ~pass_name ~kind ~nominal_rate ~prog] computes the dynamically
    adjusted integer rate [0..100] and the applied scale factor [0.0..1.0]. *)

val check_budget_headroom : t -> prog:Stack_ir.program -> float
(** [check_budget_headroom reg ~prog] returns the remaining budget ratio in [0.0..1.0].
    Returns 1.0 when no budget is configured. *)
