#!/usr/bin/env bash
# ASGARD-5877 Neural Obfuscation Assessment Suite
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ $# -ge 1 && -d "$1" ]]; then
    echo "[*] Launching Neural Obfuscation Assessment Suite on $1..."
    python3 "${SCRIPT_DIR}/eval_obfuscation.py" "$1"
else
    echo "[*] No pre-existing dump directory provided. Launching full one-click license evaluation..."
    "${REPO_ROOT}/eval_license.sh"
fi
