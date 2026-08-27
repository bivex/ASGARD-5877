#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/Users/password9090/.opam/default/bin:/opt/homebrew/bin:$PATH"

echo "========================================================================="
echo "   ASGARD-5877: MULTI-BUILD ARM64 CORPUS COMPILATION & DIVERSIFIER      "
echo "========================================================================="

BUILD_COUNT=8
CORPUS_DIR="$ROOT_DIR/binaries/corpus_build_arm64"
mkdir -p "$CORPUS_DIR"

cd "$ROOT_DIR"
dune build bin/main.exe

for i in $(seq 1 $BUILD_COUNT); do
    SEED=$((1000 * i + i * 1337 + 5877))
    TARGET_DIR="$CORPUS_DIR/build_$i"
    TARGET_BIN="$TARGET_DIR/protected_app"
    mkdir -p "$TARGET_DIR"
    
    echo "[Build $i/$BUILD_COUNT] Compiling ARM64 with Seed 0x$(printf '%08X' $SEED)..."
    
    # Compile with ARM64 Lifter, CFF and Deep MBA (D=4)
    dune exec bin/main.exe -- protect-arm64 \
        -i "$ROOT_DIR/examples/demo_c_app.c" \
        -o "$TARGET_DIR" \
        --seed "$SEED" \
        --cff \
        --mba \
        --mba-depth 4 \
        --compile true > /dev/null 2>&1
    
    FILE_SIZE=$(wc -c < "$TARGET_DIR/protected.vanguard")
    echo "  -> Compiled ARM64: $TARGET_BIN (Bytecode: $FILE_SIZE bytes in $TARGET_DIR/protected.vanguard)"
done

echo "-------------------------------------------------------------------------"
echo "Successfully built $BUILD_COUNT real polymorphic ARM64 binaries in $CORPUS_DIR"
echo "========================================================================="
