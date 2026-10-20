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
  pkill -9 -f "tech_2601_test" 2>/dev/null || true
  pkill -9 -f "ocamlopt.*asgard" 2>/dev/null || true

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
  echo "The run is timed: every case reports its own duration, a line is printed"
  echo "every 30 seconds and the total is reported when the run ends."
  exit 0
fi

DUNE_PID=""
TIMER_PID=""
TAIL_PID=""
START_EPOCH="$(date +%s)"

# Per-case timings.  Alcotest captures the output of a case, so the test
# runner writes the durations to this file and the script tails it.
TIMES_FILE="$(mktemp -t asgard_test_times)"
export ASGARD_TEST_TIMES="$TIMES_FILE"

start_times_tail() {
  tail -f "$TIMES_FILE" &
  TAIL_PID=$!
}

stop_times_tail() {
  if [ -n "$TAIL_PID" ]; then
    kill "$TAIL_PID" 2>/dev/null || true
    wait "$TAIL_PID" 2>/dev/null || true
    TAIL_PID=""
  fi
}

# Print the elapsed time every 30 seconds so a long run does not look stuck.
start_ticker() {
  while kill -0 "$DUNE_PID" 2>/dev/null; do
    sleep 30
    kill -0 "$DUNE_PID" 2>/dev/null || break
    local now elapsed
    now="$(date +%s)"
    elapsed=$(( now - START_EPOCH ))
    printf '[run_tests.sh] elapsed %dm %02ds\n' "$(( elapsed / 60 ))" "$(( elapsed % 60 ))"
  done
}

cleanup_on_interrupt() {
  local sig="${1:-INT}"
  trap - INT TERM EXIT TSTP QUIT HUP
  stop_times_tail
  if [ -n "$TIMER_PID" ]; then
    kill "$TIMER_PID" 2>/dev/null || true
    TIMER_PID=""
  fi
  local now elapsed
  now="$(date +%s)"
  elapsed=$(( now - START_EPOCH ))
  printf '[run_tests.sh] total %dm %02ds (stopped by %s)\n' "$(( elapsed / 60 ))" "$(( elapsed % 60 ))" "$sig"
  echo ""
  echo "[run_tests.sh] Stopped by ${sig}! Terminating all spawned test processes..."
  if [ -n "$DUNE_PID" ] && kill -0 "$DUNE_PID" 2>/dev/null; then
    kill -TERM "$DUNE_PID" 2>/dev/null || true
    sleep 0.1
    kill -9 "$DUNE_PID" 2>/dev/null || true
  fi
  kill_running_tests "false"
  [ -t 0 ] && stty sane 2>/dev/null || true
  case "$sig" in
    SIGINT)  exit 130 ;;
    SIGQUIT) exit 131 ;;
    SIGTERM) exit 143 ;;
    SIGTSTP) exit 148 ;;
    SIGHUP)  exit 129 ;;
    *)       exit 130 ;;
  esac
}

cleanup_on_exit() {
  local exit_code=$?
  stop_times_tail
  if [ -n "$TIMER_PID" ]; then
    kill "$TIMER_PID" 2>/dev/null || true
    wait "$TIMER_PID" 2>/dev/null || true
    TIMER_PID=""
  fi
  local now elapsed
  now="$(date +%s)"
  elapsed=$(( now - START_EPOCH ))
  printf '[run_tests.sh] total %dm %02ds (exit code %d)\n' "$(( elapsed / 60 ))" "$(( elapsed % 60 ))" "$exit_code"
  if [ $exit_code -ne 0 ]; then
    kill_running_tests "false"
  fi
}

trap 'cleanup_on_interrupt SIGINT' INT
trap 'cleanup_on_interrupt SIGTERM' TERM
trap 'cleanup_on_interrupt SIGTSTP' TSTP
trap 'cleanup_on_interrupt SIGQUIT' QUIT
trap 'cleanup_on_interrupt SIGHUP' HUP
trap cleanup_on_exit EXIT

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

# Run dune runtest in background so trap can catch signals immediately
start_times_tail
dune runtest "${ARGS[@]}" &
DUNE_PID=$!

# Report the elapsed time while the run is going on
start_ticker &
TIMER_PID=$!

set +e
wait "$DUNE_PID"
EXIT_CODE=$?
set -e

DUNE_PID=""

exit "$EXIT_CODE"
