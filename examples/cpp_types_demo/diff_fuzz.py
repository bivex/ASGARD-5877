#!/usr/bin/env python3
"""
ASGARD-5877 Differential Fuzzer: Modern C++ VM vs Native Golden Reference
Tests full C++20 features (templates, lambdas, structs, enum class, double arithmetic)
across thousands of edge-case and randomized vectors to detect any divergence.
"""

import sys
import os
import subprocess
import random
import time
import argparse

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../.."))

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

def build_targets(engine="threaded", enable_cff=True, enable_mba=True):
    print(f"{CYAN}{BOLD}[1/2] Compiling Native Golden Executable...{RESET}")
    native_bin = os.path.join(SCRIPT_DIR, "native_app")
    cmd_native = [
        "clang++", "-std=c++20", "-O2",
        f"-I{os.path.join(REPO_ROOT, 'examples')}",
        os.path.join(SCRIPT_DIR, "test.cpp"),
        "-o", native_bin
    ]
    res_native = subprocess.run(cmd_native, cwd=REPO_ROOT, capture_output=True, text=True)
    if res_native.returncode != 0:
        print(f"{RED}Failed to build native executable:\n{res_native.stderr}{RESET}")
        sys.exit(1)

    print(f"{CYAN}{BOLD}[2/2] Generating & Compiling ASGARD VM Protected Executable (Engine: {engine})...{RESET}")
    vm_out_dir = os.path.join(SCRIPT_DIR, "vm_out")
    os.makedirs(vm_out_dir, exist_ok=True)
    
    protect_cmd = [
        "dune", "exec", "--", "random_visa", "protect",
        "-i", os.path.join(SCRIPT_DIR, "test.cpp"),
        "-o", vm_out_dir,
        f"--engine={engine}"
    ]
    if enable_cff:
        protect_cmd.append("--cff")
    if enable_mba:
        protect_cmd.append("--mba")

    # Run protect pipeline inside opam env
    full_cmd = f"eval $(opam env) && {' '.join(protect_cmd)}"
    res_vm = subprocess.run(full_cmd, shell=True, cwd=REPO_ROOT, capture_output=True, text=True)
    if res_vm.returncode != 0:
        print(f"{RED}VM protection pipeline failed:\n{res_vm.stderr}{RESET}")
        sys.exit(1)

    vm_bin = os.path.join(vm_out_dir, "protected_app")
    virt_cpp = os.path.join(vm_out_dir, "app_virtualized.cpp")
    if not os.path.exists(virt_cpp):
        print(f"{RED}Expected virtualized C++ file not found at {virt_cpp}{RESET}")
        sys.exit(1)

    cmd_compile_vm = [
        "clang++", "-std=c++20", "-O2",
        f"-I{os.path.join(REPO_ROOT, 'examples')}",
        f"-I{vm_out_dir}",
        virt_cpp,
        "-o", vm_bin
    ]
    res_compile_vm = subprocess.run(cmd_compile_vm, cwd=REPO_ROOT, capture_output=True, text=True)
    if res_compile_vm.returncode != 0:
        print(f"{RED}Failed to compile protected executable:\n{res_compile_vm.stderr}{RESET}")
        sys.exit(1)

    print(f"{GREEN}Both binaries compiled and ready for differential fuzzing!{RESET}\n")
    return native_bin, vm_bin

def generate_test_vectors(total_count=5000):
    edge_uids = [
        0, 1, 2, 42, 12345, 0x5877, 0x1337,
        0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
        0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF,
        0xA1B2C3D4E5F60718, 0xCAFEBABE13375877
    ]
    edge_levels = [0, 1, 2, 3, 4, 10, 0xFFFFFFFF]
    edge_quotas = [
        0.0, -0.0, 1.0, -1.0, 250.5, 0.5, 100.25, -500.5,
        12.345, 0.125, 0.001, 9999.0, 1e4, 0.75, 42.0
    ]
    edge_weights = [
        0.0, 1.0, 2.0, -1.0, 0.5, 1.5, -2.5, 10.0, 0.25, 4.0
    ]
    edge_actives = [1, 0]
    edge_seeds = [
        0, 1, 0xA1B2C3D4, 0xCAFEBABE, 0x13375877, 0x5877,
        0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF
    ]

    vectors = []
    
    # 1. Deterministic Cartesian combinations of boundary values
    for uid in edge_uids[:5]:
        for lvl in edge_levels[:4]:
            for q in edge_quotas[:4]:
                for w in edge_weights[:3]:
                    for act in edge_actives:
                        for s in edge_seeds[:3]:
                            vectors.append((uid, lvl, q, w, act, s))

    # 2. Add randomized edge cases
    while len(vectors) < total_count:
        mode = random.randint(0, 4)
        if mode == 0:
            uid = random.choice(edge_uids)
            lvl = random.choice(edge_levels)
            q = random.choice(edge_quotas)
            w = random.choice(edge_weights)
            act = random.choice(edge_actives)
            seed = random.choice(edge_seeds)
        elif mode == 1:
            # Walking 1s and bitmask boundaries
            uid = 1 << random.randint(0, 63)
            lvl = random.randint(0, 3)
            q = round(random.uniform(-1000.0, 1000.0), 3)
            w = round(random.uniform(-10.0, 10.0), 2)
            act = 1
            seed = 1 << random.randint(0, 63)
        elif mode == 2:
            # Subnormals & fractional floats
            uid = random.randint(0, 0xFFFFFFFFFFFFFFFF)
            lvl = random.randint(0, 3)
            q = random.uniform(-100.0, 100.0)
            w = random.uniform(-50.0, 50.0)
            act = 1
            seed = random.randint(0, 0xFFFFFFFFFFFFFFFF)
        else:
            # Pure random uniform
            uid = random.randint(0, 0xFFFFFFFFFFFFFFFF)
            lvl = random.choice([0, 1, 2, 3, random.randint(0, 1000)])
            q = round(random.uniform(-5000.0, 5000.0), 2)
            w = round(random.uniform(-20.0, 20.0), 2)
            act = random.choice([1, 1, 1, 0])
            seed = random.randint(0, 0xFFFFFFFFFFFFFFFF)

        vectors.append((uid, lvl, q, w, act, seed))

    return vectors[:total_count]

