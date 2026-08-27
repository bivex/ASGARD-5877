#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/Users/password9090/.opam/default/bin:/opt/homebrew/bin:$PATH"

echo "========================================================================="
echo "   ASGARD-5877: UNIFIED END-TO-END SECURITY BENCHMARK RUNNER            "
echo "========================================================================="
echo "Host: $(uname -sm) | Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "-------------------------------------------------------------------------"

# Stage 1: Build CLI Generator Binary
echo "[1/2] Building OCaml Pipeline CLI..."
cd "$ROOT_DIR"
dune build bin/main.exe

# Stage 2: Compile Real Multi-Build Polymorphic Corpus
echo ""
echo "[2/2] Compiling Real Multi-Build Corpus (8 Builds with CFF & MBA)..."
"$ROOT_DIR/scripts/build_corpus.sh"

# Stage 3: Run Full Octave Empirical Cryptanalytic & Deobfuscation Benchmark
echo ""
echo "Executing GNU Octave Empirical Security & SMT Benchmark..."
/opt/homebrew/bin/octave --no-gui "$ROOT_DIR/scripts/asgard_math_analysis.m"

echo "========================================================================="
echo "   [END-TO-END BENCHMARK RUN COMPLETED SUCCESSFULLY]                     "
echo "========================================================================="
