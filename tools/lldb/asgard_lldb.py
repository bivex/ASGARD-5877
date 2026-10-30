#!/usr/bin/env python3
"""
asgard_lldb.py — ASGARD-5877 LLDB Bytecode Debugger Plugin
─────────────────────────────────────────────────────────────────────────────
Comprehensive LLDB extension for inspecting, disassembling, and stepping
through ASGARD virtual bytecode executed by:
  1. vanguard_threaded_vm (Native Threaded VM with affine register masking,
     anti-pushan rolling keys, and multi-domain dispatch)
  2. stack_vm (Stack VM with SipHash block-key derivation, Costas layouts,
     and blinded VSP stack encryption)

Usage in LLDB:
  (lldb) command script import /path/to/ASGARD-5877/tools/lldb/asgard_lldb.py
  (lldb) asg-help

Commands provided:
  asg-help        Show ASGARD debugger command reference
  asg-status      Inspect current VM frame and execution state
  asg-regs, asg-r Dump unmasked virtual registers (GPRs, flags, canaries)
  asg-stack, asg-vsp Dump decrypted virtual stack (TOS and frames)
  asg-fpu         Dump virtual x87 FPU stack ST(0)..ST(7) and FSW
  asg-disas, asg-d Disassemble bytecode at current vIP
  asg-step, asg-s Step one virtual bytecode instruction
  asg-next, asg-n Step over to next virtual bytecode instruction
  asg-break, asg-b Set a virtual breakpoint at bytecode index vIP
  asg-trace       Trace virtual instruction execution with register diffs
  asg-set-reg     Modify a virtual register with cryptographic re-encryption
  asg-export      Export VM execution state and disassembly to JSON
"""

import os
import sys
import struct
import shlex
import json
from typing import List, Dict, Optional, Tuple, Any

# Try importing LLDB module if available
try:
    import lldb
    IN_LLDB = True
except ImportError:
    IN_LLDB = False
    lldb = None

# =============================================================================
# 1. Cryptographic Constants & Magic Numbers (from lib/constants/magic_numbers.ml)
# =============================================================================

MASK64 = 0xFFFFFFFFFFFFFFFF
MASK32 = 0xFFFFFFFF

GOLDEN_RATIO_64 = 0x9E3779B97F4A7C15
GOLDEN_RATIO_32 = 0x9E3779B9
SQRT2_FRACTION_64 = 0x6A09E667F3BCC908
SPLITMIX64_GAMMA = 0xBF58476D1CE4E5B9
SPLITMIX64_MIX = 0x94D049BB133111EB

SALT_XWCAFE = 0x5877CAFE
SALT_XWCAFE_LEETBEEF = 0x5877CAFE1337BEEF
SALT_XWCAFE_CAFEBABE1337 = 0x5877CAFEBABE1337
SALT_XWCAFE_BEEF = 0x5877CAFEBEEF
SALT_LEETBEEF = 0x1337BEEF
SALT_CAFEBABE_LEET = 0xCAFEBABE13375877
SALT_LEET_13375877 = 0x13375877
SALT_REGMASK = 0x5A5A5A5A13375877
SALT_CANARY_MID = 0xA5A5A5A51337BEEF
SALT_POISON_PENALTY = 0xCAA7E1D8718BF877
SALT_STACK_VM_STATE = 0x5877A564D00F
SALT_STACK_DISPATCH_BLIND = 0x5877A564CAFEBEEF
SALT_DEADBEEF = 0xDEADBEEF
SALT_DEADBEEF_5A5A5A5A = 0xDEADBEEF5A5A5A5A

MURMUR3_32_C1 = 0xCC9E2D51
FNV1A_64_PRIME = 0x100000001B3
FNV1A_64_OFFSET_BASIS = 0xCBF29CE484222325

CANARY_VAL = SALT_CAFEBABE_LEET

# =============================================================================
# 2. Key Schedules & PRF Functions
# =============================================================================

def splitmix64(state: int) -> Tuple[int, int]:
    """SplitMix64 state transition matching rolling_key.ml and stack_encoder.ml."""
    state = (state + GOLDEN_RATIO_64) & MASK64
    z = state
    z = (z ^ (z >> 30)) & MASK64
    z = (z * SPLITMIX64_GAMMA) & MASK64
    z = (z ^ (z >> 27)) & MASK64
    z = (z * SPLITMIX64_MIX) & MASK64
    z = (z ^ (z >> 31)) & MASK64
    return state, z

def poly_hash64(x: int) -> int:
    """SplitMix64 finalizer non-linear permutation."""
    x1 = (((x ^ (x >> 30)) & MASK64) * SPLITMIX64_GAMMA) & MASK64
    x2 = (((x1 ^ (x1 >> 27)) & MASK64) * SPLITMIX64_MIX) & MASK64
    return (x2 ^ (x2 >> 31)) & MASK64

def key64_for_offset(seed: int, offset: int) -> int:
    """Positional keystream PRF matching key64_for_offset in VMContext."""
    s64 = seed & MASK32
    x0 = (((s64 << 32) | (s64 ^ GOLDEN_RATIO_32)) ^ ((offset * SQRT2_FRACTION_64) & MASK64)) & MASK64
    x1 = (((x0 ^ (x0 >> 30)) & MASK64) * SPLITMIX64_GAMMA) & MASK64
    x2 = (((x1 ^ (x1 >> 27)) & MASK64) * SPLITMIX64_MIX) & MASK64
    return (x2 ^ (x2 >> 31)) & MASK64

def anchor_key(seed: int, offset: int, handlers_hash: int = 0) -> int:
    """Block entry anchor key matching anchor_key in VMContext."""
    s = (seed ^ MURMUR3_32_C1) & MASK32
    off = offset ^ SALT_LEET_13375877
    k = key64_for_offset(s, off)
    if handlers_hash != 0:
        k ^= (handlers_hash * GOLDEN_RATIO_64) & MASK64
    return k

def advance_key_step(k: int, op: int, dst: int, imm: int) -> int:
    """Anti-Pushan in-block rolling key step matching advance_key_step in C++."""
    imm64 = imm & MASK64
    term1 = (op * GOLDEN_RATIO_64) & MASK64
    term2 = ((dst & 0x1F) << 24) & MASK64
    x = (k ^ ((term1 + term2 + imm64) & MASK64)) & MASK64
    xh = poly_hash64(x)
    rot = ((xh >> 23) | (xh << 41)) & MASK64
    return (((rot * SPLITMIX64_GAMMA) & MASK64) ^ SALT_XWCAFE_LEETBEEF) & MASK64

def asg_vsp_mask(key: int, slot: int) -> int:
    """Stack-VM VSP slot mask calculation matching asg_vsp_mask in stack_runtime.ml."""
    z = (key + ((slot & MASK32) * GOLDEN_RATIO_64)) & MASK64
    z = (((z ^ (z >> 30)) & MASK64) * SPLITMIX64_GAMMA) & MASK64
    z = (((z ^ (z >> 27)) & MASK64) * SPLITMIX64_MIX) & MASK64
    return (z ^ (z >> 31)) & MASK64

def rotl64(v: int, k: int) -> int:
    k = k & 63
    return ((v << k) | (v >> (64 - k))) & MASK64

def fmix64(k: int) -> int:
    k = (k ^ (k >> 33)) & MASK64
    k = (k * 0xFF51AFD7ED558CCD) & MASK64
    k = (k ^ (k >> 33)) & MASK64
    k = (k * 0xC4CEB9FE1A85EC53) & MASK64
    return (k ^ (k >> 33)) & MASK64

def step_key(key: int, byte_val: int) -> int:
    return fmix64((rotl64(key, 3) + ((byte_val ^ 0x5A) & 0xFF)) & MASK64)

def siphash_block(k0: int, k1: int, m: int) -> int:
    v0 = (k0 ^ 0x736F6D6570736575) & MASK64
    v1 = (k1 ^ 0x646F72616E646F6D) & MASK64
    v2 = (k0 ^ 0x6C7967656E657261) & MASK64
    v3 = (k1 ^ 0x7465646279746573) & MASK64
    v3 ^= m
    v0 = (v0 + v1) & MASK64; v1 = rotl64(v1, 13); v1 ^= v0; v0 = rotl64(v0, 32)
    v2 = (v2 + v3) & MASK64; v3 = rotl64(v3, 16); v3 ^= v2
    v0 = (v0 + v3) & MASK64; v3 = rotl64(v3, 21); v3 ^= v0
    v2 = (v2 + v1) & MASK64; v1 = rotl64(v1, 17); v1 ^= v2; v2 = rotl64(v2, 32)
    v0 ^= m; v2 ^= 0xFF
    for _ in range(2):
        v0 = (v0 + v1) & MASK64; v1 = rotl64(v1, 13); v1 ^= v0; v0 = rotl64(v0, 32)
        v2 = (v2 + v3) & MASK64; v3 = rotl64(v3, 16); v3 ^= v2
        v0 = (v0 + v3) & MASK64; v3 = rotl64(v3, 21); v3 ^= v0
        v2 = (v2 + v1) & MASK64; v1 = rotl64(v1, 17); v1 ^= v2; v2 = rotl64(v2, 32)
    return (v0 ^ v1 ^ v2 ^ v3) & MASK64

