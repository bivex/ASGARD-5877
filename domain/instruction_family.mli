(** Instruction Family Value Object: correlated template of instruction variants. *)

type t = private {
  mnemonic_base : string;
  klass : Instruction_class.t;
  weight : float;
  formats : Types.Instruction_format.t list;
  binary_op : Types.Binary_op.t option;
  unary_op : Types.Unary_op.t option;
  element_kind : Types.Element_kind.t;
  is_widening : bool;
}

(** [make] constructs an instruction family, validating that:
    - [mnemonic_base] starts with 'v' and has no underscores;
    - either [binary_op] or [unary_op] is set (not both, not neither);
    - [formats] is non-empty and has no duplicates;
    - [is_widening] matches [(klass == Widening)];
    - [weight > 0.0]. *)
val make :
  mnemonic_base:string ->
  klass:Instruction_class.t ->
  weight:float ->
  formats:Types.Instruction_format.t list ->
  ?binary_op:Types.Binary_op.t ->
  ?unary_op:Types.Unary_op.t ->
  ?element_kind:Types.Element_kind.t ->
  ?is_widening:bool ->
  unit ->
  (t, Errors.t) result
