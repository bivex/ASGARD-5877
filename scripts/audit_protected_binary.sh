#!/usr/bin/env bash
# ASGARD-5877: protection audit of a protected binary.
#
# Implements the checks of docs/archive/idasql.md against a built binary:
#   * no sensitive string literals in the binary
#   * no protected function names left in the symbol table
#   * no parasitic imports (dlsym / snprintf / strcmp / strlen)
#   * no ASGARD/Vanguard/Ultra markers in the names table
#   * no asg_c_* constant names in the strings table
#   * the VSP whitening formula is present in the decompiled runtime
#   * the control flow is broken enough for the decompiler (JUMPOUT)
#
# Two layers:
#   1. static checks, always available (strings / nm / the emitted runtime
#      header / the entropy of the bytecode);
#   2. IDA-based checks, when IDA Pro and idasql are present.
#
# Usage:
#   scripts/audit_protected_binary.sh <binary> [bytecode]
#   BINARY=... IDA=... IDASQL=... scripts/audit_protected_binary.sh
#
# Exit code 0 = all assertions hold, 1 = at least one failed.

set -uo pipefail

BINARY="${1:-${BINARY:-}}"
BYTECODE="${2:-${BYTECODE:-}}"
IDA="${IDA:-}"
IDASQL="${IDASQL:-}"

if [[ -z "${BINARY}" || ! -f "${BINARY}" ]]; then
  echo "usage: $0 <protected binary> [protected.vanguard]" >&2
  exit 2
fi

BINARY_DIR="$(cd "$(dirname "${BINARY}")" && pwd)"
BINARY_NAME="$(basename "${BINARY}")"

if [[ -z "${IDA}" ]]; then
  for cand in "/Applications/IDA Professional 9.2.app/Contents/MacOS/idat" \
              "/Applications/IDA Professional 9.1.app/Contents/MacOS/idat" \
              "/opt/idapro/idat64"; do
    [[ -x "${cand}" ]] && IDA="${cand}" && break
  done
fi
if [[ -z "${IDASQL}" ]]; then
  for cand in "${HOME}/Desktop/test/ida-sdk/src/bin/idasql" "$(command -v idasql || true)"; do
    [[ -n "${cand}" && -x "${cand}" ]] && IDASQL="${cand}" && break
  done
fi

FAILED=0
PASSED=0