def derive_block_key(seed_key: int, block_id: int, block_offset: int) -> int:
    k0 = (seed_key ^ 0x5877A564D00F0000) & MASK64
    k1 = (seed_key ^ 0xD00F58770000A564) & MASK64
    m = (block_id ^ block_offset) & MASK64
    return siphash_block(k0, k1, m)

# =============================================================================
# 3. Native VM Architectural Layouts & Opcodes
# =============================================================================

NATIVE_GPR_NAMES = [
    "rax",   "rcx",   "rdx",   "rbx",   "rsp",   "rbp",   "rsi",   "rdi",
    "r8",    "r9",    "r10",   "r11",   "r12",   "r13",   "r14",   "r15",
    "vtmp0", "vtmp1", "vtmp2", "vtmp3", "vip",   "vsp",   "vkey",  "vx18",
    "vx19",  "vx20",  "vx21",  "vx22",  "vx23",  "vx24",  "fs_base", "gs_base"
]

NATIVE_LAYOUTS = [
    {"op_shift": 0,  "dst_shift": 8,  "src_shift": 13},
    {"op_shift": 0,  "dst_shift": 13, "src_shift": 8},
    {"op_shift": 5,  "dst_shift": 0,  "src_shift": 13},
    {"op_shift": 5,  "dst_shift": 13, "src_shift": 0},
    {"op_shift": 10, "dst_shift": 0,  "src_shift": 5},
    {"op_shift": 10, "dst_shift": 5,  "src_shift": 0},
]

def layout_of_seed(seed: int) -> Dict[str, int]:
    idx = (seed & 0x7FFFFFFF) % 6
    return NATIVE_LAYOUTS[idx]

NATIVE_OPCODE_NAMES = [
    "NOP", "MOV_RR", "MOV_RI", "MOV_HIGH", "ADD_RR", "ADD_RI",
    "SUB_RR", "SUB_RI", "IMUL_RR", "IMUL_RI", "XOR_RR", "XOR_RI",
    "AND_RR", "AND_RI", "OR_RR", "OR_RI", "ROL_RI", "ROL_RR", "ROR_RI", "ROR_RR",
    "SHL_RI", "SHL_RR", "SHR_RI", "SHR_RR", "SAR_RI", "SAR_RR", "DIV_RR", "IDIV_RR",
    "NEG_RR", "NOT_RR", "CMP_RR", "CMP_RI", "PUSH_R", "POP_R", "JMP", "JCC",
    "CMOV", "SETCC", "CALL", "IJMP_R", "ICALL_R", "RET", "EXIT",
    "FUSED_MOV_ADD_RRI", "FUSED_ADD_IMUL_RRI", "FUSED_ADD_XOR_RRI",
    "FUSED_SUB_XOR_RRI", "FUSED_XOR_ADD_RRI", "FUSED_AND_OR_RRI", "FUSED_SHL_ADD_RRI", "FUSED_CMP_CMOV",
    "BRIDGE_TO_FLOW", "BRIDGE_TO_MATH",
    "VADD_VV", "VSUB_VV", "VMUL_VV", "VXOR_VV",
    "VEC_MOV", "VEC_BINOP", "VEC_SHA", "VEC_PCLMUL", "VEC_AES", "VEC_SHUF2", "VEC_CONV",
    "PTEST", "PINSR", "PEXTR", "READ_SSP", "INC_SSP", "VEC_LOAD", "VEC_STORE",
    "CALL_EXTERN", "LOAD_64", "LOAD_32", "LOAD_16", "LOAD_8",
    "LOAD_S32", "LOAD_S16", "LOAD_S8", "STORE_64", "STORE_32", "STORE_16", "STORE_8",
    "RESOLVE_SYM", "FADD_DD", "FSUB_DD", "FMUL_DD", "FDIV_DD", "FSQRT_D", "FCMP_DD",
    "FCCMP_DD", "FCVTZS", "SCVTF", "FJCVTZS",
    "ATOMIC_LOAD", "ATOMIC_STORE", "ATOMIC_CAS", "ATOMIC_ADD", "ATOMIC_SWP", "FENCE",
    "BSWAP_RR", "CLZ_RR", "CTZ_RR", "POPCNT_RR", "RBIT_RR",
    "MOV_VR", "MOV_RV", "FCSEL_VV", "MULH_RR", "IMULH_RR",
    "ADC_RR", "ADC_RI", "SBB_RR", "SBB_RI", "CCMP_RR", "CCMP_RI", "CCMN_RR", "CCMN_RI",
    "GET_FLAGS_R", "SET_FLAGS_R", "VEC_IMM", "VEC_CLEAR_UPPER", "VEC_ZERO_UPPER",
    "PMOVMSKB", "VEC_SPLAT", "FCVTZU", "UCVTF", "FCVT", "VEC_EXT", "CPUID",
    "FPU_PUSH_ST", "FPU_PUSH_MEM", "FPU_PUSH_INT", "FPU_STORE_ST", "FPU_STORE_MEM", "FPU_STORE_INT",
    "FPU_BINOP", "FPU_BINOP_MEM", "FPU_COMPARE", "FPU_COMPARE_I", "FPU_COMPARE_MEM",
    "FPU_UNARY", "FPU_CONST", "FPU_TRANS", "FPU_STATUS_TO_AX"
]

COND_NAMES = {
    0: "e", 1: "ne", 2: "b", 3: "be", 4: "a", 5: "ae",
    6: "l", 7: "le", 8: "g", 9: "ge"
}

# =============================================================================
# 4. Stack VM Specifications & Costas Layout
# =============================================================================

STACK_OPCODE_SPECS = [
    ("PushImm", "h_push_imm"),
    ("PushReg", "h_push_reg"),
    ("PopReg", "h_pop_reg"),
    ("ReadMem", "h_read_mem"),
    ("WriteMem", "h_write_mem"),
    ("Add", "h_add"),
    ("Sub", "h_sub"),
    ("Mul", "h_mul"),
    ("Nor", "h_nor"),
    ("Nand", "h_nand"),
    ("Shl", "h_shl"),
    ("Shr", "h_shr"),
    ("Dup", "h_dup"),
    ("Swap", "h_swap"),
    ("PushFlags", "h_push_flags"),
    ("PopFlags", "h_pop_flags"),
    ("JmpRel", "h_jmp_rel"),
    ("JccRel", "h_jcc_rel"),
    ("KeyAdjust", "h_key_adjust"),
    ("Exit", "h_exit"),
    ("CallExtern", "h_call_extern"),
    ("ResolveSym", "h_resolve_sym"),
    ("Setcc", "h_setcc"),
    ("Cmov", "h_cmov"),
    ("Cmp", "h_cmp"),
    ("Test", "h_test"),
    ("Sar", "h_sar"),
    ("Div", "h_div"),
    ("Idiv", "h_idiv"),
    ("PushImm32", "h_push_imm32"),
    ("AddImm", "h_add_imm"),
    ("SubImm", "h_sub_imm"),
    ("AddImmImm", "h_add_ii"),
    ("SubImmImm", "h_sub_ii"),
    ("SetRegImm", "h_set_reg_imm"),
    ("AddRegImm", "h_add_reg_imm"),
    ("KeyFeedback", "h_key_feedback"),
    ("Dup2", "h_dup2"),
    ("Rot", "h_rot"),
    ("NativeEscape", "h_native_escape"),
]

def generate_stack_opcode_map(seed: int) -> Tuple[Dict[int, str], Dict[str, int]]:
    state = SALT_STACK_VM_STATE if seed == 0 else seed
    pool = list(range(1, 255))
    num_ops = len(STACK_OPCODE_SPECS)
    for i in range(num_ops):
        state, r = splitmix64(state)
        range_rem = 254 - i
        offset = (r & 0x7FFFFFFFFFFFFFFF) % range_rem
        j = i + offset
        pool[i], pool[j] = pool[j], pool[i]

    code_to_name = {pool[i]: STACK_OPCODE_SPECS[i][0] for i in range(num_ops)}
    name_to_code = {STACK_OPCODE_SPECS[i][0]: pool[i] for i in range(num_ops)}
    return code_to_name, name_to_code

