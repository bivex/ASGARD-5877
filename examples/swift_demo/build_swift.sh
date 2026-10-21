#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Native Swift Application Protection Pipeline
#
# ASGARD now natively accepts pure Swift source files (.swift), compiles them to
# ARM64, lifts and virtualizes marked functions into the polymorphic Stack-VM,
# synthesizes in-place assembly trampolines, and links the final binary directly.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: Native Swift Protection Pipeline (Engine Builtin)"
echo "=================================================================="

# 1. Build ASGARD CLI if needed
if [[ ! -f "${ROOT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Compiling ASGARD-5877 compiler toolchain via Dune..."
    (cd "${ROOT_DIR}" && dune build bin/main.exe)
fi

OUT_DIR="${SCRIPT_DIR}/build"

# 2. Invoke ASGARD protect-arm64 directly on the Swift source file!
"${ROOT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${SCRIPT_DIR}/Sources/App/main.swift" \
    -o "${OUT_DIR}" \
    --engine=stack \
    --cff \
    --mba \
    --mba-depth 4 \
    --seed 1337 \
    --compile=true

echo "=================================================================="
echo "✅ Native Protection Complete: ${OUT_DIR}/protected_app"
echo "=================================================================="
