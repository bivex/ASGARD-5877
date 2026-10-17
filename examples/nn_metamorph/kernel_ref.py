#!/usr/bin/env python3
"""
ASGARD-5877 nn_metamorph - Bit-exact numpy reference of the protected kernels
===============================================================================

Vectorized reimplementation of the two ASGARD-protected kernels from
examples/diff_fuzz/proj_src/compute_core.cpp:

  * asgard_fuzz_compute (ULTRA virtualization)
  * asgard_fuzz_mix     (VIRTUALIZE)

Because the differential fuzzers maintain 100% parity between the native
golden build and the ASGARD VM build, this reference -- validated against
BOTH real binaries by validate_ref.py -- is the ground truth for neural
network training.

Semantics notes (each one verified against the shipped arm64 binaries):

  * All integer arithmetic is mod 2^64 (numpy uint64 wraps under errstate).
  * The (int64_t)double cast saturates with ARM `fcvtzs` semantics:
    >= 2^63 -> INT64_MAX, < -2^63 -> INT64_MIN, NaN -> 0, else truncate
    toward zero. (The x86 cvttsd2si "indefinite" constant from the source
    comments does NOT match the shipped arm64 binaries.)
  * `su >> 3` is a LOGICAL shift: su is uint64 (sign-extended b reinterpreted).
  * q = d*e and q2 = q+d are two separate IEEE double ops (never FMA).
  * (float)(e + 1.0) rounds-to-nearest-even to f32 (numpy astype), overflow
    goes to +/-inf; -0.0f survives the `fq < 0.0f` branch as bits 0x80000000.
  * The data-dependent loop (iters = (c & 15) + 4 in [4,19]) is vectorized
    as a fixed 19-step schedule with a boolean activity mask: `x` is
    read-only inside the loop (x ^= acc happens after it) and `acc` is the
    only carried state, so masked np.where updates are exact.
"""

import numpy as np

MASK64 = np.uint64(0xFFFFFFFFFFFFFFFF)


def wrap_i32(b: np.ndarray) -> np.ndarray:
    """Wrap b to the signed 32-bit range.

    IMPORTANT: the --fuzz driver parses b with strtoll and then stores it
    into an int32_t field, i.e. (int32_t)(int64_t)value.  Values like
    0xCAFEBABE from the edge tables therefore wrap BEFORE the kernel's
    sign-extension.  Skipping this step diverges with xor mask
    0xFFFFFFFF00000000 on every such vector.
    """
    b = np.asarray(b, dtype=np.int64)
    return ((b + 2**31) % 2**32) - 2**31