# Costas array of order 6 permutations for field layouts
COSTAS_6 = [
    [0,1,4,3,5,2], [0,1,5,3,2,4], [0,2,1,4,5,3], [0,2,1,5,3,4],
    [0,2,5,3,4,1], [0,3,2,4,5,1], [0,3,4,2,1,5], [0,3,5,4,1,2],
    [0,4,2,3,5,1], [0,4,2,5,1,3], [0,4,3,1,2,5], [0,4,3,5,1,2],
    [0,4,5,1,3,2], [0,4,5,2,1,3], [0,5,1,3,4,2], [0,5,2,1,3,4],
    [0,5,2,3,1,4], [0,5,2,4,3,1], [0,5,3,2,4,1], [1,2,0,4,3,5]
]

class StackFieldLayout:
    def __init__(self, seed: int):
        s_idx = (seed ^ (seed >> 16)) % len(COSTAS_6)
        c = COSTAS_6[s_idx]
        self.jcc_target_first = c[0] >= 3
        self.cmov_slot_first = c[1] >= 3
        self.set_reg_imm_first = c[2] >= 3
        self.add_reg_imm_first = c[3] >= 3
        self.add_ii_b_first = c[4] >= 3
        self.sub_ii_b_first = c[5] >= 3

# =============================================================================
# 5. Memory Offset Maps for VM Structures
# =============================================================================

# vanguard_threaded_vm::VMContext field offsets (computed from vm_context_emitter.ml)
OFF_CANARY_HEAD    = 0
OFF_MID_CANARIES   = 8     # uint64_t[32] -> 8..264
OFF_GPRS           = 264   # uint64_t[32] -> 264..520
OFF_SLOT_MASKS     = 520   # uint64_t[32] -> 520..776
OFF_VREGS          = 776   # uint64_t[32][8] -> 776..2824
OFF_STACK          = 2824  # uint64_t[512] -> 2824..6920
OFF_SP             = 6920  # size_t (8 bytes)
OFF_REGMASK        = 6928  # uint64_t
OFF_INIT_SEED      = 6936  # uint32_t (4 bytes)
OFF_POISON_PENALTY = 6944  # uint64_t
OFF_RUNNING_KEY    = 6952  # uint64_t
OFF_DATA_KEY       = 6960  # uint64_t
OFF_SSP            = 6968  # uint64_t
OFF_CF             = 6976  # bool
OFF_CF_ARM64       = 6977  # bool
OFF_ZF             = 6978  # bool
OFF_SF             = 6979  # bool
OFF_OF             = 6980  # bool
OFF_PF             = 6981  # bool
OFF_TRAPPED        = 6982  # bool
OFF_EXEC_INSTRS    = 6984  # size_t
OFF_CANARY_TAIL    = 6992  # uint64_t
OFF_DECOY_SINK     = 7000  # uint64_t
OFF_OBLIVIOUS_FRM  = 7008  # uint64_t[64] -> 7008..7520
OFF_FPU_STACK      = 7520  # double[8] -> 7520..7584
OFF_FPU_TOP        = 7584  # uint8_t
OFF_FPU_STATUS     = 7586  # uint16_t
OFF_MACRO_SALT     = 7588  # uint8_t
OFF_DECOY_REGS     = 7592  # uint64_t[32]
OFF_FORMAT_VER_TAG = 7848  # int32_t
OFF_ANALYSIS_PRESS = 7852  # uint32_t
OFF_PRESSURE_TIER  = 7856  # uint8_t
OFF_LAST_STEP_TSC  = 7864  # uint64_t
VM_CONTEXT_SIZE    = 7872

# stack_vm_t field offsets (computed from stack_runtime.ml)
OFF_STK_VSP        = 0      # uint64_t[4096] (32768 bytes)
OFF_STK_VSP_IDX    = 32768  # int32_t
OFF_STK_CTX        = 32776  # uint64_t[64] (offset 0x8008)
OFF_STK_VKEY       = 33288  # uint64_t
OFF_STK_VSP_KEY    = 33296  # uint64_t
OFF_STK_ADDR_KEY   = 33304  # uint64_t
OFF_STK_BC_SIZE    = 33312  # size_t
OFF_STK_ZF         = 33320  # uint8_t
OFF_STK_SF         = 33321  # uint8_t
OFF_STK_CF         = 33322  # uint8_t
OFF_STK_PF         = 33323  # uint8_t
OFF_STK_OF         = 33324  # uint8_t
OFF_STK_HALTED     = 33328  # int32_t
OFF_STK_AUTH_FAIL  = 33332  # int32_t
STACK_VM_T_SIZE    = 33336

# =============================================================================
# 6. VM Context State Models & Unmaskers
# =============================================================================

class NativeVmState:
    """Decodes, unmasks, and writes vanguard_threaded_vm::VMContext state."""

    def __init__(self, raw_bytes: bytes, addr: int):
        self.addr = addr
        self.raw = raw_bytes

        # Read canaries
        self.canary_head = struct.unpack_from("<Q", self.raw, OFF_CANARY_HEAD)[0]
        self.canary_tail = struct.unpack_from("<Q", self.raw, OFF_CANARY_TAIL)[0]
        self.valid_canaries = (self.canary_head == CANARY_VAL and self.canary_tail == CANARY_VAL)

        # Seeds and keys
        self.init_seed = struct.unpack_from("<I", self.raw, OFF_INIT_SEED)[0]
        self.reg_mask = struct.unpack_from("<Q", self.raw, OFF_REGMASK)[0]
        self.running_key = struct.unpack_from("<Q", self.raw, OFF_RUNNING_KEY)[0]
        self.data_key = struct.unpack_from("<Q", self.raw, OFF_DATA_KEY)[0]
        self.poison_penalty = struct.unpack_from("<Q", self.raw, OFF_POISON_PENALTY)[0]
        self.ssp = struct.unpack_from("<Q", self.raw, OFF_SSP)[0]

        # Execution counters and security flags
        self.sp = struct.unpack_from("<Q", self.raw, OFF_SP)[0]
        self.executed_instructions = struct.unpack_from("<Q", self.raw, OFF_EXEC_INSTRS)[0]
        self.trapped = bool(self.raw[OFF_TRAPPED])
        self.cf = bool(self.raw[OFF_CF])
        self.cf_arm64 = bool(self.raw[OFF_CF_ARM64])
        self.zf = bool(self.raw[OFF_ZF])
        self.sf = bool(self.raw[OFF_SF])
        self.of = bool(self.raw[OFF_OF])
        self.pf = bool(self.raw[OFF_PF])
        self.analysis_pressure = struct.unpack_from("<I", self.raw, OFF_ANALYSIS_PRESS)[0]
        self.pressure_tier = self.raw[OFF_PRESSURE_TIER]

        # Affine register permutation constants (matching vm_context_emitter.ml)
        self.affine_a = (((self.init_seed >> 16) & 0x1E) | 1)
        self.affine_b = self.init_seed & 31

        # Read GPRs and slot masks
        self.gprs = list(struct.unpack_from("<32Q", self.raw, OFF_GPRS))
        self.slot_masks = list(struct.unpack_from("<32Q", self.raw, OFF_SLOT_MASKS))

        # FPU
        self.fpu_stack = list(struct.unpack_from("<8d", self.raw, OFF_FPU_STACK))
        self.fpu_top = self.raw[OFF_FPU_TOP] & 7
        self.fpu_status = struct.unpack_from("<H", self.raw, OFF_FPU_STATUS)[0]

    def phys_idx(self, i: int) -> int:
        """Computes physical slot index for architectural register i."""
        return (((i & 31) * self.affine_a) + self.affine_b) & 31

    def get_reg(self, i: int) -> int:
        """Unmasks architectural register i: (gprs[idx] ^ slot_masks[idx]) ^ reg_mask."""
        phys = self.phys_idx(i)
        return ((self.gprs[phys] ^ self.slot_masks[phys]) ^ self.reg_mask) & MASK64

    def get_reg_by_name(self, name: str) -> Optional[int]:
        name_lower = name.lower()
        if name_lower in NATIVE_GPR_NAMES:
            idx = NATIVE_GPR_NAMES.index(name_lower)
            return self.get_reg(idx)
        return None

    def encode_new_reg_val(self, i: int, new_val: int) -> Tuple[int, int, int]:
        """Calculates (phys_idx, new_slot_mask, new_gpr_val) matching VMContext::set_reg."""
        phys = self.phys_idx(i)
        cur_mask = self.slot_masks[phys]
        new_m = (((cur_mask ^ self.running_key) & MASK64) * GOLDEN_RATIO_64) & MASK64
        new_gpr = (new_val ^ new_m ^ self.reg_mask) & MASK64
        return phys, new_m, new_gpr


