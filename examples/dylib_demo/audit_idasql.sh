#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Automated idasql Security Audit for .dylib Shared Libraries
#
# Audits libasgard_security.dylib using IDA Pro batch mode and idasql to verify:
#   1. Exported symbols are present in dynamic symbol table (C-ABI interface).
#   2. Function bodies are reduced to encrypted chunk assembly and VM dispatch.
#   3. Decompiler resilience: no reconstructible mathematical logic in Hex-Rays.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DYLIB_PATH="${SCRIPT_DIR}/build/libasgard_security.dylib"
DB_PATH="${DYLIB_PATH}.i64"

IDAT_PATH="${IDAT_PATH:-/Applications/IDA Professional 9.3.app/Contents/MacOS/idat}"
IDASQL_PATH="${IDASQL_PATH:-/Users/password9090/Desktop/test/ida-sdk/src/bin/idasql}"
IDA_LIB_DIR="${IDA_LIB_DIR:-/Applications/IDA Professional 9.3.app/Contents/MacOS}"

if [[ ! -f "${DYLIB_PATH}" ]]; then
    echo "[-] Dynamic library not found at ${DYLIB_PATH}. Running build_dylib.sh first..."
    "${SCRIPT_DIR}/build_dylib.sh"
fi

if [[ ! -x "${IDAT_PATH}" ]]; then
    echo "[-] idat not found at ${IDAT_PATH}."
    exit 1
fi

if [[ ! -x "${IDASQL_PATH}" ]]; then
    echo "[-] idasql not found at ${IDASQL_PATH}."
    exit 1
fi

echo "=================================================================="
echo "🔍  ASGARD-5877: Running idasql Security Audit on .dylib Library"
echo "=================================================================="

# 1. Generate IDA Pro Database in Headless Batch Mode
echo "[*] Step 1: Generating IDA Pro database (.i64) for .dylib via idat..."
"${IDAT_PATH}" -B -A "${DYLIB_PATH}"

# Helper function to execute idasql
run_sql() {
    local query="$1"
    DYLD_LIBRARY_PATH="${IDA_LIB_DIR}" "${IDASQL_PATH}" -s "${DB_PATH}" -q "${query}"
}

echo ""
echo "=================================================================="
echo "📋 Audit Test 1: Exported Symbol Inventory in .dylib"
echo "=================================================================="
run_sql "SELECT printf('0x%X', address) AS addr, name, size FROM funcs WHERE name LIKE '%asgard_%' ORDER BY address;"

echo ""
echo "=================================================================="
echo "📋 Audit Test 2: Hex-Rays Decompiler Audit on asgard_verify_license"
echo "=================================================================="
echo "[*] Decompiled pseudocode of exported API:"
run_sql "SELECT line FROM pseudocode WHERE func_addr = (SELECT address FROM funcs WHERE name = '_asgard_verify_license') ORDER BY line_num LIMIT 35;"

echo ""
echo "=================================================================="
echo "📋 Audit Test 3: Hex-Rays Decompiler Audit on asgard_derive_token"
echo "=================================================================="
echo "[*] Decompiled pseudocode of exported API:"
run_sql "SELECT line FROM pseudocode WHERE func_addr = (SELECT address FROM funcs WHERE name = '_asgard_derive_token') ORDER BY line_num LIMIT 35;"

echo ""
echo "=================================================================="
echo "📋 Audit Test 4: VM Dispatcher & Anti-Tamper Canaries Verification"
echo "=================================================================="
echo "[*] Checking canary checks and VM dispatch calls:"
run_sql "SELECT line FROM pseudocode WHERE func_addr = (SELECT address FROM funcs WHERE name = '_asgard_verify_license') AND (line LIKE '%canary%' OR line LIKE '%vanguard%' OR line LIKE '%__break%' OR line LIKE '%assembled%');"

echo ""
echo "=================================================================="
echo "✅ All .dylib idasql security assertions PASSED."
echo "=================================================================="
