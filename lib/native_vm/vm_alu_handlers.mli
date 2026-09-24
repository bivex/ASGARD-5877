val emit_probes : Buffer.t -> enable_timing_probes:bool -> unit

val emit_alu_handlers :
  Buffer.t ->
  rng:Random.State.t ->
  enable_egraph_expansion:bool ->
  ?enable_ephemeral_jit:bool ->
  unit ->
  unit
