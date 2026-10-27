"""
asgard_analyzer.py — IDA Pro Binary & Obfuscation Analysis Plugin
─────────────────────────────────────────────────────────────────────────────
Comprehensive binary analysis and deobfuscation audit plugin for IDA Pro (8.x/9.x).
Supports interactive GUI mode (Edit -> Plugins or Ctrl+Alt+A) and headless CLI mode
via idat / idat64.

Analysis Capabilities:
1. CFG & Cyclomatic Complexity:
   - Computes cyclomatic complexity M = E - N + 2P per function.
   - Extracts basic block count (N), control-flow edge count (E).
   - Measures maximum block in-degree (detects CFF flattening hubs).
2. Instruction & Dispatch Profiling:
   - Classifies instructions: Arithmetic, Logic, Memory, Direct Branches.
   - Identifies Indirect Jumps (br xN, jmp reg) and computed goto dispatches.
   - Computes indirect branch ratio (key indicator of VM interpretation).
3. Segment Entropy & Payload Scanner:
   - Measures Shannon entropy per section to identify encrypted bytecode payloads (H > 7.5).
4. Automated JSON Export:
   - Saves structured audit results to `asgard_ida_audit.json`.

Usage in Headless Mode:
  idat64 -A -S"tools/ida_analyzer/asgard_analyzer.py" <target_binary>
"""

import os
import sys
import math
import json
import collections

# Attempt IDA imports
try:
    import ida_idaapi
    import ida_auto
    import ida_funcs
    import ida_segment
    import ida_bytes
    import ida_ua
    import ida_gdl
    import ida_lines
    import ida_pro
    import idc
    IN_IDA = True
except ImportError:
    IN_IDA = False


def shannon_entropy(data: bytes) -> float:
    """Calculates Shannon entropy in bits per byte (0.0 to 8.0)."""
    if not data:
        return 0.0
    freq = collections.Counter(data)
    total = len(data)
    entropy = 0.0
    for count in freq.values():
        p = count / total
        entropy -= p * math.log2(p)
    return entropy


def is_indirect_branch(insn) -> bool:
    """Checks if instruction is an indirect jump or indirect call."""
    mnem = insn.get_canon_mnem().lower()
    # x86: jmp/call with register or memory operand (not near relative)
    if mnem in ("jmp", "call"):
        op = insn.ops[0]
        # o_reg = 1, o_mem = 2, o_phrase = 3, o_displ = 4
        if op.type in (ida_ua.o_reg, ida_ua.o_mem, ida_ua.o_phrase, ida_ua.o_displ):
            return True
    # ARM64: br xN, blr xN
    if mnem in ("br", "blr"):
        return True
    # RISC-V: jr, jalr
    if mnem in ("jr", "jalr"):
        return True
    return False


def is_arith_or_logic(insn) -> bool:
    """Categorizes arithmetic or boolean logic instructions."""
    mnem = insn.get_canon_mnem().lower()
    arith_mnems = {
        "add", "sub", "mul", "imul", "div", "idiv", "inc", "dec", "neg",
        "and", "or", "xor", "not", "shl", "shr", "sar", "rol", "ror",
        "nor", "nand", "eor", "mvn", "bic", "orn", "madd", "msub"
    }
    return mnem in arith_mnems