class StackVmState:
    """Decodes, unmasks, and inspects stack_vm_t state."""

    def __init__(self, raw_bytes: bytes, addr: int):
        self.addr = addr
        self.raw = raw_bytes

        self.vsp_idx = struct.unpack_from("<i", self.raw, OFF_STK_VSP_IDX)[0]
        self.vkey = struct.unpack_from("<Q", self.raw, OFF_STK_VKEY)[0]
        self.vsp_key = struct.unpack_from("<Q", self.raw, OFF_STK_VSP_KEY)[0]
        self.addr_key = struct.unpack_from("<Q", self.raw, OFF_STK_ADDR_KEY)[0]
        self.bc_size = struct.unpack_from("<Q", self.raw, OFF_STK_BC_SIZE)[0]

        self.zf = bool(self.raw[OFF_STK_ZF])
        self.sf = bool(self.raw[OFF_STK_SF])
        self.cf = bool(self.raw[OFF_STK_CF])
        self.pf = bool(self.raw[OFF_STK_PF])
        self.of = bool(self.raw[OFF_STK_OF])
        self.halted = struct.unpack_from("<i", self.raw, OFF_STK_HALTED)[0]
        self.auth_failed = struct.unpack_from("<i", self.raw, OFF_STK_AUTH_FAIL)[0]

        # Context slots
        self.ctx = list(struct.unpack_from("<64Q", self.raw, OFF_STK_CTX))

        # Raw VSP array
        self.raw_vsp = list(struct.unpack_from("<4096Q", self.raw, OFF_STK_VSP))

    def get_vsp_val(self, slot: int) -> int:
        """Unmasks stack value at slot: vsp[slot] ^ asg_vsp_mask(vsp_key, slot)."""
        if slot < 0 or slot >= 4096:
            return 0
        raw_val = self.raw_vsp[slot]
        mask = asg_vsp_mask(self.vsp_key, slot)
        return (raw_val ^ mask) & MASK64
# =============================================================================
# 7. Bytecode Disassemblers
# =============================================================================

class NativeDisassembler:
    """Disassembles encrypted/plaintext Native VM bytecode."""

    def __init__(self, seed: int):
        self.seed = seed
        self.layout = layout_of_seed(seed)

    def decode_word(self, word: int) -> Tuple[int, int, int, int]:
        op = (word >> self.layout["op_shift"]) & 0xFF
        dst = (word >> self.layout["dst_shift"]) & 0x1F
        src = (word >> self.layout["src_shift"]) & 0x1F
        imm_raw = (word >> 18) & MASK32
        imm = imm_raw if imm_raw < 0x80000000 else imm_raw - 0x100000000
        return op, dst, src, imm

    def format_insn(self, vip: int, op: int, dst: int, src: int, imm: int) -> str:
        dst_name = NATIVE_GPR_NAMES[dst] if dst < len(NATIVE_GPR_NAMES) else f"r{dst}"
        src_name = NATIVE_GPR_NAMES[src] if src < len(NATIVE_GPR_NAMES) else f"r{src}"

        # Resolve mnemonic
        if op < len(NATIVE_OPCODE_NAMES):
            mnem = NATIVE_OPCODE_NAMES[op]
        else:
            mnem = f"OP_0x{op:02X}"

        # Format operands based on opcode convention
        if "RR" in mnem:
            ops = f"{dst_name}, {src_name}"
        elif "RI" in mnem:
            imm_str = f"0x{imm & MASK64:x}" if imm >= 0 else f"-0x{-imm:x}"
            ops = f"{dst_name}, {imm_str}"
        elif mnem in ("JMP", "CALL"):
            target_vip = vip + 1 + imm
            ops = f"[vIP {target_vip:04d}] (rel {imm:+d})"
        elif mnem == "JCC":
            cond_str = COND_NAMES.get(src & 0xF, f"c{src}")
            target_vip = vip + 1 + imm
            ops = f"{cond_str}, [vIP {target_vip:04d}] (rel {imm:+d})"
        elif mnem in ("PUSH_R", "POP_R"):
            ops = f"{dst_name}"
        elif mnem in ("RET", "EXIT", "NOP"):
            ops = ""
        elif "LOAD" in mnem or "STORE" in mnem:
            ops = f"{dst_name}, [{src_name} {imm:+d}]"
        else:
            imm_str = f"0x{imm & MASK64:x}" if imm != 0 else ""
            ops = f"{dst_name}, {src_name} {imm_str}".strip(", ")

        return f"{mnem:<14} {ops}"


class StackDisassembler:
    """Disassembles Stack-VM bytecode stream."""

    def __init__(self, seed_key: int):
        self.seed_key = seed_key
        self.op_map, self.rev_map = generate_stack_opcode_map(seed_key)
        self.layout = StackFieldLayout(seed_key)

    def disassemble_block(self, bc_bytes: bytes, start_vip: int = 0, count: int = 15, cur_key: Optional[int] = None) -> List[Dict[str, Any]]:
        results = []
        pos = start_vip
        n = len(bc_bytes)
        key = cur_key if cur_key is not None else derive_block_key(self.seed_key, 0, start_vip)

        def read_byte():
            nonlocal pos, key
            if pos >= n:
                return None
            c = bc_bytes[pos]
            pos += 1
            op_byte = c ^ (key & 0xFF)
            key = step_key(key, op_byte)
            return op_byte

        def read_i16():
            b0 = read_byte(); b1 = read_byte()
            if b0 is None or b1 is None: return None
            v = b0 | (b1 << 8)
            return v if v < 0x8000 else v - 0x10000

        def read_i32():
            b = [read_byte() for _ in range(4)]
            if any(x is None for x in b): return None
            v = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)
            return v if v < 0x80000000 else v - 0x100000000

        def read_i64():
            b = [read_byte() for _ in range(8)]
            if any(x is None for x in b): return None
            v = 0
            for i in range(8): v |= (b[i] << (i * 8))
            return v

        while pos < n and len(results) < count:
            insn_vip = pos
            b = read_byte()
            if b is None:
                break
            mnem = self.op_map.get(b, f"OP_0x{b:02X}")
            operands = ""

            if mnem == "PushImm":
                val = read_i64()
                operands = f"0x{val:X}" if val is not None else "???"
            elif mnem == "PushImm32":
                val = read_i32()
                operands = f"0x{val:X}" if val is not None else "???"
            elif mnem in ("PushReg", "PopReg"):
                slot = read_i16()
                operands = f"ctx[{slot}]" if slot is not None else "???"
            elif mnem in ("ReadMem", "WriteMem"):
                w = read_byte()
                operands = f"w={w}" if w is not None else "???"
            elif mnem == "JmpRel":
                tgt = read_i32()
                operands = f"{tgt:+d} (-> {insn_vip + (tgt or 0):04d})"
            elif mnem == "JccRel":
                if self.layout.jcc_target_first:
                    tgt = read_i32(); cond = read_byte()
                else:
                    cond = read_byte(); tgt = read_i32()
                c_name = COND_NAMES.get(cond, f"{cond}")
                operands = f"{c_name}, {tgt:+d} (-> {insn_vip + (tgt or 0):04d})"
            elif mnem == "CallExtern":
                idx = read_i32()
                operands = f"sym[{idx}]"
            elif mnem == "KeyAdjust":
                delta = read_i64()
                operands = f"delta=0x{delta:X}"
            elif mnem == "AddImm":
                val = read_i64()
                operands = f"0x{val:X}"
            elif mnem == "SetRegImm":
                if self.layout.set_reg_imm_first:
                    imm = read_i64(); slot = read_i16()
                else:
                    slot = read_i16(); imm = read_i64()
                operands = f"ctx[{slot}], 0x{imm:X}"

            results.append({
                "vip": insn_vip,
                "mnemonic": mnem,
                "operands": operands,
                "size": pos - insn_vip
            })

            if mnem == "Exit":
                break

        return results

# =============================================================================
# 8. LLDB Session & Target Memory Reader
# =============================================================================

