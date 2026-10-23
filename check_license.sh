#!/usr/bin/env bash
# License key checker for ASGARD-5877 protected app

set -euo pipefail

EXPECTED_KEY="ASGARD-5877-GOLD"
PROTECTED_APP="${1:-/Volumes/External/Code/ASGARD-5877/protected_arm64_out/protected_app}"

if [[ ! -f "$PROTECTED_APP" ]]; then
    echo "[!] Protected app not found at: $PROTECTED_APP"
    echo "    Build it first with: ./eval_license.sh examples/license_check.c 1337 /tmp/license_eval_json"
    exit 1
fi

echo "[*] Testing license key: $EXPECTED_KEY"
echo "[*] Running: $PROTECTED_APP"
echo ""

printf "%s\n" "$EXPECTED_KEY" | "$PROTECTED_APP"

EXIT_CODE=$?
echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "[+] License key is VALID"
else
    echo "[-] License key is INVALID (exit code: $EXIT_CODE)"
fi

exit $EXIT_CODE