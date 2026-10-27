#!/usr/bin/env python3
"""
triton_symbolic_eval.py — Triton-style Symbolic Execution & SMT Deobfuscator
─────────────────────────────────────────────────────────────────────────────
Simulates a Triton-based Dynamic Binary Analysis (DBA) / Symbolic Execution
attack against Stack-VM bytecode phase dumps.

Attack Capabilities:
1. Symbolic BitVector AST Execution: Models 64-bit context registers (ctx[r])
   and LIFO stack elements as BitVector terms in Z3's QF_BV theory.
2. Flag & Condition Emulation: Tracks lazy symbolic expressions for Zero (ZF),
   Sign (SF), Carry (CF), and Overflow (OF) flags across ALU and bitwise ops.
3. Opaque Predicate Simplification: Solves condition codes of JccRel branch
   terminators using SMT simplification to detect Always-True (de-obfuscated)
   or Always-False (dead) decoy edges.
4. Symbolic Constant Folding: Evaluates whether obfuscated register and stack
   expressions resolve to ground constants via SMT term rewriting.
5. Symbolic AST Complexity Metrics: Measures node counts, tree depth, and
   residual complexity after SMT simplification.

Usage:
  python3 examples/deobf_probe/triton_symbolic_eval.py <DUMP_DIR> [...]
"""

import sys
import os
import glob
import re
import time
import json
import z3

PHASE_RE = re.compile(r"phase_(.+)\.json$")
MASK64 = 0xFFFFFFFFFFFFFFFF


def count_ast_nodes(ast):
    """Counts unique sub-AST nodes in a Z3 expression."""
    visited = set()
    stack = [ast]
    count = 0
    while stack:
        curr = stack.pop()
        ast_id = curr.get_id()
        if ast_id in visited:
            continue
        visited.add(ast_id)
        count += 1
        for child in curr.children():
            stack.append(child)
    return count


def parse_arg(a):
    if isinstance(a, str):
        try:
            return int(a, 0) if a.startswith(("0x", "0X")) else int(a)
        except ValueError:
            return a
    return a


class SymbolicFlags:
    """Lazy symbolic condition flags for Stack-VM."""
    def __init__(self, prefix="init"):
        self.zf = z3.Bool(f"zf_{prefix}")
        self.sf = z3.Bool(f"sf_{prefix}")
        self.cf = z3.Bool(f"cf_{prefix}")
        self.of = z3.Bool(f"of_{prefix}")


class TritonSymbolicVM:
    """Symbolic Execution Engine for Stack-VM using Z3 bitvectors."""
    def __init__(self, block_id):
        self.block_id = block_id
        self.ctx = {}
        self.stack = []
        self.flags = SymbolicFlags(f"b{block_id}")
        self.flags_saved = []
        self.modified_regs = set()
        self.underflow_counter = 0

    def get_reg(self, r):
        if r not in self.ctx:
            self.ctx[r] = z3.BitVec(f"ctx_{r}", 64)
        return self.ctx[r]

    def set_reg(self, r, v):
        self.ctx[r] = v
        self.modified_regs.add(r)

    def push(self, v):
        self.stack.append(v)

    def pop(self):
        if self.stack:
            return self.stack.pop()
        self.underflow_counter += 1
        return z3.BitVec(f"underflow_b{self.block_id}_{self.underflow_counter}", 64)

    def update_flags_add(self, a, b, res):
        self.flags.zf = (res == 0)
        self.flags.sf = (z3.Extract(63, 63, res) == 1)
        self.flags.cf = z3.ULT(res, a)
        sign_a = z3.Extract(63, 63, a)
        sign_b = z3.Extract(63, 63, b)
        sign_r = z3.Extract(63, 63, res)
        self.flags.of = z3.And(sign_a == sign_b, sign_a != sign_r)

    def update_flags_sub(self, a, b, res):
        # a - b
        self.flags.zf = (res == 0)
        self.flags.sf = (z3.Extract(63, 63, res) == 1)
        self.flags.cf = z3.ULT(a, b)
        sign_a = z3.Extract(63, 63, a)
        sign_b = z3.Extract(63, 63, b)
        sign_r = z3.Extract(63, 63, res)
        self.flags.of = z3.And(sign_a != sign_b, sign_a != sign_r)

    def update_flags_logic(self, res):
        self.flags.zf = (res == 0)
        self.flags.sf = (z3.Extract(63, 63, res) == 1)
        self.flags.cf = z3.BoolVal(False)
        self.flags.of = z3.BoolVal(False)

    def eval_condition(self, cond):
        c = cond.upper()
        if c in ("E", "Z"):
            return self.flags.zf
        if c in ("NE", "NZ"):
            return z3.Not(self.flags.zf)
        if c in ("S",):
            return self.flags.sf
        if c in ("NS",):
            return z3.Not(self.flags.sf)
        if c in ("B", "C"):
            return self.flags.cf
        if c in ("AE", "NC"):
            return z3.Not(self.flags.cf)
        if c in ("BE",):
            return z3.Or(self.flags.cf, self.flags.zf)
        if c in ("A",):
            return z3.And(z3.Not(self.flags.cf), z3.Not(self.flags.zf))
        if c in ("L",):
            return self.flags.sf != self.flags.of
        if c in ("GE",):
            return self.flags.sf == self.flags.of
        if c in ("LE",):
            return z3.Or(self.flags.zf, self.flags.sf != self.flags.of)
        if c in ("G",):
            return z3.And(z3.Not(self.flags.zf), self.flags.sf == self.flags.of)
        return z3.Bool(f"cond_{c}")