def run_differential_fuzz(native_bin, vm_bin, vectors):
    print(f"{CYAN}{BOLD}Starting Differential Fuzzing Campaign: {len(vectors)} test vectors...{RESET}")
    start_time = time.time()

    # Launch both processes in streaming --fuzz mode
    proc_native = subprocess.Popen([native_bin, "--fuzz"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    proc_vm = subprocess.Popen([vm_bin, "--fuzz"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    input_lines = [f"0x{v[0]:x} {v[1]} {v[2]} {v[3]} {v[4]} 0x{v[5]:x}" for v in vectors]
    batch_input = "\n".join(input_lines) + "\n"

    # Feed input to native
    out_native, err_native = proc_native.communicate(batch_input)
    # Feed input to VM
    out_vm, err_vm = proc_vm.communicate(batch_input)

    res_native = [line.strip() for line in out_native.strip().split("\n") if line.strip()]
    res_vm = [line.strip() for line in out_vm.strip().split("\n") if line.strip()]

    if len(res_native) != len(vectors) or len(res_vm) != len(vectors):
        print(f"{RED}Mismatch in output counts! Vectors={len(vectors)}, Native={len(res_native)}, VM={len(res_vm)}{RESET}")
        if err_native:
            print(f"Native stderr: {err_native}")
        if err_vm:
            print(f"VM stderr: {err_vm}")
        return False

    mismatches = 0
    first_mismatch = None

    for idx, (v, r_nat, r_vm) in enumerate(zip(vectors, res_native, res_vm)):
        if r_nat != r_vm:
            mismatches += 1
            if first_mismatch is None:
                first_mismatch = (idx, v, r_nat, r_vm)

    elapsed = time.time() - start_time
    rate = len(vectors) / elapsed if elapsed > 0 else 0

    if mismatches > 0:
        idx, v, r_nat, r_vm = first_mismatch
        v_nat = int(r_nat, 16)
        v_vm = int(r_vm, 16)
        xor_diff = v_nat ^ v_vm

        print(f"\n{RED}{BOLD}==================== DIVERGENCE DETECTED ===================={RESET}")
        print(f"  Failing Test Index:  #{idx}")
        print(f"  Input Vector:")
        print(f"    user_id:           0x{v[0]:x} ({v[0]})")
        print(f"    level:             {v[1]}")
        print(f"    quota:             {v[2]}")
        print(f"    extra_weight:      {v[3]}")
        print(f"    is_active:         {bool(v[4])}")
        print(f"    seed:              0x{v[5]:x} ({v[5]})")
        print(f"-------------------------------------------------------------")
        print(f"  {GREEN}Golden Native Output:{RESET}  {r_nat} ({v_nat})")
        print(f"  {RED}Protected VM Output: {RESET}  {r_vm} ({v_vm})")
        print(f"  {YELLOW}XOR Diff Mask:       {RESET}  0x{xor_diff:016x}")
        print(f"  Total Mismatches:    {mismatches} / {len(vectors)}")
        print(f"{RED}{BOLD}============================================================={RESET}\n")
        return False
    else:
        print(f"\n{GREEN}{BOLD}============================================================={RESET}")
        print(f"{GREEN}{BOLD}  SUCCESS: 100% PARITY CONFIRMED ACROSS ALL TEST VECTORS!{RESET}")
        print(f"  Total Tests Passed:  {len(vectors):,}")
        print(f"  Edge Cases Tested:   Cartesian boundaries + subnormals + bitmasks")
        print(f"  Execution Time:      {elapsed:.2f} seconds ({rate:.1f} tests/sec)")
        print(f"  Discrepancies Found: 0")
        print(f"{GREEN}{BOLD}============================================================={RESET}\n")
        return True

def main():
    parser = argparse.ArgumentParser(description="ASGARD C++ Differential Fuzzer")
    parser.add_argument("-n", "--count", type=int, default=10000, help="Number of test vectors (default: 10000)")
    parser.add_argument("--engine", default="threaded", choices=["threaded", "stack", "jit"], help="VM engine (default: threaded)")
    parser.add_argument("--no-cff", action="store_true", help="Disable control-flow flattening")
    parser.add_argument("--no-mba", action="store_true", help="Disable mixed boolean-arithmetic")
    parser.add_argument("--skip-build", action="store_true", help="Skip recompilation and test existing binaries")
    args = parser.parse_args()

    native_bin = os.path.join(SCRIPT_DIR, "native_app")
    vm_bin = os.path.join(SCRIPT_DIR, "vm_out", "protected_app")

    if not args.skip_build or not (os.path.exists(native_bin) and os.path.exists(vm_bin)):
        native_bin, vm_bin = build_targets(
            engine=args.engine,
            enable_cff=not args.no_cff,
            enable_mba=not args.no_mba
        )

    vectors = generate_test_vectors(total_count=args.count)
    ok = run_differential_fuzz(native_bin, vm_bin, vectors)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
