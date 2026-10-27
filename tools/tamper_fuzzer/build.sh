#!/usr/bin/env bash
# Build script for ASGARD C++ Bytecode Tamper & Fault-Injection Fuzzer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Compiling tamper_fuzzer with clang++ -std=c++20 -O2 ..."
clang++ -std=c++20 -O2 \
    -I"${REPO_ROOT}/protected_arm64_out" \
    "${SCRIPT_DIR}/tamper_fuzzer.cpp" \
    -o "${SCRIPT_DIR}/tamper_fuzzer"

echo "[+] Built successfully: ${SCRIPT_DIR}/tamper_fuzzer"
