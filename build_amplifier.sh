#!/usr/bin/env bash
# build_amplifier.sh — Bytecode Amplifier demo build and run helper
# Usage:
#   ./build_amplifier.sh          # build + run smoke demo
#   ./build_amplifier.sh build    # build only
#   ./build_amplifier.sh run      # run only (binary must be built)
#   ./build_amplifier.sh clean    # dune clean
#
# To view phase-by-phase bytecode trace under protect-arm64:
#   ASGARD_DUMP_BYTECODE=1 ./build_license.sh
#   # or via CLI flag:
#   _build/default/bin/main.exe protect-arm64 -i examples/license_check.c \
#     --engine=stack --dump-bytecode 2>bytecode_trace.txt
set -euo pipefail

# Activate opam environment (dune resides in ~/.opam/default/bin)
if command -v opam &>/dev/null; then
  eval "$(opam env 2>/dev/null)" || true
else
  # opam not in PATH — look for dune directly
  OPAM_BIN="${HOME}/.opam/default/bin"
  [[ -d "${OPAM_BIN}" ]] && export PATH="${OPAM_BIN}:${PATH}"
fi

DEMO_EXE="_build/default/examples/amplifier_demo/demo_amplifier.exe"

build() {
  echo "[build_amplifier] Building demo_amplifier..."
  dune build examples/amplifier_demo/demo_amplifier.exe
  echo "[build_amplifier] Built -> ${DEMO_EXE}"
}

run() {
  if [[ ! -f "${DEMO_EXE}" ]]; then
    echo "[build_amplifier] Binary not found, building first..."
    build
  fi
  echo "[build_amplifier] Running smoke-demo..."
  echo ""
  "${DEMO_EXE}"
}

case "${1:-all}" in
  build)  build ;;
  run)    run   ;;
  clean)  dune clean ;;
  all)    build; run ;;
  *)
    echo "Usage: $0 [build|run|clean|all]"
    exit 1
    ;;
esac
