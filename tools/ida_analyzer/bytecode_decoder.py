"""
bytecode_decoder.py — ASGARD-5877 Stack-VM Rolling-Key Bytecode Disassembler
─────────────────────────────────────────────────────────────────────────────
Implements exact decryption, rolling-key schedule, dynamic opcode permutation,
and operand decoding matching Stack_encoder.ml and stack_runtime.ml.
"""

import struct
from typing import List, Dict, Optional, Tuple, Any

MASK64 = 0xFFFFFFFFFFFFFFFF
GOLDEN_RATIO_64 = 0x9E3779B97F4A7C15
SPLITMIX64_GAMMA = 0xBF58476D1CE4E5B9
SPLITMIX64_MIX = 0x94D049BB133111EB
SALT_STACK_VM_STATE = 0x5877_CAFE_BEEF_0001


def splitmix64(state: int) -> Tuple[int, int]:
    state = (state + GOLDEN_RATIO_64) & MASK64
    z = state
    z = (z ^ (z >> 30)) & MASK64
    z = (z * SPLITMIX64_GAMMA) & MASK64
    z = (z ^ (z >> 27)) & MASK64
    z = (z * SPLITMIX64_MIX) & MASK64
    z = (z ^ (z >> 31)) & MASK64
    return state, z


def fmix64(k: int) -> int:
    k = (k ^ (k >> 33)) & MASK64
    k = (k * 0xFF51AFD7ED558CCD) & MASK64
    k = (k ^ (k >> 33)) & MASK64
    k = (k * 0xC4CEB9FE1A85EC53) & MASK64
    k = (k ^ (k >> 33)) & MASK64
    return k


def rotl64(v: int, k: int) -> int:
    return ((v << k) | (v >> (64 - k))) & MASK64


def step_key(key: int, byte_val: int) -> int:
    """Murmur3 fmix64 non-linear byte-rolling step matching stack_runtime.ml."""
    return fmix64((rotl64(key, 3) + (byte_val ^ 0x5A)) & MASK64)


def siphash_block(k0: int, k1: int, m: int) -> int:
    """SipHash-1-2 PRF for per-block entry key derivation."""
    v0 = k0 ^ 0x736F6D6570736575
    v1 = k1 ^ 0x646F72616E646F6D
    v2 = k0 ^ 0x6C7967656E657261
    v3 = k1 ^ 0x7465646279746573
    v3 ^= m
    v0 = (v0 + v1) & MASK64; v1 = rotl64(v1, 13); v1 ^= v0; v0 = rotl64(v0, 32)
    v2 = (v2 + v3) & MASK64; v3 = rotl64(v3, 16); v3 ^= v2
    v0 = (v0 + v3) & MASK64; v3 = rotl64(v3, 21); v3 ^= v0
    v2 = (v2 + v1) & MASK64; v1 = rotl64(v1, 17); v1 ^= v2; v2 = rotl64(v2, 32)
    v0 ^= m
    v2 ^= 0xFF
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
OPCODE_SPECS = [
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
    ("Rot", "h_rot")
]

def generate_opcode_map(seed: int) -> Tuple[Dict[int, str], Dict[str, int], Dict[int, Dict[str, str]]]:
    """Generates the dynamic polymorphic 39-opcode permutation and handler mappings for this seed."""
    state = SALT_STACK_VM_STATE if seed == 0 else seed
    pool = list(range(1, 255))
    for i in range(39):
        state, r = splitmix64(state)
        range_rem = 254 - i
        offset = (r & 0x7FFFFFFFFFFFFFFF) % range_rem
        j = i + offset
        pool[i], pool[j] = pool[j], pool[i]

    code_to_name = {pool[i]: OPCODE_SPECS[i][0] for i in range(39)}
    name_to_code = {OPCODE_SPECS[i][0]: pool[i] for i in range(39)}
    code_to_info = {
        pool[i]: {
            "mnemonic": OPCODE_SPECS[i][0],
            "handler": OPCODE_SPECS[i][1],
            "label": f"lbl_{pool[i]:02X}",
        }
        for i in range(39)
    }
    return code_to_name, name_to_code, code_to_info

class FieldLayout:
    def __init__(self, seed: int):
        state, r = splitmix64(seed)
        self.jcc_target_first = bool(r & 1)
        self.cmov_slot_first = bool(r & 2)
        self.set_reg_imm_first = bool(r & 4)
        self.add_reg_imm_first = bool(r & 8)


COND_MAP = {
    0: "E", 1: "NE", 2: "B", 3: "BE", 4: "A", 5: "AE",
    6: "L", 7: "LE", 8: "G", 9: "GE"
}


