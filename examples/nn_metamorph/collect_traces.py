#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - VM trace collection
==============================================

Builds a matrix of ASGARD-protected binaries (config x seed), streams test
vectors through each in --fuzz mode with ASG_VM_TRACE=1, and parses the
stderr handler-class trace into npz datasets for train_trace.py.

The trace tokens are SEMANTIC handler classes (canonical across builds: the
runtime emits ASG_TRC_CLASS[slot] = index into the sorted handler-name list
of that build). Legends are remapped here to the sorted union of names so
token ids are directly comparable across every build in the matrix.

Per --fuzz vector the VM runs twice (asgard_fuzz_compute, then
asgard_fuzz_mix) -> two "# B ... # E" segments per vector, labeled 0/1.

Layout (generated, gitignored): traces/<config>_<seed>/ with the build tree,
traces/legend.json and traces/<config>_<seed>.npz holding:
    flat  int16  concatenated segment tokens
    offs  int64  segment boundaries (len = n_segments + 1)
    kidx  int8   0 = compute segment, 1 = mix segment

Usage:
    python3 collect_traces.py [-n 300] [--seeds 1001 2002] [--configs full plain]
"""

import argparse
import json
import os
import re
import subprocess
import sys

import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
sys.path.insert(0, os.path.join(SCRIPT_DIR, "..", "diff_fuzz"))

from run_diff_project import format_line, generate_vectors  # noqa: E402

PROJ_SRC = os.path.join(SCRIPT_DIR, "..", "diff_fuzz", "proj_src")
OUT_DIR = os.path.join(SCRIPT_DIR, "traces")

CONFIG_FLAGS = {
    "full": ["--cff", "--mba"],
    "plain": [],
}
ALL_CONFIGS = ["full", "plain"]
ALL_SEEDS = [1001, 2002]


def build(config: str, seed: int, binpath: str) -> str:
    """random_visa project -> protected binary; returns the vm hpp path."""
    cmd = (f"eval $(opam env) && dune exec -- random_visa project "
           f"-d {PROJ_SRC} -o {binpath} -s {seed} --run=false "
           f"{' '.join(CONFIG_FLAGS[config])}")
    res = subprocess.run(["/bin/zsh", "-c", cmd], cwd=REPO_ROOT,
                         capture_output=True, text=True)
    out = res.stdout + res.stderr
    if res.returncode != 0 or not os.path.exists(binpath) or "[ERROR]" in out:
        print(f"BUILD FAILED [{config}/{seed}]:\n{out[-2000:]}")
        sys.exit(1)
    hpp = os.path.join(os.path.dirname(binpath), ".asgard_build",
                       "compute_core_threaded_vm.hpp")
    if not os.path.exists(hpp):
        print(f"BUILD FAILED [{config}/{seed}]: no {hpp}")
        sys.exit(1)
    return hpp


def parse_legend(hpp_path: str) -> list:
    """ASG_TRC_NAMES[...] = { "H_A", "H_B", ... } -> list of names."""
    src = open(hpp_path).read()
    m = re.search(r"ASG_TRC_NAMES\[\d+\]\s*=\s*\{(.*?)\};", src, re.S)
    if not m:
        raise RuntimeError(f"ASG_TRC_NAMES not found in {hpp_path}")
    return re.findall(r'"([^"]+)"', m.group(1))


def collect(binpath: str, vectors) -> tuple:
    """Run --fuzz with ASG_VM_TRACE=1; return (flat, offs, kidx)."""
    batch = "\n".join(format_line(v) for v in vectors) + "\n"
    env = dict(os.environ, ASG_VM_TRACE="1")
    proc = subprocess.Popen([binpath, "--fuzz"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, env=env)
    _, err = proc.communicate(batch)

    segs, cur = [], []
    for line in err.split("\n"):
        line = line.strip()
        if line == "# B":
            cur = []
        elif line == "# E":
            if cur:
                segs.append(cur)
            cur = []
        elif line.isdigit():
            cur.append(int(line))
    # per --fuzz vector the VM runs compute first, then mix
    kidx = np.array([i % 2 for i in range(len(segs))], dtype=np.int8)
    flat = np.array([t for s in segs for t in s], dtype=np.int16)
    offs = np.zeros(len(segs) + 1, dtype=np.int64)
    np.cumsum([len(s) for s in segs], out=offs[1:])
    return flat, offs, np.array(kidx, dtype=np.int8), len(segs) // 2


def main() -> None:
    ap = argparse.ArgumentParser(description="Collect VM handler traces")
    ap.add_argument("-n", "--count", type=int, default=300,
                    help="vectors per build (2 segments each)")
    ap.add_argument("--seeds", type=int, nargs="+", default=ALL_SEEDS)
    ap.add_argument("--configs", nargs="+", default=ALL_CONFIGS,
                    choices=sorted(CONFIG_FLAGS))
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    vectors = generate_vectors(args.count)
    legends = {}

    for config in args.configs:
        for seed in args.seeds:
            tag = f"{config}_{seed}"
            binpath = os.path.join(args.out, tag, "bin")
            print(f"== [{tag}] building ({' '.join(CONFIG_FLAGS[config]) or 'no flags'})...")
            hpp = build(config, seed, binpath)
            legend = parse_legend(hpp)
            legends[tag] = legend
            print(f"   legend: {len(legend)} handler classes")

            flat, offs, kidx, n_vec = collect(binpath, vectors)
            assert len(kidx) == 2 * n_vec, (len(kidx), n_vec)
            np.savez_compressed(
                os.path.join(args.out, f"{tag}.npz"),
                flat=flat, offs=offs, kidx=kidx,
                legend=np.array(legend, dtype=object),
            )
            n_comp = int((kidx == 0).sum())
            print(f"   collected {n_vec} vectors -> {len(kidx)} segments "
                  f"({n_comp} compute), {len(flat):,} steps total")

    with open(os.path.join(args.out, "legend.json"), "w") as fh:
        json.dump(legends, fh, indent=1)
    print(f"done. legends and npz files in {args.out}/")


if __name__ == "__main__":
    main()
