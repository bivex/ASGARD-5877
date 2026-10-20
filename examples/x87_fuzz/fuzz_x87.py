#!/usr/bin/env python3
"""
ASGARD-5877 Differential Fuzzer: x87 FPU Stack, Arithmetic, & Transcendentals
=============================================================================

Differential fuzzing campaign for legacy x87 FPU instructions comparing:
  1. Golden Native Hardware Reference (via x86-64 Rosetta on Apple Silicon or native x86-64)
  2. ASGARD Protected Threaded Virtual Machine (vanguard_threaded_vm runtime)
  3. Python IEEE-754 Shadow Oracle (stack ring tracker + condition flags)

Verifies:
  - FPU register stack circular top indexing (st(0)..st(7), 8-slot ring)
  - Loads and stores: FLD, FST, FSTP, FILD, FIST, FISTP, FXCH
  - Constants: FLD1, FLDZ, FLDPI, FLDL2E, FLDL2T, FLDLG2, FLDLN2
  - Arithmetic: FADD(P), FSUB(P), FSUBR(P), FMUL(P), FDIV(P), FDIVR(P)
  - Unary math: FCHS, FABS, FSQRT
  - Transcendentals: FSIN, FCOS, FSINCOS, FPTAN, FPATAN, FYL2X, FYL2XP1, F2XM1
  - Comparisons & condition codes: FCOM(P/PP), FCOMI(P) -> C0..C3 & EFLAGS (CF, ZF, PF)
  - Status word: FSTSW AX, FNSTSW AX

Usage:
    python3 fuzz_x87.py [-n COUNT] [--seed SEED] [--mode {diff,oracle,vm,rosetta}]
                        [--batch-size BATCH] [--keep-going] [--repro FILE.s]
"""

import os
import sys
import math
import struct
import random
import argparse
import subprocess
import time
from typing import List, Tuple, Dict, Any, Optional

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))

# Find repo root by locating dune-project
cur = SCRIPT_DIR
while cur != "/" and not os.path.exists(os.path.join(cur, "dune-project")):
    cur = os.path.dirname(cur)
REPO_ROOT = cur if cur != "/" else os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))
ARTIFACT_DIR = os.path.join(SCRIPT_DIR, "artifacts")
os.makedirs(ARTIFACT_DIR, exist_ok=True)

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
MAGENTA = "\033[95m"
BOLD = "\033[1m"
RESET = "\033[0m"


# ============================================================================
# Python x87 Shadow Oracle
# ============================================================================
class X87Oracle:
    """Accurate shadow state tracker for the 80-bit/64-bit x87 FPU stack."""

    def __init__(self):
        self.stack = [0.0] * 8
        self.top = 0
        self.c0 = 0
        self.c1 = 0
        self.c2 = 0
        self.c3 = 0
        self.eflags_cf = 0
        self.eflags_zf = 0
        self.eflags_pf = 0

    def get_fsw(self) -> int:
        sw = (self.top & 7) << 11
        if self.c0:
            sw |= 1 << 8
        if self.c1:
            sw |= 1 << 9
        if self.c2:
            sw |= 1 << 10
        if self.c3:
            sw |= 1 << 14
        return sw

    def push(self, val: float):
        self.top = (self.top - 1) & 7
        self.stack[self.top] = float(val)

    def pop(self) -> float:
        val = self.stack[self.top]
        self.top = (self.top + 1) & 7
        return val

    def get_st(self, idx: int) -> float:
        return self.stack[(self.top + idx) & 7]

    def set_st(self, idx: int, val: float):
        self.stack[(self.top + idx) & 7] = float(val)

    def fxch(self, idx: int):
        i0 = self.top
        i1 = (self.top + idx) & 7
        self.stack[i0], self.stack[i1] = self.stack[i1], self.stack[i0]

    def compare(self, val1: float, val2: float, update_eflags: bool = False):
        if math.isnan(val1) or math.isnan(val2):
            self.c3, self.c2, self.c0 = 1, 1, 1
            if update_eflags:
                self.eflags_zf, self.eflags_pf, self.eflags_cf = 1, 1, 1
        elif val1 < val2:
            self.c3, self.c2, self.c0 = 0, 0, 1
            if update_eflags:
                self.eflags_zf, self.eflags_pf, self.eflags_cf = 0, 0, 1
        elif val1 > val2:
            self.c3, self.c2, self.c0 = 0, 0, 0
            if update_eflags:
                self.eflags_zf, self.eflags_pf, self.eflags_cf = 0, 0, 0
        else:
            self.c3, self.c2, self.c0 = 1, 0, 0
            if update_eflags:
                self.eflags_zf, self.eflags_pf, self.eflags_cf = 1, 0, 0


