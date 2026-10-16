/* ========================================================================= */
/*  ASGARD-5877 Differential Fuzzing - Protected Kernels (canonical copy)    */
/*                                                                           */
/*  This translation unit is the target under test. It is built two ways:    */
/*                                                                           */
/*    1. NATIVE GOLDEN : plain clang++ compile. The ASGARD marker macros     */
/*       expand to an inert `jmp` over an .ascii blob, so the function       */
/*       executes as ordinary native code.                                   */
/*    2. PROTECTED VM  : `random_visa project -d proj_src --cff --mba`       */
/*       lifts the marked region to VM bytecode behind a C trampoline.       */
/*                                                                           */
/*  Writing rules for the kernels (important - they keep the comparison     */
/*  meaningful and free of C++ undefined behaviour that could make the       */
/*  golden side miscompile independently of the VM):                        */
/*                                                                           */
/*    * shifts: unsigned only, counts pre-masked to 0..63                    */
/*    * rotations: (x << s) | (x >> ((64 - s) & 63))  -- no shift-by-64      */
/*    * division/modulo: unsigned only, divisor forced non-zero via `| 1`   */
/*    * signed values are widened and reinterpreted as unsigned before any   */
/*      wrap-around arithmetic (C++20 two's-complement semantics)            */
/*    * no float expressions that could FMA-contract; multiplies and adds    */
/*      live in separate statements so native -O2/-O3 and the lifted x86     */
/*      baseline (separate mulsd/addsd) round identically                    */
/*    * the double -> int64_t cast below is UB in the C++ abstract machine   */
/*      for out-of-range values but is *the* cvttsd2si parity test we want:  */
/*      both sides compile/lift to cvttsd2si and must agree (0x8000...0 on   */
/*      overflow/NaN). NaN/Inf inputs are filtered by the harness unless     */
/*      ASG_FUZZ_ALLOW_NAN=1 is set.                                         */
/* ========================================================================= */
#include "asgard_obf.h"
#include "../fuzz_types.h"

#include <stdint.h>

/* ------------------------------------------------------------------------- */
/* Kernel 1: arithmetic/state-machine stress (ULTRA virtualization)          */
/* Exercises: branch, switch, wide int add/sub/mul, xor/and/or/not,          */
/* variable rotate, unsigned div/mod, arithmetic shift, double mul/add/cmp,  */
/* cvttsd2si, cvtsd2ss, 4-iteration..15-iteration data-dependent loop.       */
/* ------------------------------------------------------------------------- */
extern "C" __attribute__((noinline)) uint64_t asgard_fuzz_compute(const TestPayload& p) {
    uint64_t res = 0;

    ASGARD_BEGIN_ULTRA("FuzzCompute");

    if ((p.flags & 1u) == 0u) {
        /* Early-exit path still mixes real inputs (no constants to fold). */
        res = (p.a ^ 0x5877ULL) + (uint64_t)(int64_t)p.b;
    } else {
        /* --- wide integer mixing: add / mul / xor / shifts ---------------- */
        uint64_t x = p.a + (uint64_t)(int64_t)p.b;
        x = (x * 0x9E3779B97F4A7C15ULL) ^ ((uint64_t)p.c + 0x1337ULL);
        x ^= x >> 29;
        x *= 0xBF58476D1CE4E5B9ULL;
        x ^= x >> 32;

        /* Variable rotation via masked counts (no shift-by-64 UB). */
        uint32_t s = p.c & 63u;
        uint64_t rot = (x << s) | (x >> ((64u - s) & 63u));
        x ^= rot;

        /* Unsigned div / mod, divisor forced non-zero. */
        uint32_t udv = p.c | 1u;
        x ^= p.a / udv;
        x = x - (p.a % udv);

        /* Signed widening + arithmetic shift (defined in C++20). */
        uint64_t su = (uint64_t)(int64_t)p.b;
        x = (x + su) ^ (su >> 3);

        /* --- floating point path ------------------------------------------ */
        double q = p.d * p.e;   /* separate statements: never FMA-contracted */
        double q2 = q + p.d;
        int64_t qi = (int64_t)q2;              /* cvttsd2si parity          */
        x ^= (uint64_t)qi;

        if (q2 > 1.0e12) {
            x ^= 0xDEADBEEFULL;
        } else if (q2 < -1.0e12) {
            x ^= 0xCAFEBABEULL;
        } else if (q2 == 0.0) {
            x ^= 0xFFFFULL;
        }

        /* double -> float rounding (cvtsd2ss) observed via bit pattern. */
        float fq = (float)(p.e + 1.0);
        if (fq < 0.0f) fq = -fq;
        uint32_t fbits = 0;
        __builtin_memcpy(&fbits, &fq, sizeof fbits);
        x ^= (uint64_t)fbits << 1;

        /* --- control flow: switch + data-dependent loop -------------------- */
        switch (p.flags & 7u) {
            case 1: x += 0x1111111111111111ULL; break;
            case 3: x -= 0x2222222222222222ULL; break;
            case 5: x ^= 0x4444444444444444ULL; break;
            case 7: x = ~x;                       break;
            default: x = (x & 0x0F0F0F0F0F0F0F0FULL) | (x & 0xF0F0F0F0F0F0F0F0ULL); break;
        }

        uint64_t acc = 0x243F6A8885A308D3ULL;
        uint32_t iters = (p.c & 15u) + 4u;
        for (uint32_t i = 0; i < iters; ++i) {
            acc = (acc ^ (x + i)) * 0x100000001B3ULL;
            if ((acc & 1ULL) == 0ULL) {
                acc ^= 0x9E3779B9ULL;
            } else {
                acc += (uint64_t)i << 8;
            }
        }
        x ^= acc;

        res = x;
    }

    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------------- */
/* Kernel 2: streaming hash mix over a caller buffer (VIRTUALIZE)            */
/* Exercises: pointer loads from memory outside the marked frame, loop       */
/* back-edges, in-loop data-dependent branch (flattening stress).            */
/* ------------------------------------------------------------------------- */
extern "C" __attribute__((noinline)) uint64_t asgard_fuzz_mix(uint64_t seed, const uint8_t* data, size_t n) {
    uint64_t h = seed;

    ASGARD_BEGIN_VIRTUALIZE("FuzzMix");

    for (size_t i = 0; i < n; ++i) {
        h ^= (uint64_t)data[i];
        h *= 0x100000001B3ULL;
        h ^= h >> 31;
        if ((h & 1ULL) == 0ULL) {
            h += 0x9E3779B97F4A7C15ULL;
        } else {
            h -= 0x5877ULL;
        }
    }
    if (n == 0) {
        h ^= 0xC0FFEEULL;
    }

    ASGARD_END();
    return h;
}