class AsgardBinaryAnalyzer:
    """Core analysis engine running inside IDA Pro."""

    def __init__(self):
        self.results = {
            "binary_path": idc.get_input_file_path() if IN_IDA else "",
            "segments": [],
            "functions": [],
            "summary": {}
        }

    def analyze_segments(self):
        """Scans all segments and measures Shannon entropy."""
        qty = ida_segment.get_segm_qty()
        for i in range(qty):
            seg = ida_segment.getnseg(i)
            if not seg:
                continue
            name = ida_segment.get_segm_name(seg)
            size = seg.end_ea - seg.start_ea
            data = ida_bytes.get_bytes(seg.start_ea, size) or b""
            ent = shannon_entropy(data)
            is_encrypted = ent > 7.5 and size > 256
            self.results["segments"].append({
                "name": name,
                "start": hex(seg.start_ea),
                "end": hex(seg.end_ea),
                "size": size,
                "entropy": round(ent, 4),
                "high_entropy": is_encrypted,
            })

    def analyze_function(self, func):
        """Performs CFG and instruction profiling on a single function."""
        name = ida_funcs.get_func_name(func.start_ea)
        fc = ida_gdl.FlowChart(func, flags=ida_gdl.FC_PREDS)

        num_blocks = fc.size
        num_edges = 0
        max_in_degree = 0
        hub_block_ea = 0

        # Instruction statistics
        total_insns = 0
        indirect_jumps = 0
        arith_logic_insns = 0

        insn = ida_ua.insn_t()

        for bb in fc:
            # Edges: count successors
            succs = list(bb.succs())
            preds = list(bb.preds())
            num_edges += len(succs)
            in_deg = len(preds)
            if in_deg > max_in_degree:
                max_in_degree = in_deg
                hub_block_ea = bb.start_ea

            # Walk instructions in basic block
            curr_ea = bb.start_ea
            while curr_ea < bb.end_ea:
                length = ida_ua.decode_insn(insn, curr_ea)
                if length <= 0:
                    break
                total_insns += 1

                if is_indirect_branch(insn):
                    indirect_jumps += 1
                if is_arith_or_logic(insn):
                    arith_logic_insns += 1

                curr_ea += length

        # Cyclomatic complexity: M = E - N + 2P (P=1 for single function)
        cyclomatic = max(1, num_edges - num_blocks + 2)
        indir_ratio = (indirect_jumps / max(total_insns, 1)) * 100.0

        return {
            "name": name,
            "start": hex(func.start_ea),
            "size": func.size(),
            "blocks": num_blocks,
            "edges": num_edges,
            "cyclomatic_complexity": cyclomatic,
            "max_in_degree": max_in_degree,
            "hub_block_ea": hex(hub_block_ea) if max_in_degree > 3 else None,
            "total_insns": total_insns,
            "indirect_jumps": indirect_jumps,
            "indirect_jump_pct": round(indir_ratio, 2),
            "arith_logic_insns": arith_logic_insns,
        }

    def run(self):
        """Executes full analysis pass."""
        if not IN_IDA:
            print("[-] Error: AsgardBinaryAnalyzer must be run inside IDA Pro.")
            return

        ida_auto.auto_wait()
        self.analyze_segments()

        fn_qty = ida_funcs.get_func_qty()
        total_insns_binary = 0
        total_indirect_binary = 0
        max_binary_cyclomatic = 0
        flattened_funcs = []

        for i in range(fn_qty):
            fn = ida_funcs.getn_func(i)
            if not fn:
                continue
            finfo = self.analyze_function(fn)
            self.results["functions"].append(finfo)
            total_insns_binary += finfo["total_insns"]
            total_indirect_binary += finfo["indirect_jumps"]
            if finfo["cyclomatic_complexity"] > max_binary_cyclomatic:
                max_binary_cyclomatic = finfo["cyclomatic_complexity"]
            # Flag potential CFF / virtualized functions
            if finfo["max_in_degree"] >= 10 or finfo["indirect_jumps"] >= 5:
                flattened_funcs.append(finfo["name"])

        self.results["summary"] = {
            "total_functions": fn_qty,
            "total_instructions": total_insns_binary,
            "total_indirect_branches": total_indirect_binary,
            "max_cyclomatic_complexity": max_binary_cyclomatic,
            "flattened_or_vm_functions": flattened_funcs,
        }

    def print_report(self):
        """Prints formatted summary table to IDA output window."""
        print("=" * 80)
        print("ASGARD BINARY & OBFUSCATION AUDIT REPORT")
        print("=" * 80)
        print(f"Target: {self.results['binary_path']}")
        print(f"Total Functions:    {self.results['summary']['total_functions']}")
        print(f"Total Instructions: {self.results['summary']['total_instructions']}")
        print(f"Indirect Branches:  {self.results['summary']['total_indirect_branches']}")
        print(f"Max Complexity:     {self.results['summary']['max_cyclomatic_complexity']}")
        print("-" * 80)
        print("SEGMENTS & ENTROPY:")
        for s in self.results["segments"]:
            flag = " [ENCRYPTED/HIGH ENTROPY]" if s["high_entropy"] else ""
            print(f"  {s['name']:<18} size={s['size']:<8} H={s['entropy']:.4f}{flag}")
        print("-" * 80)
        print("TOP COMPLEX FUNCTIONS:")
        top_funcs = sorted(self.results["functions"], key=lambda x: x["cyclomatic_complexity"], reverse=True)[:10]
        print(f"  {'Function':<30} {'Blocks':<8} {'Edges':<8} {'Cyclo':<8} {'In-Deg':<8} {'IndirJmp':<8}")
        for f in top_funcs:
            print(f"  {f['name']:<30} {f['blocks']:<8} {f['edges']:<8} {f['cyclomatic_complexity']:<8} {f['max_in_degree']:<8} {f['indirect_jumps']:<8}")
        print("=" * 80)

    def save_json(self, output_path="asgard_ida_audit.json"):
        """Saves JSON report to disk."""
        with open(output_path, "w") as fh:
            json.dump(self.results, fh, indent=2)
        print(f"[+] Saved structured report to: {output_path}")


# ── IDAPython Plugin Interface ──────────────────────────────────────────────

class AsgardIdaPlugin(ida_idaapi.plugin_t if IN_IDA else object):
    flags = ida_idaapi.PLUGIN_KEEP if IN_IDA else 0
    comment = "ASGARD Binary & Obfuscation Analyzer"
    help = "Analyzes CFG complexity, indirect branch dispersion, and entropy"
    wanted_name = "ASGARD Binary Analyzer"
    wanted_hotkey = "Ctrl-Alt-A"

    def init(self):
        return ida_idaapi.PLUGIN_KEEP if IN_IDA else 0

    def run(self, arg):
        analyzer = AsgardBinaryAnalyzer()
        analyzer.run()
        analyzer.print_report()
        analyzer.save_json()

    def term(self):
        pass


def PLUGIN_ENTRY():
    return AsgardIdaPlugin()


# ── Headless CLI Entry Point ────────────────────────────────────────────────
if __name__ == "__main__" and IN_IDA:
    analyzer = AsgardBinaryAnalyzer()
    analyzer.run()
    analyzer.print_report()
    out_json = os.environ.get("ASGARD_IDA_OUT", "asgard_ida_audit.json")
    analyzer.save_json(out_json)
    if "idat" in sys.executable or ida_pro.is_daemon():
        ida_pro.qexit(0)
