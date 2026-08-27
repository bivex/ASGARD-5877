#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/Users/password9090/.opam/default/bin:/opt/homebrew/bin:$PATH"

echo "========================================================================="
echo "   ASGARD-5877: UNIFIED TEST SUITE & CODE COVERAGE RUNNER                "
echo "========================================================================="
echo "Host: $(uname -s) $(uname -m) | Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "-------------------------------------------------------------------------"

echo "[1/2] Running Complete Test Suite (131 Unit, Property & E2E Tests)..."
cd "$ROOT_DIR"
dune test

echo ""
echo "[2/2] Generating Comprehensive Code Coverage Audit Report..."
ocaml "$ROOT_DIR/scripts/coverage_audit.ml"

echo "========================================================================="
echo "   [COVERAGE AUDIT COMPLETED SUCCESSFULLY]                               "
echo "========================================================================="
