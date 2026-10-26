#!/usr/bin/env python3
"""Dispatch topology of a protected Stack-VM program + machine-code check.

Bytecode layer (always available): rebuilds the block CFG from a phase
dump (JmpRel/JccRel targets are the only edges - every block ends in an
explicit terminator) and reports hub concentration.  A classical central
dispatcher (CFF unflattening target) shows up as one block with in-degree
dominating the edge set; dispersion shows up as a flat in-degree profile.

Machine-code layer (optional, --binary): analyzes an unstripped -O0 build
of the same runtime.  Beyond counting indirect-branch sites inside
`stack_vm_run`, it detects *epilogue re-centralization*: when the C
compiler merges the identical handler epilogues into one shared
trampoline, a single `br xN` block accumulates a near-#handlers in-degree
even though the source dispatches per handler - the exact hub topology
the pipelined design is meant to avoid, resurrected by codegen.

Usage:
    python3 dispatch_topology.py --phase-json "DUMP/phase_7-balance_(final).json" \
        [--binary probe_O0_binary]
"""

import argparse
import json
import re
import subprocess
import sys
from collections import Counter

BRANCH_RE = re.compile(r"\b(b|br|ret|cbz|cbnz|tbz|tbnz|blr)\b")


def load(path):
    with open(path) as fh:
        return json.load(fh)


def analyze_cfg(doc):
    edges = []
    for b in doc["blocks"]:
        for o in b["ops"]:
            if o["op"] in ("JmpRel", "JccRel"):
                edges.append((b["id"], o["args"][0]))
    blocks = {b["id"]: b for b in doc["blocks"]}
    indeg = Counter(t for _s, t in edges)
    hub, hub_in = (indeg.most_common(1)[0] if indeg else (None, 0))
    return {
        "blocks": len(blocks),
        "edges": len(edges),
        "indeg": indeg,
        "hub": hub,
        "hub_in": hub_in,
        "hub_label": blocks[hub]["label"] if hub in blocks else "?",
    }


def sym_ranges(binary):
    """symbol -> (start_addr, end_addr) from the (unstripped) symtab."""
    try:
        out = subprocess.run(["nm", "-n", binary], capture_output=True,
                             text=True, check=True).stdout
    except Exception as e:  # noqa: BLE001
        print("nm failed on %s: %s" % (binary, e))
        return {}
    syms = []
    for line in out.splitlines():
        m = re.match(r"^([0-9a-f]+)\s+[tT]\s+(\S+)", line)
        if m:
            syms.append((int(m.group(1), 16), m.group(2)))
    ranges = {}
    for i, (addr, name) in enumerate(syms):
        end = syms[i + 1][0] if i + 1 < len(syms) else addr + 0x100000
        ranges.setdefault(name, (addr, end))
    return ranges


def disasm(binary):
    for tool, args in (("llvm-objdump", ["-d"]), ("otool", ["-tv"])):
        try:
            out = subprocess.run([tool] + args + [binary], capture_output=True,
                                 text=True, check=True)
            return tool, out.stdout
        except Exception:  # noqa: BLE001
            continue
    return None, ""


