(** DAG-based Instruction Scheduler for Basic Blocks.
    Topologically schedules independent instructions within basic blocks
    using randomized priority queues driven by the metamorphic RNG.
    Preserves all RAW, WAR, WAW, memory, flag, and control dependencies. *)

val schedule_block : rng:Random.State.t -> Ir.basic_block -> Ir.basic_block

val transform : rng:Random.State.t -> Ir.func -> Ir.func