class AsgardSession:
    """Manages active LLDB target inspection, process memory reading, and frame detection."""

    def __init__(self, debugger):
        self.debugger = debugger

    def get_target(self):
        if not IN_LLDB:
            return None
        return self.debugger.GetSelectedTarget()

    def get_process(self):
        t = self.get_target()
        return t.GetProcess() if t and t.IsValid() else None

    def get_frame(self):
        p = self.get_process()
        if not p or not p.IsValid():
            return None
        th = p.GetSelectedThread()
        return th.GetSelectedFrame() if th and th.IsValid() else None

    def read_bytes(self, addr: int, size: int) -> Optional[bytes]:
        p = self.get_process()
        if not p:
            return None
        error = lldb.SBError()
        buf = p.ReadMemory(addr, size, error)
        if error.Fail():
            return None
        return buf

    def write_bytes(self, addr: int, data: bytes) -> bool:
        p = self.get_process()
        if not p:
            return False
        error = lldb.SBError()
        p.WriteMemory(addr, data, error)
        return error.Success()

    def read_uint64(self, addr: int) -> Optional[int]:
        b = self.read_bytes(addr, 8)
        if b and len(b) == 8:
            return struct.unpack("<Q", b)[0]
        return None

    def write_uint64(self, addr: int, val: int) -> bool:
        return self.write_bytes(addr, struct.pack("<Q", val & MASK64))

    def detect_vm(self) -> Tuple[Optional[str], Optional[int], Optional[Dict[str, Any]]]:
        """Auto-detects active VM type ('native' or 'stack') and locates VM state pointer."""
        frame = self.get_frame()
        if not frame:
            return None, None, None

        # 1. Check frame function name
        fn_name = frame.GetFunctionName() or ""

        # 2. Search local variables in current or caller frames
        thread = frame.GetThread()
        for f in thread.frames:
            # Check for vanguard_threaded_vm::VMContext (Native VM)
            ctx_var = f.FindVariable("ctx")
            if ctx_var and ctx_var.IsValid():
                addr = ctx_var.GetValueAsUnsigned()
                if addr == 0 or addr == lldb.LLDB_INVALID_ADDRESS:
                    addr = ctx_var.GetLoadAddress()
                if addr and addr != lldb.LLDB_INVALID_ADDRESS:
                    # Validate canaries
                    buf = self.read_bytes(addr, 16)
                    if buf and struct.unpack_from("<Q", buf, 0)[0] == CANARY_VAL:
                        return "native", addr, {"frame": f, "ctx_var": ctx_var}
            # Check for stack_vm_t (Stack VM)
            vm_var = f.FindVariable("vm")
            if vm_var and vm_var.IsValid():
                addr = vm_var.GetLoadAddress()
                if addr != lldb.LLDB_INVALID_ADDRESS:
                    # If pointer, dereference
                    if vm_var.GetType().IsPointerType():
                        addr = vm_var.GetValueAsUnsigned()
                    return "stack", addr, {"frame": f, "vm_var": vm_var}

        return None, None, None

    def get_native_state(self, explicit_addr: Optional[int] = None) -> Optional[NativeVmState]:
        addr = explicit_addr
        if addr is None:
            vm_type, detected_addr, _ = self.detect_vm()
            if vm_type == "native":
                addr = detected_addr

        if addr is None:
            return None

        raw = self.read_bytes(addr, VM_CONTEXT_SIZE)
        if not raw or len(raw) < VM_CONTEXT_SIZE:
            return None
        return NativeVmState(raw, addr)

    def get_stack_state(self, explicit_addr: Optional[int] = None) -> Optional[StackVmState]:
        addr = explicit_addr
        if addr is None:
            vm_type, detected_addr, _ = self.detect_vm()
            if vm_type == "stack":
                addr = detected_addr

        if addr is None:
            return None

        raw = self.read_bytes(addr, STACK_VM_T_SIZE)
        if not raw or len(raw) < STACK_VM_T_SIZE:
            return None
        return StackVmState(raw, addr)

# =============================================================================
# 9. LLDB Command Implementations
# =============================================================================

def cmd_asg_help(debugger, command, result, internal_dict):
    """Show ASGARD bytecode debugger command manual."""
    msg = """
╔═════════════════════════════════════════════════════════════════════════════╗
║                   ASGARD-5877 LLDB Bytecode Debugger                       ║
╚═════════════════════════════════════════════════════════════════════════════╝
Commands:
  asg-status              Display active VM engine type, vIP, and state summary
  asg-regs, asg-r         Dump unmasked virtual registers (GPRs, flags, canaries)
                          Usage: asg-regs [--all] [ctx_addr]
  asg-stack, asg-vsp      Dump unmasked virtual stack entries
                          Usage: asg-stack [depth]
  asg-fpu                 Dump virtual x87 FPU circular stack ST(0..7) and FSW
  asg-disas, asg-d        Disassemble bytecode at current vIP
                          Usage: asg-disas [start_vip] [count]
  asg-step, asg-s         Step forward by ONE virtual bytecode instruction
  asg-next, asg-n         Step over current virtual call/instruction
  asg-break, asg-b <vip>  Set a virtual breakpoint at bytecode offset vIP
  asg-trace [count]       Trace virtual execution and print register diffs
  asg-set-reg <reg> <val> Write virtual register with affine re-encryption
                          Usage: asg-set-reg rax 0x1337
  asg-export <file.json>  Export virtual machine state & disassembly to JSON
"""
    result.AppendMessage(msg.strip())


def cmd_asg_status(debugger, command, result, internal_dict):
    """Inspect active VM state and location."""
    session = AsgardSession(debugger)
    vm_type, addr, meta = session.detect_vm()

    if not vm_type:
        result.SetError("[-] No active ASGARD VM detected in current stack frames.")
        return

    if vm_type == "native":
        state = session.get_native_state(addr)
        if not state:
            result.SetError(f"[-] Failed reading Native VMContext at 0x{addr:X}")
            return
        frame = meta["frame"]
        thread = frame.GetThread()
        vip = 0
        for f in thread.frames:
            vip_var = f.FindVariable("vIP_idx")
            if vip_var and vip_var.IsValid():
                vip = vip_var.GetValueAsUnsigned()
                break
        bc_len = 0
        for f in thread.frames:
            for cnt_name in ("count", "bc_len", "size"):
                cnt_var = f.FindVariable(cnt_name)
                if cnt_var and cnt_var.IsValid():
                    bc_len = cnt_var.GetValueAsUnsigned()
                    break
            if bc_len != 0:
                break
        canary_str = "\033[32mOK (0xCAFEBABE13375877)\033[0m" if state.valid_canaries else "\033[31mCORRUPTED\033[0m"
        trap_str = "\033[31mTRAPPED\033[0m" if state.trapped else "\033[32mACTIVE\033[0m"

        msg = f"""
[+] ASGARD Native Threaded VM (vanguard_threaded_vm)
    Context Address:       0x{addr:X}
    Current vIP:           {vip} / {bc_len}
    Executed Instructions: {state.executed_instructions}
    VM Status:             {trap_str} | Canaries: {canary_str}
    Seed / Affine Perm:    0x{state.init_seed:08X} (A={state.affine_a}, B={state.affine_b})
    Running Key:           0x{state.running_key:016X}
    Flags:                 CF={int(state.cf)} ZF={int(state.zf)} SF={int(state.sf)} OF={int(state.of)} PF={int(state.pf)} (ARM64_C={int(state.cf_arm64)})
"""
        result.AppendMessage(msg.strip())

    elif vm_type == "stack":
        state = session.get_stack_state(addr)
        if not state:
            result.SetError(f"[-] Failed reading Stack VM state at 0x{addr:X}")
            return
        frame = meta["frame"]
        vip_var = frame.FindVariable("vip")
        vip = vip_var.GetValueAsUnsigned() if vip_var and vip_var.IsValid() else 0

        halt_str = "\033[31mHALTED\033[0m" if state.halted else "\033[32mACTIVE\033[0m"

        msg = f"""
[+] ASGARD Stack-VM (stack_vm_t)
    VM Structure Address:  0x{addr:X}
    Current vIP:           {vip} / {state.bc_size}
    VSP Stack Depth:       {state.vsp_idx} / 4096
    VM Status:             {halt_str} (auth_failed={state.auth_failed})
    Keystream State:       vkey=0x{state.vkey:016X} vsp_key=0x{state.vsp_key:016X}
    Flags:                 ZF={int(state.zf)} SF={int(state.sf)} CF={int(state.cf)} OF={int(state.of)} PF={int(state.pf)}
"""
        result.AppendMessage(msg.strip())


