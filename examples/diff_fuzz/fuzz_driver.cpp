/* ========================================================================= */
/*  ASGARD-5877 Differential Fuzzing - libFuzzer Driver                      */
/*                                                                           */
/*  One process, one struct layout, two implementations:                     */
/*                                                                           */
/*    asgard_fuzz*_native : compiled from proj_src/compute_core.cpp with     */
/*                          plain clang++ (markers are inert no-ops)         */
/*    asgard_fuzz*        : compiled from the project-mode virtualized TU    */
/*                          (.asgard_build/compute_core_virtualized.cpp)     */
/*                          - macro-obf + CFF + MBA + VM bytecode            */
/*                                                                           */
/*  libFuzzer mutates raw bytes with coverage feedback, so it finds the      */
/*  boundary inputs automatically: shift counts 0/31/32/63, INT32_MIN,       */
/*  subnormals, +-0.0, cvttsd2si saturation, loop trip-count edges.          */
/*  Any divergence prints a full input dump and traps, so libFuzzer saves    */
/*  the exact crashing bytes into ./artifacts/ and can minimize them         */
/*  (-minimize_crash=1).                                                     */
/*                                                                           */
/*  Layout per input: [TestPayload (40 bytes)][blob 1..64 bytes]             */
/* ========================================================================= */
#include "fuzz_types.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>

/* Native golden kernels (renamed at compile time via -D in run_libfuzzer.sh). */
extern "C" uint64_t asgard_fuzz_compute_native(const TestPayload& p);
extern "C" uint64_t asgard_fuzz_mix_native(uint64_t seed, const uint8_t* data, size_t n);

/* ASGARD-protected VM trampolines (from the virtualized translation unit).   */
extern "C" uint64_t asgard_fuzz_compute(const TestPayload& p);
extern "C" uint64_t asgard_fuzz_mix(uint64_t seed, const uint8_t* data, size_t n);

static void dump_payload(const TestPayload& p) {
    uint64_t dbits = 0, ebits = 0;
    memcpy(&dbits, &p.d, sizeof dbits);
    memcpy(&ebits, &p.e, sizeof ebits);
    fprintf(stderr,
            "    a=0x%016llx (%llu)\n"
            "    b=%d (0x%x)\n"
            "    c=0x%x (%u)\n"
            "    d=%.17g (bits 0x%016llx)\n"
            "    e=%.17g (bits 0x%016llx)\n"
            "    flags=0x%02x\n",
            (unsigned long long)p.a, (unsigned long long)p.a,
            p.b, (unsigned)p.b,
            (unsigned)p.c, (unsigned)p.c,
            p.d, (unsigned long long)dbits,
            p.e, (unsigned long long)ebits,
            (unsigned)p.flags);
}

static void report_divergence(const char* fn, const TestPayload* p,
                              uint64_t seed, const uint8_t* data, size_t n,
                              uint64_t golden, uint64_t vm) {
    fprintf(stderr, "\n[DIVERGENCE FOUND] %s\n", fn);
    if (p != nullptr) dump_payload(*p);
    if (data != nullptr) {
        fprintf(stderr, "    mix: seed=0x%016llx n=%zu\n",
                (unsigned long long)seed, n);
    }
    fprintf(stderr, "    Golden Reference: 0x%016llx (%llu)\n",
            (unsigned long long)golden, (unsigned long long)golden);
    fprintf(stderr, "    Protected VM:     0x%016llx (%llu)\n",
            (unsigned long long)vm, (unsigned long long)vm);
    fprintf(stderr, "    XOR Diff Mask:    0x%016llx\n",
            (unsigned long long)(golden ^ vm));
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
    if (size < ASG_TEST_PAYLOAD_SIZE + 1) return 0;

    /* Non-finite doubles are skipped by default: static_cast<int64_t> on NaN
     * is the one place where the C++ abstract machine leaves the mapping to
     * the compiler. Set ASG_FUZZ_ALLOW_NAN=1 to attack cvttsd2si parity too. */
    static const bool allow_nonfinite = getenv("ASG_FUZZ_ALLOW_NAN") != nullptr;

    TestPayload p;
    memset(&p, 0, sizeof p);                 /* deterministic padding bytes  */
    memcpy(&p, data, sizeof p);

    if (!allow_nonfinite && (!std::isfinite(p.d) || !std::isfinite(p.e))) return 0;

    const uint8_t* blob = data + sizeof p;
    size_t n = size - sizeof p;
    if (n > 64) n = 64;

    int bad = 0;

    uint64_t g1 = asgard_fuzz_compute_native(p);
    uint64_t v1 = asgard_fuzz_compute(p);
    if (g1 != v1) {
        report_divergence("asgard_fuzz_compute", &p, 0, nullptr, 0, g1, v1);
        bad = 1;
    }

    uint64_t g2 = asgard_fuzz_mix_native(p.a, blob, n);
    uint64_t v2 = asgard_fuzz_mix(p.a, blob, n);
    if (g2 != v2) {
        report_divergence("asgard_fuzz_mix", nullptr, p.a, blob, n, g2, v2);
        bad = 1;
    }

    if (bad) __builtin_trap();   /* libFuzzer persists the exact input bytes */
    return 0;
}
