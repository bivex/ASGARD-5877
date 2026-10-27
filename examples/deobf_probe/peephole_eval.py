#!/usr/bin/env python3
"""Multi-Tier Attacker-Grade Peephole & SMT-Pattern Reducer for ASGARD Stack-VM.

Evaluates how much of a protected Stack-VM program can be simplified by
automated deobfuscation tools at different capability tiers:

Tier 1: Structural & Dead-Slot Patterns (Local Peephole + Linear DCE)
  - Multiplicity Structural Inverses:
      Swap,Swap,Swap                        -> Swap
      Dup,Swap,Swap                         -> Dup
      Rot,Rot,Rot,Rot                       -> Rot
      PushReg r,[Dup|PushReg r],PopReg r    -> PushReg r
  - Dead-Slot Junk Elimination (provably dead slots in O(log n)):
      PushImm v,PopReg s                    -> <nothing>
      PushImm v,Dup,Sub,PopReg s            -> <nothing>
      PushImm v,PushReg s,PopReg s,PopReg s -> <nothing>
      SetRegImm s,a,AddRegImm s,b,PopReg s  -> <nothing>

Tier 2: Semantic ALU & Algebraic Zero-Knot Inverses (Z3/D810/SMT-grade)
  - Add via Double-Negation Inverse:
      PushImm 0L,Swap,Sub,Sub               -> Add
  - Sub via Two's Complement Inverse:
      Dup,Nor,Add,PushImm 1L,Add            -> Sub
  - 5-NOR XOR Circuit Constant Folding:
      PushImm v1,PushImm v2,Dup2,Nor,Dup,Rot,Nor,Swap,Rot,Nor,Nor,Dup,Nor
                                            -> PushImm (v1 ^ v2)
  - Zero-Knots & Algebraic Neutral Elements:
      PushReg r,PushReg r,Nor,PushReg r,Nor,Add -> <nothing>  (r ^ ~r = -1; Nor(r, -1) = 0; +0 = id)
      PushImm 0L,Add                        -> <nothing>
      AddImm imm,SubImm imm                 -> <nothing>
      PushFlags,AddImm imm,SubImm imm,PopFlags -> <nothing>
  - Sub-Zero Difference Reductions:
      Sub,PushImm 0L,Cmp                    -> Cmp

Usage:
    python3 peephole_eval.py DUMP_DIR [DUMP_DIR ...]
"""

import glob
import json
import os
import re
import sys
import time
from bisect import bisect_left
from collections import Counter

PHASE_RE = re.compile(r"phase_(.+)\.json$")
MAX_PASSES = 8
MASK64 = 0xFFFFFFFFFFFFFFFF


def is_mod_inv_64(a, b):
    return isinstance(a, int) and isinstance(b, int) and (((a * b) & MASK64) == 1)
def load_phase(path):
    with open(path) as fh:
        return json.load(fh)


def parse_arg(a):
    if isinstance(a, str):
        try:
            return int(a, 0)
        except ValueError:
            return a
    return a


def ops_of(doc):
    out = {}
    for b in doc["blocks"]:
        out[b["id"]] = [(o["op"], tuple(parse_arg(x) for x in o["args"])) for o in b["ops"]]
    return out


def total_ops(blocks):
    return sum(len(v) for v in blocks.values())


def slot_reads_writes(op):
    name, args = op
    reads, writes = set(), set()
    if name == "PushReg":
        reads.add(args[0])
    elif name == "PopReg":
        writes.add(args[0])
    elif name == "SetRegImm":
        writes.add(args[0])
    elif name == "AddRegImm":
        reads.add(args[0])
        writes.add(args[0])
    elif name == "KeyFeedback":
        reads.add(args[0])
    elif name == "Cmov":
        writes.add(args[1])
    return reads, writes


def global_read_slots(blocks):
    reads = set()
    for ops in blocks.values():
        for op in ops:
            reads |= slot_reads_writes(op)[0]
    return reads


class SlotEvents:
    """Per-slot sorted (position, is_read) event list of one block."""

    def __init__(self, ops):
        self.events = {}
        for pos, op in enumerate(ops):
            reads, writes = slot_reads_writes(op)
            for s in reads:
                self.events.setdefault(s, []).append((pos, True))
            for s in writes:
                self.events.setdefault(s, []).append((pos, False))

    def dead(self, pos, slot, global_reads):
        """Slot dead at `pos` (rest-of-block only)."""
        evs = self.events.get(slot)
        if evs is None:
            return slot not in global_reads
        i = bisect_left(evs, (pos, False))
        if i >= len(evs):
            return slot not in global_reads
        return not evs[i][1]  # first event is a write -> dead


