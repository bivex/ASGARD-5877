#!/usr/bin/env bash
# ASGARD-5877: Multi-VM Nested Stack license build with Heterogeneous Dual-VM protection.
set -euo pipefail

OUT_DIR="./protected_multivm_out"
mkdir -p "$OUT_DIR"

_build/default/bin/main.exe protect-arm64 \
  -i examples/license_check_multivm.c \
  -o "$OUT_DIR" \
  --engine=multi \
  --config samples/protection_config.multivm.json \
  --mba \
  --mba-depth 4 \
  --seed 1337 \
  --watermark 0x58771337 \
  --compile=true