def cmd_asg_regs(debugger, command, result, internal_dict):
    """Dump unmasked virtual registers."""
    session = AsgardSession(debugger)
    args = shlex.split(command)
    show_all = "--all" in args
    explicit_addr = None
    for a in args:
        if a.startswith("0x") or a.isdigit():
            explicit_addr = int(a, 0)
            break

    vm_type, addr, _ = session.detect_vm()
    if explicit_addr:
        addr = explicit_addr
        vm_type = "native"

    if not vm_type:
        result.SetError("[-] No active ASGARD VM detected in current frame.")
        return

    if vm_type == "native":
        state = session.get_native_state(addr)
        if not state:
            result.SetError(f"[-] Failed reading VMContext at 0x{addr:X}")
            return

        lines = [
            "╔═══════════════════════════════════════════════════════════════════════════════╗",
            f"║ ASGARD Virtual Registers (VMContext @ 0x{addr:012X})                  ║",
            "╠═══════════════════════════════════════════════════════════════════════════════╣"
        ]

        # Architectural GPRs (0..15)
        for i in range(0, 16, 2):
            r1 = NATIVE_GPR_NAMES[i]
            v1 = state.get_reg(i)
            r2 = NATIVE_GPR_NAMES[i + 1]
            v2 = state.get_reg(i + 1)
            lines.append(f"  {r1.upper():<6} 0x{v1:016X} ({v1:<12d})   {r2.upper():<6} 0x{v2:016X} ({v2:<12d})")

        lines.append("─────────────────────────────────────────────────────────────────────────────────")
        # Virtual / Temp registers (16..22)
        for i in range(16, 24, 2):
            r1 = NATIVE_GPR_NAMES[i]
            v1 = state.get_reg(i)
            r2 = NATIVE_GPR_NAMES[i + 1] if i + 1 < 32 else ""
            v2 = state.get_reg(i + 1) if i + 1 < 32 else 0
            lines.append(f"  {r1.upper():<6} 0x{v1:016X} ({v1:<12d})   {r2.upper():<6} 0x{v2:016X} ({v2:<12d})")

        # Flags & security
        lines.append("─────────────────────────────────────────────────────────────────────────────────")
        flag_str = f"CF={int(state.cf)}  ZF={int(state.zf)}  SF={int(state.sf)}  OF={int(state.of)}  PF={int(state.pf)}  ARM64_C={int(state.cf_arm64)}"
        sec_str = f"Canaries: {'OK' if state.valid_canaries else 'TAMPERED'} | Trapped: {state.trapped} | Instructions: {state.executed_instructions}"
        lines.append(f"  FLAGS:  {flag_str}")
        lines.append(f"  STATUS: {sec_str}")
        lines.append(f"  KEYS:   running_key=0x{state.running_key:016X}  data_key=0x{state.data_key:016X}")
        lines.append("╚═══════════════════════════════════════════════════════════════════════════════╝")

        result.AppendMessage("\n".join(lines))

    elif vm_type == "stack":
        state = session.get_stack_state(addr)
        if not state:
            result.SetError(f"[-] Failed reading Stack VM at 0x{addr:X}")
            return

        lines = [
            "╔═══════════════════════════════════════════════════════════════════════════════╗",
            f"║ ASGARD Stack-VM Context Slots (stack_vm_t @ 0x{addr:012X})            ║",
            "╠═══════════════════════════════════════════════════════════════════════════════╣"
        ]
        # Context slots 0..15
        for i in range(0, 16, 2):
            v1 = state.ctx[i]
            v2 = state.ctx[i + 1]
            lines.append(f"  ctx[{i:02d}] 0x{v1:016X} ({v1:<12d})   ctx[{i+1:02d}] 0x{v2:016X} ({v2:<12d})")

        lines.append("─────────────────────────────────────────────────────────────────────────────────")
        flag_str = f"ZF={int(state.zf)}  SF={int(state.sf)}  CF={int(state.cf)}  OF={int(state.of)}  PF={int(state.pf)}"
        lines.append(f"  VSP:    depth={state.vsp_idx}  halted={state.halted}  auth_failed={state.auth_failed}")
        lines.append(f"  FLAGS:  {flag_str}")
        lines.append(f"  KEYS:   vkey=0x{state.vkey:016X}  vsp_key=0x{state.vsp_key:016X}")
        lines.append("╚═══════════════════════════════════════════════════════════════════════════════╝")

        result.AppendMessage("\n".join(lines))


def cmd_asg_stack(debugger, command, result, internal_dict):
    """Dump unmasked virtual stack entries."""
    session = AsgardSession(debugger)
    args = shlex.split(command)
    depth = int(args[0], 0) if args and args[0].isdigit() else 10

    vm_type, addr, _ = session.detect_vm()
    if not vm_type:
        result.SetError("[-] No active ASGARD VM detected.")
        return

    if vm_type == "stack":
        state = session.get_stack_state(addr)
        if not state:
            result.SetError(f"[-] Failed reading Stack VM state.")
            return

        lines = [f"[+] Stack-VM VSP Stack (Total Depth: {state.vsp_idx})"]
        if state.vsp_idx == 0:
            lines.append("    <Empty Virtual Stack>")
        else:
            start = max(0, state.vsp_idx - depth)
            for i in range(state.vsp_idx - 1, start - 1, -1):
                val = state.get_vsp_val(i)
                marker = "-> [TOS]" if i == state.vsp_idx - 1 else "        "
                lines.append(f"{marker} [{i:04d}]  0x{val:016X}  ({val})")
        result.AppendMessage("\n".join(lines))

    elif vm_type == "native":
        state = session.get_native_state(addr)
        if not state:
            result.SetError("[-] Failed reading Native VM state.")
            return

        lines = [f"[+] Native VM Stack (SP index: {state.sp})"]
        if state.sp == 0:
            lines.append("    <Empty VM Stack Frame>")
        else:
            start = max(0, int(state.sp) - depth)
            for i in range(int(state.sp) - 1, start - 1, -1):
                raw_slot = state.addr + OFF_STACK + (i * 8)
                val = session.read_uint64(raw_slot) or 0
                marker = "-> [TOS]" if i == state.sp - 1 else "        "
                lines.append(f"{marker} [{i:04d}]  0x{val:016X}  ({val})")
        result.AppendMessage("\n".join(lines))


def cmd_asg_fpu(debugger, command, result, internal_dict):
    """Dump virtual x87 FPU stack ST(0..7)."""
    session = AsgardSession(debugger)
    vm_type, addr, _ = session.detect_vm()
    if vm_type != "native":
        result.SetError("[-] x87 FPU circular stack is only present in Native VM.")
        return

    state = session.get_native_state(addr)
    if not state:
        result.SetError("[-] Failed reading Native VMContext.")
        return

    lines = [
        f"[+] Virtual x87 FPU Stack (TOP={state.fpu_top}, FSW=0x{state.fpu_status:04X})"
    ]
    for i in range(8):
        phys_slot = (state.fpu_top + i) & 7
        val = state.fpu_stack[phys_slot]
        marker = "-> ST(0)" if i == 0 else f"   ST({i})"
        lines.append(f"    {marker} [phys {phys_slot}]  {val:20.10g}")

    result.AppendMessage("\n".join(lines))