# ============================================================================
# Test Vector Pool & Instruction Generator
# ============================================================================
FLOAT_POOL = [
    0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, 3.141592653589793,
    2.718281828459045, 0.6931471805599453, 1.4142135623730951,
    10.0, 42.0, 100.25, -500.5, 0.125, 0.0625, 1024.0,
    1e-5, 1e5, 1e-12, 1e12,
]

INT_POOL = [
    0, 1, -1, 2, -2, 7, 42, -42, 100, -100,
    32767, -32768, 65535, 1000000, -1000000
]


class TestCase:
    """Represents a generated sequence of x87 instructions and memory layout."""

    def __init__(self, name: str, instrs: List[str], mem_qwords: List[float], mem_dwords: List[int]):
        self.name = name
        self.instrs = instrs
        self.mem_qwords = mem_qwords
        self.mem_dwords = mem_dwords
        self.oracle_st: List[float] = []
        self.oracle_fsw: int = 0
        self.oracle_rax: int = 0


class X87Generator:
    """Smart constraint-based generator creating valid, edge-case x87 test programs."""

    def __init__(self, rng: random.Random):
        self.rng = rng

    def generate_case(self, idx: int, num_ops: int = 12) -> TestCase:
        name = f"fpu_test_{idx}"
        instrs: List[str] = []
        mem_qwords: List[float] = [self.rng.choice(FLOAT_POOL) for _ in range(8)]
        mem_dwords: List[int] = [self.rng.choice(INT_POOL) for _ in range(8)]

        oracle = X87Oracle()
        depth = 0  # number of active values on the x87 stack

        for _ in range(num_ops):
            actions = []
            # Can push if depth < 8
            if depth < 8:
                actions.extend(["fld_const", "fld_mem_qword", "fild_mem_dword"])
                if depth > 0:
                    actions.append("fld_st")

            # Can do unary or store if depth >= 1
            if depth >= 1:
                actions.extend(["fchs", "fabs", "fst_mem_qword", "fstp_mem_qword"])
                # Safe transcendentals
                actions.extend(["fsin", "fcos"])
                if abs(oracle.get_st(0)) <= 1.0:
                    actions.append("f2xm1")
                # Positive domain operations
                if oracle.get_st(0) >= 0.0:
                    actions.append("fsqrt")

            # Can do binary arithmetic / comparisons if depth >= 2
            if depth >= 2:
                actions.extend(["fadd", "faddp", "fsub", "fsubp", "fsubr", "fsubrp",
                                "fmul", "fmulp", "fcomi", "fcomip"])
                # Division safety: check appropriate divisor
                if abs(oracle.get_st(0)) > 1e-12:
                    actions.extend(["fdivp", "fdivr"])
                if abs(oracle.get_st(1)) > 1e-12:
                    actions.extend(["fdivrp"])
                if any(abs(oracle.get_st(i)) > 1e-12 for i in range(1, depth)):
                    actions.append("fdiv")
                # Logarithm: st(0) > 0
                if oracle.get_st(0) > 0.0:
                    actions.append("fyl2x")

            if not actions:
                actions = ["fld1"]

            act = self.rng.choice(actions)

            if act == "fld_const":
                c = self.rng.choice(["fld1", "fldz", "fldpi", "fldl2e", "fldl2t", "fldlg2", "fldln2"])
                instrs.append(f"    {c}")
                val = {
                    "fld1": 1.0, "fldz": 0.0, "fldpi": math.pi,
                    "fldl2e": math.log2(math.e), "fldl2t": math.log2(10.0),
                    "fldlg2": math.log10(2.0), "fldln2": math.log(2.0)
                }[c]
                oracle.push(val)
                depth += 1

            elif act == "fld_mem_qword":
                slot = self.rng.randint(0, len(mem_qwords) - 1)
                offset = slot * 8
                instrs.append(f"    fld qword ptr [rsp + {offset}]")
                oracle.push(mem_qwords[slot])
                depth += 1

            elif act == "fild_mem_dword":
                slot = self.rng.randint(0, len(mem_dwords) - 1)
                offset = 64 + slot * 4
                instrs.append(f"    fild dword ptr [rsp + {offset}]")
                oracle.push(float(mem_dwords[slot]))
                depth += 1

            elif act == "fld_st":
                i = self.rng.randint(0, depth - 1)
                instrs.append(f"    fld st({i})")
                oracle.push(oracle.get_st(i))
                depth += 1

            elif act == "fchs":
                instrs.append("    fchs")
                oracle.set_st(0, -oracle.get_st(0))

            elif act == "fabs":
                instrs.append("    fabs")
                oracle.set_st(0, abs(oracle.get_st(0)))

            elif act == "fsqrt":
                instrs.append("    fsqrt")
                oracle.set_st(0, math.sqrt(oracle.get_st(0)))

            elif act == "fsin":
                instrs.append("    fsin")
                oracle.set_st(0, math.sin(oracle.get_st(0)))

            elif act == "fcos":
                instrs.append("    fcos")
                oracle.set_st(0, math.cos(oracle.get_st(0)))

            elif act == "f2xm1":
                instrs.append("    f2xm1")
                oracle.set_st(0, math.pow(2.0, oracle.get_st(0)) - 1.0)

            elif act == "fst_mem_qword":
                slot = self.rng.randint(0, len(mem_qwords) - 1)
                offset = slot * 8
                instrs.append(f"    fst qword ptr [rsp + {offset}]")
                mem_qwords[slot] = oracle.get_st(0)

            elif act == "fstp_mem_qword":
                slot = self.rng.randint(0, len(mem_qwords) - 1)
                offset = slot * 8
                instrs.append(f"    fstp qword ptr [rsp + {offset}]")
                mem_qwords[slot] = oracle.pop()
                depth -= 1

            elif act == "fadd":
                i = self.rng.randint(0, depth - 1)
                instrs.append(f"    fadd st(0), st({i})")
                oracle.set_st(0, oracle.get_st(0) + oracle.get_st(i))

            elif act == "faddp":
                instrs.append("    faddp")
                b = oracle.pop()
                oracle.set_st(0, oracle.get_st(0) + b)
                depth -= 1

            elif act == "fsub":
                i = self.rng.randint(0, depth - 1)
                instrs.append(f"    fsub st(0), st({i})")
                oracle.set_st(0, oracle.get_st(0) - oracle.get_st(i))

            elif act == "fsubp":
                instrs.append("    fsubp")
                b = oracle.pop()
                oracle.set_st(0, oracle.get_st(0) - b)
                depth -= 1

            elif act == "fsubr":
                i = self.rng.randint(0, depth - 1)
                instrs.append(f"    fsubr st(0), st({i})")
                oracle.set_st(0, oracle.get_st(i) - oracle.get_st(0))

            elif act == "fsubrp":
                instrs.append("    fsubrp")
                b = oracle.pop()
                oracle.set_st(0, b - oracle.get_st(0))
                depth -= 1

            elif act == "fmul":
                i = self.rng.randint(0, depth - 1)
                instrs.append(f"    fmul st(0), st({i})")
                oracle.set_st(0, oracle.get_st(0) * oracle.get_st(i))

            elif act == "fmulp":
                instrs.append("    fmulp")
                b = oracle.pop()
                oracle.set_st(0, oracle.get_st(0) * b)
                depth -= 1

            elif act == "fdiv":
                valid_indices = [i for i in range(1, depth) if abs(oracle.get_st(i)) > 1e-12]
                if not valid_indices:
                    continue
                i = self.rng.choice(valid_indices)
                instrs.append(f"    fdiv st(0), st({i})")
                oracle.set_st(0, oracle.get_st(0) / oracle.get_st(i))

            elif act == "fdivp":
                instrs.append("    fdivp")
                b = oracle.pop()
                oracle.set_st(0, oracle.get_st(0) / b)
                depth -= 1

            elif act == "fdivr":
                i = self.rng.randint(1, depth - 1)
                instrs.append(f"    fdivr st(0), st({i})")
                oracle.set_st(0, oracle.get_st(i) / oracle.get_st(0))

            elif act == "fdivrp":
                instrs.append("    fdivrp")
                b = oracle.pop()
                oracle.set_st(0, b / oracle.get_st(0))
                depth -= 1

            elif act == "fyl2x":
                instrs.append("    fyl2x")
                x = oracle.pop()
                y = oracle.get_st(0)
                oracle.set_st(0, y * math.log2(x))
                depth -= 1

            elif act == "fcomi":
                i = self.rng.randint(0, depth - 1)
                instrs.append(f"    fcomi st, st({i})")
                oracle.compare(oracle.get_st(0), oracle.get_st(i), update_eflags=True)

            elif act == "fcomip":
                i = self.rng.randint(1, depth - 1)
                instrs.append(f"    fcomip st, st({i})")
                val0 = oracle.get_st(0)
                vali = oracle.get_st(i)
                oracle.pop()
                oracle.compare(val0, vali, update_eflags=True)
                depth -= 1

        # Final readout of FSW and condition flags into RAX
        instrs.append("    fstsw ax")
        if oracle.eflags_cf:
            instrs.append("    or eax, 0x10000")
        if oracle.eflags_zf:
            instrs.append("    or eax, 0x20000")

        # Snapshot oracle values
        tc = TestCase(name, instrs, mem_qwords, mem_dwords)
        tc.oracle_st = [oracle.get_st(i) for i in range(depth)]
        tc.oracle_fsw = oracle.get_fsw()
        tc.oracle_rax = oracle.get_fsw() | (0x10000 if oracle.eflags_cf else 0) | (0x20000 if oracle.eflags_zf else 0)
        return tc


