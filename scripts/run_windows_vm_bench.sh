#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877 Parallels Windows ARM64 Benchmark & Runner Script
# Compiles on macOS Host, Builds via MSVC in Windows VM, Executes & Verifies
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/Users/password9090/.opam/default/bin:/opt/homebrew/bin:$PATH"

SRC_NAME="${1:-openssl_sha256.c}"
BENCH_NAME="${2:-openssl}"
ITERS="${3:-10}"
VM_ID="${4:-d53f9ec7-88af-4baf-831a-08a68d4dbb9a}"

SRC_PATH="$ROOT_DIR/examples/real_corpus/$SRC_NAME"
OUT_DIR="$ROOT_DIR/_build/real_corpus_bench/$BENCH_NAME/asgard_out"

if [[ ! -f "$SRC_PATH" ]]; then
    echo "[-] Error: Source file not found: $SRC_PATH"
    echo "Usage: $0 <source_file.c> <bench_name> [iterations] [vm_uuid]"
    exit 1
fi

echo "========================================================================="
echo "   ASGARD-5877: PARALLELS WINDOWS ARM64 BENCHMARK RUNNER                 "
echo "========================================================================="
echo "Target Source: $SRC_NAME ($ITERS iterations)"
echo "Output Dir:    $OUT_DIR"
echo "Target VM:     $VM_ID"
echo "-------------------------------------------------------------------------"

# 1. Verify VM is running
VM_STATUS=$(prlctl list -a | grep -F "$VM_ID" | awk '{print $2}' || true)
if [[ "$VM_STATUS" != "running" ]]; then
    echo "[!] VM $VM_ID is not running (status: $VM_STATUS). Attempting to start..."
    prlctl start "$VM_ID"
    sleep 5
fi

# 2. Build ASGARD Toolchain on macOS
echo "[1/4] Building ASGARD toolchain on macOS host..."
cd "$ROOT_DIR"
eval $(opam env 2>/dev/null || true)
dune build bin/main.exe

# 3. Generate Protected ARM64 C++
echo "[2/4] Generating protected ARM64 C++ code..."
mkdir -p "$OUT_DIR"
_build/default/bin/main.exe protect-arm64 -i "$SRC_PATH" -o "$OUT_DIR" --flatten --mba

# 4. Clean up any locked processes in VM
prlctl exec "$VM_ID" --current-user cmd.exe /c \
  "taskkill /f /im cdb.exe & taskkill /f /im app.exe & exit 0" >/dev/null 2>&1 || true

# 5. Compile with MSVC cl.exe in Windows ARM64 VM
echo "[3/4] Compiling app_virtualized.cpp with MSVC cl.exe in Windows VM..."
WIN_REL_PATH="_build\\real_corpus_bench\\$BENCH_NAME\\asgard_out"
prlctl exec "$VM_ID" --current-user cmd.exe /c \
  "call \"C:\\Program Files\\Microsoft Visual Studio\\18\\Insiders\\VC\\Auxiliary\\Build\\vcvarsall.bat\" arm64 && \
   cd /d W:\\$WIN_REL_PATH && \
   cl /std:c++20 /O2 app_virtualized.cpp /Fe:app.exe"

# 6. Execute inside Windows VM
echo "[4/4] Executing app.exe $ITERS in Windows VM..."
prlctl exec "$VM_ID" --current-user cmd.exe /c \
  "cd /d W:\\$WIN_REL_PATH && app.exe $ITERS"

echo "-------------------------------------------------------------------------"
echo "[+] Done: Windows ARM64 execution finished successfully."
