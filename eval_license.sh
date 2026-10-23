#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877: One-Click Neural Obfuscation Assessment Suite (NOAS) Runner
#
# Dumps all 10 Stack-VM pipeline phases for a protected C/C++ target and
# executes the full 9-phase neural reverse-engineering evaluation suite:
#   [Phase 1] GAT Graph Attention Network (CFG & CFF Flattening)
#   [Phase 2] AST Transformer (MBA Incompressibility)
#   [Phase 3] LSTM Next-Byte Predictor (Dynamic Trace & Rolling Key)
#   [Phase 4] Seq2Seq / Transformer (Bytecode Amplifier & DCE Recovery)
#   [Phase 5] BiLSTM / Transformer (Opaque Predicate Realism)
#   [Phase 6] Sequence Taggers (Ghost Stack Padding Stripping)
#   [Phase 7] Siamese Bidirectional LSTM (Spaghetti Block Reassembly)
#   [Phase 8] Metamorphic Pattern Scanner (Branchless VIP Metamorphism)
#   [Phase 9] Cross-Build Transfer Classifier (Superop ISA Diversification)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [TARGET_SOURCE] [SEED] [DUMP_DIR]"
    echo ""
    echo "Arguments:"
    echo "  TARGET_SOURCE   Path to C/C++/Swift file to protect (default: examples/license_check.c)"
    echo "  SEED            Randomization seed for reproducible builds (default: 1337)"
    echo "  DUMP_DIR        Directory for intermediate JSON phase dumps (default: /tmp/license_eval_json)"
    echo ""
    echo "Example:"
    echo "  $0 examples/license_check.c 1337 /tmp/fresh_license_json"
    exit 0
fi

TARGET="${1:-examples/license_check.c}"
SEED="${2:-1337}"
DUMP_DIR="${3:-/tmp/license_eval_json}"
OUT_DIR="/tmp/license_eval_out"
echo "=============================================================================="
echo "🛡️  ASGARD-5877: One-Click Neural Obfuscation Evaluator (NOAS)"
echo "=============================================================================="
echo "[*] Target Source:       ${TARGET}"
echo "[*] Randomization Seed:  ${SEED}"
echo "[*] Pipeline Dump Dir:   ${DUMP_DIR}"
echo "[*] Engine:              Stack-VM (All 10 Passes Active)"
echo "------------------------------------------------------------------------------"

# 1. Build ASGARD main executable if not present
if [[ ! -f "${SCRIPT_DIR}/_build/default/bin/main.exe" ]]; then
    echo "[*] Building ASGARD compiler executable via Dune..."
    if command -v opam >/dev/null 2>&1; then eval "$(opam env --switch=default 2>/dev/null || true)"; fi
    (cd "${SCRIPT_DIR}" && dune build bin/main.exe)
fi

# 2. Prepare clean dump directory
rm -rf "${DUMP_DIR}" "${OUT_DIR}"
mkdir -p "${DUMP_DIR}" "${OUT_DIR}"

# 3. Protect target with full 10-phase pipeline and dump JSON phases
echo "[*] Step 1/2: Compiling & dumping all 10 Stack-VM pipeline phases..."
ASGARD_DUMP_JSON_DIR="${DUMP_DIR}" "${SCRIPT_DIR}/_build/default/bin/main.exe" protect-arm64 \
    -i "${TARGET}" \
    -o "${OUT_DIR}" \
    --engine=stack \
    --config "${SCRIPT_DIR}/samples/protection_config.full.json" \
    --cff \
    --mba \
    --mba-depth 4 \
    --seed "${SEED}" \
    --compile=false

echo "[+] Pipeline dump complete. Generated phase files:"
ls -lh "${DUMP_DIR}"/*.json | awk '{print "    " $9 " (" $5 ")"}'

# 4. Run Neural Obfuscation Assessment Suite
echo ""
echo "[*] Step 2/2: Launching Neural Obfuscation Assessment Suite (NOAS)..."
echo "------------------------------------------------------------------------------"
python3 "${SCRIPT_DIR}/examples/nn_obf_eval/eval_obfuscation.py" "${DUMP_DIR}"
