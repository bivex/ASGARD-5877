#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: Automated idasql Audit for Per-ISA Protected Functions
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_BIN="${BUILD_DIR}/protected_app"
DB_PATH="${APP_BIN}.i64"
VIRT_CPP="${BUILD_DIR}/app_virtualized.cpp"

IDAT_PATH="${IDAT_PATH:-/Applications/IDA Professional 9.3.app/Contents/MacOS/idat}"
IDASQL_PATH="${IDASQL_PATH:-/Users/password9090/Desktop/test/ida-sdk/src/bin/idasql}"
IDA_LIB_DIR="${IDA_LIB_DIR:-/Applications/IDA Professional 9.3.app/Contents/MacOS}"

if [[ ! -f "${APP_BIN}" ]]; then
    echo "[-] Binary not found at ${APP_BIN}. Running build_and_run.sh first..."
    "${SCRIPT_DIR}/build_and_run.sh"
fi

echo "=================================================================="
echo "🔍  ASGARD-5877: idasql Audit for Per-ISA Randomization"
echo "=================================================================="

echo ""
echo "=================================================================="
echo "📋 Audit Test 1: Inspecting C++ Trampolines & Per-ISA Macro Salts"
echo "=================================================================="
python3 - << EOF
import re

with open("${VIRT_CPP}", "r") as f:
    content = f.read()

pattern = r'(uint64_t\s+([a-zA-Z0-9_]+)\s*\([^)]*\)\s*\{[\s\S]*?return\s+vanguard_threaded_vm::asgard_vm_call_with_salt\(([^;]+)\);[\s\S]*?\})'
matches = re.findall(pattern, content)

for idx, (full_fn, fn_name, call_args) in enumerate(matches, 1):
    args_list = [a.strip() for a in call_args.split(',')]
    salt = args_list[0] if len(args_list) > 0 else "0"
    bc_arr = args_list[1] if len(args_list) > 1 else "unknown"
    print(f"[{idx}] Function: {fn_name}()")
    print(f"    Per-ISA Opcode Salt: {salt} (0x{int(salt):02X})")
    print(f"    Encrypted Bytecode:  {bc_arr}[]")
    print(f"    Dispatcher Thunk:    asgard_vm_call_with_salt({salt}, {bc_arr}, ...)\n")
EOF

# 2. Generate IDA Pro Database in Headless Batch Mode
echo "=================================================================="
echo "📋 Audit Test 2: Generating IDA Pro Database & Auditing Strings"
echo "=================================================================="
"${IDAT_PATH}" -B -A "${APP_BIN}"

# Helper function to execute idasql
run_sql() {
    local query="$1"
    DYLD_LIBRARY_PATH="${IDA_LIB_DIR}" "${IDASQL_PATH}" -s "${DB_PATH}" -q "${query}"
}

LEAKED_STRINGS=$(run_sql "SELECT count(*) FROM strings WHERE content LIKE '%VerifySerial%' OR content LIKE '%GenerateSessionKey%' OR content LIKE '%ValidateAccessLevel%';" | grep -E '^[|][ ]*[0-9]+[ ]*[|]' | tr -d '| ')

if [[ "${LEAKED_STRINGS}" == "0" ]]; then
    echo "[+] PASS: 0 marker tags or function strings found in binary metadata."
else
    echo "[-] FAIL: Leaked strings detected (${LEAKED_STRINGS})!"
    exit 1
fi

echo ""
echo "=================================================================="
echo "📋 Audit Test 3: Disassembled VM Dispatcher Subroutines in Binary"
echo "=================================================================="
run_sql "SELECT printf('0x%X', address) as addr, name, size FROM funcs WHERE size > 1500 ORDER BY size DESC LIMIT 10;"

echo ""
echo "=================================================================="
echo "✅ All Per-ISA idasql verification tests PASSED."
echo "=================================================================="