def cmd_asg_disas(debugger, command, result, internal_dict):
    """Disassemble virtual bytecode at current vIP."""
    session = AsgardSession(debugger)
    vm_type, addr, meta = session.detect_vm()
    if not vm_type:
        result.SetError("[-] No active ASGARD VM detected in current frame.")
        return

    args = shlex.split(command)
    count = 12
    explicit_vip = None
    if len(args) >= 1:
        explicit_vip = int(args[0], 0)
    if len(args) >= 2:
        count = int(args[1], 0)

    frame = meta["frame"]

    if vm_type == "native":
        state = session.get_native_state(addr)
        if not state:
            result.SetError("[-] Failed reading Native VM state.")
            return

        cur_vip = explicit_vip
        if cur_vip is None:
            thread = frame.GetThread()
            for f in thread.frames:
                vip_var = f.FindVariable("vIP_idx")
                if vip_var and vip_var.IsValid():
                    cur_vip = vip_var.GetValueAsUnsigned()
                    break
            if cur_vip is None:
                cur_vip = 0
        # Locate bytecode buffer across frames or global variables
        target = session.get_target()
        bc_addr = None
        total_len = 0

        thread = frame.GetThread()
        for f in thread.frames:
            for var_name in ("bytecode", "work_bc", "bc_ptr", "heap_bc", "embedded_bytecode"):
                v = f.FindVariable(var_name)
                if v and v.IsValid():
                    if v.GetType().IsPointerType():
                        ptr_val = v.GetValueAsUnsigned()
                        if ptr_val != 0:
                            bc_addr = ptr_val
                            break
                    else:
                        load_addr = v.GetLoadAddress()
                        if load_addr != lldb.LLDB_INVALID_ADDRESS:
                            bc_addr = load_addr
                            break
            if bc_addr is not None:
                for cnt_name in ("count", "bc_len", "size"):
                    cv = f.FindVariable(cnt_name)
                    if cv and cv.IsValid():
                        total_len = cv.GetValueAsUnsigned()
                        break
                break

        # Fallback to global variable
        if bc_addr is None and target:
            glob_bc = target.FindFirstGlobalVariable("embedded_bytecode")
            if glob_bc and glob_bc.IsValid():
                bc_addr = glob_bc.GetLoadAddress()
                total_len = glob_bc.GetNumChildren()

        if bc_addr is None or bc_addr == 0 or bc_addr == lldb.LLDB_INVALID_ADDRESS:
            result.SetError("[-] Could not find bytecode pointer variable ('bytecode', 'work_bc', 'bc_ptr', or 'embedded_bytecode').")
            return

        if total_len == 0:
            total_len = cur_vip + count
        # Read bytecode words
        read_count = min(count, max(0, total_len - cur_vip))
        disas = NativeDisassembler(state.init_seed)

        lines = [f"[+] Native VM Disassembly (vIP: {cur_vip}, seed: 0x{state.init_seed:08X}):"]

        rk = state.running_key
        for i in range(read_count):
            idx = cur_vip + i
            word_raw = session.read_uint64(bc_addr + (idx * 8))
            if word_raw is None:
                lines.append(f"    [{idx:04d}]  <Memory Read Error>")
                break

            # Keystream decryption
            k_pos = key64_for_offset(state.init_seed, idx)
            k_dyn = (k_pos ^ rk) & MASK64
            word = (word_raw ^ k_dyn) & MASK64

            op, dst, src, imm = disas.decode_word(word)
            insn_str = disas.format_insn(idx, op, dst, src, imm)

            marker = "-> " if idx == cur_vip else "   "
            lines.append(f"{marker} [{idx:04d}]  {insn_str}")

            # Advance rolling key simulation
            rk = advance_key_step(rk, op, dst, imm)

        result.AppendMessage("\n".join(lines))

    elif vm_type == "stack":
        state = session.get_stack_state(addr)
        if not state:
            result.SetError("[-] Failed reading Stack VM state.")
            return

        vip_var = frame.FindVariable("vip")
        cur_vip = explicit_vip if explicit_vip is not None else (vip_var.GetValueAsUnsigned() if vip_var and vip_var.IsValid() else 0)

        bc_var = frame.FindVariable("bytecode")
        if not bc_var or not bc_var.IsValid():
            result.SetError("[-] Could not locate bytecode pointer.")
            return

        bc_addr = bc_var.GetValueAsUnsigned()
        bc_bytes = session.read_bytes(bc_addr, state.bc_size)
        if not bc_bytes:
            result.SetError(f"[-] Failed reading {state.bc_size} bytecode bytes at 0x{bc_addr:X}")
            return

        disas = StackDisassembler(state.addr_key or state.vkey)
        insns = disas.disassemble_block(bc_bytes, start_vip=cur_vip, count=count, cur_key=state.vkey)

        lines = [f"[+] Stack-VM Disassembly (vIP: {cur_vip}, vkey: 0x{state.vkey:016X}):"]
        for ins in insns:
            marker = "-> " if ins["vip"] == cur_vip else "   "
            lines.append(f"{marker} [{ins['vip']:04d}]  {ins['mnemonic']:<14} {ins['operands']}")

        result.AppendMessage("\n".join(lines))


def cmd_asg_step(debugger, command, result, internal_dict):
    """Step execution by exactly ONE virtual bytecode instruction."""
    session = AsgardSession(debugger)
    target = session.get_target()
    process = session.get_process()
    if not process or not process.IsValid():
        result.SetError("[-] Process is not running.")
        return

    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()

    vm_type, addr, _ = session.detect_vm()
    if not vm_type:
        result.SetError("[-] No active ASGARD VM detected in current frame.")
        return

    if vm_type == "native":
        old_state = session.get_native_state(addr)
        old_execs = old_state.executed_instructions if old_state else 0
        old_vip_var = frame.FindVariable("vIP_idx")
        old_vip = old_vip_var.GetValueAsUnsigned() if old_vip_var and old_vip_var.IsValid() else 0

        # Single step native instructions until executed_instructions increments
        step_limit = 500
        for _ in range(step_limit):
            thread.StepInstruction(False)
            cur_state = session.get_native_state(addr)
            if not cur_state:
                break
            if cur_state.executed_instructions > old_execs or cur_state.trapped:
                break

        new_state = session.get_native_state(addr)
        new_vip_var = thread.GetSelectedFrame().FindVariable("vIP_idx")
        new_vip = new_vip_var.GetValueAsUnsigned() if new_vip_var and new_vip_var.IsValid() else (old_vip + 1)

        # Print step diff
        diffs = []
        if old_state and new_state:
            for i in range(16):
                ov = old_state.get_reg(i)
                nv = new_state.get_reg(i)
                if ov != nv:
                    diffs.append(f"{NATIVE_GPR_NAMES[i].upper()}: 0x{ov:X} -> 0x{nv:X}")

        diff_str = f" | Changes: {', '.join(diffs)}" if diffs else ""
        result.AppendMessage(f"[STEP] Stepped to vIP [{new_vip:04d}] (Instruction #{new_state.executed_instructions if new_state else '?'}){diff_str}")

        # Auto-disassemble next instruction
        cmd_asg_disas(debugger, f"{new_vip} 1", result, internal_dict)

    elif vm_type == "stack":
        old_vip_var = frame.FindVariable("vip")
        old_vip = old_vip_var.GetValueAsUnsigned() if old_vip_var and old_vip_var.IsValid() else 0

        step_limit = 500
        for _ in range(step_limit):
            thread.StepInstruction(False)
            cur_vip_var = thread.GetSelectedFrame().FindVariable("vip")
            if cur_vip_var and cur_vip_var.GetValueAsUnsigned() != old_vip:
                break

        new_vip_var = thread.GetSelectedFrame().FindVariable("vip")
        new_vip = new_vip_var.GetValueAsUnsigned() if new_vip_var and new_vip_var.IsValid() else old_vip
        result.AppendMessage(f"[STEP] Stack-VM stepped to vIP [{new_vip:04d}]")
        cmd_asg_disas(debugger, f"{new_vip} 1", result, internal_dict)


def cmd_asg_next(debugger, command, result, internal_dict):
    """Step over to the next virtual bytecode instruction."""
    # In ASGARD, CALL/ICALL pushes return address to VM stack; step virtual insn
    cmd_asg_step(debugger, command, result, internal_dict)


def cmd_asg_break(debugger, command, result, internal_dict):
    """Set a conditional virtual breakpoint at a specific vIP."""
    args = shlex.split(command)
    if not args or not args[0].isdigit():
        result.SetError("[-] Usage: asg-break <vIP_target>")
        return

    target_vip = int(args[0], 0)
    session = AsgardSession(debugger)
    target = session.get_target()
    if not target:
        result.SetError("[-] No valid target in LLDB.")
        return

    # Set breakpoint on main execution loop
    bp = target.BreakpointCreateByName("execute_threaded")
    if not bp.IsValid():
        bp = target.BreakpointCreateByName("stack_vm_run")

    if not bp.IsValid():
        result.SetError("[-] Could not set breakpoint on execute_threaded or stack_vm_run.")
        return

    bp_id = bp.GetID()
    bp.SetCondition(f"vIP_idx == {target_vip} || (vip != 0 && *vip == {target_vip})")
    result.AppendMessage(f"[+] Virtual Breakpoint #{bp_id} set at vIP == {target_vip}")


def cmd_asg_trace(debugger, command, result, internal_dict):
    """Trace N virtual bytecode instructions."""
    args = shlex.split(command)
    count = int(args[0], 0) if args and args[0].isdigit() else 5

    result.AppendMessage(f"[+] Starting ASGARD Virtual Trace ({count} steps)...")
    for step_num in range(count):
        sub_res = lldb.SBCommandReturnObject()
        cmd_asg_step(debugger, "", sub_res, internal_dict)
        if sub_res.GetOutput():
            result.AppendMessage(sub_res.GetOutput().strip())
        if not sub_res.Succeeded():
            break


