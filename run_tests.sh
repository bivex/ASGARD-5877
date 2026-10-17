#!/usr/bin/env bash
set -euo pipefail

# Run from repo root
cd "$(dirname "${BASH_SOURCE[0]}")"

# Set up opam env if available
if command -v opam >/dev/null 2>&1; then
  eval "$(opam env)"
fi

exec dune runtest "$@"
