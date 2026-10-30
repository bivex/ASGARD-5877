#!/usr/bin/env python3
"""
ASGARD-5877: CFF Opaque Predicate & Zero-Identity Synthesizer (v2)
====================================================================
Rewrite of the original hand-templated synthesizer. Three structural
changes, all motivated by concrete issues found in the v1 script:

  1. SINGLE SOURCE OF TRUTH. v1 built the Z3 proof from one Python
     expression and the exported OCaml from an independently hand-typed
     if/elif block per template -- nothing enforced that the two stayed
     in sync. Here, one `Expr` AST drives *both* the Z3 proof and the
     OCaml codegen, so a proven identity cannot silently export
     different code than what was proved.

  2. EQUIVALENCE-CLASS DEDUP. v1's `Or_And_Xor_Cycle` and
     `Nilpotent_Xor_Or_And` templates are, verified by Z3 simplify,
     the *exact same function* -- two names for one identity. v1 had
     no mechanism to notice this. Here, every sound candidate is
     canonicalized (z3.simplify sexpr) and grouped into equivalence
     classes; duplicate "discoveries" collapse into one class with
     multiple syntactic *variants* instead of two unrelated catalog
     entries.

  3. EXHAUSTIVE GENERATION, NOT 8 HAND-PICKED TEMPLATES. Despite the
     "Synthesizer" name, v1 only ever checked 8 fixed expressions. This
     version enumerates all expression trees up to --max-depth over a
     small grammar, so the catalog is honestly "complete up to depth D"
     rather than "whatever the author thought to type".

Admission criteria (unchanged intent from v1, strengthened in (b)):
  (a) Formal soundness: Z3 BitVec(64) proves E(x, c) == 0 for all
      (x, c) -- i.e. UNSAT on `E(x, c) != 0`.
  (b) Anti-peephole resistance: *none* of several independent Z3
      simplification/canonicalization strategies collapse E(x, c) to
      the literal constant 0 (v1 only tried the default simplify()).
  (c) Operator heterogeneity: must mix arithmetic (+/-) with bitwise
      logic (&, |, ^) -- enforced by construction (see GRAMMAR).

Requires: pip install z3-solver
"""

import argparse
import itertools
import json
import random
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import z3

MASK64 = 0xFFFFFFFFFFFFFFFF
ARITH_OPS = ("add", "sub")
LOGIC_OPS = ("and", "or", "xor")
ALL_OPS = ARITH_OPS + LOGIC_OPS

# IR alu_op constructor names, keyed by this script's internal op names.
IR_OP_NAME = {"add": "Add", "sub": "Sub", "and": "And", "or": "Or", "xor": "Xor"}


# ---------------------------------------------------------------------------
# 1. Expression AST -- the single source of truth for proof + codegen
# ---------------------------------------------------------------------------

class Expr:
    """Base class. Subclasses: Var, Not, Bin."""

    def to_z3(self, x, c):
        raise NotImplementedError

    def leaves_used(self) -> set:
        raise NotImplementedError

    def ops_used(self) -> set:
        raise NotImplementedError

    def size(self) -> int:
        raise NotImplementedError


@dataclass(frozen=True)
class Var(Expr):
    name: str  # "x" or "c"

    def to_z3(self, x, c):
        return x if self.name == "x" else c

    def leaves_used(self):
        return {self.name}

    def ops_used(self):
        return set()

    def size(self):
        return 1


@dataclass(frozen=True)
class Not(Expr):
    inner: Expr

    def to_z3(self, x, c):
        return ~self.inner.to_z3(x, c)

    def leaves_used(self):
        return self.inner.leaves_used()

    def ops_used(self):
        return self.inner.ops_used()

    def size(self):
        return 1 + self.inner.size()


@dataclass(frozen=True)
class Bin(Expr):
    op: str  # one of ALL_OPS
    left: Expr
    right: Expr

    def to_z3(self, x, c):
        a, b = self.left.to_z3(x, c), self.right.to_z3(x, c)
        if self.op == "add":
            return a + b
        if self.op == "sub":
            return a - b
        if self.op == "and":
            return a & b
        if self.op == "or":
            return a | b
        if self.op == "xor":
            return a ^ b
        raise ValueError(self.op)

    def leaves_used(self):
        return self.left.leaves_used() | self.right.leaves_used()

    def ops_used(self):
        return {self.op} | self.left.ops_used() | self.right.ops_used()

    def size(self):
        return 1 + self.left.size() + self.right.size()


# ---------------------------------------------------------------------------
# 2. Exhaustive generation of candidate expressions up to a depth bound
# ---------------------------------------------------------------------------

