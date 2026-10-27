#!/usr/bin/env bash
# Build script for the coverage-guided Stack-VM fuzzer.
# Produces:
#   vm_fuzz            — libFuzzer + ASan + USan (needs full LLVM toolchain)
#   vm_fuzz_standalone — plain -O2 random-mutation stress runner (no deps)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INC="-I${REPO_ROOT}/protected_arm64_out"

echo "[*] Building vm_fuzz (libFuzzer + AddressSanitizer + UBSan) ..."
if clang++ -std=c++20 -O1 -g \
    -fsanitize=fuzzer,address,undefined \
    -fno-omit-frame-pointer \
    $INC \
    "${SCRIPT_DIR}/vm_fuzz_harness.cpp" \
    -o "${SCRIPT_DIR}/vm_fuzz" 2>/dev/null; then
    echo "[+] Built libFuzzer target: ${SCRIPT_DIR}/vm_fuzz"
else
    echo "[!] libFuzzer runtime unavailable (Apple clang ships without it)."
    echo "    Build with Homebrew LLVM (brew install llvm) for coverage-guided"
       echo "    campaigns. The standalone stress mode below works everywhere."
fi

echo "[*] Building vm_fuzz_standalone (plain -O2 stress mode) ..."
clang++ -std=c++20 -O2 -DVM_FUZZ_STANDALONE \
    $INC \
    "${SCRIPT_DIR}/vm_fuzz_harness.cpp" \
    -o "${SCRIPT_DIR}/vm_fuzz_standalone"

echo "[+] Done. Artifacts in ${SCRIPT_DIR}/"
