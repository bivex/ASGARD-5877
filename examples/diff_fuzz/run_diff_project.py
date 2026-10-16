#!/usr/bin/env python3
"""
ASGARD-5877 Differential Fuzzer (project mode)
==============================================

Compiles the SAME multi-file project (proj_src/) two ways:

  1. app_native    : plain clang++            -> Golden Reference
  2. protected_proj: random_visa project      -> macro-obf + CFF + MBA + VM

Then streams thousands of test vectors through both binaries in --fuzz
mode and reports the first divergence with a full input dump.

Usage:
    python3 run_diff_project.py [-n 10000] [--seed N] [--no-cff] [--no-mba]
                                [--skip-build] [--keep-going]

Vectors cover: INT32_MIN/INT32_MAX, shift boundaries (0/31/32/63/64),
walking 1s, 0/-0.0/subnormals/1e300/DBL_MAX, every switch selector class,
empty and 64-byte hash blobs, and pure-random 64-bit fields.
"""

import argparse
import os
import random
import subprocess
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))
PROJ_SRC = os.path.join(SCRIPT_DIR, "proj_src")
VM_OUT = os.path.join(SCRIPT_DIR, "vm_out")

GREEN, RED, YELLOW, CYAN, BOLD, RESET = (
    "\033[92m", "\033[91m", "\033[93m", "\033[96m", "\033[1m", "\033[0m")


# --------------------------------------------------------------------------
# Build stages
# --------------------------------------------------------------------------
def build_native():
    """Golden reference: unobfuscated compile of the identical sources."""
    native_bin = os.path.join(VM_OUT, "app_native")
    cmd = [
        "clang++", "-std=c++20", "-O2", "-ffp-contract=off",
        f"-I{os.path.join(REPO_ROOT, 'examples')}",
        os.path.join(PROJ_SRC, "compute_core.cpp"),
        os.path.join(PROJ_SRC, "main_driver.cpp"),
        "-o", native_bin,
    ]
    res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"{RED}Native golden build failed:\n{res.stderr}{RESET}")
        sys.exit(1)
    return native_bin


def build_protected(seed, enable_cff, enable_mba):
    """Full ASGARD pipeline: macro-obf + CFF + MBA + VM virtualization."""
    protected_bin = os.path.join(VM_OUT, "protected_proj")
    os.makedirs(VM_OUT, exist_ok=True)
    cmd = [
        "dune", "exec", "--", "random_visa", "project",
        "-d", PROJ_SRC,
        "-o", protected_bin,
        "--run=false",
    ]
    if enable_cff:
        cmd.append("--cff")
    if enable_mba:
        cmd.append("--mba")
    if seed is not None:
        cmd += ["-s", str(seed)]

    full = f"eval $(opam env) && {' '.join(cmd)}"
    res = subprocess.run(["/bin/zsh", "-c", full], cwd=REPO_ROOT,
                         capture_output=True, text=True)
    if res.returncode != 0 or not os.path.exists(protected_bin):
        print(f"{RED}ASGARD project pipeline failed:\n{res.stdout}\n{res.stderr}{RESET}")
        sys.exit(1)
    return protected_bin


# --------------------------------------------------------------------------
# Vector generation
# --------------------------------------------------------------------------
EDGE_U64 = [
    0, 1, 2, 42, 12345, 0x5877, 0x1337,
    0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
    0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF,
    0xA1B2C3D4E5F60718, 0xCAFEBABE13375877,
]
EDGE_I32 = [0, 1, -1, 42, -12345, 0x7FFFFFFF, -0x80000000, 0xCAFEBABE]
EDGE_U32 = [0, 1, 31, 32, 63, 64, 0x1337, 0xFFFFFFFF, 0x80000000]
EDGE_DBL = [
    0.0, -0.0, 1.0, -1.0, 250.5, 0.5, 100.25, -500.5,
    12.345, 0.125, 0.001, 9999.0, 1e4, 0.75, 42.0,
    5e-324, 1e-5, 1e300, -1e300, 1.7976931348623157e308,
]
EDGE_FLAGS = [0, 1, 2, 3, 5, 7, 9, 0x0F, 0x55, 0xAA, 0xFF]


