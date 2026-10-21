#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Shared Dynamic Library (.dylib / .so) Protection Pipeline
#
# Builds an obfuscated shared dynamic library (.dylib on macOS, .so on Linux)
# containing:
#   1. In-place macro obfuscation (ASG_STR, ASG_MBA, ASGARD_BEGIN_VIRTUALIZE).
#   2. Polymorphic Virtual Machine Runtime (Position-Independent Code / PIC).
#   3. Encrypted bytecode chunks with dynamic canary integrity checks.
#   4. Dynamic export symbols (C-ABI) invoking the VM engine seamlessly.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: Building Protected .dylib Shared Library"
echo "=================================================================="

# 1. Verify Prerequisites
command -v clang++ >/dev/null 2>&1 || { echo >&2 "[-] clang++ is required but not found in PATH."; exit 1; }

# 2. Build ASGARD-5877 CLI if needed
if [[ ! -f "${ROOT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Compiling ASGARD-5877 compiler toolchain via Dune..."
    (cd "${ROOT_DIR}" && dune build bin/main.exe)
fi

BUILD_DIR="${SCRIPT_DIR}/build"
VM_OUT="${BUILD_DIR}/vm_out"
mkdir -p "${VM_OUT}"

LIB_SRC="${SCRIPT_DIR}/Sources/Lib/asgard_security.c"
DYLIB_NAME="libasgard_security.dylib"
DYLIB_PATH="${BUILD_DIR}/${DYLIB_NAME}"

# 3. Virtualize the library using ASGARD Protection Engine
echo "[*] Step 1/3: Virtualizing C Library Routines via ASGARD Engine..."
"${ROOT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${LIB_SRC}" \
    -o "${VM_OUT}" \
    --engine=threaded \
    --compile=false

# 4. Compile into Position-Independent Dynamic Shared Library (.dylib)
echo "[*] Step 2/3: Compiling Position-Independent Shared Library (.dylib)..."
clang++ -std=c++17 -O2 -dynamiclib -fPIC \
    -I"${VM_OUT}" \
    -I"${SCRIPT_DIR}/Sources/Lib" \
    "${VM_OUT}/app_virtualized.cpp" \
    -o "${DYLIB_PATH}"

echo "=================================================================="
echo "✅ Dynamic Library Generated: ${DYLIB_PATH}"
echo "=================================================================="
nm -gU "${DYLIB_PATH}" | grep -E "asgard_" || true

# 5. Compile and run C++ Host Client
echo ""
echo "[*] Step 3/3: Validating Dynamic Library from Host Clients..."
echo "[*] Compiling C++ Host Client..."
clang++ -std=c++17 -O2 \
    "${SCRIPT_DIR}/Sources/Host/host_runner.cpp" \
    -o "${BUILD_DIR}/host_runner_cpp"

echo "[*] Launching C++ Host Client (Testing dlopen/dlsym on .dylib):"
"${BUILD_DIR}/host_runner_cpp" "${DYLIB_PATH}"

# 6. Run Swift Host Client if swift is available
if command -v swift >/dev/null 2>&1; then
    echo ""
    echo "[*] Launching Swift Host Client (Testing dynamic binding from Swift):"
    swift "${SCRIPT_DIR}/Sources/Host/host_runner.swift" "${DYLIB_PATH}"
fi

echo "=================================================================="
echo "✅ All .dylib Dynamic Host Tests PASSED."
echo "=================================================================="