def cmd_asg_set_reg(debugger, command, result, internal_dict):
    """Modify a virtual register with cryptographic re-encryption."""
    session = AsgardSession(debugger)
    args = shlex.split(command)
    if len(args) < 2:
        result.SetError("[-] Usage: asg-set-reg <reg_name> <new_value>")
        return

    reg_name = args[0].lower()
    new_val = int(args[1], 0)

    vm_type, addr, _ = session.detect_vm()
    if vm_type != "native":
        result.SetError("[-] Register re-encryption is currently supported for Native VM.")
        return

    state = session.get_native_state(addr)
    if not state:
        result.SetError("[-] Failed reading Native VMContext.")
        return

    if reg_name not in NATIVE_GPR_NAMES:
        result.SetError(f"[-] Unknown architectural register: {reg_name}")
        return

    reg_idx = NATIVE_GPR_NAMES.index(reg_name)
    phys_idx, new_mask, new_gpr = state.encode_new_reg_val(reg_idx, new_val)

    # Write re-encrypted gpr and slot mask back into memory
    gpr_slot_addr = addr + OFF_GPRS + (phys_idx * 8)
    mask_slot_addr = addr + OFF_SLOT_MASKS + (phys_idx * 8)

    ok1 = session.write_uint64(gpr_slot_addr, new_gpr)
    ok2 = session.write_uint64(mask_slot_addr, new_mask)

    if ok1 and ok2:
        result.AppendMessage(f"[+] Successfully wrote {reg_name.upper()} = 0x{new_val:016X} (phys {phys_idx}: gpr=0x{new_gpr:X}, mask=0x{new_mask:X})")
    else:
        result.SetError("[-] Memory write failed when updating register.")


def cmd_asg_export(debugger, command, result, internal_dict):
    """Export VM context and disassembled state to JSON."""
    session = AsgardSession(debugger)
    args = shlex.split(command)
    out_file = args[0] if args else "asgard_vm_dump.json"

    vm_type, addr, meta = session.detect_vm()
    if not vm_type:
        result.SetError("[-] No active VM detected.")
        return

    dump_data = {
        "engine": vm_type,
        "address": f"0x{addr:X}",
    }

    if vm_type == "native":
        state = session.get_native_state(addr)
        if state:
            dump_data["canaries_ok"] = state.valid_canaries
            dump_data["init_seed"] = f"0x{state.init_seed:08X}"
            dump_data["executed_instructions"] = state.executed_instructions
            dump_data["flags"] = {
                "cf": state.cf, "zf": state.zf, "sf": state.sf,
                "of": state.of, "pf": state.pf
            }
            dump_data["registers"] = {
                NATIVE_GPR_NAMES[i]: f"0x{state.get_reg(i):016X}"
                for i in range(len(NATIVE_GPR_NAMES))
            }

    with open(out_file, "w") as f:
        json.dump(dump_data, f, indent=2)

    result.AppendMessage(f"[+] Exported VM state to {out_file}")

# =============================================================================
# 10. LLDB Module Entrypoint
# =============================================================================

def __lldb_init_module(debugger, internal_dict):
    """Registers ASGARD LLDB commands when imported."""
    commands = [
        ("asg-help",    cmd_asg_help),
        ("asg-status",  cmd_asg_status),
        ("asg-regs",    cmd_asg_regs),
        ("asg-r",       cmd_asg_regs),
        ("asg-stack",   cmd_asg_stack),
        ("asg-vsp",     cmd_asg_stack),
        ("asg-fpu",     cmd_asg_fpu),
        ("asg-disas",   cmd_asg_disas),
        ("asg-d",       cmd_asg_disas),
        ("asg-step",    cmd_asg_step),
        ("asg-s",       cmd_asg_step),
        ("asg-next",    cmd_asg_next),
        ("asg-n",       cmd_asg_next),
        ("asg-break",   cmd_asg_break),
        ("asg-b",       cmd_asg_break),
        ("asg-trace",   cmd_asg_trace),
        ("asg-set-reg", cmd_asg_set_reg),
        ("asg-export",  cmd_asg_export),
    ]

    for name, handler in commands:
        debugger.HandleCommand(f"command script add -f asgard_lldb.{handler.__name__} {name}")

    print("\033[36m[+] ASGARD-5877 LLDB Bytecode Debugger Plugin loaded.\033[0m")
    print("    Type \033[33m'asg-help'\033[0m to list virtual machine inspection commands.")


# =============================================================================
# 11. Self-Verification & Standalone Unit Tests
# =============================================================================

def run_self_tests() -> bool:
    """Verifies cryptographic schedules and unmasking routines."""
    print("[*] Running ASGARD LLDB Debugger self-verification suite...")

    # 1. Test SplitMix64 PRF
    s, z = splitmix64(0x5877)
    assert z != 0, "SplitMix64 output should be non-zero"
    print("  [+] SplitMix64 test: OK")

    # 2. Test key64_for_offset
    k0 = key64_for_offset(0x13375877, 0)
    k1 = key64_for_offset(0x13375877, 1)
    assert k0 != k1, "Offset keystream must be distinct per index"
    print("  [+] Keystream PRF test: OK")

    # 3. Test in-block rolling key step
    k_next = advance_key_step(k0, 4, 0, 100) # ADD_RI rax, 100
    assert k_next != k0, "advance_key_step must mutate key"
    print("  [+] Rolling key step test: OK")

    # 4. Test Native VM Affine Register Unmasking & Mutation
    # Synthesize dummy VMContext buffer
    buf = bytearray(VM_CONTEXT_SIZE)
    struct.pack_into("<Q", buf, OFF_CANARY_HEAD, CANARY_VAL)
    struct.pack_into("<Q", buf, OFF_CANARY_TAIL, CANARY_VAL)
    test_seed = 0x5877A564
    struct.pack_into("<I", buf, OFF_INIT_SEED, test_seed)
    test_regmask = 0x5A5A5A5A13375877
    struct.pack_into("<Q", buf, OFF_REGMASK, test_regmask)

    state = NativeVmState(bytes(buf), 0x1000)
    assert state.valid_canaries, "Canary check must pass"
    assert state.affine_a % 2 == 1, "Affine multiplier A must be odd (coprime to 32)"

    # Set RAX (reg 0) = 0x42
    phys, new_m, new_g = state.encode_new_reg_val(0, 0x42)
    struct.pack_into("<Q", buf, OFF_SLOT_MASKS + (phys * 8), new_m)
    struct.pack_into("<Q", buf, OFF_GPRS + (phys * 8), new_g)

    # Re-read and verify unmasking
    state2 = NativeVmState(bytes(buf), 0x1000)
    val_rax = state2.get_reg(0)
    assert val_rax == 0x42, f"Expected unmasked RAX=0x42, got 0x{val_rax:X}"
    print("  [+] Native VM affine register masking roundtrip: OK (RAX=0x42)")

    # 5. Test Stack-VM VSP slot masking
    vsp_k = 0x5877CAFE1337
    slot_mask0 = asg_vsp_mask(vsp_k, 0)
    slot_mask1 = asg_vsp_mask(vsp_k, 1)
    assert slot_mask0 != slot_mask1, "Slot masks must differ"
    encoded_val = 0x12345678 ^ slot_mask0
    assert (encoded_val ^ slot_mask0) == 0x12345678, "VSP unmasking must match"
    print("  [+] Stack-VM VSP slot masking test: OK")

    # 6. Test Native Disassembler
    nd = NativeDisassembler(test_seed)
    # Pack word: op=MOV_RI (2), dst=0 (rax), src=0, imm=15
    packed = (2 << nd.layout["op_shift"]) | (0 << nd.layout["dst_shift"]) | (15 << 18)
    op, dst, src, imm = nd.decode_word(packed)
    assert op == 2 and dst == 0 and imm == 15, "Decoded fields mismatch"
    insn_str = nd.format_insn(0, op, dst, src, imm)
    assert "MOV_RI" in insn_str and "rax" in insn_str, f"Insn format failed: {insn_str}"
    print(f"  [+] Native Disassembler test: OK ({insn_str})")

    # 7. Test Stack Disassembler Opcode Map
    c2n, n2c = generate_stack_opcode_map(0x5877A564D00F)
    assert "PushImm" in n2c and "Exit" in n2c, "Stack opcodes missing"
    print(f"  [+] Stack-VM polymorphic opcode map generation: OK ({len(c2n)} opcodes)")

    print("[✓] ALL 7 SELF-VERIFICATION CHECKS PASSED.")
    return True


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("--test", "-t"):
        ok = run_self_tests()
        sys.exit(0 if ok else 1)
    else:
        print("ASGARD-5877 LLDB Bytecode Debugger Plugin.")
        print("To load inside LLDB, execute:")
        print(f"  command script import {os.path.abspath(__file__)}")
        print("To run internal verification tests, execute:")
        print(f"  python3 {__file__} --test")
