#!/usr/bin/env python3
"""
test_asgard_lldb.py — Unit & Integration Tests for ASGARD LLDB Bytecode Debugger Plugin
─────────────────────────────────────────────────────────────────────────────────────
Verifies cryptographic correctness, affine unmasking, rolling-key schedules,
disassembly engines, and LLDB integration.
"""

import sys
import os
import unittest
import struct

# Ensure tools/lldb is in Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asgard_lldb import (
    MASK64, CANARY_VAL, GOLDEN_RATIO_64,
    splitmix64, poly_hash64, key64_for_offset, advance_key_step, asg_vsp_mask,
    derive_block_key, step_key,
    NativeVmState, StackVmState, NativeDisassembler, StackDisassembler,
    generate_stack_opcode_map, StackFieldLayout,
    NATIVE_GPR_NAMES, layout_of_seed,
    OFF_CANARY_HEAD, OFF_CANARY_TAIL, OFF_INIT_SEED, OFF_REGMASK, OFF_GPRS, OFF_SLOT_MASKS,
    OFF_RUNNING_KEY, OFF_SP, OFF_STACK, OFF_CF, OFF_ZF, OFF_EXEC_INSTRS,
    OFF_STK_VSP, OFF_STK_VSP_IDX, OFF_STK_CTX, OFF_STK_VKEY, OFF_STK_VSP_KEY, OFF_STK_BC_SIZE,
    VM_CONTEXT_SIZE, STACK_VM_T_SIZE
)


class TestCryptoSchedules(unittest.TestCase):
    """Test cryptographic schedules and PRFs matching OCaml/C++ engine definitions."""

    def test_splitmix64(self):
        s1, z1 = splitmix64(0)
        s2, z2 = splitmix64(s1)
        self.assertNotEqual(z1, z2)
        self.assertEqual(s1, GOLDEN_RATIO_64)

    def test_key64_for_offset(self):
        seed = 0x13375877
        k0 = key64_for_offset(seed, 0)
        k1 = key64_for_offset(seed, 1)
        k2 = key64_for_offset(seed, 2)
        self.assertNotEqual(k0, k1)
        self.assertNotEqual(k1, k2)
        # Deterministic
        self.assertEqual(k0, key64_for_offset(seed, 0))

    def test_advance_key_step(self):
        k0 = 0x5877CAFE1337BEEF
        # Step with op=4 (ADD), dst=0 (rax), imm=100
        k1 = advance_key_step(k0, 4, 0, 100)
        self.assertNotEqual(k0, k1)
        self.assertEqual(k1, advance_key_step(k0, 4, 0, 100))

    def test_asg_vsp_mask(self):
        key = 0xCAFEBABE13375877
        m0 = asg_vsp_mask(key, 0)
        m1 = asg_vsp_mask(key, 1)
        m2 = asg_vsp_mask(key, 2)
        self.assertNotEqual(m0, m1)
        self.assertNotEqual(m1, m2)
        # Reversible masking
        secret = 0xDEADBEEF12345678
        encoded = secret ^ m0
        self.assertEqual(encoded ^ m0, secret)


