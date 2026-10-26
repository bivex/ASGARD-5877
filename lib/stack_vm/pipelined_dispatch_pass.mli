(** Phase 8: Pipelined Stage Dispatch Pass (Stage Relocation & Decoupled
    Execution).  See [docs/Pipelined_stage_dispatch.md]. *)

open Stack_ir

type pipelined_config = {
  enabled     : bool;
  chaff_slots : int;
  seed        : int64;
}

val default_pipelined_config : int64 -> pipelined_config

type dispatch_plan = {
  chaff_slot_base    : int;
  chaff_slot_count   : int;
  chaff_salt         : int64;
  (** Per-build affine table mask [K(i) = (i * mask_mult) ^ mask_add];
      each epilogue embeds its own compile-time [K(i)] so identical-tail
      merging by the C compiler is impossible. *)
  mask_mult          : int64;
  mask_add           : int64;
  ctx_slots_required : int;
}

(** Normalize a requested chaff slot count to a power of two in [1; 16]. *)
val normalize_chaff_slots : int -> int

(** Per-build Stage-2 slot-hash salt derived from the pass seed. *)
val derive_chaff_salt : int64 -> int64

(** Derive the chaff plan for a finalized program; [None] when disabled. *)
val plan_dispatch : pipelined_config -> program -> dispatch_plan option

(** Audit a plan's soundness invariants against a program. *)
val check_plan_invariants : program -> dispatch_plan -> unit

(** Compile-time mask literal for one opcode's epilogue; agrees with the
    runtime formula [(op * mask_mult) ^ mask_add] used by the table init
    and the entry priming. *)
val slot_mask : dispatch_plan -> int -> int64

val pipelined_stats : dispatch_plan option -> string