def gen_leaves() -> List[Expr]:
    base = [Var("x"), Var("c")]
    return base + [Not(e) for e in base]


def gen_exprs(max_size: int) -> List[Expr]:
    """Returns all expression trees with up to `max_size` internal binary
    nodes (i.e. Unary `Not` doesn't count, only Bin nodes do), enumerated
    by a standard Catalan-style size split so each tree is built exactly
    once per (op, left-size, right-size, left-choice, right-choice) --
    no combinatorial double-counting across size buckets.

    NOTE on scaling: tree count at size n is
        Catalan(n) * |ALL_OPS|^n * |leaves|^(n+1)
    With |ALL_OPS|=5 and |leaves|=4 this is already ~538M at n=5 (the
    depth of some of v1's hand-written templates, e.g. DeMorgan_AddSub).
    Exhaustive search is only honest up to about n=3 (~160k trees) on a
    single machine; beyond that, either raise this bound on a cluster,
    canonicalize+dedup incrementally per size bucket before moving to the
    next (not done here, to keep the script simple), or switch to the
    GFlowNet curriculum-seeded search discussed alongside this tool."""
    by_size: Dict[int, List[Expr]] = {0: gen_leaves()}
    for n in range(1, max_size + 1):
        pool = []
        for i in range(0, n):  # left has i internal nodes, right has n-1-i
            j = n - 1 - i
            for op in ALL_OPS:
                for l in by_size[i]:
                    for r in by_size[j]:
                        pool.append(Bin(op, l, r))
        by_size[n] = pool
    return [e for n in range(0, max_size + 1) for e in by_size[n]]


def is_heterogeneous(e: Expr) -> bool:
    ops = e.ops_used()
    return bool(ops & set(ARITH_OPS)) and bool(ops & set(LOGIC_OPS))


# ---------------------------------------------------------------------------
# 3. Quick concrete pre-filter (cheap rejection before invoking Z3)
# ---------------------------------------------------------------------------

def eval_concrete(e: Expr, xv: int, cv: int) -> int:
    if isinstance(e, Var):
        return xv if e.name == "x" else cv
    if isinstance(e, Not):
        return (~eval_concrete(e.inner, xv, cv)) & MASK64
    a = eval_concrete(e.left, xv, cv)
    b = eval_concrete(e.right, xv, cv)
    if e.op == "add":
        return (a + b) & MASK64
    if e.op == "sub":
        return (a - b) & MASK64
    if e.op == "and":
        return a & b
    if e.op == "or":
        return a | b
    if e.op == "xor":
        return a ^ b
    raise ValueError(e.op)


def passes_concrete_filter(e: Expr, n_trials: int = 24, seed: int = 1234) -> bool:
    rng = random.Random(seed)
    for _ in range(n_trials):
        xv = rng.getrandbits(64)
        cv = rng.getrandbits(64)
        if eval_concrete(e, xv, cv) != 0:
            return False
    return True


# ---------------------------------------------------------------------------
# 4. Formal verification: soundness + multi-strategy collapse resistance
# ---------------------------------------------------------------------------

def _strategy_default(expr):
    return z3.simplify(expr)


def _strategy_som(expr):
    return z3.simplify(expr, som=True, cache_all=True)


def _strategy_blast(expr):
    return z3.simplify(expr, blast_distinct=True, flat=True)


COLLAPSE_STRATEGIES = [_strategy_default, _strategy_som, _strategy_blast]


def verify(e: Expr, timeout_ms: int = 2000) -> Tuple[bool, bool, str]:
    """Returns (is_sound, collapses_under_any_strategy, canonical_key)."""
    x, c = z3.BitVecs("x c", 64)
    expr = e.to_z3(x, c)

    s = z3.Solver()
    s.set("timeout", timeout_ms)
    s.add(expr != 0)
    is_sound = s.check() == z3.unsat
    if not is_sound:
        return False, False, ""

    collapses = False
    for strat in COLLAPSE_STRATEGIES:
        try:
            if str(strat(expr)) == "0":
                collapses = True
                break
        except z3.Z3Exception:
            continue

    canonical = z3.simplify(expr, elim_sign_ext=True, local_ctx=True).sexpr()
    return True, collapses, canonical


# ---------------------------------------------------------------------------
# 5. OCaml codegen -- walks the *same* Expr tree used for the Z3 proof
# ---------------------------------------------------------------------------

SCRATCH_POOL = ["vtmp0", "vtmp1", "vtmp2", "vtmp3"]


class RegisterPressureExceeded(Exception):
    pass


