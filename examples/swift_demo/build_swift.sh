#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Swift Native Application Protection Pipeline
#
# This script builds and virtualizes the critical security core into a polymorphic
# ASGARD Stack-VM, generates encrypted bytecode with MBA constant synthesis and
# CFG flattening, binds the VM runtime via a zero-overhead C bridge, and links
# the final protected Swift binary.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: Building Protected Swift Application"
echo "=================================================================="

# 1. Verify Prerequisites
command -v swiftc >/dev/null 2>&1 || { echo >&2 "[-] swiftc is required but not found in PATH."; exit 1; }
command -v clang++ >/dev/null 2>&1 || { echo >&2 "[-] clang++ is required but not found in PATH."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo >&2 "[-] python3 is required but not found in PATH."; exit 1; }

# 2. Build ASGARD-5877 CLI if needed
if [[ ! -f "${ROOT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Compiling ASGARD-5877 compiler toolchain via Dune..."
    (cd "${ROOT_DIR}" && dune build bin/main.exe)
fi

OUT_DIR="${SCRIPT_DIR}/build"
VM_OUT="${OUT_DIR}/vm_out"
mkdir -p "${VM_OUT}"

# 3. Virtualize the ARM64 security core using ASGARD Stack-VM Engine
echo "[*] Virtualizing ARM64 Security Core with ASGARD Stack-VM Engine..."
"${ROOT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${SCRIPT_DIR}/Sources/Core/license_core_arm64.s" \
    -o "${VM_OUT}" \
    --engine=stack \
    --cff \
    --mba \
    --mba-depth 4 \
    --seed 1337 \
    --compile=false

# 4. Extract generated encrypted bytecode for direct static compilation
echo "[*] Extracting polymorphic bytecode for static bridge linking..."
python3 - << EOF
import re

with open("${VM_OUT}/runner.cpp", "r") as f:
    content = f.read()

match = re.search(r'static uint64_t embedded_bytecode\[\] = \{[\s\S]*?\};', content)
if not match:
    raise RuntimeError("Failed to extract embedded_bytecode from runner.cpp")

arr = match.group(0).replace("static uint64_t", "alignas(16) static const uint64_t")

with open("${VM_OUT}/embedded_bytecode.hpp", "w") as out:
    out.write("#pragma once\n#include <stdint.h>\n" + arr + "\n")
EOF

# 5. Compile C++ VM Bridge into Object File
echo "[*] Compiling C++ ASGARD VM Bridge..."
clang++ -std=c++17 -O2 \
    -I"${SCRIPT_DIR}/Sources/Bridge" \
    -I"${VM_OUT}" \
    -c "${SCRIPT_DIR}/Sources/Bridge/LicenseBridge.cpp" \
    -o "${OUT_DIR}/LicenseBridge.o"

# 6. Compile Swift Application and Link Protected Core
echo "[*] Compiling Protected Swift Application via swiftc..."
swiftc -O \
    "${SCRIPT_DIR}/Sources/App/main.swift" \
    "${OUT_DIR}/LicenseBridge.o" \
    -lc++ \
    -o "${OUT_DIR}/protected_swift_app"

echo "=================================================================="
echo "✅ Build Successful: ${OUT_DIR}/protected_swift_app"
echo "=================================================================="
echo ""
echo "[*] Launching Protected Swift Application:"
echo "------------------------------------------------------------------"
"${OUT_DIR}/protected_swift_app"
echo "------------------------------------------------------------------"
