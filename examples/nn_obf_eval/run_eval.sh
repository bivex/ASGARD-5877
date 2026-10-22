#!/usr/bin/env bash
# ASGARD-5877 Neural Obfuscation Assessment Suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[*] Building ASGARD pipeline dump tools..."
cd "${REPO_ROOT}"
dune build examples/pipeline_dump/dump_pipeline.exe

echo "[*] Launching Neural Obfuscation Assessment Suite..."
python3 "${SCRIPT_DIR}/eval_obfuscation.py"