@dataclass
class CodegenCtx:
    free: List[str] = field(default_factory=lambda: list(SCRATCH_POOL))
    lines: List[str] = field(default_factory=list)
    max_live: int = 0

    def alloc(self) -> str:
        if not self.free:
            raise RegisterPressureExceeded(
                f"expression needs more than {len(SCRATCH_POOL)} live scratch "
                f"registers -- reject this candidate for codegen rather than "
                f"silently clobbering a still-live value"
            )
        r = self.free.pop()
        in_use = len(SCRATCH_POOL) - len(self.free)
        self.max_live = max(self.max_live, in_use)
        return r

    def release(self, reg: str):
        self.free.append(reg)


def emit_subexpr(e: Expr, ctx: CodegenCtx, src_reg_name: str, c_operand: str) -> str:
    """Emits IR for `e`, returns the register holding its value. Because
    `e` is a tree (not a DAG), every subexpression has exactly one
    consumer -- its parent -- so as soon as a Bin/Not node has consumed
    its operand register(s) it is safe to return them to the free pool
    immediately (classic Sethi-Ullman style tree evaluation). This is
    what guarantees emit_subexpr never reuses a register that is still
    needed, unlike the round-robin allocator this replaced."""
    if isinstance(e, Var):
        dst = ctx.alloc()
        if e.name == "x":
            ctx.lines.append(f"Mov {{ dst = Reg {dst}; src = Reg {src_reg_name} }};")
        else:
            ctx.lines.append(f"Mov {{ dst = Reg {dst}; src = Imm {c_operand} }};")
        return dst
    if isinstance(e, Not):
        inner_reg = emit_subexpr(e.inner, ctx, src_reg_name, c_operand)
        dst = ctx.alloc()
        # NOT via NAND(v, v): dst = ~(v & v) = ~v -- replace with the real
        # Unary-Not IR instruction if lib/vm_ir/ir.ml defines one; kept as
        # NAND-with-self here only because that's confirmed available.
        ctx.lines.append(f"Alu {{ op = Nand; dst = {dst}; src1 = Reg {inner_reg}; src2 = Reg {inner_reg}; set_flags = false }};")
        ctx.release(inner_reg)
        return dst
    # Bin
    lreg = emit_subexpr(e.left, ctx, src_reg_name, c_operand)
    rreg = emit_subexpr(e.right, ctx, src_reg_name, c_operand)
    dst = ctx.alloc()
    ir_op = IR_OP_NAME[e.op]
    ctx.lines.append(f"Alu {{ op = {ir_op}; dst = {dst}; src1 = Reg {lreg}; src2 = Reg {rreg}; set_flags = false }};")
    ctx.release(lreg)
    ctx.release(rreg)
    return dst


def emit_variant_ocaml(e: Expr, variant_name: str) -> str:
    """Emits one OCaml match-arm body: `Ir.instr list` computing e(src_reg, c)
    into dst_reg, derived mechanically from the same Expr used for the proof."""
    ctx = CodegenCtx()
    final_reg = emit_subexpr(e, ctx, "src_reg", "c")
    # retarget the very last write to land directly in dst_reg instead of
    # one more scratch slot, and set_flags=true there (mirrors cff.ml's
    # existing inject_opaque_predicate convention of flagging the final op)
    if ctx.lines:
        last = ctx.lines[-1]
        ctx.lines[-1] = last.replace(f"dst = {final_reg};", "dst = dst_reg;").replace(
            "set_flags = false", "set_flags = true"
        )
    body = "\n".join(f"        {l}" for l in ctx.lines)
    return f"  | {variant_name} ->\n      [\n{body}\n      ]"


# ---------------------------------------------------------------------------
# 6. Driver
# ---------------------------------------------------------------------------

def discover(max_size: int, variants_per_class: int) -> Dict:
    t0 = time.time()
    candidates = [e for e in gen_exprs(max_size) if is_heterogeneous(e)]
    print(f"[*] Generated {len(candidates)} heterogeneous candidate expressions (max_size={max_size})")

    prefiltered = [e for e in candidates if passes_concrete_filter(e)]
    print(f"[*] {len(prefiltered)} survive the 24-vector concrete pre-filter")

    classes: Dict[str, Dict] = {}
    n_sound = 0
    for e in prefiltered:
        is_sound, collapses, key = verify(e)
        if not is_sound or collapses:
            continue
        n_sound += 1
        cls = classes.setdefault(key, {"canonical": key, "exprs": [], "size": e.size()})
        cls["size"] = min(cls["size"], e.size())
        if len(cls["exprs"]) < variants_per_class:
            cls["exprs"].append(e)

    elapsed = time.time() - t0
    print(f"[*] {n_sound} sound + non-collapsing instances -> {len(classes)} distinct equivalence classes "
          f"({elapsed:.1f}s)")
    return classes


