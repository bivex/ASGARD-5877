(** Phase 2a: Superoperator Fusion Pass
    ───────────────────────────────────
    Fuses recurring consecutive stack instruction sequences into specialized
    superoperators, collapsing multi-dispatch instruction sequences into single
    VM dispatches and diversifying the bytecode ISA on a per-build basis.

    Fused patterns:
      • [PushImm a; PushImm b; Add]       → [AddImmImm (a, b)]
      • [PushImm a; PushImm b; Sub]       → [SubImmImm (a, b)]
      • [PushReg r; PushImm c; Add]       → [AddRegImm (r, c)]
      • [PushImm c; PopReg r]             → [SetRegImm (r, c)]
      • [PushImm c; Add]                  → [AddImm c]
      • [PushImm c; Sub]                  → [SubImm c]

    Soundness invariants:
      • Net stack delta of each fused sequence is strictly identical to the
        original sequence.
      • Produced architectural flags are identical to the original arithmetic
        tail operation.
*)

open Stack_ir

type superop_config = {
  seed               : int64;
  fusion_rate        : int;   (** Probability (0–100) of fusing eligible sequences *)
  enable_add_imm     : bool;
  enable_sub_imm     : bool;
  enable_add_ii      : bool;
  enable_sub_ii      : bool;
  enable_set_reg_imm : bool;
  enable_add_reg_imm : bool;
}

val default_superop_config : int64 -> superop_config

type superop_stats = {
  initial_ops       : int;
  final_ops         : int;
  fused_ops         : int;
  add_imm_count     : int;
  sub_imm_count     : int;
  add_ii_count      : int;
  sub_ii_count      : int;
  set_reg_imm_count : int;
  add_reg_imm_count : int;
}

val apply_block : superop_config -> block -> block
val apply_program : superop_config -> program -> program
val superop_stats : program -> program -> superop_stats
