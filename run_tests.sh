#!/usr/bin/env bash
set -euo pipefail

# Run from repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

kill_running_tests() {
  local verbose="${1:-false}"
  if [ "$verbose" = "true" ]; then
    echo "[run_tests.sh] Terminating any running test processes..."
  fi

  # 1. Kill any active dune runtest processes
  pkill -9 -f "dune runtest" 2>/dev/null || true

  # 2. Kill test binaries
  pkill -9 -f "run_tests\.exe" 2>/dev/null || true
  pkill -9 -f "test_.*\.exe" 2>/dev/null || true

  # 3. Kill clang/clang++ compilations of test runners
  pkill -9 -f "clang.*asgard_test_" 2>/dev/null || true
  pkill -9 -f "clang.*tech_2601_test" 2>/dev/null || true

  # 4. Kill any running test-generated runner binaries
  pkill -9 -f "asgard_test_" 2>/dev/null || true

  # 5. Remove stale dune lock file if left over from forcefully killed dune
  if [ -f "_build/.lock" ]; then
    rm -f "_build/.lock" 2>/dev/null || true
    if [ "$verbose" = "true" ]; then
      echo "[run_tests.sh] Removed stale _build/.lock"
    fi
  fi
}

# Standalone --kill / -k flag
if [[ "${1:-}" == "--kill" || "${1:-}" == "-k" ]]; then
  kill_running_tests "true"
  echo "[run_tests.sh] All test processes terminated."
  exit 0
fi

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: ./run_tests.sh [OPTIONS] [DUNE_ARGS...]"
  echo ""
  echo "Options:"
  echo "  -k, --kill     Kill all running test processes and stale locks, then exit"
  echo "  -h, --help     Show this help message"
  echo ""
  echo "All other options are forwarded directly to 'dune runtest'."
  echo "By default, '--no-buffer' is passed so test execution logs stream in real-time."
  exit 0
fi

# Set up opam env if available
if command -v opam >/dev/null 2>&1; then
  eval "$(opam env)"
fi

# Kill any lingering test processes before starting a fresh run
kill_running_tests "false"

# Check if user specified buffering preference
ARGS=("$@")
HAS_BUFFER_ARG=false
for arg in "$@"; do
  if [[ "$arg" == "--no-buffer" || "$arg" == "--buffer" ]]; then
    HAS_BUFFER_ARG=true
    break
  fi
done

if [ "$HAS_BUFFER_ARG" = "false" ]; then
  ARGS+=("--no-buffer")
fi

DUNE_PID=""

cleanup_on_interrupt() {
  trap - INT TERM EXIT
  echo ""
  echo "[run_tests.sh] Interrupted! Terminating all spawned test processes..."
  if [ -n "$DUNE_PID" ] && kill -0 "$DUNE_PID" 2>/dev/null; then
    kill -TERM "$DUNE_PID" 2>/dev/null || true
    sleep 0.1
    kill -9 "$DUNE_PID" 2>/dev/null || true
  fi
  kill_running_tests "false"
  exit 130
}

cleanup_on_exit() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    kill_running_tests "false"
  fi
}

trap cleanup_on_interrupt INT TERM
trap cleanup_on_exit EXIT

# Run dune runtest in background so trap can catch signals immediately
dune runtest "${ARGS[@]}" &
DUNE_PID=$!

set +e
wait "$DUNE_PID"
EXIT_CODE=$?
set -e

DUNE_PID=""

exit "$EXIT_CODE"
