(** Generation Profile Value Object: class-frequency priors for V-ISA synthesis. *)

type t = private {
  name : string;
  class_weights : (Instruction_class.t * float) list;
}

(** [make ~name ~class_weights] creates a new profile after validating that:
    - [name] is non-empty;
    - all classes in [class_weights] are supported;
    - there are no duplicate classes;
    - all weights are non-negative;
    - at least one class has weight > 0.0. *)
val make :
  name:string ->
  class_weights:(Instruction_class.t * float) list ->
  (t, Errors.t) result

(** Classes eligible for sampling (positive weight). *)
val enabled_classes : t -> Instruction_class.t list

(** Weight of a class (0.0 when absent). *)
val weight_for : t -> Instruction_class.t -> float

(** Predefined RVV-like class mix: ARITH 55%, WIDENING 18%, COMPARE 15%, SATURATING 12%. *)
val rvv_like : t

(** Predefined uniform class mix: equal 25% weights across all 4 supported classes. *)
val uniform : t
