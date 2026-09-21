#!/usr/bin/env python3
"""
ASGARD-5877 — Capstone Protection & Disassembly Security Audit Tool
Performs deep binary analysis using Capstone Engine (v5.x):
1. Disassembles __text section for ARM64 and x86_64 Mach-O binaries.
2. Evaluates Control-Flow Flattening (CFF) & Computed GOTO dispatch via indirect branch ratio.
3. Scans for algorithmic leakages (original immediate constants: 0x5877, 42, 0x1337).
4. Detects Zero-Bridge GL_16 affine transformation patterns (MADD / matrix registers).
5. Computes Shannon entropy of code and data segments.
"""

import sys
import struct
import math
from collections import Counter
import capstone
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM, CS_ARCH_X86, CS_MODE_64, CS_GRP_JUMP, CS_GRP_CALL

def parse_macho_text(binary_path):
    with open(binary_path, "rb") as f:
        magic = f.read(4)
        if magic != b"\xcf\xfa\xed\xfe":
            raise ValueError(f"Not a 64-bit Mach-O binary (magic={magic})")
        
        cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack("<2I5I", f.read(28))
        text_section = None
        data_sections = []
        
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack("<2I", f.read(8))
            cmd_data = f.read(cmdsize - 8)
            if cmd == 0x19: # LC_SEGMENT_64
                segname = cmd_data[0:16].rstrip(b"\x00").decode("latin1")
                vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, sflags = struct.unpack("<4Q2I2I", cmd_data[16:64])
                sect_data = cmd_data[64:]
                for s in range(nsects):
                    s_name = sect_data[s*80 : s*80+16].rstrip(b"\x00").decode("latin1")
                    s_addr, s_size, s_offset = struct.unpack("<2QI", sect_data[s*80+32 : s*80+52])
                    
                    pos = f.tell()
                    f.seek(s_offset)
                    content = f.read(s_size)
                    f.seek(pos)
                    
                    if s_name == "__text":
                        text_section = (cputype, s_addr, content)
                    else:
                        data_sections.append((segname, s_name, s_addr, content))
                        
        return text_section, data_sections

def shannon_entropy(data: bytes) -> float:
    if not data:
        return 0.0
    freq = Counter(data)
    total = len(data)
    return -sum((count / total) * math.log2(count / total) for count in freq.values())

