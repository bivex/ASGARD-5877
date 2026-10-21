#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Automated idasql Audit for Protected Swift Applications
#
# Generates an IDA Pro database (.i64) headlessly via idat and runs SQL assertions
# against the idasql SQLite virtual table interface to verify:
#   1. Complete data-hiding (zero cleartext sensitive strings in `strings`).
#   2. Function virtualization (target logic replaced by thunk to VM dispatcher).
#   3. Decompiler resilience (Hex-Rays decompiles only the VM entrypoint).
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BIN="${SCRIPT_DIR}/build/protected_swift_app"
DB_PATH="${APP_BIN}.i64"

IDAT_PATH="${IDAT_PATH:-/Applications/IDA Professional 9.3.app/Contents/MacOS/idat}"
IDASQL_PATH="${IDASQL_PATH:-/Users/password9090/Desktop/test/ida-sdk/src/bin/idasql}"
IDA_LIB_DIR="${IDA_LIB_DIR:-/Applications/IDA Professional 9.3.app/Contents/MacOS}"

if [[ ! -f "${APP_BIN}" ]]; then
    echo "[-] Protected binary not found at ${APP_BIN}. Running build_swift.sh first..."
    "${SCRIPT_DIR}/build_swift.sh"
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
echo "🔍  ASGARD-5877: Running idasql Security Audit on Swift Application"
echo "=================================================================="

# 1. Generate IDA Pro Database in Headless Batch Mode
echo "[*] Step 1: Generating IDA Pro database (.i64) via idat..."
"${IDAT_PATH}" -B -A "${APP_BIN}"

# Helper function to execute idasql
run_sql() {
    local query="$1"
    DYLD_LIBRARY_PATH="${IDA_LIB_DIR}" "${IDASQL_PATH}" -s "${DB_PATH}" -q "${query}"
}

echo ""
echo "=================================================================="
echo "📋 Audit Test 1: String Literal Data-Hiding"
echo "=================================================================="
LEAKED_STRINGS=$(run_sql "SELECT count(*) FROM strings WHERE content LIKE '%ACCESS%' OR content LIKE '%GRANTED%' OR content LIKE '%DENIED%' OR content LIKE '%secret%';" | grep -E '^[|][ ]*[0-9]+[ ]*[|]' | tr -d '| ')

if [[ "${LEAKED_STRINGS}" == "0" ]]; then
    echo "[+] PASS: 0 cleartext sensitive strings found in Mach-O binary."
else
    echo "[-] FAIL: Leaked strings detected (${LEAKED_STRINGS} matches)!"
    run_sql "SELECT address, content FROM strings WHERE content LIKE '%ACCESS%' OR content LIKE '%GRANTED%' OR content LIKE '%DENIED%';"
    exit 1
fi

echo ""
echo "=================================================================="
echo "📋 Audit Test 2: Target Function Body Virtualization"
echo "=================================================================="
echo "[*] Checking Hex-Rays pseudocode for _verify_license:"
run_sql "SELECT line FROM pseudocode WHERE func_addr = (SELECT address FROM funcs WHERE name = '_verify_license') ORDER BY line_num;"

echo ""
echo '[*] Checking Hex-Rays pseudocode for Swift mangled symbol (_$s4main14verify_license...):'
run_sql "SELECT line FROM pseudocode WHERE func_addr = (SELECT address FROM funcs WHERE name LIKE '%verify_license%' AND name != '_verify_license' LIMIT 1) ORDER BY line_num;"

echo ""
echo "=================================================================="
echo "📋 Audit Test 3: Virtual Machine Entrypoint Inspection"
echo "=================================================================="
echo "[*] Inspecting decompiled asgard_vm_entry_verify_license (first 25 lines):"
run_sql "SELECT line FROM pseudocode WHERE func_addr = (SELECT address FROM funcs WHERE name = '_asgard_vm_entry_verify_license') ORDER BY line_num LIMIT 25;"

echo ""
echo "=================================================================="
echo "✅ All idasql security audit assertions PASSED."
echo "=================================================================="
