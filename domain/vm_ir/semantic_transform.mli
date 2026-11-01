(** Semantic Diversification Transformer.
    Performs verifiable equivalent algebraic rewrites, polynomial invariant blinding,
    modular inverse expansions in Z/2^64Z, and non-linear MBA transforms
    to maximize Tier-5 semantic divergence while preserving exact runtime output. *)

val mod_inv64 : int64 -> int64
val transform_block : rng:Random.State.t -> Ir.basic_block -> Ir.basic_block
val transform_func : seed:Seed.t -> Ir.func -> Ir.func