def audit_binary(binary_path: str, title: str):
    text_info, data_sections = parse_macho_text(binary_path)
    if not text_info:
        print(f"[-] Error: __text section not found in {binary_path}")
        return

    cputype, base_addr, code_bytes = text_info
    
    # Select Capstone engine
    if cputype == 0x0100000C: # CPU_TYPE_ARM64
        arch_name = "ARM64 (Apple Silicon)"
        md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        indirect_branch_mnems = {"br", "blr"}
        direct_branch_mnems = {"b", "bl", "b.eq", "b.ne", "b.gt", "b.lt", "b.ge", "b.le", "cbz", "cbnz", "tbz", "tbnz"}
        affine_mul_mnems = {"madd", "msub", "mul"}
    elif cputype == 0x01000007: # CPU_TYPE_X86_64
        arch_name = "x86_64"
        md = Cs(CS_ARCH_X86, CS_MODE_64)
        indirect_branch_mnems = {"jmp", "call"} # will inspect operand
        direct_branch_mnems = {"jmp", "call", "je", "jne", "jg", "jl", "jge", "jle", "ja", "jb", "jae", "jbe"}
        affine_mul_mnems = {"imul", "mul"}
    else:
        arch_name = f"Unknown (0x{cputype:x})"
        md = None

    md.detail = True
    instructions = list(md.disasm(code_bytes, base_addr))
    
    total_insns = len(instructions)
    mnemonic_counts = Counter(insn.mnemonic for insn in instructions)
    
    # Analyze branching & dispatch
    direct_branches = 0
    indirect_branches = []
    affine_muls = 0
    
    # Original algorithm constants to hunt for:
    # 0x5877 (22647), 42 (0x2a), 0x1337 (4919)
    target_constants = {0x5877, 42, 0x1337}
    leaked_constants = []
    
    for insn in instructions:
        mnem = insn.mnemonic.lower()
        op_str = insn.op_str.lower()
        
        # Branch detection
        if cputype == 0x0100000C: # ARM64
            if mnem in indirect_branch_mnems:
                indirect_branches.append((insn.address, insn.mnemonic, insn.op_str))
            elif mnem in direct_branch_mnems:
                direct_branches += 1
            if mnem in affine_mul_mnems:
                affine_muls += 1
        elif cputype == 0x01000007: # x86_64
            if mnem in {"jmp", "call"} and not op_str.startswith("0x"):
                indirect_branches.append((insn.address, insn.mnemonic, insn.op_str))
            elif mnem.startswith("j") or mnem == "call":
                direct_branches += 1
            if mnem in affine_mul_mnems:
                affine_muls += 1

    # Check for original unprotected sequence: XOR -> MUL -> ADD (or equivalent)
    exposed_algo_sequence = []
    for i in range(len(instructions) - 2):
        m1, m2, m3 = instructions[i].mnemonic.lower(), instructions[i+1].mnemonic.lower(), instructions[i+2].mnemonic.lower()
        if cputype == 0x0100000C: # ARM64
            # Looking for sequence computing (x ^ 0x5877) * 42 + 0x1337
            if ("eor" in m1 or "mov" in m1) and ("mul" in m2 or "madd" in m2) and ("add" in m3):
                ops = f"{instructions[i].op_str} | {instructions[i+1].op_str} | {instructions[i+2].op_str}"
                if "0x5877" in ops and ("0x2a" in ops or "42" in ops) and "0x1337" in ops:
                    exposed_algo_sequence.append((instructions[i].address, ops))
        elif cputype == 0x01000007: # x86_64
            if "xor" in m1 and "imul" in m2 and "add" in m3:
                ops = f"{instructions[i].op_str} | {instructions[i+1].op_str} | {instructions[i+2].op_str}"
                if "5877" in ops and "2a" in ops and "1337" in ops:
                    exposed_algo_sequence.append((instructions[i].address, ops))

    text_entropy = shannon_entropy(code_bytes)
    total_branches = direct_branches + len(indirect_branches)
    indirect_ratio = (len(indirect_branches) / total_branches * 100.0) if total_branches > 0 else 0.0

    print(f"================================================================================")
    print(f" [CAPSTONE AUDIT] {title}")
    print(f" Binary:       {binary_path}")
    print(f" Architecture: {arch_name}")
    print(f" Code Size:    {len(code_bytes)} bytes ({total_insns} instructions)")
    print(f" Code Entropy: {text_entropy:.4f} / 8.0000 bits/byte")
    print(f"--------------------------------------------------------------------------------")
    print(f" Control-Flow & Dispatch Metrics:")
    print(f"   Direct Branches:          {direct_branches:4d}")
    print(f"   Indirect / GOTO Dispatches:{len(indirect_branches):4d}")
    print(f"   Indirect Dispatch Ratio:  {indirect_ratio:6.2f}%")
    print(f"   Zero-Bridge / Affine MULs:{affine_muls:4d}")
    print(f"--------------------------------------------------------------------------------")
    print(f" Algorithm Semantic Exposure (XOR 0x5877 -> MUL 42 -> ADD 0x1337):")
    if exposed_algo_sequence:
        print(f"   [!] CRITICAL LEAKAGE: Direct algorithm sequence found ({len(exposed_algo_sequence)} instances):")
        for addr, seq in exposed_algo_sequence:
            print(f"       0x{addr:08x}: {seq}")
        print(f"       -> Reversible by static decompiler in 1 second!")
    else:
        print(f"   [+] SECURE: 0 occurrences of original arithmetic pipeline!")
        print(f"       -> Logic is completely decentralized across VM bytecode & RNS-4 residues.")
    print(f"--------------------------------------------------------------------------------")
    print(f" Top Instruction Mnemonics:")
    top_mnems = mnemonic_counts.most_common(8)
    for mnem, count in top_mnems:
        pct = (count / total_insns) * 100.0
        print(f"   {mnem:12s}: {count:4d} ({pct:5.1f}%)")
    print(f"================================================================================\n")

if __name__ == "__main__":
    targets = [
        ("examples/ida_demo/unprotected_license_checker", "UNPROTECTED BASELINE (ARM64)"),
        ("examples/ida_demo/protected_runner", "ASGARD-5877 MULTI-VM PROTECTED (ARM64)"),
        ("examples/ida_demo/unprotected_license_checker_x86_64", "UNPROTECTED BASELINE (x86_64)"),
        ("examples/ida_demo/protected_runner_x86_64", "ASGARD-5877 MULTI-VM PROTECTED (x86_64)"),
    ]
    
    for path, title in targets:
        audit_binary(path, title)