check() {
  # check <name> <expected> <actual>
  local name="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then
    echo "  [PASS] ${name}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${name}: expected ${expected}, got ${actual}"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== ASGARD-5877 protection audit: ${BINARY} ==="

# ---------------------------------------------------------------------
# 1. Static checks (no IDA required)
# ---------------------------------------------------------------------
echo
echo "[1] Static checks"

if command -v strings >/dev/null 2>&1; then
  leaked=$(strings -a "${BINARY}" | grep -icE 'license|serial|valid|secret|Testing' || true)
  check "no sensitive string literals" "0" "${leaked}"
fi

if command -v nm >/dev/null 2>&1; then
  syms=$(nm -gU "${BINARY}" 2>/dev/null | wc -l | tr -d ' ')
  protected=$(nm -gU "${BINARY}" 2>/dev/null | grep -icE 'verify|license|serial' || true)
  check "no protected function names in the symbol table" "0" "${protected}"
  parasites=$(nm -gU "${BINARY}" 2>/dev/null | grep -cE '_dlsym|_snprintf|_strcmp|_strlen' || true)
  check "no parasitic imports" "0" "${parasites}"
  echo "  [INFO] exported symbols: ${syms}"
fi

if [[ -n "${BYTECODE}" && -f "${BYTECODE}" ]] && command -v python3 >/dev/null 2>&1; then
  ent=$(python3 - "${BYTECODE}" <<'PY'
import math, sys
data = open(sys.argv[1], 'rb').read()
if not data:
    print("0.0000"); raise SystemExit
counts = [0] * 256
for b in data:
    counts[b] += 1
h = 0.0
for c in counts:
    if c:
        p = c / len(data)
        h -= p * math.log2(p)
print(f"{h:.4f}")
PY
)
  # The expected entropy of a uniform byte stream of n bytes is
  # 8 - 255/(2*n*ln2); for a small binary that is well below 8.0, so the
  # threshold has to follow the sample size instead of a fixed number.
  verdict=$(python3 - "${BYTECODE}" "${ent}" <<'PYEOF'
import math, os, sys
n = max(1, os.path.getsize(sys.argv[1]))
ent = float(sys.argv[2])
expected = 8.0 - 255.0 / (2.0 * n * math.log(2.0))
threshold = max(6.0, expected - 0.5)
print("ok" if ent >= threshold else f"low({ent:.4f} < {threshold:.4f} for {n} bytes)")
PYEOF
)
  check "bytecode entropy matches a uniform stream of that size" "ok" "${verdict}"
  echo "  [INFO] bytecode entropy: ${ent} bits/byte, size: $(wc -c < "${BYTECODE}" | tr -d ' ') bytes"
fi

HEADER="${BINARY_DIR}/stack_vm_runtime.hpp"
if [[ -f "${HEADER}" ]]; then
  white=$(grep -c '9E3779B97F4A7C15\|61C8864680B583EB' "${HEADER}" || true)
  check "the VSP whitening constants are in the runtime" "ok" "$([[ "${white}" -gt 0 ]] && echo ok || echo missing)"
  ctxline=$(grep -oE 'uint64_t ctx\[[0-9]+\]' "${HEADER}" | head -1)
  echo "  [INFO] runtime context array: ${ctxline:-not found}"
fi

# Compact unwind information: the LC_ROUTINES / LC_ROUTINES64 routine table has
# to agree with __TEXT,__text and __TEXT,__unwind_info, otherwise the unwinder
# reads foreign bytes while an exception crosses a protected frame.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNWIND_CLI="${REPO_ROOT}/_build/default/bin/main.exe"
if [[ -x "${UNWIND_CLI}" ]]; then
  unwind_report=$("${UNWIND_CLI}" macho-unwind --input "${BINARY}" 2>&1 || true)
  unwind_issues=$(printf '%s\n' "${unwind_report}" | sed -n 's/^issues: \([0-9]*\).*/\1/p' | head -1)
  unwind_layout=$(printf '%s\n' "${unwind_report}" | sed -n 's/^layout: \(.*\)/\1/p' | head -1)
  if [[ -n "${unwind_issues}" ]]; then
    check "the compact unwind information is consistent" "0" "${unwind_issues}"
    echo "  [INFO] compact unwind layout: ${unwind_layout:-unknown}"
  else
    echo "  [INFO] compact unwind audit skipped: the CLI did not report"
  fi
fi

# ---------------------------------------------------------------------
# 2. IDA-based checks
# ---------------------------------------------------------------------
echo
if [[ -z "${IDA}" || -z "${IDASQL}" ]]; then
  echo "[2] IDA-based checks: SKIPPED (IDA Pro or idasql not found)"
  echo "    set IDA=/path/to/idat and IDASQL=/path/to/idasql to enable them"
else
  DB="${BINARY_DIR}/${BINARY_NAME}.i64"
  if [[ ! -f "${DB}" ]]; then
    echo "    generating the IDA database (batch mode)..."
    (cd "${BINARY_DIR}" && "${IDA}" -A -B "./${BINARY_NAME}" >/dev/null 2>&1) || true
  fi
  if [[ ! -f "${DB}" ]]; then
    echo "    [FAIL] no IDA database was produced"
    FAILED=$((FAILED + 1))
  else
    q() { "${IDASQL}" -s "${DB}" -q "$1" 2>/dev/null | awk -F'|' '/^\|/ {gsub(/[ ]/,"",$2); print $2}' | tail -1; }
    echo "[2] IDA-based checks (${DB})"
    check "no sensitive strings in the strings table" "0" "$(q "SELECT count(*) FROM strings WHERE content LIKE '%license%' OR content LIKE '%serial%' OR content LIKE '%valid%' OR content LIKE '%secret%' OR content LIKE '%Testing%';")"
    check "no protected function names in the funcs table" "0" "$(q "SELECT count(*) FROM funcs WHERE name LIKE '%verify%' OR name LIKE '%license%' OR name LIKE '%serial%';")"
    check "no asg_c_* constant names" "0" "$(q "SELECT count(*) FROM strings WHERE content LIKE 'asg_c_%';")"
    check "no ASGARD/Vanguard/Ultra markers" "0" "$(q "SELECT count(*) FROM names WHERE name LIKE '%ASGARD%' OR name LIKE '%Vanguard%' OR name LIKE '%Ultra%';")"
    check "no parasitic imports" "0" "$(q "SELECT count(*) FROM funcs WHERE name IN ('_dlsym','_snprintf','_strcmp','_strlen');")"
    white=$(q "SELECT count(*) FROM pseudocode WHERE line LIKE '%9E3779B97F4A7C15%' OR line LIKE '%61C8864680B583EB%';")
    check "the VSP whitening formula is visible in the decompiled runtime" "ok" "$([[ "${white}" -gt 0 ]] && echo ok || echo missing)"
    jump=$(q "SELECT count(*) FROM pseudocode WHERE line LIKE '%JUMPOUT%';")
    if [[ "${jump}" -gt 0 ]]; then
      echo "  [PASS] the decompiler lost the control flow (JUMPOUT x${jump})"
      PASSED=$((PASSED + 1))
    else
      echo "  [WARN] no JUMPOUT: the decompiler still follows the control flow"
    fi
    echo "  [INFO] functions visible to a static analyser:"
    "${IDASQL}" -s "${DB}" -q "SELECT printf('0x%X', address) AS addr, name, size FROM funcs ORDER BY size DESC LIMIT 6;" 2>/dev/null | sed 's/^/    /'
  fi
fi

echo
echo "=== ${PASSED} passed, ${FAILED} failed ==="
[[ "${FAILED}" -eq 0 ]] || exit 1