def analyze_binary(binary, fn="stack_vm_run"):
    ranges = sym_ranges(binary)
    if fn not in ranges:
        cand = [k for k in ranges if fn in k]  # namespace-qualified name
        if not cand:
            print("symbol %s not found (binary stripped?) - skipping "
                  "machine-code layer" % fn)
            return None
        fn = cand[0]
    tool, text = disasm(binary)
    if tool is None:
        print("no disassembler (llvm-objdump/otool) - skipping machine-code layer")
        return None
    start, end = ranges[fn]
    body = []
    for line in text.splitlines():
        stripped = line.strip()
        m = re.match(r"^([0-9a-f]+)[\s\t]", stripped)
        if m:
            a = int(m.group(1), 16)
            if start <= a < end:
                body.append((a, stripped))
    indirect = [(a, l) for a, l in body
                if re.search(r"\bbr\s+x\d+", l) or re.search(r"\bjmp\s*\*", l)]
    rets = sum(1 for _a, l in body if re.search(r"\bret\b", l))
    handler_calls = sum(1 for _a, l in body if re.search(r"\bbl\s+_?h_", l))
    # Re-centralization: for each indirect site, find its basic-block head.
    # Epilogues are entered via direct branches, so the head is the nearest
    # preceding address that is itself a direct-branch target; the number of
    # `b <head>` predecessors measures how much the compiler merged the
    # per-handler epilogues back into one shared trampoline.
    targets = set()
    for _a, l in body:
        m = re.search(r"\bb\s+(0x[0-9a-f]+)", l)
        if m:
            t = int(m.group(1), 16)
            if start <= t < end:
                targets.add(t)
    body_index = {a: i for i, (a, _l) in enumerate(body)}
    sites = []
    for a, _l in indirect:
        head = body[0][0]
        for j in range(body_index[a], -1, -1):
            if body[j][0] in targets:
                head = body[j][0]
                break
        preds = sum(1 for _a2, l2 in body if re.search(r"\bb\s+0x0*%x\b" % head, l2))
        sites.append({"addr": a, "head": head, "direct_preds": preds})
    return {
        "tool": tool, "function": fn, "size": end - start,
        "indirect_sites": len(indirect), "sites": sites,
        "rets": rets, "handler_calls": handler_calls,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase-json", required=True)
    ap.add_argument("--binary", default=None,
                    help="unstripped -O0 build of the same runtime "
                         "(runner.cpp + stack_vm_runtime.hpp)")
    args = ap.parse_args()

    doc = load(args.phase_json)
    cfg = analyze_cfg(doc)
    hist = Counter(o["op"] for b in doc["blocks"] for o in b["ops"])

    print("=" * 78)
    print("DISPATCH TOPOLOGY  %s" % args.phase_json)
    print("=" * 78)
    print("blocks=%d  cfg-edges=%d" % (cfg["blocks"], cfg["edges"]))
    if cfg["hub"] is not None:
        share = 100.0 * cfg["hub_in"] / cfg["edges"] if cfg["edges"] else 0.0
        print("max in-degree: block %s (%r) with %d incoming edges "
              "(%.1f%% of all edges)"
              % (cfg["hub"], cfg["hub_label"], cfg["hub_in"], share))
        print("bytecode verdict: %s"
              % ("CENTRALIZED DISPATCHER CANDIDATE - unflattening target"
                 if share > 30.0 else "DISPERSED - no dominant hub"))
    print("top in-degree blocks: %s"
          % (", ".join("%s:%d" % kv for kv in cfg["indeg"].most_common(5)) or "-"))
    print("op histogram (top 10): %s"
          % ", ".join("%s=%d" % kv for kv in hist.most_common(10)))

    if args.binary:
        print("-" * 78)
        res = analyze_binary(args.binary)
        if res:
            print("machine-code layer [%s]: function %s, %d bytes, "
                  "%d indirect-branch site(s), %d rets, %d out-of-line "
                  "handler calls (0 = handlers inlined)"
                  % (res["tool"], res["function"], res["size"],
                     res["indirect_sites"], res["rets"], res["handler_calls"]))
            for s in res["sites"]:
                print("  site 0x%x: block head 0x%x, %d direct-branch "
                      "predecessors" % (s["addr"], s["head"], s["direct_preds"]))
            worst = max(res["sites"], key=lambda s: s["direct_preds"], default=None)
            if worst and worst["direct_preds"] > 32:
                print("  VERDICT: compiler merged the epilogues - the indirect "
                      "branch is CENTRALIZED again (hub in-degree %d); "
                      "per-handler dispersion was lost in codegen"
                      % worst["direct_preds"])
            elif res["indirect_sites"] > 32:
                print("  VERDICT: per-epilogue computed gotos survived codegen "
                      "(dispersion intact)")
            else:
                print("  VERDICT: centralized switch-style dispatch")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
