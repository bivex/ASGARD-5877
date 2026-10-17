#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - Ground-truth validation
===================================================

Proves that the numpy reference in kernel_ref.py reproduces the output of the
REAL ASGARD-protected binary (and the native golden binary) bit-for-bit.

Streams the same boundary-weighted vector distribution the differential
fuzzer uses (imported from ../diff_fuzz/run_diff_project.py, so the coverage
stays in lockstep) through both binaries in --fuzz mode and compares every
compute/mix output against the vectorized reference.

Exit code 0 iff every value matches on both binaries.

Usage:
    python3 validate_ref.py [-n 30000] [--seed N]

If the binaries are missing, build them first:
    python3 ../diff_fuzz/run_diff_project.py --skip-build   # or without the flag
"""

import argparse
import os
import subprocess
import sys
import time

import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, "..", "diff_fuzz"))

from kernel_ref import compute_kernel_np, mix_kernel_np, wrap_i32
from run_diff_project import format_line, generate_vectors  # noqa: E402

DIFF_FUZZ_DIR = os.path.join(SCRIPT_DIR, "..", "diff_fuzz")
BINARIES = [
    ("native golden ", os.path.join(DIFF_FUZZ_DIR, "vm_out", "app_native")),
    ("protected VM  ", os.path.join(DIFF_FUZZ_DIR, "vm_out", "protected_proj")),
]


def run_binary(bin_path: str, vectors) -> tuple:
    """Stream every vector through `bin --fuzz`; return (r1, r2) u64 arrays."""
    batch = "\n".join(format_line(v) for v in vectors) + "\n"
    proc = subprocess.Popen([bin_path, "--fuzz"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True)
    out, _ = proc.communicate(batch)
    lines = [l.strip() for l in out.strip().split("\n") if l.strip()]
    if len(lines) != len(vectors):
        raise RuntimeError(f"{bin_path}: got {len(lines)} lines for "
                           f"{len(vectors)} vectors")
    r1 = np.array([int(l.split()[0], 16) for l in lines], dtype=np.uint64)
    r2 = np.array([int(l.split()[1], 16) for l in lines], dtype=np.uint64)
    return r1, r2


def main() -> None:
    ap = argparse.ArgumentParser(description="Validate numpy ref vs real binaries")
    ap.add_argument("-n", "--count", type=int, default=30000)
    ap.add_argument("--seed", type=int, default=None,
                    help="seed for the randomized vector tail")
    args = ap.parse_args()

    for _, path in BINARIES:
        if not os.path.exists(path):
            print(f"ERROR: {path} not found.\n"
                  f"Build it first:  python3 {os.path.join(DIFF_FUZZ_DIR, 'run_diff_project.py')}")
            sys.exit(2)

    vectors = generate_vectors(args.count)

    # numpy reference over the whole batch
    b_wrapped = wrap_i32(np.array([v[1] for v in vectors], dtype=np.int64))
    ref_compute = compute_kernel_np(
        np.array([v[0] for v in vectors], dtype=np.uint64),
        b_wrapped,
        np.array([v[2] for v in vectors], dtype=np.uint32),
        np.array([v[3] for v in vectors], dtype=np.float64),
        np.array([v[4] for v in vectors], dtype=np.float64),
        np.array([v[5] for v in vectors], dtype=np.uint8),
    )
    blob = np.zeros((len(vectors), 64), dtype=np.uint8)
    n = np.zeros(len(vectors), dtype=np.int64)
    for k, v in enumerate(vectors):
        blob[k, :len(v[7])] = np.frombuffer(v[7], dtype=np.uint8)
        n[k] = len(v[7])
    ref_mix = mix_kernel_np(
        np.array([v[6] for v in vectors], dtype=np.uint64), blob, n)

    all_ok = True
    for label, path in BINARIES:
        t0 = time.time()
        r1, r2 = run_binary(path, vectors)
        dt = time.time() - t0

        ok_c = r1 == ref_compute
        ok_m = r2 == ref_mix
        print(f"[{label}] {os.path.basename(path)}: "
              f"compute {'OK ' if ok_c.all() else 'FAIL'} "
              f"({int(ok_c.sum())}/{len(vectors)}), "
              f"mix {'OK ' if ok_m.all() else 'FAIL'} "
              f"({int(ok_m.sum())}/{len(vectors)})  [{dt:.1f}s]")

        if not (ok_c.all() and ok_m.all()):
            all_ok = False
            bad = np.flatnonzero(~ok_c | ~ok_m)[:10]
            for idx in bad:
                a, b, c, d, e, flags, seed, blb = vectors[idx]
                print(f"  --- divergence #{idx} ---")
                print(f"    a=0x{a:016x} b={b} c=0x{c:x} d={d!r} e={e!r} "
                      f"flags=0x{flags:02x} seed=0x{seed:016x} blob={blb.hex()}")
                if not ok_c[idx]:
                    print(f"    compute: binary=0x{int(r1[idx]):016x} "
                          f"ref=0x{int(ref_compute[idx]):016x} "
                          f"xor=0x{int(r1[idx]) ^ int(ref_compute[idx]):016x}")
                if not ok_m[idx]:
                    print(f"    mix:     binary=0x{int(r2[idx]):016x} "
                          f"ref=0x{int(ref_mix[idx]):016x} "
                          f"xor=0x{int(r2[idx]) ^ int(ref_mix[idx]):016x}")

    if all_ok:
        print(f"GROUND TRUTH CONFIRMED: numpy reference == both binaries "
              f"on {len(vectors):,} vectors (compute + mix).")
    else:
        print("DIVERGENCE: numpy reference does not match the binaries.")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