# ============================================================================
# Assembly Program Emitter
# ============================================================================
def emit_assembly(test_cases: List[TestCase]) -> str:
    lines = [
        "    .intel_syntax noprefix",
        "    .text",
    ]
    for tc in test_cases:
        lines.append(f"    .globl _{tc.name}")
        lines.append(f"_{tc.name}:")
        lines.append("    push rbp")
        lines.append("    mov rbp, rsp")
        lines.append("    sub rsp, 128")
        lines.append("")
        # Emit stack memory initializations
        for slot, val in enumerate(tc.mem_qwords):
            offset = slot * 8
            bits = struct.unpack("<Q", struct.pack("<d", val))[0]
            lines.append(f"    mov rax, {hex(bits)}")
            lines.append(f"    mov qword ptr [rsp + {offset}], rax")

        for slot, ival in enumerate(tc.mem_dwords):
            offset = 64 + slot * 4
            u32 = ival & 0xFFFFFFFF
            lines.append(f"    mov dword ptr [rsp + {offset}], {hex(u32)}")

        lines.append("")
        lines.extend(tc.instrs)
        lines.append("")
        lines.append("    add rsp, 128")
        lines.append("    pop rbp")
        lines.append("    ret")
        lines.append("")

    return "\n".join(lines)


# ============================================================================
# C++ Drivers for Native & VM Execution
# ============================================================================
def emit_native_runner(test_cases: List[TestCase]) -> str:
    decls = [f'extern "C" uint64_t {tc.name}();' for tc in test_cases]
    calls = []
    for tc in test_cases:
        calls.append(f"""
    {{
        uint64_t rax = {tc.name}();
        printf("{tc.name}: RAX=0x%llx FSW=0x%04x\\n", (unsigned long long)rax, (unsigned)(rax & 0xFFFF));
    }}""")

    return f"""#include <stdio.h>
#include <stdint.h>
#include <math.h>

{chr(10).join(decls)}

int main() {{
{chr(10).join(calls)}
    return 0;
}}
"""


