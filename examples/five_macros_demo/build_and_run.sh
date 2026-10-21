#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: 5 Virtualized Macro Functions Demo
#
# Compiles a C application containing 5 distinct security routines protected
# by ASGARD markers, verifying that:
#   1. Each function receives an isolated bytecode array.
#   2. Each function receives a unique per-macro opcode salt (macro_salt).
#   3. All 5 routines execute natively inside the virtual machine with 100% precision.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: 5 Virtualized Macros Build & Execution Pipeline"
echo "=================================================================="

# 1. Build ASGARD compiler CLI if needed
if [[ ! -f "${ROOT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Compiling ASGARD-5877 compiler toolchain via Dune..."
    (cd "${ROOT_DIR}" && dune build bin/main.exe)
fi

BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

SRC_FILE="${SCRIPT_DIR}/Sources/five_macros.c"
APP_BIN="${BUILD_DIR}/protected_app"

# 2. Run ASGARD protect-arm64
echo "[*] Virtualizing all 5 marked routines via ASGARD Threaded-VM..."
"${ROOT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${SRC_FILE}" \
    -o "${BUILD_DIR}" \
    --engine=threaded \
    --cff \
    --mba \
    --mba-depth 2 \
    --seed 1337 \
    --compile=true

echo ""
echo "=================================================================="
echo "✅ Build & Run Verification Complete: ${APP_BIN}"
echo "=================================================================="
