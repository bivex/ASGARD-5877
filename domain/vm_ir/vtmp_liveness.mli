(** Liveness analysis for shadow/scratch registers (VTMP0..VTMP3).
    ARM64 lifting maps real GPRs (x14, x15, x16, x30) onto VTMP0..VTMP3,
    so these registers carry live values across long instruction sequences
    and basic block boundaries.  Passes that inject decoys, superoperators,
    or opaque predicates must verify that a candidate VTMP slot is dead at
    the point of mutation. *)

val all_vtmps : Register.t list

val canonical_vtmp : Register.t -> Register.t option

val is_vtmp : Register.t -> bool

val vtmp_mem : Register.t -> Register.t list -> bool

val vtmps_read_by_instr : Ir.instr -> Register.t list

val vtmps_referenced_by_instr : Ir.instr -> Register.t list

val vtmp_kills : Ir.instr -> Register.t list

val compute_block_liveness :
  Ir.instr array -> live_out:Register.t list -> Register.t list array

val compute_func_live_outs : Ir.func -> (int, Register.t list) Hashtbl.t
