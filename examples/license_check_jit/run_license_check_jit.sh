#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: RD-JIT License Check Example
#
# Builds the license token derivation core with the Register-Driven JIT
# engine (--engine=jit) and validates a key against the protected runner.
#
# The protected core is straight-line ALU (the RD-JIT opcode contract has no
# data-dependent branches), so it derives
#     token = ((key ^ 0x5877) * 42 + 0x1337) mod 2^64
# inside the sealed nano-chunk pipeline (OEIS A000002 Kolakoski fission,
# A010060 Thue-Morse dummies, A000166 derangements, A002487 Stern transfer,
# A000695 immediate blinding, A003022/A000201 arena placement, A001511/A269160
# fractal Rule 30 wipe) and prints the token in REG 0.
#
# Usage:
#   ./examples/license_check_jit/run_license_check_jit.sh [OUT_DIR] [KEY]
#
#   OUT_DIR   build directory (default: ./protected_jit_out)
#   KEY       license key to validate (default: 22647, the shipped valid key)
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$ROOT/protected_jit_out}"
KEY="${2:-22647}"                     # key to validate
VALID_KEY=22647                       # 0x5877 - derives the golden token
SALT=$((0x5877))
MUL=42
ADD=$((0x1337))

MAIN_EXE="$ROOT/_build/default/bin/main.exe"

echo "=========================================================="
echo "[*] ASGARD-5877 RD-JIT License Validator"
echo "    Engine:      Register-Driven JIT (sealed nano-chunks)"
echo "    Build dir:   $OUT_DIR"
echo "    License key: $KEY"
echo "=========================================================="

if [[ ! -x "$MAIN_EXE" ]]; then
    echo "[*] Building protector..."
    (cd "$ROOT" && eval "$(opam env)" && dune build bin/main.exe)
fi

if [[ ! -x "$OUT_DIR/protected_runner" ]]; then
    echo "[*] Protecting license core with --engine=jit..."
    (cd "$ROOT" && "$MAIN_EXE" protect-arm64 \
        -i "$ROOT/examples/license_check_jit/license_core_arm64.s" \
        -o "$OUT_DIR" \
        --engine=jit \
        -s 5877)
fi

APP="$OUT_DIR/protected_runner"
[[ -x "$APP" ]] || { echo "[!] protected_runner missing in $OUT_DIR"; exit 2; }

RUN_OUT="$("$APP" "$KEY" 0)"
TOKEN_HEX="$(sed -n 's/.*Result (REG 0): [0-9]* (0x\([0-9A-Fa-f]*\)).*/\1/p' <<< "$RUN_OUT")"

if [[ -z "$TOKEN_HEX" ]]; then
    echo "[!] Protected runner did not report REG 0:"
    echo "$RUN_OUT"
    exit 2
fi

# Golden token of the valid key, computed natively outside the VM.
EXPECTED=$(( ((VALID_KEY ^ SALT) * MUL + ADD) & 0xFFFFFFFFFFFFFFFF ))
EXPECTED_HEX="$(printf '%x' "$EXPECTED")"

echo ""
echo "$RUN_OUT" | grep -E "Sealed Chunks|Result|JIT Cycle"
echo ""
echo "    Derived token: 0x$TOKEN_HEX"
echo "    Expected:      0x$EXPECTED_HEX"
echo ""

if [[ "${TOKEN_HEX,,}" == "${EXPECTED_HEX,,}" ]]; then
    echo "[+] ACCESS GRANTED - token matches"
    exit 0
else
    echo "[-] ACCESS DENIED - token mismatch"
    exit 1
fi