def evaluate_block_symbolic(block, max_ops=5000):
    """Executes a block symbolically up to max_ops and runs SMT simplification."""
    ops = block["ops"]
    if len(ops) > max_ops:
        ops = ops[:max_ops]

    vm = TritonSymbolicVM(block["id"])
    broken_opaque = []
    folded_constants = []

    for o in ops:
        name = o["op"]
        args = [parse_arg(a) for a in o.get("args", [])]

        if name == "PushImm":
            vm.push(z3.BitVecVal(args[0] & MASK64, 64))

        elif name == "PushReg":
            vm.push(vm.get_reg(args[0]))

        elif name == "PopReg":
            vm.set_reg(args[0], vm.pop())

        elif name == "Add":
            b = vm.pop()
            a = vm.pop()
            res = a + b
            vm.update_flags_add(a, b, res)
            vm.push(res)

        elif name == "Sub":
            b = vm.pop()
            a = vm.pop()
            res = a - b
            vm.update_flags_sub(a, b, res)
            vm.push(res)

        elif name == "Mul":
            b = vm.pop()
            a = vm.pop()
            vm.push(a * b)

        elif name == "Nor":
            b = vm.pop()
            a = vm.pop()
            res = ~(a | b)
            vm.update_flags_logic(res)
            vm.push(res)

        elif name == "Nand":
            b = vm.pop()
            a = vm.pop()
            res = ~(a & b)
            vm.update_flags_logic(res)
            vm.push(res)

        elif name == "Shl":
            b = vm.pop()
            a = vm.pop()
            vm.push(a << b)

        elif name == "Shr":
            b = vm.pop()
            a = vm.pop()
            vm.push(z3.LShR(a, b))

        elif name == "Sar":
            b = vm.pop()
            a = vm.pop()
            vm.push(a >> b)

        elif name == "Dup":
            top = vm.pop()
            vm.push(top)
            vm.push(top)

        elif name == "Dup2":
            first = vm.pop()
            second = vm.pop()
            vm.push(second)
            vm.push(first)
            vm.push(second)
            vm.push(first)

        elif name == "Rot":
            if len(vm.stack) >= 3:
                a = vm.pop()
                b = vm.pop()
                c = vm.pop()
                vm.push(b)
                vm.push(a)
                vm.push(c)

        elif name == "Swap":
            first = vm.pop()
            second = vm.pop()
            vm.push(first)
            vm.push(second)

        elif name == "PushFlags":
            vm.flags_saved.append((vm.flags.zf, vm.flags.sf, vm.flags.cf, vm.flags.of))

        elif name == "PopFlags":
            if vm.flags_saved:
                zf, sf, cf, of = vm.flags_saved.pop()
                vm.flags.zf = zf
                vm.flags.sf = sf
                vm.flags.cf = cf
                vm.flags.of = of

        elif name == "Cmp":
            b = vm.pop()
            a = vm.pop()
            vm.update_flags_sub(a, b, a - b)

        elif name == "Test":
            b = vm.pop()
            a = vm.pop()
            vm.update_flags_logic(a & b)

        elif name == "Setcc":
            cond = args[0]
            c_expr = vm.eval_condition(cond)
            vm.push(z3.If(c_expr, z3.BitVecVal(1, 64), z3.BitVecVal(0, 64)))

        elif name == "Cmov":
            cond, slot = args[0], args[1]
            c_expr = vm.eval_condition(cond)
            val = vm.pop()
            vm.set_reg(slot, z3.If(c_expr, val, vm.get_reg(slot)))

        elif name == "AddImm":
            c = z3.BitVecVal(args[0] & MASK64, 64)
            a = vm.pop()
            res = a + c
            vm.update_flags_add(a, c, res)
            vm.push(res)

        elif name == "SubImm":
            c = z3.BitVecVal(args[0] & MASK64, 64)
            a = vm.pop()
            res = a - c
            vm.update_flags_sub(a, c, res)
            vm.push(res)

        elif name == "AddImmImm":
            a = z3.BitVecVal(args[0] & MASK64, 64)
            b = z3.BitVecVal(args[1] & MASK64, 64)
            res = a + b
            vm.update_flags_add(a, b, res)
            vm.push(res)

        elif name == "SubImmImm":
            a = z3.BitVecVal(args[0] & MASK64, 64)
            b = z3.BitVecVal(args[1] & MASK64, 64)
            res = a - b
            vm.update_flags_sub(a, b, res)
            vm.push(res)

        elif name == "SetRegImm":
            vm.set_reg(args[0], z3.BitVecVal(args[1] & MASK64, 64))

        elif name == "AddRegImm":
            c = z3.BitVecVal(args[1] & MASK64, 64)
            v = vm.get_reg(args[0])
            res = v + c
            vm.update_flags_add(v, c, res)
            vm.set_reg(args[0], res)

        elif name == "JccRel":
            target, cond = args[0], args[1]
            cond_expr = vm.eval_condition(cond)
            # SMT Simplification of branch condition
            try:
                simp_cond = z3.simplify(cond_expr)
                if z3.is_true(simp_cond):
                    broken_opaque.append((block["id"], target, cond, "ALWAYS_TRUE"))
                elif z3.is_false(simp_cond):
                    broken_opaque.append((block["id"], target, cond, "ALWAYS_FALSE"))
            except Exception:
                pass

    # SMT Evaluation of modified context slots at block exit
    ast_initial = 0
    ast_simplified = 0
    expressions_checked = 0

    for r in vm.modified_regs:
        expr = vm.ctx[r]
        n_init = count_ast_nodes(expr)
        ast_initial += n_init
        expressions_checked += 1
        try:
            simp = z3.simplify(expr)
            n_simp = count_ast_nodes(simp)
            ast_simplified += n_simp
            if z3.is_bv_value(simp) and n_init > 1:
                folded_constants.append((block["id"], f"ctx[{r}]", simp.as_long()))
        except Exception:
            ast_simplified += n_init

    # Evaluate stack outputs
    for s_idx, expr in enumerate(vm.stack):
        n_init = count_ast_nodes(expr)
        ast_initial += n_init
        expressions_checked += 1
        try:
            simp = z3.simplify(expr)
            n_simp = count_ast_nodes(simp)
            ast_simplified += n_simp
            if z3.is_bv_value(simp) and n_init > 1:
                folded_constants.append((block["id"], f"stack[{s_idx}]", simp.as_long()))
        except Exception:
            ast_simplified += n_init

    return {
        "ops_executed": len(ops),
        "broken_opaque": broken_opaque,
        "folded_constants": folded_constants,
        "ast_initial": ast_initial,
        "ast_simplified": ast_simplified,
        "expressions_checked": expressions_checked,
    }