def export_ocaml(classes: Dict[str, Dict], out_path: str):
    # Build (constructor_name, Expr) pairs for every variant that actually
    # fits in SCRATCH_POOL -- NOT just one representative per class, so the
    # catalog genuinely offers multiple syntactic shapes per identity.
    arms: List[Tuple[str, Expr, str]] = []  # (name, expr, canonical)
    n_rejected_pressure = 0
    for ci, cls in enumerate(classes.values()):
        for vi, expr in enumerate(cls["exprs"]):
            probe_ctx = CodegenCtx()
            try:
                emit_subexpr(expr, probe_ctx, "src_reg", "c")
            except RegisterPressureExceeded:
                n_rejected_pressure += 1
                continue
            name = f"Id_{ci:03d}_v{vi}"
            arms.append((name, expr, cls["canonical"]))

    if n_rejected_pressure:
        print(f"[!] {n_rejected_pressure} variant(s) need more than {len(SCRATCH_POOL)} "
              f"live scratch registers and were dropped rather than risk clobbering "
              f"a live value -- widen SCRATCH_POOL or lower --max-size if you need them")

    lines = [
        "(* lib/cff/cff_opaque_catalog.ml",
        "   ASGARD-5877: Formally Verified Non-Linear Zero Identities for Opaque Predicates",
        "   Generated by scripts/cff_opaque_synth_v2.py -- DO NOT EDIT MANUALLY",
        "",
        "   Every variant below is emitted mechanically from the same Expr tree that",
        "   Z3 proved E(x, c) == 0 for all (x, c) over a *liveness-aware* register",
        "   allocator (see RegisterPressureExceeded in the generator) -- there is no",
        "   hand-written codegen path that could drift out of sync with the proof,",
        "   and no path that silently reuses a still-live scratch register.",
        "",
        "   Multiple _v0/_v1/... constructors per Id_NNN are DIFFERENT instruction",
        "   orderings of the SAME proven-zero identity; callers should vary which",
        "   one they pick per call site rather than always using _v0, or this",
        "   catalog reintroduces the single-fixed-shape fingerprint weakness it",
        "   was built to avoid (see cff.ml's single trap_block_id / go_disp). *)",
        "",
        "open Vm_ir",
        "",
        "type predicate_variant =",
    ]
    for name, _, _ in arms:
        lines.append(f"  | {name}")
    lines += ["", "let all_variants : predicate_variant array = [| " + "; ".join(n for n, _, _ in arms) + " |]", ""]
    lines.append("(** Emits IR evaluating a provably-zero E(src_reg, c) into [dst_reg], flags set on")
    lines.append("    the final write. Caller is responsible for the trailing Cmp/Jcc against 0 and")
    lines.append("    for picking a fresh, call-site-specific [c] -- reusing one global constant across")
    lines.append("    every call site reintroduces the single-fingerprint weakness this catalog exists")
    lines.append("    to avoid. *)")
    lines.append("let emit_ir_predicate ~(variant : predicate_variant) ~(src_reg : Register.t) ~(dst_reg : Register.t) ~(c : int64) : Ir.instr list =")
    lines.append("  let open Ir in")
    lines.append("  match variant with")
    for name, expr, canonical in arms:
        lines.append(f"  (* canonical: {canonical[:70].replace(chr(10), ' ')}... *)")
        lines.append(emit_variant_ocaml(expr, name))
    lines.append("")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[+] Wrote {len(classes)} equivalence classes / {len(arms)} total syntactic variants to {out_path}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-size", type=int, default=3, help="max internal (binary) nodes per expression tree -- see scaling note in gen_exprs")
    ap.add_argument("--variants-per-class", type=int, default=3)
    ap.add_argument("--out", type=str, default="cff_opaque_catalog.ml")
    ap.add_argument("--json", type=str, default=None, help="also dump raw catalog as JSON")
    args = ap.parse_args()

    classes = discover(args.max_size, args.variants_per_class)
    export_ocaml(classes, args.out)

    if args.json:
        dump = [{"canonical": c["canonical"], "size": c["size"],
                 "n_variants": len(c["exprs"])} for c in classes.values()]
        with open(args.json, "w") as f:
            json.dump(dump, f, indent=2)
        print(f"[+] Wrote raw catalog to {args.json}")


if __name__ == "__main__":
    main()