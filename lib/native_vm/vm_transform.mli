(** Vm_transform — Instruction canonicalization, junk injection, and fusion transforms. *)

open Vm_ir

val reg_to_index : Register.t -> int
val cond_to_code : Flags.condition -> int

type raw_op_kind =
  | OP_NOP
  | OP_MOV_RR
  | OP_MOV_RI
  | OP_MOV_HIGH
  | OP_ADD_RR
  | OP_ADD_RI
  | OP_SUB_RR
  | OP_SUB_RI
  | OP_NEG_RR
  | OP_NOT_RR
  | OP_IMUL_RR
  | OP_IMUL_RI
  | OP_XOR_RR
  | OP_XOR_RI
  | OP_AND_RR
  | OP_AND_RI
  | OP_OR_RR
  | OP_OR_RI
  | OP_ROL_RI
  | OP_ROR_RI
  | OP_SHL_RI
  | OP_SHR_RI
  | OP_SAR_RI
  | OP_DIV_RR
  | OP_IDIV_RR
  | OP_CMP_RR
  | OP_CMP_RI
  | OP_PUSH_R
  | OP_POP_R
  | OP_JMP
  | OP_JCC
  | OP_CMOV
  | OP_SETCC
  | OP_CALL
  | OP_IJMP_R
  | OP_ICALL_R
  | OP_RET
  | OP_EXIT
  | OP_FUSED_MOV_ADD_RRI
  | OP_FUSED_ADD_IMUL_RRI
  | OP_FUSED_ADD_XOR_RRI
  | OP_FUSED_SUB_XOR_RRI
  | OP_FUSED_XOR_ADD_RRI
  | OP_FUSED_CMP_CMOV
  | OP_BRIDGE_TO_FLOW
  | OP_BRIDGE_TO_MATH
  | OP_VADD_VV
  | OP_VSUB_VV
  | OP_VMUL_VV
  | OP_VXOR_VV
  | OP_VEC_MOV
  | OP_VEC_BINOP
  | OP_VEC_LOAD
  | OP_VEC_STORE
  | OP_CALL_EXTERN
  | OP_LOAD_64
  | OP_LOAD_32
  | OP_LOAD_16
  | OP_LOAD_8
  | OP_LOAD_S32
  | OP_LOAD_S16
  | OP_LOAD_S8
  | OP_STORE_64
  | OP_STORE_32
  | OP_STORE_16
  | OP_STORE_8
  | OP_RESOLVE_SYM
  | OP_FADD_DD
  | OP_FSUB_DD
  | OP_FMUL_DD
  | OP_FDIV_DD
  | OP_FSQRT_D
  | OP_FCMP_DD
  | OP_FCVTZS
  | OP_SCVTF
  | OP_ATOMIC_LOAD
  | OP_ATOMIC_STORE
  | OP_ATOMIC_CAS
  | OP_ATOMIC_ADD
  | OP_ATOMIC_SWP
  | OP_BSWAP_RR
  | OP_CLZ_RR
  | OP_CTZ_RR
  | OP_POPCNT_RR
  | OP_RBIT_RR
  | OP_MOV_VR
  | OP_MOV_RV
  | OP_FCSEL_VV
  | OP_MULH_RR
  | OP_IMULH_RR
  | OP_ADC_RR
  | OP_ADC_RI
  | OP_SBB_RR
  | OP_SBB_RI
  | OP_CCMP_RR
  | OP_CCMP_RI
  | OP_CCMN_RR
  | OP_CCMN_RI
  | OP_GET_FLAGS_R
  | OP_SET_FLAGS_R
  | OP_VEC_IMM
  | OP_VEC_CLEAR_UPPER
  | OP_VEC_ZERO_UPPER
  | OP_PMOVMSKB
  | OP_VEC_SPLAT
  | OP_FCVTZU
  | OP_UCVTF
  | OP_FCVT
  | OP_VEC_EXT

val all_op_kinds : raw_op_kind list
val op_kind_to_handler_name : raw_op_kind -> string

type fused_op =
  | Raw of Ir.instr
  | Fused_Mov_Add of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Add_Imul of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Add_Xor of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Sub_Xor of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Xor_Add of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Cmp_Cmov of {
      cmp_dst : Register.t;
      cmp_imm : int64;
      cond : Flags.condition;
      cmov_dst : Register.t;
      cmov_src : Register.t;
    }

val extract_real_regs : Ir.instr list -> Register.t list
val generate_junk_instrs : Random.State.t -> real_regs:Register.t list -> Ir.instr list
val inject_junk_instructions : rng:Random.State.t -> Ir.instr list -> Ir.instr list
val is_commutative_alu_op : Ir.alu_op -> bool
val pick_scratch_reg : Register.t -> Register.t -> Register.t
val canonicalize_instr : Ir.instr -> Ir.instr list
val canonicalize_3addr_alu : Ir.instr list -> Ir.instr list
val fuse_block_instructions : Ir.instr list -> fused_op list