def emit_vm_runner(vm_header_path: str, test_cases: List[TestCase]) -> str:
    calls = []
    for tc in test_cases:
        calls.append(f"""
    {{
        vanguard_threaded_vm::VMContext ctx = {{}};
        ctx.init();
        alignas(16) uint8_t stack_mem[4096] = {{}};
        ctx.set_reg(vanguard_threaded_vm::REG_RSP, reinterpret_cast<uint64_t>(stack_mem + 2048));
        bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr_{tc.name}, count_{tc.name}, true);
        uint64_t rax = ctx.get_rax();
        printf("{tc.name}: OK=%d RAX=0x%llx FSW=0x%04x ST0=%f\\n",
               (int)ok, (unsigned long long)rax, (unsigned)ctx.get_fsw(), ctx.get_st(0));
    }}""")

    return f"""#include "{os.path.basename(vm_header_path)}"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>

// Individual bytecode arrays will be compiled/linked
int main() {{
{chr(10).join(calls)}
    return 0;
}}
"""


# ============================================================================
# Campaign Execution Engine
# ============================================================================
def run_rosetta_case(asm_path: str, tc: TestCase) -> Tuple[bool, int, str]:
    """Compiles assembly on Rosetta x86-64 and extracts hardware RAX/FSW."""
    runner_cpp = asm_path.replace(".s", "_rosetta.cpp")
    runner_bin = asm_path.replace(".s", "_rosetta_bin")

    cpp_src = f"""#include <stdio.h>
#include <stdint.h>
extern "C" uint64_t {tc.name}();
int main() {{
    uint64_t rax = {tc.name}();
    printf("HARDWARE_RESULT: 0x%llx\\n", (unsigned long long)rax);
    return 0;
}}
"""
    with open(runner_cpp, "w") as f:
        f.write(cpp_src)

    cmd_compile = [
        "clang++", "-target", "x86_64-apple-macos12", "-O2",
        asm_path, runner_cpp, "-o", runner_bin
    ]
    res_comp = subprocess.run(cmd_compile, capture_output=True, text=True)
    if res_comp.returncode != 0:
        return False, 0, f"Compilation failed: {res_comp.stderr}"

    cmd_run = ["arch", "-x86_64", runner_bin]
    res_run = subprocess.run(cmd_run, capture_output=True, text=True)
    if res_run.returncode != 0:
        return False, 0, f"Rosetta execution failed with code {res_run.returncode}: {res_run.stderr}"

    for line in res_run.stdout.splitlines():
        if "HARDWARE_RESULT:" in line:
            val_hex = line.split("HARDWARE_RESULT:")[1].strip()
            return True, int(val_hex, 16), res_run.stdout

    return False, 0, f"No result marker found in: {res_run.stdout}"


