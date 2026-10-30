#!/usr/bin/env python3
"""
ASGARD-5877: Non-Linear Zero-Knot Synthesizer & Oracle (v2)
=============================================================
Rewrite of the hand-templated zero-knot script for stack_sink_barrier_pass,
stack_mba_pass, and stack_polymba_pass. Same structural fix as the CFF
opaque-predicate rewrite applied to this (different, push-based) IR:

  1. SINGLE SOURCE OF TRUTH. v1 paired each Z3 `z3_expr` with an
     independently hand-typed `ocaml_code` string -- nothing checked
     that the stack bytecode actually computes the proven expression.
     Here one `Expr` tree drives the Z3 proof *and* the stack bytecode.

  2. MECHANICALLY-CHECKED STACK INVARIANTS, not asserted ones. v1's
     docstring claims "net stack delta +1 / min depth >= 0 / peak <= 6"
     but never computes any of that. Here `emit_stack_ops` returns the
     actual net delta / peak depth / min depth alongside the bytecode,
     and candidates that violate the stated invariants are rejected
     with a concrete reason, not assumed correct.

  3. CLOSED-LOOP CROSS-CHECK. Before anything is accepted, the emitted
     bytecode is replayed on a concrete stack-machine interpreter against
     100 random (r, c) pairs and compared to Expr's own concrete
     evaluation. This is independent of the Z3 proof and independent of
     the codegen -- it is the thing that would have caught an
     Add(a,b)-vs-Sub(b,a) stack-order slip in a hand-written template.

Also included: an exhaustive depth-bounded generator for the
Add/Sub/And/Or family (mirrors cff_opaque_synth_v2.py), PLUS the
original 8 families re-expressed as Expr trees (including the Mul-based
Rivest/Mersenne polynomial knots, which the exhaustive generator does not
reach -- polynomial identities need a different generation strategy, not
in scope here; see NOTE in main()).

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
BIN_OPS = ("add", "sub", "mul", "and", "or")
IR_STACK_OP = {"add": "Add", "sub": "Sub", "mul": "Mul", "and": None, "or": None}
# `and`/`or` have no single stack opcode in this VM -- they are
# synthesized from Nand/Nor via double-negation (confirmed against the
# real stack_mba_pass.ml convention: AND = Nand;Dup;Nand, OR = Nor;Dup;Nor).


# ---------------------------------------------------------------------------
# 1. Expr AST: register `r`, salt `c`, and small integer literals
# ---------------------------------------------------------------------------

class Expr:
    def to_z3(self, r, c):
        raise NotImplementedError

    def eval_concrete(self, rv: int, cv: int) -> int:
        raise NotImplementedError

    def emit(self, ctx: "EmitCtx"):
        raise NotImplementedError

    def size(self) -> int:
        raise NotImplementedError


@dataclass(frozen=True)
class Var(Expr):
    name: str  # "r" or "c"

    def to_z3(self, r, c):
        return r if self.name == "r" else c

    def eval_concrete(self, rv, cv):
        return (rv if self.name == "r" else cv) & MASK64

    def emit(self, ctx):
        if self.name == "r":
            ctx.push("PushReg reg")
        else:
            ctx.push("PushImm c")

    def size(self):
        return 1


@dataclass(frozen=True)
class Const(Expr):
    value: int  # small non-negative literal, e.g. 1, 2, 3

    def to_z3(self, r, c):
        return z3.BitVecVal(self.value, 64)

    def eval_concrete(self, rv, cv):
        return self.value & MASK64

    def emit(self, ctx):
        ctx.push(f"PushImm {self.value}L")

    def size(self):
        return 1


@dataclass(frozen=True)
class Not(Expr):
    inner: Expr

    def to_z3(self, r, c):
        return ~self.inner.to_z3(r, c)

    def eval_concrete(self, rv, cv):
        return (~self.inner.eval_concrete(rv, cv)) & MASK64

    def emit(self, ctx):
        self.inner.emit(ctx)
        # NOT(v) via NAND(v, v): push v again is wrong (consumes extra
        # stack slot); use Dup so the single live value is duplicated
        # then NANDed with itself.
        ctx.push("Dup")
        ctx.push("Nand")

    def size(self):
        return 1 + self.inner.size()


@dataclass(frozen=True)
class Bin(Expr):
    op: str
    left: Expr
    right: Expr

    def to_z3(self, r, c):
        a, b = self.left.to_z3(r, c), self.right.to_z3(r, c)
        if self.op == "add":
            return a + b
        if self.op == "sub":
            return a - b
        if self.op == "mul":
            return a * b
        if self.op == "and":
            return a & b
        if self.op == "or":
            return a | b
        raise ValueError(self.op)

    def eval_concrete(self, rv, cv):
        a, b = self.left.eval_concrete(rv, cv), self.right.eval_concrete(rv, cv)
        if self.op == "add":
            return (a + b) & MASK64
        if self.op == "sub":
            return (a - b) & MASK64
        if self.op == "mul":
            return (a * b) & MASK64
        if self.op == "and":
            return a & b
        if self.op == "or":
            return a | b
        raise ValueError(self.op)

    def emit(self, ctx):
        self.left.emit(ctx)
        self.right.emit(ctx)
        if self.op == "add":
            ctx.push("Add")
        elif self.op == "sub":
            ctx.push("Sub")
        elif self.op == "mul":
            ctx.push("Mul")
        elif self.op == "and":
            # a & b = NAND(NAND(a,b), NAND(a,b))
            ctx.push("Nand")
            ctx.push("Dup")
            ctx.push("Nand")
        elif self.op == "or":
            ctx.push("Nor")
            ctx.push("Dup")
            ctx.push("Nor")
        else:
            raise ValueError(self.op)

    def size(self):
        return 1 + self.left.size() + self.right.size()


# convenience constructors matching the ops this VM actually exposes
def R():
    return Var("r")


def C():
    return Var("c")


def K(v: int):
    return Const(v)


# ---------------------------------------------------------------------------
# 2. Stack-emission context: tracks net delta / peak depth / min depth
#    MECHANICALLY, by assigning a real per-opcode stack effect, instead
#    of asserting it in a comment.
# ---------------------------------------------------------------------------

STACK_EFFECT = {
    "PushReg reg": +1, "PushImm c": +1,
    "Add": -1, "Sub": -1, "Mul": -1, "Nand": -1, "Nor": -1,
    "Dup": +1,
}


def _effect(op: str) -> int:
    if op in STACK_EFFECT:
        return STACK_EFFECT[op]
    if op.startswith("PushImm"):
        return +1
    raise ValueError(f"unknown stack effect for op {op!r}")


@dataclass
class EmitCtx:
    ops: List[str] = field(default_factory=list)
    depth: int = 0
    peak_depth: int = 0
    min_depth: int = 0

    def push(self, op: str):
        self.ops.append(op)
        self.depth += _effect(op)
        self.peak_depth = max(self.peak_depth, self.depth)
        self.min_depth = min(self.min_depth, self.depth)


def emit_stack_ops(e: Expr) -> Tuple[List[str], int, int, int]:
    """Returns (ops, net_delta, peak_depth, min_depth_relative_to_start)."""
    ctx = EmitCtx()
    e.emit(ctx)
    return ctx.ops, ctx.depth, ctx.peak_depth, ctx.min_depth


# ---------------------------------------------------------------------------
# 3. Concrete stack-machine interpreter -- the closed-loop cross-check.
#    Independent of Expr.eval_concrete: this replays the *emitted bytecode*,
#    so a left/right operand-order bug in `emit()` would show up here as a
#    mismatch against Expr.eval_concrete, even though both ultimately trace
#    back to the same Expr -- it catches bugs in `emit()` itself.
# ---------------------------------------------------------------------------

def run_stack_ops(ops: List[str], rv: int, cv: int) -> Optional[int]:
    stk: List[int] = []
    for op in ops:
        if op == "PushReg reg":
            stk.append(rv & MASK64)
        elif op == "PushImm c":
            stk.append(cv & MASK64)
        elif op.startswith("PushImm "):
            lit = int(op[len("PushImm "):].rstrip("L"))
            stk.append(lit & MASK64)
        elif op == "Dup":
            if not stk:
                return None
            stk.append(stk[-1])
        elif op in ("Add", "Sub", "Mul", "Nand", "Nor"):
            if len(stk) < 2:
                return None
            b, a = stk.pop(), stk.pop()
            if op == "Add":
                stk.append((a + b) & MASK64)
            elif op == "Sub":
                stk.append((a - b) & MASK64)
            elif op == "Mul":
                stk.append((a * b) & MASK64)
            elif op == "Nand":
                stk.append((~(a & b)) & MASK64)
            elif op == "Nor":
                stk.append((~(a | b)) & MASK64)
        else:
            raise ValueError(f"unhandled op {op!r}")
    if len(stk) != 1:
        return None
    return stk[0]


def cross_check(e: Expr, ops: List[str], n_trials: int = 100, seed: int = 7) -> bool:
    rng = random.Random(seed)
    for _ in range(n_trials):
        rv, cv = rng.getrandbits(64), rng.getrandbits(64)
        expected = e.eval_concrete(rv, cv)
        actual = run_stack_ops(ops, rv, cv)
        if actual != expected:
            return False
    return True


# ---------------------------------------------------------------------------
# 4. Z3 soundness + multi-strategy collapse resistance (same as CFF v2)
# ---------------------------------------------------------------------------

def _strategy_default(expr):
    return z3.simplify(expr)


def _strategy_som(expr):
    return z3.simplify(expr, som=True, cache_all=True)


def _strategy_blast(expr):
    return z3.simplify(expr, blast_distinct=True, flat=True)


COLLAPSE_STRATEGIES = [_strategy_default, _strategy_som, _strategy_blast]


def verify_z3(e: Expr, timeout_ms: int = 2000) -> Tuple[bool, bool, str]:
    r, c = z3.BitVecs("r c", 64)
    expr = e.to_z3(r, c)
    s = z3.Solver()
    s.set("timeout", timeout_ms)
    s.add(expr != 0)
    is_sound = s.check() == z3.unsat
    if not is_sound:
        return False, False, ""
    collapses = any(str(strat(expr)) == "0" for strat in COLLAPSE_STRATEGIES)
    canonical = z3.simplify(expr, elim_sign_ext=True, local_ctx=True).sexpr()
    return True, collapses, canonical


# ---------------------------------------------------------------------------
# 5. The 8 original families, re-expressed as Expr trees (single source)
# ---------------------------------------------------------------------------

def hand_curated_families() -> List[Tuple[str, str, Expr]]:
    r, c = R(), C()
    return [
        ("Knot_DeMorgan_AddSub",
         "((r + c) - (r & c)) - (r | c)",
         Bin("sub", Bin("sub", Bin("add", r, c), Bin("and", r, c)), Bin("or", r, c))),

        ("Knot_DeMorgan_OrAndSum",
         "((r | c) + (r & c)) - (r + c)",
         Bin("sub", Bin("add", Bin("or", r, c), Bin("and", r, c)), Bin("add", r, c))),

        ("Knot_Disjoint_Intersection",
         "(r & c) & ((r | c) - (r & c))",
         Bin("and", Bin("and", r, c), Bin("sub", Bin("or", r, c), Bin("and", r, c)))),

        ("Knot_Shannon_Projection",
         "((r & c) + (r & ~c)) - r",
         Bin("sub", Bin("add", Bin("and", r, c), Bin("and", r, Not(c))), r)),

        ("Knot_Rivest_Cubic_Multinomial",
         "(r+1)^3 - (r^3 + 3r^2 + 3r + 1)",
         Bin("sub",
             Bin("mul", Bin("mul", Bin("add", r, K(1)), Bin("add", r, K(1))), Bin("add", r, K(1))),
             Bin("add",
                 Bin("add",
                     Bin("mul", Bin("mul", r, r), r),
                     Bin("mul", K(3), Bin("mul", r, r))),
                 Bin("add", Bin("mul", K(3), r), K(1))))),

        ("Knot_Rivest_Quartic_Difference",
         "(r^2+1)^2 - (r^4 + 2r^2 + 1)",
         Bin("sub",
             Bin("mul", Bin("add", Bin("mul", r, r), K(1)), Bin("add", Bin("mul", r, r), K(1))),
             Bin("add",
                 Bin("add", Bin("mul", Bin("mul", r, r), Bin("mul", r, r)),
                     Bin("mul", K(2), Bin("mul", r, r))),
                 K(1)))),

        ("Knot_Mersenne31_Carrier",
         "y(y+1) - (y^2 + y), y = r & M31",
         (lambda y: Bin("sub", Bin("mul", y, Bin("add", y, K(1))),
                        Bin("add", Bin("mul", y, y), y)))(Bin("and", r, K(0x7FFFFFFF)))),

        ("Knot_Nilpotent_Dual_Xor",
         "((r|c) - (r&c)) - ((r & ~c) + (~r & c))",
         Bin("sub",
             Bin("sub", Bin("or", r, c), Bin("and", r, c)),
             Bin("add", Bin("and", r, Not(c)), Bin("and", Not(r), c)))),
    ]


# ---------------------------------------------------------------------------
# 6. Exhaustive generator for the (cheap) Add/Sub/And/Or family
#    (mirrors cff_opaque_synth_v2.py's gen_exprs -- not repeated in full
#    detail here; Mul-bearing polynomial knots are NOT reachable by this
#    generator, see NOTE in main()).
# ---------------------------------------------------------------------------

def gen_leaves() -> List[Expr]:
    base = [R(), C()]
    return base + [Not(e) for e in base]


def gen_exprs(max_size: int, ops=("add", "sub", "and", "or")) -> List[Expr]:
    by_size: Dict[int, List[Expr]] = {0: gen_leaves()}
    for n in range(1, max_size + 1):
        pool = []
        for i in range(0, n):
            j = n - 1 - i
            for op in ops:
                for l in by_size[i]:
                    for rr in by_size[j]:
                        pool.append(Bin(op, l, rr))
        by_size[n] = pool
    return [e for n in range(0, max_size + 1) for e in by_size[n]]


def is_heterogeneous(e: Expr) -> bool:
    def ops_used(x: Expr) -> set:
        if isinstance(x, Bin):
            return {x.op} | ops_used(x.left) | ops_used(x.right)
        if isinstance(x, Not):
            return ops_used(x.inner)
        return set()
    o = ops_used(e)
    return bool(o & {"add", "sub"}) and bool(o & {"and", "or"})


def passes_concrete_filter(e: Expr, n_trials: int = 24, seed: int = 1234) -> bool:
    rng = random.Random(seed)
    for _ in range(n_trials):
        rv, cv = rng.getrandbits(64), rng.getrandbits(64)
        if e.eval_concrete(rv, cv) != 0:
            return False
    return True


# ---------------------------------------------------------------------------
# 7. Admission pipeline -- shared by both the curated and generated sources
# ---------------------------------------------------------------------------

@dataclass
class Admitted:
    name: str
    description: str
    expr: Expr
    ops: List[str]
    net_delta: int
    peak_depth: int
    min_depth: int
    canonical: str


def admit(name: str, description: str, e: Expr, max_peak_depth: int = 6) -> Optional[Admitted]:
    ops, net_delta, peak_depth, min_depth = emit_stack_ops(e)

    if net_delta != 1:
        print(f"[REJECTED] {name:<30}: net stack delta = {net_delta:+d} (need +1)")
        return None
    if min_depth < 0:
        print(f"[REJECTED] {name:<30}: stack underflow, min relative depth = {min_depth}")
        return None
    if peak_depth > max_peak_depth:
        print(f"[REJECTED] {name:<30}: peak depth {peak_depth} > {max_peak_depth}")
        return None
    if not cross_check(e, ops):
        print(f"[REJECTED] {name:<30}: emitted bytecode does NOT match Expr.eval_concrete "
              f"on random (r,c) -- codegen/semantics mismatch")
        return None

    is_sound, collapses, canonical = verify_z3(e)
    if not is_sound:
        print(f"[REJECTED] {name:<30}: Z3 could not prove E(r,c)==0 (not sound)")
        return None
    if collapses:
        print(f"[REJECTED] {name:<30}: collapses to literal 0 under a simplification strategy")
        return None

    print(f"[PASSED  ] {name:<30}: delta={net_delta:+d} peak={peak_depth} min={min_depth} "
          f"ops={len(ops)} sound=True collapse=False")
    return Admitted(name, description, e, ops, net_delta, peak_depth, min_depth, canonical)


# ---------------------------------------------------------------------------
# 8. Export
# ---------------------------------------------------------------------------

def format_ops_literal(ops: List[str]) -> str:
    return "[ " + "; ".join(ops) + " ]"


def export_ocaml(knots: List[Admitted], out_mli: str, out_ml: str):
    mli = [
        "(* lib/stack_vm/stack_zero_knots.mli",
        "   ASGARD-5877: Formally Verified Non-Linear Zero-Knots",
        "   Generated by scripts/zero_knot_synth_v2.py -- DO NOT EDIT MANUALLY",
        "   Every variant's bytecode is emitted mechanically from the Expr tree that",
        "   was both Z3-proven sound and cross-checked against a concrete stack-machine",
        "   interpreter -- see admit() in the generator for what each variant passed. *)",
        "",
        "open Stack_ir",
        "",
        "type zero_knot_variant =",
    ]
    for k in knots:
        mli.append(f"  | {k.name}")
    mli += [
        "",
        "val all_variants : zero_knot_variant array",
        "",
        "val emit_zero_knot :",
        "  ?variant:zero_knot_variant ->",
        "  rng:Random.State.t ->",
        "  reg:int ->",
        "  ?salt:int64 ->",
        "  unit ->",
        "  stack_op list",
        "(** [emit_zero_knot ~rng ~reg ?salt ()] emits a diversified zero-knot pushing 0L,",
        "    net stack delta +1, no underflow, peak depth within the bound checked at",
        "    catalog build time (see admit() / max_peak_depth). *)",
        "",
    ]
    with open(out_mli, "w") as f:
        f.write("\n".join(mli))
    print(f"[+] Wrote interface to: {out_mli}")

    ml = [
        "(* lib/stack_vm/stack_zero_knots.ml",
        "   ASGARD-5877: Formally Verified Non-Linear Zero-Knots",
        "   Generated by scripts/zero_knot_synth_v2.py -- DO NOT EDIT MANUALLY *)",
        "",
        "open Stack_ir",
        "",
        "type zero_knot_variant =",
    ]
    for k in knots:
        ml.append(f"  | {k.name}")
    ml += ["", "let all_variants : zero_knot_variant array = [|"]
    for k in knots:
        ml.append(f"  {k.name};")
    ml += [
        "|]",
        "",
        "let emit_zero_knot ?variant ~rng ~reg ?salt () : stack_op list =",
        "  let c = match salt with",
        "    | Some s -> s",
        "    | None -> Int64.logor (Random.State.int64 rng Int64.max_int) 1L",
        "  in",
        "  let v = match variant with",
        "    | Some var -> var",
        "    | None -> all_variants.(Random.State.int rng (Array.length all_variants))",
        "  in",
        "  match v with",
    ]
    for k in knots:
        ml.append(f"  (* {k.description}  [canonical: {k.canonical[:60].replace(chr(10), ' ')}...]")
        ml.append(f"     delta={k.net_delta:+d} peak_depth={k.peak_depth} min_depth={k.min_depth} *)")
        ml.append(f"  | {k.name} -> {format_ops_literal(k.ops)}")
    ml.append("")
    with open(out_ml, "w") as f:
        f.write("\n".join(ml))
    print(f"[+] Wrote implementation to: {out_ml}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out-mli", type=str, default="stack_zero_knots.mli")
    ap.add_argument("--out-ml", type=str, default="stack_zero_knots.ml")
    ap.add_argument("--include-generated", action="store_true",
                     help="also run the exhaustive Add/Sub/And/Or generator (NOTE: does not "
                          "reach the Mul-based polynomial knots -- those only come from "
                          "hand_curated_families())")
    ap.add_argument("--gen-max-size", type=int, default=3)
    ap.add_argument("--gen-limit", type=int, default=20,
                     help="cap how many generated (non-curated) identities to keep, by shortest size")
    args = ap.parse_args()

    print("=" * 75)
    print("Proving Zero-Knot Invariants (Z3 BitVec64 + stack-machine cross-check)")
    print("=" * 75)

    admitted: List[Admitted] = []
    for name, desc, e in hand_curated_families():
        a = admit(name, desc, e)
        if a:
            admitted.append(a)

    if args.include_generated:
        print(f"\n[*] Generating exhaustive Add/Sub/And/Or candidates (max_size={args.gen_max_size})...")
        t0 = time.time()
        candidates = [e for e in gen_exprs(args.gen_max_size) if is_heterogeneous(e)]
        candidates = [e for e in candidates if passes_concrete_filter(e)]
        print(f"[*] {len(candidates)} candidates survive generation + concrete pre-filter "
              f"({time.time()-t0:.1f}s)")
        seen_canonical = {a.canonical for a in admitted}
        gen_admitted = []
        for i, e in enumerate(candidates):
            a = admit(f"Knot_Gen_{i:04d}", "(generated)", e)
            if a and a.canonical not in seen_canonical:
                seen_canonical.add(a.canonical)
                gen_admitted.append(a)
        gen_admitted.sort(key=lambda a: len(a.ops))
        admitted.extend(gen_admitted[: args.gen_limit])

    print(f"\nFormally proved + stack-cross-checked {len(admitted)} zero-knot families.")
    export_ocaml(admitted, args.out_mli, args.out_ml)


if __name__ == "__main__":
    main()