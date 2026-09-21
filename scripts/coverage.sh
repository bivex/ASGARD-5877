#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
eval $(opam env 2>/dev/null || true)

echo "========================================================================="
echo "   ASGARD-5877: UNIFIED TEST SUITE & CODE COVERAGE RUNNER                "
echo "========================================================================="
echo "Host: $(uname -s) $(uname -m) | Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "-------------------------------------------------------------------------"

echo "[1/2] Running Complete Test Suite (160 Unit, Property & E2E Tests)..."
cd "$ROOT_DIR"
dune runtest

echo ""
echo "[2/2] Generating Comprehensive Code Coverage Audit Report..."
ocaml "$ROOT_DIR/scripts/coverage_audit.ml"

echo "========================================================================="
echo "   [COVERAGE AUDIT COMPLETED SUCCESSFULLY]                               "
echo "========================================================================="
