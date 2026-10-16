#!/usr/bin/env bash
# ===========================================================================
#  ASGARD-5877 Differential Fuzzing - libFuzzer Orchestrator
#
#  Coverage-guided differential campaign in ONE process:
#
#    fuzz bytes ──> TestPayload ──┬─> asgard_fuzz_compute_native (golden)
#                                └─> asgard_fuzz_compute      (ASGARD VM)
#
#  Build stages:
#    [1/4] random_visa project on proj_src/ (macro-obf + CFF + MBA + VM lift)
#    [2/4] native golden TU      (plain clang++, markers inert, -D rename)
#    [3/4] VM trampoline TU      (.asgard_build/compute_core_virtualized.cpp)
#    [4/4] link everything with -fsanitize=fuzzer and run the campaign
#
#  Environment knobs:
#    ASG_FUZZ_SECONDS  campaign wall-clock seconds        (default 60)
#    ASG_FUZZ_RUNS     fixed iteration count instead of time (overrides above)
#    ASG_FUZZ_SEED     project-mode randomization seed     (default: random)
#    ASG_FUZZ_NO_CFF=1 disable control-flow flattening
#    ASG_FUZZ_NO_MBA=1 disable mixed boolean-arithmetic rewriting
#    ASG_FUZZ_ALLOW_NAN=1  do NOT skip NaN/Inf doubles (cvttsd2si parity)
#
#  On divergence the driver traps; the crashing input lands in ./artifacts/
#  and can be shrunk with:
#    ./build/diff_fuzzer -minimize_crash=1 -runs=100000 ./artifacts/crash-*
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

FUZZ_SECONDS="${ASG_FUZZ_SECONDS:-60}"
FUZZ_RUNS="${ASG_FUZZ_RUNS:-}"
SEED="${ASG_FUZZ_SEED:-}"
VM_OUT="$SCRIPT_DIR/vm_out"
BUILD_DIR="$SCRIPT_DIR/build"
CORPUS_DIR="$SCRIPT_DIR/corpus"
ARTIFACT_DIR="$SCRIPT_DIR/artifacts"
MAX_LEN=104   # sizeof(TestPayload)=40 + max mix blob=64

mkdir -p "$VM_OUT" "$BUILD_DIR" "$CORPUS_DIR" "$ARTIFACT_DIR"

# --------------------------------------------------------------------------
echo "== [1/4] ASGARD project-mode protection (macro-obf + CFF + MBA + VM) =="
PROTECT_CMD=(dune exec -- random_visa project
    -d "$SCRIPT_DIR/proj_src"
    -o "$VM_OUT/protected_proj"
    --run=false)
[ "${ASG_FUZZ_NO_CFF:-0}" != "1" ] && PROTECT_CMD+=(--cff)
[ "${ASG_FUZZ_NO_MBA:-0}" != "1" ] && PROTECT_CMD+=(--mba)
if [ -n "$SEED" ]; then PROTECT_CMD+=(-s "$SEED"); fi
echo "   ${PROTECT_CMD[*]}"

cd "$REPO_ROOT"
eval "$(opam env)" && "${PROTECT_CMD[@]}"

VIRT_TU="$VM_OUT/.asgard_build/compute_core_virtualized.cpp"
VM_HDR_DIR="$VM_OUT/.asgard_build"
if [ ! -f "$VIRT_TU" ]; then
    echo "ERROR: project mode did not produce $VIRT_TU" >&2
    exit 1
fi

# Free smoke test: the linked protected binary must run its self-test.
"$VM_OUT/protected_proj"