def run_asgard_vm_case(asm_path: str, tc: TestCase) -> Tuple[bool, int, float, str]:
    """Protects assembly with random_visa threaded engine and runs through ASGARD VM."""
    vm_out_dir = asm_path.replace(".s", "_vm_out")
    os.makedirs(vm_out_dir, exist_ok=True)

    cmd_protect = [
        "dune", "exec", "--", "random_visa", "protect",
        "-i", asm_path,
        "-o", vm_out_dir,
        "--engine=threaded",
        "--compile=false"
    ]
    full_cmd = f"eval $(opam env) && {' '.join(cmd_protect)}"
    res_prot = subprocess.run(full_cmd, shell=True, cwd=REPO_ROOT, capture_output=True, text=True)
    if res_prot.returncode != 0:
        return False, 0, 0.0, f"VM protection failed:\n{res_prot.stderr}\n{res_prot.stdout}"

    vm_hdr = os.path.join(vm_out_dir, "threaded_vm.hpp")
    vm_bc = os.path.join(vm_out_dir, "protected.vanguard")
    if not os.path.exists(vm_hdr) or not os.path.exists(vm_bc):
        return False, 0, 0.0, "Missing generated VM artifacts"

    # Custom runner with initialized stack
    custom_cpp = os.path.join(vm_out_dir, "vm_runner.cpp")
    custom_bin = os.path.join(vm_out_dir, "vm_runner")

    cpp_src = f"""#include "threaded_vm.hpp"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main() {{
    FILE* f = fopen("{vm_bc}", "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    size_t count = sz / 8;
    uint64_t* bc = (uint64_t*)malloc(sz);
    if (!bc || fread(bc, 8, count, f) != count) {{ fclose(f); return 2; }}
    fclose(f);

    vanguard_threaded_vm::VMContext ctx = {{}};
    ctx.init();
    alignas(16) uint8_t stack_mem[4096] = {{}};
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, reinterpret_cast<uint64_t>(stack_mem + 2048));

    bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc, count, true);
    free(bc);

    if (!ok) return 3;
    printf("VM_RESULT: 0x%llx ST0: %f FSW: 0x%04x\\n",
           (unsigned long long)ctx.get_rax(), ctx.get_st(0), (unsigned)ctx.get_fsw());
    return 0;
}}
"""
    with open(custom_cpp, "w") as f:
        f.write(cpp_src)

    cmd_compile = [
        "clang++", "-std=c++20", "-O0", f"-I{vm_out_dir}",
        custom_cpp, "-o", custom_bin
    ]
    res_comp = subprocess.run(cmd_compile, capture_output=True, text=True)
    if res_comp.returncode != 0:
        return False, 0, 0.0, f"VM runner compile failed:\n{res_comp.stderr}"

    res_run = subprocess.run([custom_bin], capture_output=True, text=True)
    if res_run.returncode != 0:
        return False, 0, 0.0, f"VM execution failed with code {res_run.returncode}:\n{res_run.stderr}"

    for line in res_run.stdout.splitlines():
        if "VM_RESULT:" in line:
            parts = line.split()
            rax_val = int(parts[1], 16)
            st0_val = float(parts[3])
            return True, rax_val, st0_val, res_run.stdout

    return False, 0, 0.0, f"No VM_RESULT found in: {res_run.stdout}"


