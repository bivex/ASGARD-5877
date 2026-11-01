(** Control Flow Graph (CFG) Diversification Transformer.
    Performs block splitting, decoy block injection, and topological reordering
    to maximize Tier-4 structural diversity. *)

val transform : seed:Seed.t -> Ir.func -> Ir.func