# --------------------------------------------------------------------------
# Locate a clang++ compiler that has libFuzzer support.
# Apple Clang in Xcode does not ship libclang_rt.fuzzer_osx.a.
# Homebrew LLVM (e.g. llvm@21 or llvm) includes it out of the box.
find_fuzzer_compiler() {
    if [ -n "${CLANGXX:-}" ] && command -v "$CLANGXX" >/dev/null 2>&1; then
        echo "$CLANGXX"
        return 0
    fi
    for cand in \
        "/opt/homebrew/opt/llvm@21/bin/clang++" \
        "/opt/homebrew/opt/llvm/bin/clang++" \
        "$(brew --prefix llvm@21 2>/dev/null)/bin/clang++" \
        "$(brew --prefix llvm 2>/dev/null)/bin/clang++" \
        "/usr/local/opt/llvm/bin/clang++"; do
        if [ -x "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    echo "clang++"
}

FUZZ_CXX="$(find_fuzzer_compiler)"

if ! echo 'extern "C" int LLVMFuzzerTestOneInput(const unsigned char *d, unsigned long s) { return 0; }' | "$FUZZ_CXX" -fsanitize=fuzzer -x c++ - -o /dev/null 2>/dev/null; then
    echo "ERROR: $FUZZ_CXX does not have libFuzzer support (libclang_rt.fuzzer_osx.a is missing in Apple Clang)." >&2
    echo "Please install LLVM via Homebrew: brew install llvm@21" >&2
    echo "or set CLANGXX=/path/to/clang++" >&2
    exit 1
fi

FUZZ_FLAGS=(-fsanitize=fuzzer-no-link -ffp-contract=off -g)

echo "== [2/4] Compiling native golden TU using $FUZZ_CXX =="
"$FUZZ_CXX" -std=c++20 -O1 "${FUZZ_FLAGS[@]}" \
    -I"$REPO_ROOT/examples" \
    -Dasgard_fuzz_compute=asgard_fuzz_compute_native \
    -Dasgard_fuzz_mix=asgard_fuzz_mix_native \
    -c "$SCRIPT_DIR/proj_src/compute_core.cpp" \
    -o "$BUILD_DIR/compute_core_native.o"

echo "== [3/4] Compiling VM trampoline TU + fuzz driver =="
"$FUZZ_CXX" -std=c++20 -O1 "${FUZZ_FLAGS[@]}" \
    -I"$VM_HDR_DIR" -I"$SCRIPT_DIR/proj_src" \
    -c "$VIRT_TU" \
    -o "$BUILD_DIR/compute_core_vm.o"

"$FUZZ_CXX" -std=c++20 -O1 "${FUZZ_FLAGS[@]}" \
    -I"$SCRIPT_DIR" \
    -c "$SCRIPT_DIR/fuzz_driver.cpp" \
    -o "$BUILD_DIR/fuzz_driver.o"

echo "== [4/4] Linking differential fuzzer =="
"$FUZZ_CXX" -fsanitize=fuzzer \
    "$BUILD_DIR/compute_core_native.o" \
    "$BUILD_DIR/compute_core_vm.o" \
    "$BUILD_DIR/fuzz_driver.o" \
    -o "$BUILD_DIR/diff_fuzzer"

# --------------------------------------------------------------------------
# Seed corpus: deterministic boundary vectors so every campaign starts deep.
python3 - "$CORPUS_DIR" <<'PYEOF'
import os, struct, sys
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for f in os.listdir(out):
    os.remove(os.path.join(out, f))

edges_u64 = [0, 1, 2, 42, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
             0x7FFFFFFFFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF,
             0xCAFEBABE13375877]
edges_i32 = [0, 1, -1, 42, -12345, 0x7FFFFFFF, -0x80000000]
edges_u32 = [0, 1, 31, 32, 63, 64, 0xFFFFFFFF, 0x1337]   # shift boundaries
quots = [0.0, -0.0, 1.0, -1.0, 0.5, 250.5, -500.5, 12.345,
         1e300, -1e300, 5e-324, 1e-5, 1.7976931348623157e308]
weights = [0.0, 1.0, -1.0, 2.0, 0.5, -2.5, 1e-300, 3.5]
k = 0
def emit(a, b, c, d, e, flags, blob):
    global k
    payload = struct.pack('<QIIddB7x', a, b & 0xFFFFFFFF, c, d, e, flags)
    with open(os.path.join(out, f"seed_{k:05d}"), "wb") as fh:
        fh.write(payload + blob)
    k += 1

for a in edges_u64:
    for c in edges_u32:
        emit(a, -12345, c, 250.5, 2.0, 0xAB, b"\xde\xad\xbe\xef")
for b in edges_i32:
    for d in quots:
        emit(0x0123456789ABCDEF, b, 63, d, -1.5, 1, b"\x00")
for e in weights:
    emit(0xFFFFFFFFFFFFFFFF, 0x7FFFFFFF, 32, 1e300, e, 3, bytes(range(8)))
for flags in (0, 1, 2, 3, 7, 0x0F, 0x55, 0xAA, 0xFF):
    emit(0xCAFEBABE, -1, 0, 0.0, 0.0, flags, b"\x58\x77")
print(f"seed corpus: {k} files")
PYEOF

# --------------------------------------------------------------------------
DICT_FILE="$SCRIPT_DIR/diff_fuzz.dict"
RUN_ARGS=(-max_len="$MAX_LEN" -rss_limit_mb=4096 -print_final_stats=1
          -artifact_prefix="$ARTIFACT_DIR/")
if [ -f "$DICT_FILE" ]; then
    RUN_ARGS+=(-dict="$DICT_FILE")
fi
RUN_ARGS+=("$CORPUS_DIR")
if [ -n "$FUZZ_RUNS" ]; then
    RUN_ARGS=(-runs="$FUZZ_RUNS" "${RUN_ARGS[@]}")
    echo "== Running libFuzzer differential campaign: $FUZZ_RUNS iterations =="
else
    RUN_ARGS=(-max_total_time="$FUZZ_SECONDS" "${RUN_ARGS[@]}")
    echo "== Running libFuzzer differential campaign: ${FUZZ_SECONDS}s budget =="
fi
"$BUILD_DIR/diff_fuzzer" "${RUN_ARGS[@]}"

echo ""
echo "SUCCESS: differential campaign finished with zero divergences."