def generate_vectors(total):
    vectors = []

    # 1. Deterministic Cartesian boundary sweep (structured depth).
    for a in EDGE_U64[:6]:
        for c in EDGE_U32:
            for d in EDGE_DBL[:6]:
                for flags in EDGE_FLAGS[:6]:
                    vectors.append((a, -12345, c, d, 2.0, flags,
                                    0xDEADBEEF, b"\xde\xad\xbe\xef"))

    # 2. Shift/trip-count focused: every rotate count 0..63.
    for sh in range(0, 64):
        vectors.append((0x0123456789ABCDEF, sh - 32, sh, 250.5, -1.5,
                        1, 0x13375877, bytes([sh & 0xFF])))

    # 3. Signed-32 boundaries against every FP class.
    for b in EDGE_I32:
        for d in (0.0, -0.0, 5e-324, 1e300, -1e300, 12.345):
            vectors.append((0xFFFFFFFFFFFFFFFF, b, 63, d, -2.5, 3,
                            0x80000000, b"\x00"))

    # 4. Randomized edge blend + pure random.
    rng = random.Random(0x5877)
    while len(vectors) < total:
        mode = rng.randint(0, 3)
        if mode == 0:      # all-edge random combination
            v = (rng.choice(EDGE_U64), rng.choice(EDGE_I32),
                 rng.choice(EDGE_U32), rng.choice(EDGE_DBL),
                 rng.choice(EDGE_DBL), rng.choice(EDGE_FLAGS),
                 rng.choice(EDGE_U64), bytes(rng.randrange(256) for _ in range(rng.randrange(1, 65))))
        elif mode == 1:    # walking 1s / bitmask boundaries
            v = (1 << rng.randrange(64),
                 (1 << rng.randrange(32)) - (1 << 31),
                 1 << rng.randrange(32),
                 round(rng.uniform(-1000.0, 1000.0), 3),
                 round(rng.uniform(-10.0, 10.0), 2),
                 rng.randrange(256),
                 1 << rng.randrange(64),
                 bytes(rng.randrange(256) for _ in range(rng.randrange(1, 65))))
        elif mode == 2:    # subnormal / fractional floats
            v = (rng.randrange(2**64), rng.randint(-2**31, 2**31 - 1),
                 rng.randrange(2**32),
                 rng.uniform(-100.0, 100.0) * 1e-300,
                 rng.uniform(-50.0, 50.0),
                 rng.randrange(256),
                 rng.randrange(2**64),
                 bytes(rng.randrange(256) for _ in range(rng.randrange(1, 65))))
        else:              # pure random uniform
            v = (rng.randrange(2**64), rng.randint(-2**31, 2**31 - 1),
                 rng.randrange(2**32), round(rng.uniform(-5000.0, 5000.0), 4),
                 round(rng.uniform(-20.0, 20.0), 4), rng.randrange(256),
                 rng.randrange(2**64),
                 bytes(rng.randrange(256) for _ in range(rng.randrange(1, 65))))
        vectors.append(v)

    return vectors[:total]


def format_line(vec):
    a, b, c, d, e, flags, seed, blob = vec
    return f"0x{a:x} {b} 0x{c:x} {d!r} {e!r} {flags} 0x{seed:x} {blob.hex()}"