def compute_kernel_np(a, b, c, d, e, flags) -> np.ndarray:
    """Vectorized asgard_fuzz_compute.

    dtypes: a u64, b i64 (already int32-wrapped), c u32, d f64, e f64, flags u8
    returns: u64 (N,)
    """
    a = np.asarray(a, dtype=np.uint64)
    b = np.asarray(b, dtype=np.int64)
    c = np.asarray(c, dtype=np.uint32)
    d = np.asarray(d, dtype=np.float64)
    e = np.asarray(e, dtype=np.float64)
    flags = np.asarray(flags, dtype=np.uint8)

    with np.errstate(all="ignore"):  # wraparound semantics are intentional
        # Sign-extend b to 64 bits, then reinterpret as unsigned.
        su = b.view(np.uint64) if b.dtype == np.int64 else b.astype(np.int64).view(np.uint64)

        early = (flags & 1) == 0
        res_early = (a ^ np.uint64(0x5877)) + su

        x = a + su
        x = (x * np.uint64(0x9E3779B97F4A7C15)) ^ (c.astype(np.uint64) + np.uint64(0x1337))
        x ^= x >> 29
        x = x * np.uint64(0xBF58476D1CE4E5B9)
        x ^= x >> 32

        # Variable rotation with masked counts (no shift-by-64 UB).
        s = (c & np.uint32(63)).astype(np.uint64)
        rot = (x << s) | (x >> ((np.uint64(64) - s) & np.uint64(63)))
        x ^= rot

        # Unsigned div/mod; divisor forced non-zero via |1.
        udv = (c | np.uint32(1)).astype(np.uint64)
        x = x ^ (a // udv)
        x = x - (a % udv)

        # Signed widening + LOGICAL shift of the sign-extended value.
        x = (x + su) ^ (su >> 3)

        # FP path: two separate double ops (never FMA-contracted).
        q = d * e
        q2 = q + d

        # Saturating (int64_t)double -- ARM fcvtzs semantics.
        # Clip first so the cast itself is always in-range, then patch the
        # saturated lanes (2**63 - 1024.0 is the largest f64 below 2^63).
        t = np.trunc(np.where(np.isnan(q2), 0.0, q2))
        t = np.clip(t, -2.0**63, 2.0**63 - 1024.0)
        qi = np.where(q2 >= 2.0**63, np.int64(2**63 - 1),
                      np.where(q2 < -2.0**63, np.int64(-2**63),
                               t.astype(np.int64)))
        x = x ^ qi.view(np.uint64)

        # elif-chain on q2 (NaN compares false everywhere; -0.0 == 0.0).
        x = np.where(q2 > 1.0e12, x ^ np.uint64(0xDEADBEEF), x)
        x = np.where((q2 <= 1.0e12) & (q2 < -1.0e12), x ^ np.uint64(0xCAFEBABE), x)
        x = np.where((q2 <= 1.0e12) & (q2 >= -1.0e12) & (q2 == 0.0),
                     x ^ np.uint64(0xFFFF), x)

        # cvtsd2ss observed through the bit pattern (RNE, overflow -> inf).
        fq = (e + 1.0).astype(np.float32)
        fq = np.where(fq < np.float32(0.0), -fq, fq)
        fbits = np.ascontiguousarray(fq).view(np.uint32)
        x = x ^ (fbits.astype(np.uint64) << np.uint64(1))

        # switch (flags & 7): default arm is a no-op mask-OR.
        sel = (flags & 7)
        xs = x
        xs = np.where(sel == 1, x + np.uint64(0x1111111111111111), xs)
        xs = np.where(sel == 3, x - np.uint64(0x2222222222222222), xs)
        xs = np.where(sel == 5, x ^ np.uint64(0x4444444444444444), xs)
        xs = np.where(sel == 7, ~x, xs)
        x = xs

        # Data-dependent loop: iters = (c & 15) + 4 in [4, 19].
        acc = np.full_like(x, np.uint64(0x243F6A8885A308D3))
        iters = ((c & np.uint32(15)) + np.uint32(4)).astype(np.uint64)
        for i in range(19):
            act = np.uint64(i) < iters
            upd = (acc ^ (x + np.uint64(i))) * np.uint64(0x100000001B3)
            upd = np.where((upd & 1) == 0,
                           upd ^ np.uint64(0x9E3779B9),
                           upd + (np.uint64(i) << 8))
            acc = np.where(act, upd, acc)
        x = x ^ acc

        return np.where(early, res_early, x).astype(np.uint64)


def mix_kernel_np(seed, blob, n) -> np.ndarray:
    """Vectorized asgard_fuzz_mix.

    dtypes: seed u64 (N,), blob u8 (N, 64) zero-padded, n i64 (N,)
    returns: u64 (N,)
    """
    seed = np.asarray(seed, dtype=np.uint64)
    blob = np.asarray(blob, dtype=np.uint8)
    n = np.asarray(n, dtype=np.int64)

    with np.errstate(all="ignore"):
        h = seed.copy()
        for i in range(64):
            act = i < n
            upd = (h ^ blob[:, i].astype(np.uint64)) * np.uint64(0x100000001B3)
            upd = upd ^ (upd >> 31)
            upd = np.where((upd & 1) == 0,
                           upd + np.uint64(0x9E3779B97F4A7C15),
                           upd - np.uint64(0x5877))
            h = np.where(act, upd, h)
        h = np.where(n == 0, h ^ np.uint64(0xC0FFEE), h)
        return h.astype(np.uint64)