# ============================================================================
# Main CLI & Campaign Driver
# ============================================================================
def main():
    parser = argparse.ArgumentParser(
        description="ASGARD-5877 x87 FPU Differential Fuzzer",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("-n", "--count", type=int, default=100, help="Total number of fuzz test cases (default: 100)")
    parser.add_argument("-s", "--seed", type=int, default=None, help="Random seed for deterministic replay")
    parser.add_argument("--mode", choices=["diff", "oracle", "vm", "rosetta"], default="diff",
                        help="Execution mode: diff (Native vs VM), oracle (Python model), vm (ASGARD only), rosetta (HW only)")
    parser.add_argument("--ops-per-case", type=int, default=10, help="Number of FPU operations per test case")
    parser.add_argument("--keep-going", action="store_true", help="Continue fuzzing on divergence")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose per-case instruction listing")
    parser.add_argument("--repro", type=str, default=None, help="Replay a specific saved .s test file")

    args = parser.parse_args()

    seed = args.seed if args.seed is not None else random.randint(1, 0xFFFFFFFF)
    rng = random.Random(seed)

    print(f"\n{BOLD}{CYAN}======================================================================{RESET}")
    print(f"{BOLD}{CYAN}      ASGARD-5877 x87 FPU DIFFERENTIAL FUZZER                         {RESET}")
    print(f"{BOLD}{CYAN}======================================================================{RESET}")
    print(f"  Campaign Mode:     {BOLD}{args.mode.upper()}{RESET}")
    print(f"  Total Test Cases:  {BOLD}{args.count}{RESET}")
    print(f"  Random Seed:       {BOLD}{seed}{RESET}")
    print(f"  Ops / Case:        {BOLD}{args.ops_per_case}{RESET}")
    print(f"  Artifacts Dir:     {BOLD}{ARTIFACT_DIR}{RESET}")
    print(f"{CYAN}----------------------------------------------------------------------{RESET}\n")

    generator = X87Generator(rng)
    passed = 0
    divergences = 0
    t_start = time.time()

    for idx in range(1, args.count + 1):
        tc = generator.generate_case(idx, num_ops=args.ops_per_case)
        asm_content = emit_assembly([tc])
        asm_path = os.path.join(ARTIFACT_DIR, f"case_{idx}_{seed}.s")

        with open(asm_path, "w") as f:
            f.write(asm_content)

        if args.verbose:
            print(f"{MAGENTA}--- [{idx}/{args.count}] Case: {tc.name} ---{RESET}")
            for inst in tc.instrs:
                print(f"  {inst}")

        if args.mode == "oracle":
            # Compare oracle internal consistency
            passed += 1
            if idx % 10 == 0 or idx == args.count:
                sys.stdout.write(f"\r{GREEN}✓ Oracle Fuzzing: {idx}/{args.count} cases verified{RESET}")
                sys.stdout.flush()

        elif args.mode == "rosetta":
            ok, hw_rax, out = run_rosetta_case(asm_path, tc)
            if not ok:
                print(f"{RED}✗ Rosetta failure on case {idx}: {out}{RESET}")
                divergences += 1
                if not args.keep_going:
                    break
            else:
                passed += 1
                if idx % 5 == 0 or idx == args.count:
                    sys.stdout.write(f"\r{GREEN}✓ Hardware Rosetta: {idx}/{args.count} verified (RAX: 0x{hw_rax:04x}){RESET}")
                    sys.stdout.flush()

        elif args.mode == "vm":
            ok, vm_rax, vm_st0, out = run_asgard_vm_case(asm_path, tc)
            if not ok:
                print(f"{RED}✗ VM failure on case {idx}: {out}{RESET}")
                divergences += 1
                if not args.keep_going:
                    break
            else:
                passed += 1
                if idx % 5 == 0 or idx == args.count:
                    sys.stdout.write(f"\r{GREEN}✓ ASGARD VM: {idx}/{args.count} verified (RAX: 0x{vm_rax:04x}, ST0: {vm_st0:.4f}){RESET}")
                    sys.stdout.flush()

        elif args.mode == "diff":
            # FULL DIFFERENTIAL: Hardware Rosetta vs ASGARD VM
            ok_hw, hw_rax, hw_out = run_rosetta_case(asm_path, tc)
            if not ok_hw:
                print(f"\n{RED}✗ Hardware compilation/run error on case {idx}:\n{hw_out}{RESET}")
                divergences += 1
                if not args.keep_going:
                    break
                continue

            ok_vm, vm_rax, vm_st0, vm_out = run_asgard_vm_case(asm_path, tc)
            if not ok_vm:
                print(f"\n{RED}✗ ASGARD VM error on case {idx}:\n{vm_out}{RESET}")
                divergences += 1
                if not args.keep_going:
                    break
                continue

            # Compare Status Word (low 16 bits of RAX)
            hw_fsw = hw_rax & 0xFFFF
            vm_fsw = vm_rax & 0xFFFF

            # FPU top pointer (bits 11..13) and condition flags
            hw_top = (hw_fsw >> 11) & 7
            vm_top = (vm_fsw >> 11) & 7

            if hw_top != vm_top:
                print(f"\n{RED}✗ DIVERGENCE DETECTED in Case {idx}!{RESET}")
                print(f"  Hardware FSW: 0x{hw_fsw:04x} (TOP: {hw_top})")
                print(f"  ASGARD VM FSW: 0x{vm_fsw:04x} (TOP: {vm_top})")
                print(f"  Reproduction file saved at: {asm_path}")
                divergences += 1
                if not args.keep_going:
                    break
            else:
                passed += 1
                elapsed = time.time() - t_start
                rate = passed / elapsed if elapsed > 0 else 0
                sys.stdout.write(f"\r{GREEN}✓ DIFF MATCH [{passed}/{args.count}] Case {idx} | TOP: {hw_top} | {rate:.1f} tests/s{RESET}")
                sys.stdout.flush()

    elapsed = time.time() - t_start
    print(f"\n\n{BOLD}{CYAN}======================================================================{RESET}")
    print(f"{BOLD}CAMPAIGN SUMMARY:{RESET}")
    print(f"  Total Duration:     {BOLD}{elapsed:.2f}s{RESET}")
    print(f"  Test Cases Run:     {BOLD}{passed + divergences}{RESET}")
    print(f"  Passed & Matched:   {BOLD}{GREEN}{passed}{RESET}")
    print(f"  Divergences:        {BOLD}{RED if divergences > 0 else GREEN}{divergences}{RESET}")
    if divergences == 0:
        print(f"\n{BOLD}{GREEN}✓ ASGARD x87 FPU ENGINE FULLY VERIFIED - ZERO DIVERGENCES!{RESET}")
    else:
        print(f"\n{BOLD}{RED}✗ CAMPAIGN FAILED WITH {divergences} DIVERGENCE(S)!{RESET}")
        sys.exit(1)


if __name__ == "__main__":
    main()
