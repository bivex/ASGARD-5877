#!/usr/bin/env bash
# ==============================================================================
# ASGARD-5877 Real-World Benchmark Corpus Runner
# Target Corpus: SQLite (Varint/PageHash), GNU Coreutils (CRC-32), OpenSSL (SHA-256)
# Measures: Devirtualization Resistance Score (DRS), Execution Overhead, Code Bloat
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/Users/password9090/.opam/default/bin:/opt/homebrew/bin:$PATH"
BENCH_BUILD_DIR="$ROOT_DIR/_build/real_corpus_bench"
mkdir -p "$BENCH_BUILD_DIR"

echo "========================================================================="
echo "   ASGARD-5877: REAL-WORLD PRODUCTION CORPUS BENCHMARK SUITE             "
echo "========================================================================="
echo "Host: $(uname -s) $(uname -m) | OS: $(sw_vers -productVersion 2>/dev/null || uname -r)"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Workloads: OpenSSL (SHA-256), Coreutils (CRC-32), SQLite (Varint), WireGuard (ChaCha20), Zstandard (xxHash64)"
echo "Protection Profile: Full ARM64 Virtualization + CFF + 2-Round MBA + RNS-4"
echo "-------------------------------------------------------------------------"

echo "[1/4] Building ASGARD-5877 Virtualization Toolchain..."
cd "$ROOT_DIR"
eval $(opam env 2>/dev/null || true)
dune build bin/main.exe

MAIN_EXE="$ROOT_DIR/_build/default/bin/main.exe"
if [[ ! -x "$MAIN_EXE" ]]; then
    echo "[-] Error: main.exe not found at $MAIN_EXE"
    exit 1
fi

RESULTS_JSON="$BENCH_BUILD_DIR/results.json"
echo "[]" > "$RESULTS_JSON"

