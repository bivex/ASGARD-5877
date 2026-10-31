(** Super-Operator Synthesis and Decoy Interleaving Engine.
    Fuses micro-instruction pairs into compound forms and interleaves shadow register
    updates (VTMP0..VTMP3) to maximize conditional transition entropy H(Xt+1|Xt). *)

val fuse_and_interleave_block :
  rng:Random.State.t ->
  Ir.basic_block ->
  Ir.basic_block

val transform_func : seed:Seed.t -> Ir.func -> Ir.func