def analyze_phase(phase_path, max_blocks=100):
    with open(phase_path) as fh:
        doc = json.load(fh)

    blocks = doc.get("blocks", [])
    if max_blocks and len(blocks) > max_blocks:
        blocks = blocks[:max_blocks]

    t0 = time.time()
    total_ops = 0
    all_broken_opaque = []
    all_folded_constants = []
    total_ast_init = 0
    total_ast_simp = 0
    total_exprs = 0

    for b in blocks:
        res = evaluate_block_symbolic(b)
        total_ops += res["ops_executed"]
        all_broken_opaque.extend(res["broken_opaque"])
        all_folded_constants.extend(res["folded_constants"])
        total_ast_init += res["ast_initial"]
        total_ast_simp += res["ast_simplified"]
        total_exprs += res["expressions_checked"]

    elapsed = time.time() - t0
    reduction_pct = (1.0 - (total_ast_simp / max(total_ast_init, 1))) * 100.0

    return {
        "blocks": len(blocks),
        "ops": total_ops,
        "opaque_broken": len(all_broken_opaque),
        "consts_folded": len(all_folded_constants),
        "ast_init": total_ast_init,
        "ast_simp": total_ast_simp,
        "reduction_pct": reduction_pct,
        "time": elapsed,
    }


def main(dirs):
    for d in dirs:
        phases = sorted(glob.glob(os.path.join(d, "phase_*.json")))
        if not phases:
            print("[-] No phase_*.json found in", d)
            continue

        print("=" * 80)
        print("TRITON-STYLE SYMBOLIC EXECUTION & SMT DEOBFUSCATION PROBE")
        print("Target:", d)
        print("Engine: Z3 SMT (QF_BV Theory, AST Simplification & Opaque Solver)")
        print("=" * 80)
        print("%-22s %7s %8s %8s %10s %10s %9s %6s" %
              ("Phase", "Blocks", "SymOps", "Opaque", "ConstFold", "AST Init", "AST Simp", "Time"))
        print("-" * 80)

        for p in phases:
            p_name = PHASE_RE.search(os.path.basename(p)).group(1)
            # Sample up to 50 blocks per phase for fast execution
            r = analyze_phase(p, max_blocks=50)
            print("%-22s %7d %8d %8d %10d %10d %9d %5.1fs" %
                  (p_name, r["blocks"], r["ops"], r["opaque_broken"],
                   r["consts_folded"], r["ast_init"], r["ast_simp"], r["time"]))

        print("-" * 80)
        print("[+] Symbolic execution analysis complete.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
