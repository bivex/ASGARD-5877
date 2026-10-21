#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Per-ISA Polymorphic Randomization Build & Execution
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "=================================================================="
echo "🛡️  ASGARD-5877: Per-ISA Polymorphic Randomization Pipeline"
echo "=================================================================="

BUILD_DIR="${SCRIPT_DIR}/build"
mkdir -p "${BUILD_DIR}"

SRC_FILE="${SCRIPT_DIR}/Sources/per_isa_demo.c"
APP_BIN="${BUILD_DIR}/protected_app"

# Virtualize via protect-arm64
echo "[*] Virtualizing functions via Per-ISA Threaded-VM..."
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
echo "✅ Build & Run Complete: ${APP_BIN}"
echo "=================================================================="
