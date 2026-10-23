#!/usr/bin/env bash
# License key checker for ASGARD-5877 protected app

set -euo pipefail

VALID_KEY="ASGARD-5877-GOLD"
BAD_KEY="INVALID-KEY-BAD0"
PROTECTED_APP="${1:-/Volumes/External/Code/ASGARD-5877/protected_arm64_out/protected_app}"

if [[ ! -f "$PROTECTED_APP" ]]; then
    echo "[!] Protected app not found at: $PROTECTED_APP"
    echo "    Build it first with: ./eval_license.sh examples/license_check.c 1337 /tmp/license_eval_json"
    exit 1
fi

echo "=========================================================="
echo "[*] Target Binary: $PROTECTED_APP"
echo "=========================================================="
echo ""

# -----------------------------------------------------------------------------
# Test 1: Valid License Key (Expect: Exit 0 & ACCESS GRANTED)
# -----------------------------------------------------------------------------
echo "[Test 1/2] Verifying VALID license key: '$VALID_KEY'"
echo "----------------------------------------------------------"
set +e
OUTPUT_VALID=$(printf "%s\n" "$VALID_KEY" | "$PROTECTED_APP" 2>&1)
EXIT_VALID=$?
set -e

echo "$OUTPUT_VALID"
echo ""
if [[ $EXIT_VALID -eq 0 ]] && echo "$OUTPUT_VALID" | grep -q "ACCESS GRANTED"; then
    echo "[+] SUCCESS: Valid key correctly accepted (exit code 0)"
else
    echo "[-] FAILURE: Valid key was rejected or failed (exit code: $EXIT_VALID)"
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Test 2: Invalid License Key (Expect: Non-zero Exit & ACCESS DENIED)
# -----------------------------------------------------------------------------
echo "[Test 2/2] Verifying INVALID license key: '$BAD_KEY'"
echo "----------------------------------------------------------"
set +e
OUTPUT_BAD=$(printf "%s\n" "$BAD_KEY" | "$PROTECTED_APP" 2>&1)
EXIT_BAD=$?
set -e

echo "$OUTPUT_BAD"
echo ""
if [[ $EXIT_BAD -ne 0 ]] && echo "$OUTPUT_BAD" | grep -q "ACCESS DENIED"; then
    echo "[+] SUCCESS: Invalid key correctly rejected (exit code: $EXIT_BAD)"
else
    echo "[-] FAILURE: Invalid key was NOT rejected as expected (exit code: $EXIT_BAD)"
    exit 1
fi
echo ""

echo "=========================================================="
echo "[+] All license validation checks passed successfully!"
echo "=========================================================="
exit 0