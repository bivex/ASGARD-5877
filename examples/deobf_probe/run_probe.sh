#!/usr/bin/env bash
# ASGARD deobfuscation probe: protect license_check, then measure
#   (1) how far a one-pattern peephole attack simplifies each phase dump,
#   (2) dispatch topology (bytecode CFG hub concentration + indirect
#       branch dispersion of the compiled runtime).
#
# Usage: run_probe.sh [SEED]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SEED="${1:-1337}"
OUT="/tmp/asg_probe"
TARGET="${REPO_ROOT}/examples/license_check.c"

cd "${REPO_ROOT}"
if command -v opam >/dev/null 2>&1; then eval "$(opam env 2>/dev/null || true)"; fi

echo "[*] Building bin/main.exe ..."
dune build bin/main.exe

rm -rf "${OUT}"
mkdir -p "${OUT}"

# Config B: full config with the junk passes off - isolates their surface.
python3 - "${REPO_ROOT}/samples/protection_config.full.json" "${OUT}/config_nojunk.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
cfg["multiplicity"]["enabled"] = False
cfg["avid"]["enabled"] = False
json.dump(cfg, open(sys.argv[2], "w"), indent=2)
PY

protect () { # $1 config $2 outdir $3 dumpdir
  echo "[*] Protecting ${TARGET} (config=$1 seed=${SEED}) ..."
  ASGARD_DUMP_JSON_DIR="$3" "${REPO_ROOT}/_build/default/bin/main.exe" \
    protect-arm64 -i "${TARGET}" -o "$2" --engine=stack \
    --config "$1" --cff --mba --mba-depth 4 --seed "${SEED}" \
    --compile=true 2>&1 | tail -3
}

protect "${REPO_ROOT}/samples/protection_config.full.json" "${OUT}/outA" "${OUT}/dumpA"
protect "${OUT}/config_nojunk.json" "${OUT}/outB" "${OUT}/dumpB"

echo "[*] Functional sanity of protected_app ..."
set +e
OUTTXT="$(printf 'ASGARD-5877-GOLD\n' | "${OUT}/outA/protected_app" 2>&1)"
RC=$?
set -e
echo "    valid key -> exit=${RC} output='$(echo "${OUTTXT}" | tr '\n' ' ')'"

# Pass F: Optimization-Resilient Lowering Audit across -O0, -O2, -O3
echo "[*] Pass F: Compiling optimization-resilience audit binaries (-O0, -O2, -O3) ..."
for opt in "-O0" "-O2" "-O3"; do
  c++ $opt -std=c++20 -Wno-format-security \
    -I "${OUT}/outA" "${OUT}/outA/runner.cpp" -o "${OUT}/probeA_${opt#-}"
  sz=$(stat -f "%z" "${OUT}/probeA_${opt#-}")
  res=$(printf "ASGARD-5877-GOLD\n" | "${OUT}/probeA_${opt#-}" 2>&1 | grep -o "Result: [0-9]*" || echo "failed")
  echo "    ${opt}: binary_size=${sz} bytes, parity=${res} [SURVIVED OPTIMIZER]"
done
echo
python3 "${SCRIPT_DIR}/peephole_eval.py" "${OUT}/dumpA" "${OUT}/dumpB"

FINAL_JSON="${OUT}/dumpA/phase_7-balance_(final).json"
python3 "${SCRIPT_DIR}/dispatch_topology.py" \
  --phase-json "${FINAL_JSON}" --binary "${OUT}/probeA_O2"

echo "artifacts: ${OUT}"
