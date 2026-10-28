#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Stack-JIT (SJIT) Big C++ Multi-Pattern Showcase
#
# Builds and runs 8 virtualized security algorithms protected by the
# Stack-JIT engine (--engine=jit), verifying that:
#   1. All 8 routines are lowered into Kolakoski-fissioned sealed nano-chunks.
#   2. Dynamic while loops, divergent branches, and recurrences execute natively.
#   3. Every assertion matches the hardware reference bit-for-bit (30/30 PASS).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: Stack-JIT (SJIT) 8-Function Showcase Pipeline"
echo "=================================================================="

MAIN_EXE="${ROOT_DIR}/_build/default/bin/main.exe"
if [[ ! -x "${MAIN_EXE}" ]]; then
    echo "[*] Compiling ASGARD-5877 toolchain via Dune..."
    (cd "${ROOT_DIR}" && eval "$(opam env)" && dune build bin/main.exe)
fi

BUILD_DIR="${SCRIPT_DIR}/build"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

SRC_FILE="${SCRIPT_DIR}/sjit_showcase.c"
APP_BIN="${BUILD_DIR}/protected_app"

echo "[*] Virtualizing all 8 functions with Stack-JIT engine (--engine=jit)..."
"${MAIN_EXE}" protect-arm64 \
    -i "${SRC_FILE}" \
    -o "${BUILD_DIR}" \
    --engine=jit \
    -s 5877

echo ""
echo "[*] Launching protected application on native Apple Silicon hardware..."
echo ""
"${APP_BIN}"

echo ""
echo "=================================================================="
echo "✅ Showcase Complete: All 8 Functions Verified on Hardware"
echo "=================================================================="
