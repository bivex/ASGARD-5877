(** Strategy-Based Register Allocation Engine.
    Allocates and maps virtual register pools under distinct allocation strategies
    (LinearScan, Randomized, PressureAware) to drive Tier-3/Tier-4 diversity. *)

type strategy =
  | LinearScan
  | Randomized
  | PressureAware

val strategy_to_string : strategy -> string
val allocate : strategy:strategy -> seed:Seed.t -> Ir.func -> Ir.func
