val emit_handlers_hpp :
  Buffer.t ->
  rng:Random.State.t ->
  enable_running_key:bool ->
  enable_address_bound:bool ->
  enable_timing_probes:bool ->
  enable_nanomites:bool ->
  enable_egraph_expansion:bool ->
  ?enable_ephemeral_jit:bool ->
  unit ->
  unit