def one_pass(ops, ev, greads, hits):
    out = []
    i, n = 0, len(ops)
    while i < n:
        name = ops[i][0]

        # ── Tier 1: Multiplicity Structural Inverses ─────────────────────
        if name == "Swap" and i + 2 < n \
                and ops[i + 1][0] == "Swap" and ops[i + 2][0] == "Swap":
            out.append(ops[i])
            hits["T1:identity:Swap"] += 1
            i += 3
            continue

        if name == "Dup" and i + 2 < n \
                and ops[i + 1][0] == "Swap" and ops[i + 2][0] == "Swap":
            out.append(ops[i])
            hits["T1:identity:Dup"] += 1
            i += 3
            continue

        if name == "Rot" and i + 3 < n and ops[i + 1][0] == "Rot" \
                and ops[i + 2][0] == "Rot" and ops[i + 3][0] == "Rot":
            out.append(ops[i])
            hits["T1:identity:Rot"] += 1
            i += 4
            continue

        if name == "PushReg" and i + 2 < n:
            r = ops[i][1][0]
            mid, tail = ops[i + 1][0], ops[i + 2]
            if tail[0] == "PopReg" and tail[1][0] == r and \
                    (mid == "Dup" or (mid == "PushReg" and ops[i + 1][1][0] == r)):
                out.append(ops[i])
                hits["T1:identity:PushReg"] += 1
                i += 3
                continue

        # ── Tier 2: Semantic ALU Inverses ────────────────────────────────
        # Add via double negation: PushImm 0L, Swap, Sub, Sub -> Add
        if name == "PushImm" and ops[i][1] == (0,) and i + 3 < n \
                and ops[i + 1][0] == "Swap" and ops[i + 2][0] == "Sub" \
                and ops[i + 3][0] == "Sub":
            out.append(("Add", ()))
            hits["T2:semantic:Add_double_neg"] += 1
            i += 4
            continue

        # Sub via two's complement: Dup, Nor, Add, PushImm 1L, Add -> Sub
        if name == "Dup" and i + 4 < n \
                and ops[i + 1][0] == "Nor" and ops[i + 2][0] == "Add" \
                and ops[i + 3][0] == "PushImm" and ops[i + 3][1] == (1,) \
                and ops[i + 4][0] == "Add":
            out.append(("Sub", ()))
            hits["T2:semantic:Sub_twos_comp"] += 1
            i += 5
            continue

        # PushImm via 5-NOR XOR Circuit Constant Folding:
        # PushImm v1, PushImm v2, Dup2, Nor, Dup, Rot, Nor, Swap, Rot, Nor, Nor, Dup, Nor -> PushImm (v1 ^ v2)
        if name == "PushImm" and i + 12 < n and ops[i + 1][0] == "PushImm" \
                and ops[i + 2][0] == "Dup2" and ops[i + 3][0] == "Nor" \
                and ops[i + 4][0] == "Dup" and ops[i + 5][0] == "Rot" \
                and ops[i + 6][0] == "Nor" and ops[i + 7][0] == "Swap" \
                and ops[i + 8][0] == "Rot" and ops[i + 9][0] == "Nor" \
                and ops[i + 10][0] == "Nor" and ops[i + 11][0] == "Dup" \
                and ops[i + 12][0] == "Nor":
            v1 = ops[i][1][0]
            v2 = ops[i + 1][1][0]
            folded_v = v1 ^ v2
            out.append(("PushImm", (folded_v,)))
            hits["T2:semantic:PushImm_5nor_xor"] += 1
            i += 13
            continue

        # ── Tier 2: Zero-Knots & Algebraic Neutral Elements ──────────────
        # Nor-based zero knot: PushReg r, PushReg r, Nor, PushReg r, Nor, Add -> <nothing>
        if name == "PushReg" and i + 5 < n:
            r = ops[i][1][0]
            if ops[i + 1] == ops[i] and ops[i + 2][0] == "Nor" \
                    and ops[i + 3] == ops[i] and ops[i + 4][0] == "Nor" \
                    and ops[i + 5][0] == "Add":
                hits["T2:knot:Nor_zero_knot"] += 1
                i += 6
                continue

        # PushImm 0L, Add -> <nothing>
        if name == "PushImm" and ops[i][1] == (0,) and i + 1 < n \
                and ops[i + 1][0] == "Add":
            hits["T2:neutral:Add_zero"] += 1
            i += 2
            continue

        # AddImm imm, SubImm imm -> <nothing>
        if name == "AddImm" and i + 1 < n and ops[i + 1][0] == "SubImm" \
                and ops[i][1] == ops[i + 1][1]:
            hits["T2:neutral:AddImm_SubImm"] += 1
            i += 2
            continue

        # PushFlags, AddImm imm, SubImm imm, PopFlags -> <nothing>
        if name == "PushFlags" and i + 3 < n and ops[i + 1][0] == "AddImm" \
                and ops[i + 2][0] == "SubImm" and ops[i + 1][1] == ops[i + 2][1] \
                and ops[i + 3][0] == "PopFlags":
            hits["T2:neutral:Flag_AddSub"] += 1
            i += 4
            continue

        # CFF Sub-Zero Difference: Sub, PushImm 0L, Cmp -> Cmp
        if name == "Sub" and i + 2 < n and ops[i + 1][0] == "PushImm" \
                and ops[i + 1][1] == (0,) and ops[i + 2][0] == "Cmp":
            out.append(("Cmp", ()))
            hits["T2:cff:Sub_zero_cmp"] += 1
            i += 3
            continue
        # ── Tier 3: Amplifier Ring Twists & Reversible Cascades ───────────
        # v0: PushImm k, Mul, PushImm k_inv, Mul -> <nothing>
        if name == "PushImm" and i + 3 < n and ops[i + 1][0] == "Mul" \
                and ops[i + 2][0] == "PushImm" and ops[i + 3][0] == "Mul":
            if is_mod_inv_64(ops[i][1][0], ops[i + 2][1][0]):
                hits["T3:amplifier:ring_twist_v0"] += 1
                i += 4
                continue

        # v2/3: PushImm k_inv, PushImm k, Mul, Mul -> <nothing>
        if name == "PushImm" and i + 3 < n and ops[i + 1][0] == "PushImm" \
                and ops[i + 2][0] == "Mul" and ops[i + 3][0] == "Mul":
            if is_mod_inv_64(ops[i][1][0], ops[i + 1][1][0]):
                hits["T3:amplifier:ring_twist_v2"] += 1
                i += 4
                continue

        # v1: PushImm k1, Mul, PushImm k2, Mul, PushImm k_inv, Mul -> <nothing>
        if name == "PushImm" and i + 5 < n and ops[i + 1][0] == "Mul" \
                and ops[i + 2][0] == "PushImm" and ops[i + 3][0] == "Mul" \
                and ops[i + 4][0] == "PushImm" and ops[i + 5][0] == "Mul":
            k1, k2, k3 = ops[i][1][0], ops[i + 2][1][0], ops[i + 4][1][0]
            if isinstance(k1, int) and isinstance(k2, int) and isinstance(k3, int) \
                    and (((k1 * k2 * k3) & MASK64) == 1):
                hits["T3:amplifier:ring_twist_v1"] += 1
                i += 6
                continue

        # ── Tier 3: Constant Arithmetic Folding & MBA Reduction ──────────
        # PushImm a, PushImm b, BinOp -> PushImm (a OP b)
        if name == "PushImm" and i + 2 < n and ops[i + 1][0] == "PushImm" \
                and ops[i + 2][0] in ("Add", "Sub", "Mul", "Nor", "Nand"):
            a, b = ops[i][1][0], ops[i + 1][1][0]
            binop = ops[i + 2][0]
            if isinstance(a, int) and isinstance(b, int):
                res = None
                if binop == "Add": res = (a + b) & MASK64
                elif binop == "Sub": res = (a - b) & MASK64
                elif binop == "Mul": res = (a * b) & MASK64
                elif binop == "Nor": res = (~(a | b)) & MASK64
                elif binop == "Nand": res = (~(a & b)) & MASK64
                if res is not None:
                    out.append(("PushImm", (res,)))
                    hits["T3:const_fold:" + binop] += 1
                    i += 3
                    continue

        # ── Tier 3: Superoperator Immediate Constant Folding ─────────────
        if name == "AddImmImm":
            a, b = ops[i][1]
            out.append(("PushImm", (((a + b) & MASK64),)))
            hits["T3:superop:AddImmImm"] += 1
            i += 1
            continue

        if name == "SubImmImm":
            a, b = ops[i][1]
            out.append(("PushImm", (((a - b) & MASK64),)))
            hits["T3:superop:SubImmImm"] += 1
            i += 1
            continue

        if name in ("AddImm", "SubImm") and ops[i][1] == (0,):
            hits["T3:superop:ZeroImm"] += 1
            i += 1
            continue

        if name == "PushImm" and i + 1 < n and ops[i + 1][0] == "AddImm":
            a, b = ops[i][1][0], ops[i + 1][1][0]
            if isinstance(a, int) and isinstance(b, int):
                out.append(("PushImm", (((a + b) & MASK64),)))
                hits["T3:superop:PushImm_AddImm"] += 1
                i += 2
                continue

        if name == "PushImm" and i + 1 < n and ops[i + 1][0] == "SubImm":
            a, b = ops[i][1][0], ops[i + 1][1][0]
            if isinstance(a, int) and isinstance(b, int):
                out.append(("PushImm", (((a - b) & MASK64),)))
                hits["T3:superop:PushImm_SubImm"] += 1
                i += 2
                continue

        # ── Tier 3: Opaque Zero Branch Deobfuscation (CFF / Spaghetti) ────
        # [PushImm r1; PushImm r2; Mul; PushImm r3; Add;
        #  PushImm r1; PushImm r2; Mul; PushImm r3; Add;
        #  Sub; PushImm 0L; Cmp; JccRel (real, E); JmpRel decoy] -> JmpRel real
        if name == "PushImm" and i + 13 < n \
                and ops[i + 1][0] == "PushImm" and ops[i + 2][0] == "Mul" \
                and ops[i + 3][0] == "PushImm" and ops[i + 4][0] == "Add" \
                and ops[i + 5][0] == "PushImm" and ops[i + 6][0] == "PushImm" \
                and ops[i + 7][0] == "Mul" and ops[i + 8][0] == "PushImm" \
                and ops[i + 9][0] == "Add" and ops[i + 10][0] == "Sub" \
                and ops[i + 11][0] == "PushImm" and ops[i + 11][1] == (0,) \
                and ops[i + 12][0] == "Cmp" and ops[i + 13][0] == "JccRel":
            real_target = ops[i + 13][1][0]
            out.append(("JmpRel", (real_target,)))
            hits["T3:cff:opaque_zero_branch"] += 1
            i += 15 if (i + 14 < n and ops[i + 14][0] == "JmpRel") else 14
            continue


        # ── Tier 1: Dead-Slot Junk Elimination ───────────────────────────
        if name == "PushImm":
            if i + 1 < n and ops[i + 1][0] == "PopReg" \
                    and ev.dead(i + 2, ops[i + 1][1][0], greads):
                hits["T1:junk:PushImm+PopReg"] += 1
                i += 2
                continue
            if i + 3 < n and ops[i + 1][0] == "Dup" and ops[i + 2][0] == "Sub" \
                    and ops[i + 3][0] == "PopReg" \
                    and ev.dead(i + 4, ops[i + 3][1][0], greads):
                hits["T1:junk:PushImm+Dup+Sub"] += 1
                i += 4
                continue
            if i + 3 < n and ops[i + 1][0] == "PushReg" \
                    and ops[i + 2][0] == "PopReg" and ops[i + 3][0] == "PopReg" \
                    and ops[i + 1][1][0] == ops[i + 2][1][0] == ops[i + 3][1][0] \
                    and ev.dead(i + 4, ops[i + 3][1][0], greads):
                hits["T1:junk:PushImm+PushReg"] += 1
                i += 4
                continue

        if name == "SetRegImm" and i + 2 < n \
                and ops[i + 1][0] == "AddRegImm" \
                and ops[i + 1][1][0] == ops[i][1][0] \
                and ops[i + 2][0] == "PopReg" and ops[i + 2][1][0] == ops[i][1][0] \
                and ev.dead(i + 3, ops[i][1][0], greads):
            hits["T1:junk:SetRegImm+AddRegImm"] += 1
            i += 3
            continue

        out.append(ops[i])
        i += 1
    return out


