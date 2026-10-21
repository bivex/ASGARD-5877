#!/usr/bin/env bash
# ASGARD-5877: license build with the full protection set.
#
# The stack engine runs the complete ten-phase pipeline (superoperator
# fusion, mathematical amplification, MBA constant synthesis, CFF with
# a VPC dispatcher, spaghetti splitting, ghost padding, state feedback
# on the rolling key, stack balance repair).  The explicit
# configuration turns on every remaining protection feature and pins the
# seed, so the build is reproducible.
set -euo pipefail

_build/default/bin/main.exe protect-arm64 \
  -i examples/license_check.c \
  --engine=stack \
  --config samples/protection_config.full.json \
  --cff \
  --mba \
  --mba-depth 4 \
  --seed 1337 \
  --watermark 0x58771337 \
  --compile=true
