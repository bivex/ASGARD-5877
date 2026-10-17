#!/usr/bin/env bash
# ===========================================================================
#  ASGARD-5877 nn_metamorph - end-to-end run
#
#  [1/3] prove the numpy ground truth against the real protected binary
#  [2/3] architecture ladder on the compute kernel (full 6 rungs)
#  [3/3] trimmed ladder on the mix kernel (T=73 tokens is ~2x slower)
#
#  Requirements: mlx >= 0.31, numpy (pip install mlx numpy).
#  The diff_fuzz binaries must exist (see validate_ref.py error message).
# ===========================================================================
set -euo pipefail
cd "$(dirname "$0")"

python3 validate_ref.py -n 30000
python3 train.py --kernel compute --sweep
python3 train.py --kernel mix --sweep --rung 'mlp-s|mlp-w|xf-s'