def reduce_block(ops, greads):
    hits = Counter()
    for _ in range(MAX_PASSES):
        ev = SlotEvents(ops)
        new = one_pass(ops, ev, greads, hits)
        if len(new) == len(ops):
            break
        ops = new
    return ops, hits


def reduce_program(blocks):
    greads = global_read_slots(blocks)
    total = Counter()
    out = {}
    for bid, ops in blocks.items():
        out[bid], hits = reduce_block(ops, greads)
        total.update(hits)
    return out, total


def op_stack_effects(name):
    """Returns (pops, pushes) for Stack-VM operations."""
    if name in ("PushImm", "PushImm32", "PushReg", "ResolveSym", "Setcc", "AddImm", "SubImm", "AddImmImm", "SubImmImm", "AddRegImm"):
        return 0, 1
    if name == "Dup":
        return 1, 2
    if name == "Dup2":
        return 2, 4
    if name == "Rot":
        return 3, 3
    if name == "Swap":
        return 2, 2
    if name in ("PopReg", "ReadMem", "PopFlags", "Cmov", "AddImm", "SubImm"):
        return 1, 0
    if name in ("WriteMem", "Add", "Sub", "Mul", "Nor", "Nand", "Shl", "Shr", "Sar", "Div", "Idiv", "Cmp", "Test"):
        return 2, 0
    return 0, 0


