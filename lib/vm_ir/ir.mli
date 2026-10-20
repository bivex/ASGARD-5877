open Register
open Flags

type alu_op =
  | Add
  | Adc
  | Sub
  | Sbb
  | And
  | Or
  | Xor
  | Shl
  | Shr
  | Sar
  | Rol
  | Ror
  | Mul
  | Imul
  | Div
  | Idiv
  | Mulh
  | Imulh

type unary_op =
  | Not
  | Neg
  | Inc
  | Dec
  | Bswap
  | Clz
  | Ctz
  | Popcnt
  | Rbit

type segment = FS | GS

type mem_ref = {
  base : Register.t option;
  index : (Register.t * int) option; (** (index_reg, scale 1|2|4|8) *)
  disp : int64;
  width : width;
  is_signed : bool;
  segment : segment option;
}

type operand =
  | Reg of Register.t
  | Imm of int64
  | Mem of mem_ref

type target =
  | Label of string
  | BlockId of int
  | TargetImm of int64
  | TargetReg of Register.t

type fp_binop = Fadd | Fsub | Fmul | Fdiv | Fsqrt
type fp_conv = Fcvtzs | Scvtf | Fcvtzu | Ucvtf | Fcvt
type vec_op =
  | Vadd
  | Vsub
  | Vmul
  | Vand
  | Vor
  | Vxor
  | Vsll
  | Vsrl
  | Vsra
  | Vcmpeq
  | Vcmpgt
  | Vmin
  | Vmax
  | Vminu
  | Vmaxu
  | Vabs
  | Vandn
  | Vunpckl
  | Vunpckh
  | Vpackss
  | Vpackus
  | Vshuf
  | Vblend
  | Vuzp1
  | Vuzp2
  | Vtrn1
  | Vtrn2
  | Vtbl
  | Vtbx
  | Vdiv
  | Vrem
  | Vdivu
  | Vremu
  | Vcmpne
  | Vcmple
  | Vcmpltu
  | Vcmpleu
type vec_elem = VInt | VF32 | VF64

(** The x86 SHA extensions (SHA-NI).  Every instruction works on the four
    32-bit words of a 128-bit vector register. *)
type sha_op =
  | Sha1rnds4
  | Sha1nexte
  | Sha1msg1
  | Sha1msg2
  | Sha256rnds2
  | Sha256msg1
  | Sha256msg2

(** The x86 AES extensions (AES-NI). *)
type aes_op =
  | Aesenc
  | Aesenclast
  | Aesdec
  | Aesdeclast
  | Aesimc
  | Aeskeygenassist
type atomic_op = AtLoad | AtStore | AtCas | AtAdd | AtSwp

type mem_order = SeqCst | Acquire | Release | AcqRel | Relaxed

type fpu_binop =
  | FpAdd
  | FpSub
  | FpSubR
  | FpMul
  | FpDiv
  | FpDivR

type fpu_unary_op =
  | FpChs
  | FpAbs
  | FpSqrt

type fpu_const =
  | FpLd0
  | FpLd1
  | FpLdPi
  | FpLdL2e
  | FpLdL2t
  | FpLdLg2
  | FpLdLn2

type fpu_trans =
  | FpSin
  | FpCos
  | FpSinCos
  | FpTan
  | FpATan
  | FpYl2x
  | FpYl2xp1
  | Fp2xm1

type fpu_instr =
  | FpPush_mem of mem_ref
  | FpPush_int of mem_ref
  | FpPush_st of int
  | FpStore_mem of { addr : mem_ref; pop : bool }
  | FpStore_int of { addr : mem_ref; pop : bool }
  | FpStore_st of { idx : int; pop : bool }
  | FpBinop of { op : fpu_binop; dst : int; src : int; pop : bool }
  | FpBinop_mem of { op : fpu_binop; src : mem_ref }
  | FpCompare of { idx : int; pop_count : int }
  | FpCompare_i of { idx : int; pop : bool }
  | FpCompare_mem of { src : mem_ref; pop : bool }
  | FpUnary of fpu_unary_op
  | FpConst of fpu_const
  | FpTrans of fpu_trans
  | FpStatus_to_ax

