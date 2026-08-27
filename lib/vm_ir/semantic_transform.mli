(** Semantic Diversification Transformer.
    Performs verifiable equivalent algebraic rewrites and expression expansions
    to maximize Tier-5 semantic divergence while preserving exact runtime output. *)

val transform_block : rng:Random.State.t -> Ir.basic_block -> Ir.basic_block
val transform_func : seed:Seed.t -> Ir.func -> Ir.func
