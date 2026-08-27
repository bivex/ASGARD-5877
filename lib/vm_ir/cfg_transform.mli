(** Control Flow Graph (CFG) Diversification Transformer.
    Performs block splitting, topological reordering, and dummy block insertion
    to maximize Tier-4 structural diversity. *)

val transform : seed:Seed.t -> Ir.func -> Ir.func