type instr =
  | Nop
  | Mov of { dst : operand; src : operand }
  | Lea of { dst : Register.t; addr : mem_ref }
  | Push of operand
  | Pop of operand
  | Xchg of operand * operand
  | Alu of { op : alu_op; dst : Register.t; src1 : operand; src2 : operand; set_flags : bool }
  | Unary of { op : unary_op; dst : Register.t; src : operand; set_flags : bool }
  | Cmp of { src1 : operand; src2 : operand }
  | Ccmp of { cond : condition; src1 : operand; src2 : operand; nzcv : int }
  | Ccmn of { cond : condition; src1 : operand; src2 : operand; nzcv : int }
  | Test of { src1 : operand; src2 : operand }
  | Jmp of target
  | Jcc of { cond : condition; target_true : target; target_false : target }
  | Call of target
  | Ret
  | Setcc of { cond : condition; dst : operand }
  | Cmov of { cond : condition; dst : Register.t; src : operand }
  | Vm_enter
  | Vm_exit
  | Trap of string
  | Bridge_to_flow of int64
  | Bridge_to_math of int64
  | Load_symbol of { dst : Register.t; sym : string; addend : int64 }
  | Fp_binop of { op : fp_binop; dst : int; src1 : int; src2 : int }
  | Fp_cmp of { src1 : int; src2 : int; is_32 : bool }
  | Fp_conv of { op : fp_conv; dst : Register.t; src : Register.t }
  | Vec_mov of { dst : int; src : int; bits : int }
  | Vec_binop of { op : vec_op; elem : vec_elem; dst : int; src1 : int; src2 : int; bits : int; lane_bits : int }
  | Vec_sha of { op : sha_op; dst : int; src1 : int; src2 : int; src3 : int; imm : int64; bits : int }
  | Vec_pclmul of { dst : int; src1 : int; src2 : int; imm : int64; bits : int }
  | Vec_aes of { op : aes_op; dst : int; src1 : int; src2 : int; imm : int64; bits : int }
  | Vec_shuf2 of { dst : int; src1 : int; src2 : int; imm : int64; bits : int; lane_bits : int }
  | Read_ssp of { dst : Register.t }
  | Inc_ssp of { width : width }
  | Vec_imm of { op : vec_op; elem : vec_elem; dst : int; src : int; imm : int64; bits : int; lane_bits : int }
  | Vec_load of { dst : int; addr : mem_ref; bits : int }
  | Vec_store of { src : int; addr : mem_ref; bits : int }
  | Vec_clear_upper of int
  | Vec_zero_upper
  | Vec_splat of { dst : int; src : Register.t; bits : int; lane_bits : int }
  | Vec_ext of { dst : int; src1 : int; src2 : int; imm : int; bits : int }
  | Pmovmskb of { dst : Register.t; src : int; bits : int; lane_bits : int }
  | Atomic_mem of { op : atomic_op; dst : Register.t; addr : Register.t; src : Register.t; imm : int64 }
  | Fence of mem_order
  | Get_flags of Register.t
  | Set_flags of operand
  | Cpuid
  | Fpu of fpu_instr

type basic_block = {
  id : int;
  label : string;
  instrs : instr list;
}

type cfg = {
  entry_id : int;
  blocks : (int, basic_block) Hashtbl.t;
}

type func = {
  name : string;
  cfg : cfg;
}

val alu_op_to_string : alu_op -> string
val unary_op_to_string : unary_op -> string
val mem_ref_to_string : mem_ref -> string
val operand_to_string : operand -> string
val target_to_string : target -> string
val instr_to_string : instr -> string
val block_to_string : basic_block -> string
val func_to_string : func -> string

val make_block : id:int -> label:string -> instrs:instr list -> basic_block
val make_func : name:string -> entry_id:int -> blocks:basic_block list -> func
val get_block : cfg -> int -> basic_block option
val successors : basic_block -> target list