class StackVmDecoder:
    """Disassembles encrypted Stack-VM bytecode stream."""

    def __init__(self, seed_key: int):
        self.seed_key = seed_key
        self.op_map, self.rev_map, self.op_info = generate_opcode_map(seed_key)
        self.layout = FieldLayout(seed_key)
        self.ctx_model: Dict[int, int] = {}

    def decode_stream(self, cipher_bytes: bytes, max_instructions: int = 10000) -> List[Dict[str, Any]]:
        instructions = []
        pos = 0
        key = derive_block_key(self.seed_key, 0, 0)
        n = len(cipher_bytes)

        def read_byte():
            nonlocal pos, key
            if pos >= n:
                return None
            c = cipher_bytes[pos]
            pos += 1
            k_byte = key & 0xFF
            p = c ^ k_byte
            key = step_key(key, p)
            return p

        def read_i16():
            b0 = read_byte()
            b1 = read_byte()
            if b0 is None or b1 is None:
                return None
            val = b0 | (b1 << 8)
            # signed 16-bit
            return val if val < 0x8000 else val - 0x10000

        def read_i32():
            b = [read_byte() for _ in range(4)]
            if any(x is None for x in b):
                return None
            val = b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)
            return val if val < 0x80000000 else val - 0x100000000

        def read_i64():
            b = [read_byte() for _ in range(8)]
            if any(x is None for x in b):
                return None
            val = 0
            for i in range(8):
                val |= (b[i] << (i * 8))
            return val

        while pos < n and len(instructions) < max_instructions:
            start_offset = pos
            cur_key = key
            op_code = read_byte()
            if op_code is None:
                break

            info = self.op_info.get(op_code, {
                "mnemonic": f"unk_0x{op_code:02X}",
                "handler": "unknown",
                "label": f"lbl_{op_code:02X}",
            })
            name = info["mnemonic"]
            handler_name = info["handler"]
            handler_lbl = info["label"]
            operands = []
            delta = 0
            if name == "PushImm":
                val = read_i64()
                if val is not None:
                    operands.append(f"0x{val:016X}")
                delta = 1

            elif name == "PushImm32":
                val = read_i32()
                if val is not None:
                    operands.append(f"{val}")
                delta = 1

            elif name == "PushReg":
                r = read_i16()
                if r is not None:
                    operands.append(f"ctx[{r}]")
                delta = 1

            elif name == "PopReg":
                r = read_i16()
                if r is not None:
                    operands.append(f"ctx[{r}]")
                delta = -1

            elif name in ("ReadMem", "WriteMem"):
                w = read_byte()
                if w is not None:
                    operands.append(f"w={w}")
                delta = 0 if name == "ReadMem" else -2

            elif name in ("Add", "Sub", "Mul", "Nor", "Nand", "Shl", "Shr", "Sar", "Div", "Idiv"):
                delta = -1

            elif name == "Dup":
                delta = 1

            elif name == "Dup2":
                delta = 2

            elif name in ("Rot", "Swap", "PushFlags", "PopFlags"):
                delta = 0

            elif name == "JmpRel":
                tgt = read_i32()
                if tgt is not None:
                    operands.append(f"target_bid={tgt}")
                delta = 0

            elif name == "JccRel":
                if self.layout.jcc_target_first:
                    tgt = read_i32()
                    cc = read_byte()
                else:
                    cc = read_byte()
                    tgt = read_i32()
                cond_name = COND_MAP.get(cc, f"cc_{cc}")
                if tgt is not None:
                    operands.append(f"target_bid={tgt}, cond={cond_name}")
                delta = 0

            elif name == "KeyAdjust":
                d = read_i64()
                if d is not None:
                    operands.append(f"delta=0x{d:016X}")
                    key = (key ^ d) & MASK64
                delta = 0

            elif name == "CallExtern":
                idx = read_i32()
                if idx is not None:
                    operands.append(f"sym_idx={idx}")
                delta = 0

            elif name == "ResolveSym":
                idx = read_i32()
                if idx is not None:
                    operands.append(f"sym_idx={idx}")
                delta = 0

            elif name == "Setcc":
                cc = read_byte()
                cond_name = COND_MAP.get(cc, f"cc_{cc}")
                operands.append(f"cond={cond_name}")
                delta = 1

            elif name == "Cmov":
                if self.layout.cmov_slot_first:
                    r = read_i16()
                    cc = read_byte()
                else:
                    cc = read_byte()
                    r = read_i16()
                cond_name = COND_MAP.get(cc, f"cc_{cc}")
                operands.append(f"ctx[{r}], cond={cond_name}")
                delta = -1

            elif name in ("Cmp", "Test"):
                delta = -2

            elif name == "AddImm":
                val = read_i64()
                if val is not None:
                    operands.append(f"0x{val:016X}")
                delta = 0

            elif name == "SubImm":
                val = read_i64()
                if val is not None:
                    operands.append(f"0x{val:016X}")
                delta = 0

            elif name in ("AddImmImm", "SubImmImm"):
                a = read_i64()
                b = read_i64()
                if a is not None and b is not None:
                    operands.append(f"0x{a:016X}, 0x{b:016X}")
                delta = 1

            elif name == "SetRegImm":
                if self.layout.set_reg_imm_first:
                    v = read_i64()
                    r = read_i16()
                else:
                    r = read_i16()
                    v = read_i64()
                if r is not None and v is not None:
                    operands.append(f"ctx[{r}], 0x{v:016X}")
                delta = 0

            elif name == "AddRegImm":
                if self.layout.add_reg_imm_first:
                    v = read_i64()
                    r = read_i16()
                else:
                    r = read_i16()
                    v = read_i64()
                if r is not None and v is not None:
                    operands.append(f"ctx[{r}], 0x{v:016X}")
                delta = 0

            elif name == "KeyFeedback":
                r = read_i16()
                if r is not None:
                    operands.append(f"ctx[{r}]")
                delta = 0

            elif name == "Exit":
                delta = 0
                raw_bytes = cipher_bytes[start_offset:pos]
                instructions.append({
                    "offset": start_offset,
                    "opcode": op_code,
                    "mnemonic": name,
                    "handler": handler_name,
                    "label": handler_lbl,
                    "operands": ", ".join(operands),
                    "delta": delta,
                    "bytes": raw_bytes.hex(),
                    "key": hex(cur_key),
                })
                break

            raw_bytes = cipher_bytes[start_offset:pos]
            instructions.append({
                "offset": start_offset,
                "opcode": op_code,
                "mnemonic": name,
                "handler": handler_name,
                "label": handler_lbl,
                "operands": ", ".join(operands),
                "delta": delta,
                "bytes": raw_bytes.hex(),
                "key": hex(cur_key),
            })

        return instructions
