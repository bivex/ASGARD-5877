#!/usr/bin/env python3
"""Attacker-grade peephole reducer over ASGARD Stack-VM phase dumps.

Question answered: does the emitted bytecode simplify?  The reducer knows
only universal stack identities and dead-slot dataflow - no knowledge of
the pass seeds - so it lower-bounds what a one-pass pattern deobfuscator
(D810-style) recovers from the *decoded* program.

Rules (applied leftmost-first to fixpoint):
  Multiplicity inverses (always sound):
    Swap,Swap,Swap                        -> Swap
    Dup,Swap,Swap                         -> Dup
    Rot,Rot,Rot,Rot                       -> Rot
    PushReg r,[Dup|PushReg r],PopReg r    -> PushReg r
  Junk inverses (sound only when slot s is dead after the pattern; dead is
  "overwritten before any read in this block", plus a global tier for
  slots no block ever reads - that is where allocator scratch lands):
    PushImm v,PopReg s                    -> <nothing>
    PushImm v,Dup,Sub,PopReg s            -> <nothing>
    PushImm v,PushReg s,PopReg s,PopReg s -> <nothing>
    SetRegImm s,a,AddRegImm s,b,PopReg s  -> <nothing>

Implementation: linear left-to-right passes (no per-candidate forward
scans); slot deadness is answered in O(log n) from per-slot event lists.
Final programs exceed 10^6 ops, so pass count is capped and timed.

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


def load_phase(path):
    with open(path) as fh:
        return json.load(fh)


def ops_of(doc):
    out = {}
    for b in doc["blocks"]:
        out[b["id"]] = [(o["op"], tuple(o["args"])) for o in b["ops"]]
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
            # untouched for the rest of the block: only the global tier
            # can prove death (allocator scratch is never read anywhere)
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
        if name == "Swap" and i + 2 < n \
                and ops[i + 1][0] == "Swap" and ops[i + 2][0] == "Swap":
            out.append(ops[i]); hits["identity:Swap"] += 1; i += 3; continue
        if name == "Dup" and i + 2 < n \
                and ops[i + 1][0] == "Swap" and ops[i + 2][0] == "Swap":
            out.append(ops[i]); hits["identity:Dup"] += 1; i += 3; continue
        if name == "Rot" and i + 3 < n and ops[i + 1][0] == "Rot" \
                and ops[i + 2][0] == "Rot" and ops[i + 3][0] == "Rot":
            out.append(ops[i]); hits["identity:Rot"] += 1; i += 4; continue
        if name == "PushReg" and i + 2 < n:
            r = ops[i][1][0]
            mid, tail = ops[i + 1][0], ops[i + 2]
            if tail[0] == "PopReg" and tail[1][0] == r and \
                    (mid == "Dup" or (mid == "PushReg" and ops[i + 1][1][0] == r)):
                out.append(ops[i]); hits["identity:PushReg"] += 1; i += 3
                continue
        if name == "PushImm":
            if i + 1 < n and ops[i + 1][0] == "PopReg" \
                    and ev.dead(i + 2, ops[i + 1][1][0], greads):
                hits["junk:PushImm+PopReg"] += 1; i += 2; continue
            if i + 3 < n and ops[i + 1][0] == "Dup" and ops[i + 2][0] == "Sub" \
                    and ops[i + 3][0] == "PopReg" \
                    and ev.dead(i + 4, ops[i + 3][1][0], greads):
                hits["junk:PushImm+Dup+Sub"] += 1; i += 4; continue
            if i + 3 < n and ops[i + 1][0] == "PushReg" \
                    and ops[i + 2][0] == "PopReg" and ops[i + 3][0] == "PopReg" \
                    and ops[i + 1][1][0] == ops[i + 2][1][0] == ops[i + 3][1][0] \
                    and ev.dead(i + 4, ops[i + 3][1][0], greads):
                hits["junk:PushImm+PushReg"] += 1; i += 4; continue
        if name == "SetRegImm" and i + 2 < n \
                and ops[i + 1][0] == "AddRegImm" \
                and ops[i + 1][1][0] == ops[i][1][0] \
                and ops[i + 2][0] == "PopReg" and ops[i + 2][1][0] == ops[i][1][0] \
                and ev.dead(i + 3, ops[i][1][0], greads):
            hits["junk:SetRegImm+AddRegImm"] += 1; i += 3; continue
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


def main(dirs):
    for d in dirs:
        phases = sorted(glob.glob(os.path.join(d, "phase_*.json")))
        if not phases:
            print("no phase_*.json in %s" % d)
            continue
        print("=" * 78)
        print("PEEPHOLE ATTACK  %s" % d)
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
        print("final phase %s: %d ops -> %d after one-pattern attack "
              "(%.1f%% junk recovered; residual vs 1-lowered baseline: +%d ops)"
              % (final[0], final[1], final[2], pct, final[2] - base))
        print("rule hit counts: %s" % dict(final[4].most_common()))
        print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