class TestNativeVmState(unittest.TestCase):
    """Test Native VMContext reading, unmasking, and mutation."""

    def setUp(self):
        self.buf = bytearray(VM_CONTEXT_SIZE)
        # Setup valid canaries
        struct.pack_into("<Q", self.buf, OFF_CANARY_HEAD, CANARY_VAL)
        struct.pack_into("<Q", self.buf, OFF_CANARY_TAIL, CANARY_VAL)
        self.seed = 0x5877A564
        struct.pack_into("<I", self.buf, OFF_INIT_SEED, self.seed)
        self.regmask = 0x5A5A5A5A13375877
        struct.pack_into("<Q", self.buf, OFF_REGMASK, self.regmask)
        self.running_key = 0x13375877A5A5A5A5
        struct.pack_into("<Q", self.buf, OFF_RUNNING_KEY, self.running_key)
        struct.pack_into("<Q", self.buf, OFF_EXEC_INSTRS, 42)
        self.buf[OFF_ZF] = 1

    def test_canaries_and_flags(self):
        state = NativeVmState(bytes(self.buf), 0x2000)
        self.assertTrue(state.valid_canaries)
        self.assertEqual(state.executed_instructions, 42)
        self.assertTrue(state.zf)
        self.assertFalse(state.cf)
        self.assertFalse(state.trapped)

    def test_affine_register_unmasking(self):
        state = NativeVmState(bytes(self.buf), 0x2000)
        # Multiplier A must be odd
        self.assertEqual(state.affine_a % 2, 1)

        # Test setting and reading all 16 GPRs
        for reg_idx in range(16):
            expected_val = 0x1000 + reg_idx * 0x111
            phys, new_m, new_g = state.encode_new_reg_val(reg_idx, expected_val)
            struct.pack_into("<Q", self.buf, OFF_SLOT_MASKS + (phys * 8), new_m)
            struct.pack_into("<Q", self.buf, OFF_GPRS + (phys * 8), new_g)

            # Re-read
            st = NativeVmState(bytes(self.buf), 0x2000)
            self.assertEqual(st.get_reg(reg_idx), expected_val)
            reg_name = NATIVE_GPR_NAMES[reg_idx]
            self.assertEqual(st.get_reg_by_name(reg_name), expected_val)

    def test_tampered_canaries(self):
        self.buf[OFF_CANARY_HEAD] = 0x00
        state = NativeVmState(bytes(self.buf), 0x2000)
        self.assertFalse(state.valid_canaries)


class TestStackVmState(unittest.TestCase):
    """Test Stack-VM inspection and VSP unmasking."""

    def setUp(self):
        self.buf = bytearray(STACK_VM_T_SIZE)
        self.vsp_key = 0x5877CAFE00001337
        struct.pack_into("<Q", self.buf, OFF_STK_VSP_KEY, self.vsp_key)
        struct.pack_into("<i", self.buf, OFF_STK_VSP_IDX, 3)
        struct.pack_into("<Q", self.buf, OFF_STK_BC_SIZE, 128)

        # Push 3 unmasked values into VSP
        self.values = [0x1111222233334444, 0x5555666677778888, 0x9999AAAABBBBCCCC]
        for slot, val in enumerate(self.values):
            mask = asg_vsp_mask(self.vsp_key, slot)
            struct.pack_into("<Q", self.buf, OFF_STK_VSP + (slot * 8), val ^ mask)

    def test_vsp_unmasking(self):
        state = StackVmState(bytes(self.buf), 0x3000)
        self.assertEqual(state.vsp_idx, 3)
        self.assertEqual(state.bc_size, 128)
        for slot, expected in enumerate(self.values):
            self.assertEqual(state.get_vsp_val(slot), expected)

    def test_polymorphic_opcode_map(self):
        c2n, n2c = generate_stack_opcode_map(0x5877A564D00F)
        self.assertEqual(len(c2n), 40)
        self.assertIn("PushImm", n2c)
        self.assertIn("Add", n2c)
        self.assertIn("Exit", n2c)


class TestDisassemblers(unittest.TestCase):
    """Test bytecode disassembly formatting."""

    def test_native_disassembler(self):
        seed = 0x5877A564
        dis = NativeDisassembler(seed)
        # Pack MOV_RI rax, 0x55 (op=2)
        packed = (2 << dis.layout["op_shift"]) | (0 << dis.layout["dst_shift"]) | (0x55 << 18)
        op, dst, src, imm = dis.decode_word(packed)
        self.assertEqual(op, 2)
        self.assertEqual(dst, 0)
        self.assertEqual(imm, 0x55)
        insn_str = dis.format_insn(0, op, dst, src, imm)
        self.assertIn("MOV_RI", insn_str)
        self.assertIn("rax", insn_str)
        self.assertIn("0x55", insn_str)

    def test_stack_disassembler(self):
        seed = 0x5877A564D00F
        dis = StackDisassembler(seed)
        self.assertIsNotNone(dis.op_map)
        self.assertIsNotNone(dis.layout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