# --------------------------------------------------------------------------
# Differential execution
# --------------------------------------------------------------------------
def run_differential(native_bin, vm_bin, vectors, keep_going):
    print(f"{CYAN}{BOLD}Streaming {len(vectors):,} vectors through both binaries...{RESET}")
    start = time.time()

    batch = "\n".join(format_line(v) for v in vectors) + "\n"

    p_nat = subprocess.Popen([native_bin, "--fuzz"], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, text=True)
    out_nat, _ = p_nat.communicate(batch)
    p_vm = subprocess.Popen([vm_bin, "--fuzz"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True)
    out_vm, _ = p_vm.communicate(batch)

    res_nat = [l.strip() for l in out_nat.strip().split("\n") if l.strip()]
    res_vm = [l.strip() for l in out_vm.strip().split("\n") if l.strip()]

    if len(res_nat) != len(vectors) or len(res_vm) != len(vectors):
        print(f"{RED}Output count mismatch! vectors={len(vectors)} "
              f"native={len(res_nat)} vm={len(res_vm)}{RESET}")
        return False

    mismatches = []
    for idx, (vec, rn, rv) in enumerate(zip(vectors, res_nat, res_vm)):
        if rn != rv:
            mismatches.append((idx, vec, rn, rv))
            if not keep_going:
                break

    elapsed = time.time() - start
    rate = len(vectors) / elapsed if elapsed else 0.0

    if mismatches:
        print(f"\n{RED}{BOLD}==================== DIVERGENCE DETECTED ===================={RESET}")
        for idx, vec, rn, rv in mismatches[:10]:
            a, b, c, d, e, flags, seed, blob = vec
            rn1, rn2 = rn.split()
            rv1, rv2 = rv.split()
            print(f"  Failing Test Index:  #{idx}")
            print(f"    a (user_id):       0x{a:016x} ({a})")
            print(f"    b (int32):         {b}")
            print(f"    c (shift/div):     0x{c:x}")
            print(f"    d:                 {d!r}")
            print(f"    e:                 {e!r}")
            print(f"    flags:             0x{flags:02x}")
            print(f"    seed:              0x{seed:016x}")
            print(f"    mix blob ({len(blob)}B):     {blob.hex()}")
            print(f"  ---------------------------------------------------------")
            if rn1 != rv1:
                n1, v1 = int(rn1, 16), int(rv1, 16)
                print(f"  Op: asgard_fuzz_compute")
                print(f"  {GREEN}Golden Native Output:{RESET}  {rn1} ({n1})")
                print(f"  {RED}Protected VM Output: {RESET}  {rv1} ({v1})")
                print(f"  {YELLOW}XOR Diff Mask:       {RESET}  0x{n1 ^ v1:016x}")
            if rn2 != rv2:
                n2, v2 = int(rn2, 16), int(rv2, 16)
                print(f"  Op: asgard_fuzz_mix")
                print(f"  {GREEN}Golden Native Output:{RESET}  {rn2} ({n2})")
                print(f"  {RED}Protected VM Output: {RESET}  {rv2} ({v2})")
                print(f"  {YELLOW}XOR Diff Mask:       {RESET}  0x{n2 ^ v2:016x}")
            print()
        if len(mismatches) > 10:
            print(f"  ... and {len(mismatches) - 10} more mismatches")
        print(f"  Total Mismatches:    {len(mismatches)} / {len(vectors)}")
        print(f"{RED}{BOLD}============================================================={RESET}\n")
        return False

    print(f"\n{GREEN}{BOLD}============================================================={RESET}")
    print(f"{GREEN}{BOLD}  SUCCESS: 100% PARITY ACROSS ALL TEST VECTORS{RESET}")
    print(f"  Total Tests Passed:  {len(vectors):,}")
    print(f"  Coverage:            boundaries + shifts 0..63 + subnormals + blobs")
    print(f"  Execution Time:      {elapsed:.2f}s ({rate:,.0f} tests/sec)")
    print(f"  Discrepancies Found: 0")
    print(f"{GREEN}{BOLD}============================================================={RESET}\n")
    return True


def main():
    ap = argparse.ArgumentParser(description="ASGARD project-mode differential fuzzer")
    ap.add_argument("-n", "--count", type=int, default=10000,
                    help="number of test vectors (default 10000)")
    ap.add_argument("--seed", type=int, default=None,
                    help="ASGARD project randomization seed (reproducible build)")
    ap.add_argument("--no-cff", action="store_true", help="disable CFF")
    ap.add_argument("--no-mba", action="store_true", help="disable MBA rewriting")
    ap.add_argument("--skip-build", action="store_true",
                    help="reuse existing binaries in vm_out/")
    ap.add_argument("--keep-going", action="store_true",
                    help="collect all mismatches instead of stopping at the first")
    args = ap.parse_args()

    native_bin = os.path.join(VM_OUT, "app_native")
    vm_bin = os.path.join(VM_OUT, "protected_proj")

    if args.skip_build and os.path.exists(native_bin) and os.path.exists(vm_bin):
        print(f"{CYAN}[skip-build] reusing {native_bin} and {vm_bin}{RESET}")
    else:
        print(f"{CYAN}{BOLD}[1/2] Compiling native golden executable...{RESET}")
        native_bin = build_native()
        print(f"{CYAN}{BOLD}[2/2] Building ASGARD-protected project "
              f"(CFF: {'on' if not args.no_cff else 'off'}, "
              f"MBA: {'on' if not args.no_mba else 'off'})...{RESET}")
        vm_bin = build_protected(args.seed, not args.no_cff, not args.no_mba)

    vectors = generate_vectors(args.count)
    ok = run_differential(native_bin, vm_bin, vectors, args.keep_going)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