def tier4_backward_slice(blocks, entry_id=0):
    """
    Tier 4 Backward Program Slicer (fixpoint inter-block liveness):
    Computes the minimal semantic program preserving observable I/O and control flow.
    Observable Sinks: CallExtern, ResolveSym, WriteMem, Exit (with return ctx[0]), JccRel, JmpRel.
    Excludes internal VM rolling key ops (KeyFeedback, KeyAdjust) to model lifter-based devirtualization.

    Iterates slot-liveness to fixpoint across the block CFG so live-in slots
    of ANY block force retention of their writers in EVERY predecessor
    round (order-independent, unlike the previous single forward pass).
    """
    # 1. CFG Reachability
    succs = {}
    for bid, ops in blocks.items():
        succs[bid] = []
        for op in ops:
            if op[0] in ("JmpRel", "JccRel"):
                succs[bid].append(op[1][0])

    reachable = set()
    worklist = [entry_id]
    while worklist:
        curr = worklist.pop()
        if curr not in reachable and curr in blocks:
            reachable.add(curr)
            for s in succs.get(curr, []):
                worklist.append(s)

    total_ops_count = sum(len(ops) for bid, ops in blocks.items())

    def slice_block(ops, live_in):
        """One backward pass over a block; returns (marked, live_before, reads_without_write)."""
        marked = set()
        stack_needed = 0
        local_live = set(live_in)
        upward_reads = set()
        for idx in range(len(ops) - 1, -1, -1):
            name, args = ops[idx]
            is_sink = name in ("CallExtern", "ResolveSym", "WriteMem", "Exit", "JccRel", "JmpRel")
            needed = is_sink

            if stack_needed > 0:
                pushes = 1 if name in ("PushImm", "PushImm32", "PushReg", "ResolveSym", "Setcc", "AddImm", "SubImm", "AddImmImm", "SubImmImm", "AddRegImm") else (2 if name == "Dup" else (4 if name == "Dup2" else 0))
                if pushes > 0:
                    needed = True
                    stack_needed = max(0, stack_needed - pushes)

            if name in ("PopReg", "SetRegImm", "AddRegImm", "Cmov"):
                r = args[0] if name != "Cmov" else args[1]
                if r in local_live:
                    needed = True
                    local_live.discard(r)

            if needed:
                marked.add(idx)
                pops = 1 if name in ("PopReg", "ReadMem", "PopFlags", "Cmov", "AddImm", "SubImm") else (2 if name in ("WriteMem", "Add", "Sub", "Mul", "Nor", "Nand", "Shl", "Shr", "Sar", "Div", "Idiv", "Cmp", "Test", "Swap") else (3 if name == "Rot" else 0))
                stack_needed += pops
                if name in ("PushReg", "AddRegImm"):
                    local_live.add(args[0])

        # upward reads: slots read by marked ops before being written in this block
        written = set()
        for idx, op in enumerate(ops):
            name, args = op
            if idx in marked and name in ("PushReg", "AddRegImm"):
                r = args[0]
                if r not in written:
                    upward_reads.add(r)
            if name in ("PopReg", "SetRegImm", "AddRegImm", "Cmov"):
                r = args[0] if name != "Cmov" else args[1]
                written.add(r)
        return marked, local_live, upward_reads

    # 2. Fixpoint over inter-block slot liveness (max 4 rounds; converges
    # fast because live sets only grow and are bounded by slot count)
    global_live = {0}
    marks_per_block = {bid: set() for bid in blocks}
    for _round in range(4):
        changed = False
        for bid in reachable:
            ops = blocks[bid]
            marked, live_out_unused, upward = slice_block(ops, global_live)
            if not marked and ops:
                marked = {len(ops) - 1}
            if marked != marks_per_block[bid] or (upward - global_live):
                changed = True
            marks_per_block[bid] = marked
            global_live |= upward
        if not changed:
            break

    kept_ops_count = sum(len(marks_per_block[bid]) for bid in reachable)
    sliced_away = total_ops_count - kept_ops_count
    pct = 100.0 * sliced_away / max(total_ops_count, 1)
    return kept_ops_count, sliced_away, pct


