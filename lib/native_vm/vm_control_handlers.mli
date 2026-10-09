val emit_control_handlers :
  Buffer.t ->
  ?rng:Random.State.t ->
  enable_nanomites:bool ->
  enable_running_key:bool ->
  ?enable_address_bound:bool ->
  unit ->
  unit

val emit_super_operators : ?rng:Random.State.t -> Buffer.t -> unit
