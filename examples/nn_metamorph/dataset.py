#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - Dataset generation and featurization
================================================================

Samples boundary-weighted vectors (same edge tables the differential fuzzer
uses, imported from ../diff_fuzz/run_diff_project.py), runs them through the
bit-exact numpy reference and produces two featurizations for MLX training:

  * flat bit vectors for the MLP:
      compute: [a:64 | su(b):64 | c:32 | bits(d):64 | bits(e):64 | flags:8] -> (N, 296)
      mix:     [seed:64 | blob:512 | n_bits:6 | active_mask:64]            -> (N, 646)
    where su(b) is the sign-extended int64 view of b (the same 64 bits the
    kernel consumes; the high 32 bits replicate bit 31 -- kept for uniformity).

  * byte-value token grids for the transformer:
      compute: 37 tokens (a:8 b:8 c:4 d:8 e:8 flags:1)
      mix:     73 tokens (seed:8 blob:64 + 1 length token)

Bit convention (documented once, used everywhere): column j holds bit j of
the little-endian integer, i.e. LSB-first (np.unpackbits(..., bitorder="little")
over the LE byte view). Output targets use the same convention.
"""

import os
import sys

import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SCRIPT_DIR, "..", "diff_fuzz"))

from kernel_ref import compute_kernel_np, mix_kernel_np, wrap_i32
from run_diff_project import EDGE_DBL, EDGE_FLAGS, EDGE_I32, EDGE_U32, EDGE_U64

PAD_ID = 256        # transformer padding token (blob bytes at i >= n)
LEN_BASE = 257      # length token id = LEN_BASE + n, n in [0, 64]
VOCAB = LEN_BASE + 65   # 322: 256 byte values + PAD + 65 length tokens

N_TOKENS_COMPUTE = 37
N_TOKENS_MIX = 73


# --------------------------------------------------------------------------
# Bit / byte unpacking
# --------------------------------------------------------------------------
def bits_u64(x) -> np.ndarray:
    """(N,) u64 -> (N, 64) float32 in {0,1}, LSB-first."""
    x = np.ascontiguousarray(x, dtype=np.uint64)
    return np.unpackbits(x.view(np.uint8).reshape(-1, 8), axis=1,
                         bitorder="little").astype(np.float32)


def bits_u32(x) -> np.ndarray:
    x = np.ascontiguousarray(x, dtype=np.uint32)
    return np.unpackbits(x.view(np.uint8).reshape(-1, 4), axis=1,
                         bitorder="little").astype(np.float32)


def bits_u8(x) -> np.ndarray:
    x = np.ascontiguousarray(x, dtype=np.uint8).reshape(-1, 1)
    return np.unpackbits(x, axis=1, bitorder="little").astype(np.float32)


def bytes_u64(x) -> np.ndarray:
    """(N,) u64 -> (N, 8) uint8 little-endian byte tokens."""
    return np.ascontiguousarray(x, dtype=np.uint64).view(np.uint8).reshape(-1, 8)


# --------------------------------------------------------------------------
# Sampling (boundary-weighted, mirrors the diff-fuzzer distribution)
# --------------------------------------------------------------------------
def _sample_finite_bitpatterns(n, rng) -> np.ndarray:
    """Random f64 bit patterns with exponent clamped to [0, 0x7FE] (finite)."""
    bits = rng.integers(0, 2**64, size=n, dtype=np.uint64)
    exp = rng.integers(0, 0x7FF, size=n, dtype=np.uint64)
    bits = (bits & np.uint64(0x800FFFFFFFFFFFFF)) | (exp << np.uint64(52))
    return bits.view(np.float64)


def sample_raw_compute(n: int, rng: np.random.Generator) -> dict:
    a = np.zeros(n, dtype=np.uint64)
    b = np.zeros(n, dtype=np.int64)
    c = np.zeros(n, dtype=np.uint32)
    d = np.zeros(n, dtype=np.float64)
    e = np.zeros(n, dtype=np.float64)
    flags = np.zeros(n, dtype=np.uint8)

    mode = rng.integers(0, 100, size=n)
    m = mode < 25                       # edge blend
    a[m] = rng.choice(np.array(EDGE_U64, dtype=np.uint64), size=int(m.sum()))
    b[m] = wrap_i32(rng.choice(np.array(EDGE_I32, dtype=np.int64), size=int(m.sum())))
    c[m] = rng.choice(np.array(EDGE_U32, dtype=np.uint32), size=int(m.sum()))
    d[m] = rng.choice(np.array(EDGE_DBL, dtype=np.float64), size=int(m.sum()))
    e[m] = rng.choice(np.array(EDGE_DBL, dtype=np.float64), size=int(m.sum()))
    flags[m] = rng.choice(np.array(EDGE_FLAGS, dtype=np.uint8), size=int(m.sum()))

    m = (mode >= 25) & (mode < 40)      # walking 1s / single-bit boundaries
    a[m] = np.uint64(1) << rng.integers(0, 64, size=int(m.sum())).astype(np.uint64)
    b[m] = wrap_i32((np.uint64(1) << rng.integers(0, 32, size=int(m.sum())).astype(np.uint64))
                    .view(np.int64))
    c[m] = np.uint32(1) << rng.integers(0, 32, size=int(m.sum())).astype(np.uint32)
    d[m] = np.round(rng.uniform(-1000.0, 1000.0, size=int(m.sum())), 3)
    e[m] = np.round(rng.uniform(-10.0, 10.0, size=int(m.sum())), 2)
    flags[m] = rng.integers(0, 256, size=int(m.sum()), dtype=np.uint8)

    m = (mode >= 40) & (mode < 55)      # subnormal / fractional
    a[m] = rng.integers(0, 2**64, size=int(m.sum()), dtype=np.uint64)
    b[m] = wrap_i32(rng.integers(-2**31, 2**31, size=int(m.sum()), dtype=np.int64))
    c[m] = rng.integers(0, 2**32, size=int(m.sum()), dtype=np.uint32)
    d[m] = rng.uniform(-100.0, 100.0, size=int(m.sum())) * 1e-300
    e[m] = rng.uniform(-50.0, 50.0, size=int(m.sum()))
    flags[m] = rng.integers(0, 256, size=int(m.sum()), dtype=np.uint8)

    m = (mode >= 55) & (mode < 90)      # pure random uniform
    a[m] = rng.integers(0, 2**64, size=int(m.sum()), dtype=np.uint64)
    b[m] = wrap_i32(rng.integers(-2**31, 2**31, size=int(m.sum()), dtype=np.int64))
    c[m] = rng.integers(0, 2**32, size=int(m.sum()), dtype=np.uint32)
    d[m] = np.round(rng.uniform(-5000.0, 5000.0, size=int(m.sum())), 4)
    e[m] = np.round(rng.uniform(-20.0, 20.0, size=int(m.sum())), 4)
    flags[m] = rng.integers(0, 256, size=int(m.sum()), dtype=np.uint8)

    m = mode >= 90                      # full-range finite bit patterns
    a[m] = rng.integers(0, 2**64, size=int(m.sum()), dtype=np.uint64)
    b[m] = wrap_i32(rng.integers(-2**31, 2**31, size=int(m.sum()), dtype=np.int64))
    c[m] = rng.integers(0, 2**32, size=int(m.sum()), dtype=np.uint32)
    d[m] = _sample_finite_bitpatterns(int(m.sum()), rng)
    e[m] = _sample_finite_bitpatterns(int(m.sum()), rng)
    flags[m] = rng.integers(0, 256, size=int(m.sum()), dtype=np.uint8)

    return dict(a=a, b=b, c=c, d=d, e=e, flags=flags)


def sample_raw_mix(n: int, rng: np.random.Generator) -> dict:
    seed = rng.integers(0, 2**64, size=n, dtype=np.uint64)
    # lengths 0..64 (n=0 exercises the `h ^= 0xC0FFEE` tail)
    n_len = rng.integers(0, 65, size=n, dtype=np.int64)
    blob = rng.integers(0, 256, size=(n, 64), dtype=np.uint8)
    return dict(seed=seed, blob=blob, n=n_len)


# --------------------------------------------------------------------------
# Featurization
# --------------------------------------------------------------------------
def su64(b) -> np.ndarray:
    """Sign-extended int64 view of (wrapped) b, as uint64."""
    return np.ascontiguousarray(b, dtype=np.int64).view(np.uint64)


def featurize_compute(rec: dict) -> np.ndarray:
    return np.concatenate([
        bits_u64(rec["a"]),
        bits_u64(su64(rec["b"])),
        bits_u32(rec["c"]),
        bits_u64(rec["d"].view(np.uint64)),
        bits_u64(rec["e"].view(np.uint64)),
        bits_u8(rec["flags"]),
    ], axis=1)


def featurize_mix(rec: dict) -> np.ndarray:
    n = rec["n"]
    n_bits = ((n[:, None] >> np.arange(6, dtype=np.int64)) & 1).astype(np.float32)
    active = (np.arange(64, dtype=np.int64)[None, :] < n[:, None]).astype(np.float32)
    return np.concatenate([
        bits_u64(rec["seed"]),
        np.unpackbits(rec["blob"], axis=1, bitorder="little").astype(np.float32),
        n_bits,
        active,
    ], axis=1)


def targets(y) -> np.ndarray:
    return bits_u64(y)


def token_ids_compute(rec: dict) -> np.ndarray:
    tok = np.concatenate([
        bytes_u64(rec["a"]),
        bytes_u64(su64(rec["b"])),
        np.ascontiguousarray(rec["c"], dtype=np.uint32).view(np.uint8).reshape(-1, 4),
        bytes_u64(rec["d"].view(np.uint64)),
        bytes_u64(rec["e"].view(np.uint64)),
        np.ascontiguousarray(rec["flags"], dtype=np.uint8).reshape(-1, 1),
    ], axis=1)
    assert tok.shape[1] == N_TOKENS_COMPUTE
    return tok.astype(np.int32)


def token_ids_mix(rec: dict) -> np.ndarray:
    n = rec["n"]
    seed_tok = bytes_u64(rec["seed"])
    blob_tok = rec["blob"].astype(np.int32).copy()
    blob_tok[np.arange(64, dtype=np.int64)[None, :] >= n[:, None]] = PAD_ID
    len_tok = (LEN_BASE + n).astype(np.int32).reshape(-1, 1)
    tok = np.concatenate([seed_tok.astype(np.int32), blob_tok, len_tok], axis=1)
    assert tok.shape[1] == N_TOKENS_MIX
    return tok


# --------------------------------------------------------------------------
# Dataset assembly
# --------------------------------------------------------------------------
def make_dataset(kernel: str, n_train: int, n_val: int, n_test: int,
                 seed: int = 1) -> dict:
    """Returns {split: {X_bits, X_tok, Y, aux}} with numpy arrays."""
    rng = np.random.default_rng(seed)
    out = {}
    for name, n in (("train", n_train), ("val", n_val), ("test", n_test)):
        if kernel == "compute":
            rec = sample_raw_compute(n, rng)
            y = compute_kernel_np(rec["a"], rec["b"], rec["c"],
                                  rec["d"], rec["e"], rec["flags"])
            out[name] = dict(
                X_bits=featurize_compute(rec),
                X_tok=token_ids_compute(rec),
                Y=targets(y),
                aux=(rec["flags"] & 1).astype(np.int32),  # path selector
            )
        elif kernel == "mix":
            rec = sample_raw_mix(n, rng)
            y = mix_kernel_np(rec["seed"], rec["blob"], rec["n"])
            out[name] = dict(
                X_bits=featurize_mix(rec),
                X_tok=token_ids_mix(rec),
                Y=targets(y),
                aux=None,
            )
        else:
            raise ValueError(f"unknown kernel: {kernel}")
    return out