run_benchmark() {
    local NAME="$1"
    local DISPLAY_NAME="$2"
    local SRC="$ROOT_DIR/examples/real_corpus/$3"
    local ITERS="$4"
    local WORK_DIR="$BENCH_BUILD_DIR/$NAME"
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"

    echo ""
    echo "========================================================================="
    echo ">>> Target: $DISPLAY_NAME ($ITERS iterations)"
    echo "========================================================================="

    # --- 1. Native Compilation & Execution ---
    echo "[*] Compiling Native Reference (-O3)..."
    local NATIVE_BIN="$WORK_DIR/native_app"
    clang -O3 -I "$ROOT_DIR/examples" "$SRC" -o "$NATIVE_BIN"
    local NATIVE_SIZE=$(stat -f%z "$NATIVE_BIN" 2>/dev/null || stat -c%s "$NATIVE_BIN")

    echo "[*] Running Native Reference Benchmark..."
    local NATIVE_OUT
    NATIVE_OUT=$("$NATIVE_BIN" "$ITERS")
    echo "$NATIVE_OUT" | grep -E "\[BENCHMARK\]"

    local NATIVE_VERIF=$(echo "$NATIVE_OUT" | grep "Verification:" | awk '{print $NF}')
    local NATIVE_TIME_US=$(echo "$NATIVE_OUT" | grep "Elapsed:" | awk '{print $(NF-1)}')

    if [[ "$NATIVE_VERIF" != "PASS" ]]; then
        echo "[-] ERROR: Native reference verification failed!"
        exit 1
    fi

    # --- 2. ASGARD-5877 Protection ---
    echo "[*] Virtualizing with ASGARD-5877 (--flatten --mba)..."
    local PROT_DIR="$WORK_DIR/asgard_out"
    local PROT_LOG="$WORK_DIR/protection.log"

    "$MAIN_EXE" protect-arm64 -i "$SRC" -o "$PROT_DIR" --flatten --mba > "$PROT_LOG" 2>&1

    local DRS_SCORE=$(grep -E "TOTAL RESISTANCE SCORE" "$PROT_LOG" | sed -E 's/.*: +([0-9.]+) \/.*/\1/' || echo "N/A")
    local BYTECODE_BIN="$PROT_DIR/protected.vanguard"
    local BYTECODE_SIZE=0
    if [[ -f "$BYTECODE_BIN" ]]; then
        BYTECODE_SIZE=$(stat -f%z "$BYTECODE_BIN" 2>/dev/null || stat -c%s "$BYTECODE_BIN")
    fi

    local PROT_BIN="$PROT_DIR/protected_app"
    if [[ ! -x "$PROT_BIN" ]]; then
        echo "[-] ERROR: Protected binary $PROT_BIN was not generated!"
        cat "$PROT_LOG"
        exit 1
    fi
    local PROT_SIZE=$(stat -f%z "$PROT_BIN" 2>/dev/null || stat -c%s "$PROT_BIN")

    # --- 3. Protected Binary Execution ---
    echo "[*] Executing ASGARD-5877 Virtualized Binary..."
    local PROT_OUT
    PROT_OUT=$("$PROT_BIN" "$ITERS")
    echo "$PROT_OUT" | grep -E "\[BENCHMARK\]"

    local PROT_VERIF=$(echo "$PROT_OUT" | grep "Verification:" | awk '{print $NF}')
    local PROT_TIME_US=$(echo "$PROT_OUT" | grep "Elapsed:" | awk '{print $(NF-1)}')

    if [[ "$PROT_VERIF" != "PASS" ]]; then
        echo "[-] ERROR: ASGARD-5877 protected verification failed!"
        exit 1
    fi

    # Record data via python
    python3 -c "
import json
with open('$RESULTS_JSON', 'r') as f:
    data = json.load(f)
data.append({
    'name': '$NAME',
    'display': '$DISPLAY_NAME',
    'iterations': int('$ITERS'),
    'native_time_us': int('$NATIVE_TIME_US'),
    'prot_time_us': int('$PROT_TIME_US'),
    'native_size': int('$NATIVE_SIZE'),
    'prot_size': int('$PROT_SIZE'),
    'bytecode_size': int('$BYTECODE_SIZE'),
    'drs': float('$DRS_SCORE'),
    'verif': '$PROT_VERIF'
})
with open('$RESULTS_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "[+] $DISPLAY_NAME: 100% PASS (DRS: $DRS_SCORE / 100.0)"
}

# Run the 5 real-world workloads
run_benchmark "openssl" "OpenSSL (SHA-256 Transform)" "openssl_sha256.c" "100"
run_benchmark "coreutils" "GNU Coreutils (CRC-32 cksum)" "coreutils_crc32.c" "200"
run_benchmark "sqlite" "SQLite (Varint64 & Page Checksum)" "sqlite_varint_hash.c" "200"
run_benchmark "wireguard" "WireGuard (ChaCha20 Block)" "wireguard_chacha20.c" "100"
run_benchmark "zstd" "Zstandard (xxHash64 Checksum)" "zstd_xxhash64.c" "200"

echo ""
echo "========================================================================="
echo "   ASGARD-5877 REAL-WORLD BENCHMARK CORPUS REPORT                        "
echo "========================================================================="

python3 -c "
import json

with open('$RESULTS_JSON', 'r') as f:
    data = json.load(f)

print('| Benchmark Suite | Workload Core | Verification | DRS Score | Native Time | VM Protected Time | Overhead Factor | Bytecode Size | Binary Bloat |')
print('| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |')

for d in data:
    overhead = d['prot_time_us'] / max(1, d['native_time_us'])
    bloat = d['prot_size'] / max(1, d['native_size'])
    
    nat_str = f\"{d['native_time_us']} us\" if d['native_time_us'] < 1000 else f\"{d['native_time_us']/1000:.2f} ms\"
    vm_str = f\"{d['prot_time_us']/1000:.2f} ms\" if d['prot_time_us'] < 1000000 else f\"{d['prot_time_us']/1000000:.2f} s\"
    bc_str = f\"{d['bytecode_size']/1024:.1f} KB\"
    
    print(f\"| **{d['display']}** | {d['name'].upper()} Core | **{d['verif']}** | **{d['drs']:.1f} / 100.0** | {nat_str} | {vm_str} | **{overhead:.1f}x** | {bc_str} | {bloat:.1f}x |\")

print('\n')
all_pass = all(d['verif'] == 'PASS' for d in data)
if all_pass:
    print('>>> ALL 5 REAL-WORLD BENCHMARK SUITES VERIFIED AND PASSED 100% <<<')
else:
    print('>>> WARNING: Some benchmarks failed verification! <<<')
"

echo "========================================================================="
echo "   [BENCHMARK RUN COMPLETED SUCCESSFULLY]                                "
echo "========================================================================="
