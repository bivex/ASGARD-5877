#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/Users/password9090/.opam/default/bin:/opt/homebrew/bin:$PATH"

echo "========================================================================="
echo "   ASGARD-5877: UNIFIED ARM64 SECURITY BENCHMARK RUNNER                 "
echo "========================================================================="
echo "Host: $(uname -s) $(uname -m) | Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "-------------------------------------------------------------------------"

echo "[1/2] Building OCaml Pipeline CLI..."
cd "$ROOT_DIR"
dune build bin/main.exe

echo ""
echo "[2/2] Compiling Real Multi-Build ARM64 Corpus (8 Builds with CFF & MBA)..."
"$ROOT_DIR/scripts/build_corpus_arm64.sh"

echo ""
echo "========================================================================="
echo "   LAUNCHING GNU OCTAVE / MATLAB MATHEMATICAL AUDIT & CRYPTANALYSIS      "
echo "========================================================================="
export ASGARD_CORPUS_DIR="$ROOT_DIR/binaries/corpus_build_arm64"
octave --no-gui "$ROOT_DIR/scripts/asgard_math_analysis.m"

echo ""
echo "========================================================================="
echo "   [ARM64 END-TO-END BENCHMARK RUN COMPLETED SUCCESSFULLY]               "
echo "========================================================================="