def main(dirs):
    for d in dirs:
        phases = sorted(glob.glob(os.path.join(d, "phase_*.json")))
        if not phases:
            print("no phase_*.json in %s" % d)
            continue
        print("=" * 78)
        print("MULTI-TIER DEOBFUSCATION PROBE  %s" % d)
        print("=" * 78)
        baseline = None
        rows = []
        for p in phases:
            name = PHASE_RE.search(os.path.basename(p)).group(1)
            t0 = time.time()
            blocks = ops_of(load_phase(p))
            n0 = total_ops(blocks)
            if name == "1-lowered":
                baseline = n0
            reduced, hits = reduce_program(blocks)
            n1 = total_ops(reduced)
            rows.append((name, n0, n1, n0 - n1, hits))
            print("  %-22s %8d -> %8d  (%.1fs)"
                  % (name, n0, n1, time.time() - t0))
        base = baseline if baseline is not None else rows[0][1]
        print("-" * 78)
        print("%-24s %9s %9s %8s %9s" % ("phase", "ops", "reduced", "removed", "vs-base"))
        for name, n0, n1, rm, _hits in rows:
            print("%-24s %9d %9d %8d %8.1f%%"
                  % (name, n0, n1, rm, 100.0 * (n0 - n1) / max(base, 1)))
        final = rows[-1]
        pct = 100.0 * final[3] / final[1] if final[1] else 0.0
        print("-" * 78)
        print("final phase %s: %d ops -> %d after multi-tier attack "
              "(%.1f%% junk recovered; residual vs 1-lowered baseline: +%d ops)"
              % (final[0], final[1], final[2], pct, final[2] - base))

        # Categorized Rule Summary
        t1_hits = sum(cnt for r, cnt in final[4].items() if r.startswith("T1:"))
        t2_hits = sum(cnt for r, cnt in final[4].items() if r.startswith("T2:"))
        t3_hits = sum(cnt for r, cnt in final[4].items() if r.startswith("T3:"))
        print()
        print("ATTACK BREAKDOWN:")
        print("  • Tier 1 (Structural & Dead-Slot DCE): %d reductions" % t1_hits)
        print("  • Tier 2 (Semantic ALU, XOR & Knots): %d reductions" % t2_hits)
        print("  • Tier 3 (Constant Folding, Ring Twists & Superops): %d reductions" % t3_hits)
        print()
        print("RULE HIT COUNTS (Final Phase):")
        for r, cnt in final[4].most_common(12):
            print("  %-32s : %d" % (r, cnt))
        print()
        print("INTERMEDIATE PHASE ATTACK SUMMARY:")
        for name, n0, n1, rm, p_hits in rows:
            if rm > 0:
                top_p = ", ".join("%s:%d" % (k.split(":")[-1], v) for k, v in p_hits.most_common(3))
                pct_p = 100.0 * rm / n0
                print("  %-20s : -%6d ops (-%4.1f%%) [%s]" % (name, rm, pct_p, top_p))
        print()

        # ── Tier 4: Backward Program Slicing Evaluation ───────────────────────
        print("-" * 78)
        print("TIER 4: BACKWARD PROGRAM SLICING (LIFTER & I/O THREAT MODEL):")
        final_doc = load_phase(phases[-1])
        final_raw_blocks = ops_of(final_doc)
        entry_id = final_doc.get("entry_id", 0)
        s_kept, s_removed, s_pct = tier4_backward_slice(final_raw_blocks, entry_id)
        print("  • Observable I/O Sinks: CallExtern, ResolveSym, WriteMem, Exit, JccRel, JmpRel")
        print("  • Excluded from Seeds: KeyFeedback, KeyAdjust (simulating LLVM IR lifter)")
        print("  • Slicing Reduction:   %d ops -> %d kept (-%d ops, %.1f%% sliced away)"
              % (total_ops(final_raw_blocks), s_kept, s_removed, s_pct))
        print("  • Semantic Residual:   %d ops (+%.1fx vs %d baseline ops)"
              % (s_kept, float(s_kept) / max(base, 1), base))
        print("=" * 78)
        print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
