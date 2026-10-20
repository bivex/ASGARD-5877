#include <cstdio>
#include <cstdint>

// -----------------------------------------------------------------------------
// ASGARD-5877 ARM64 Instruction Expansion Demonstration
// Each step exercises newly implemented native ARM64 instructions:
// 1. MOVN
// 2. FCVTAS, FCVTMS, FCVTNS, FCVTPS, FCVTAU
// 3. FCCMP
// 4. INS, UMOV, SMOV
// 5. SQADD, SQSUB, SQRDMULH
// 6. FJCVTZS
// -----------------------------------------------------------------------------

struct DemoResults {
    uint64_t m1;
    uint32_t m2;
    int64_t as_val, ms_val, ns_val, ps_val;
    uint64_t au_val;
    uint32_t cond_lt, cond_eq;
    uint32_t u_extracted;
    int64_t s_extracted;
    uint32_t sat_add, sat_sub, sat_mul;
    uint32_t js_val, js_exact;
};

extern "C" void execute_new_arm64_instructions(DemoResults* out) {
    // 1. MOVN (inverted immediate move)
    uint64_t m1;
    uint32_t m2;
    __asm__ volatile (
        "movn %0, #0\n"           // -1LL (0xFFFFFFFFFFFFFFFF)
        "movn %w1, #0x1f\n"       // ~0x1Fu (0xFFFFFFE0)
        : "=r"(m1), "=r"(m2)
    );
    out->m1 = m1;
    out->m2 = m2;

    // 2. FCVT with Rounding Modes (Away, Floor, Nearest-Even, Ceil)
    double v_pos = 1.5;
    double v_neg = -1.5;
    int64_t as_val, ms_val, ns_val, ps_val;
    uint64_t au_val;
    __asm__ volatile (
        "fcvtas %0, %d4\n"        // Round away from zero: 1.5 -> 2
        "fcvtms %1, %d4\n"        // Floor: 1.5 -> 1
        "fcvtns %2, %d4\n"        // Nearest even: 1.5 -> 2
        "fcvtps %3, %d4\n"        // Ceil: 1.5 -> 2
        : "=r"(as_val), "=r"(ms_val), "=r"(ns_val), "=r"(ps_val)
        : "w"(v_pos)
    );
    __asm__ volatile (
        "fcvtau %0, %d1\n"        // Unsigned away from zero: -1.5 -> 0 (saturates)
        : "=r"(au_val)
        : "w"(v_neg)
    );
    out->as_val = as_val;
    out->ms_val = ms_val;
    out->ns_val = ns_val;
    out->ps_val = ps_val;
    out->au_val = au_val;

    // 3. FCCMP: Floating Conditional Compare (with NZCV fallback)
    uint32_t cond_lt, cond_eq;
    __asm__ volatile (
        "mov x0, #1\n"
        "cmp x0, #1\n"            // EQ is true
        "fmov d0, #1.0\n"
        "fmov d1, #2.0\n"
        "fccmp d0, d1, #4, eq\n"  // True: compares 1.0 < 2.0 -> LT
        "cset %w0, lt\n"          // 1
        "cmp x0, #2\n"            // EQ is false
        "fccmp d0, d1, #4, eq\n"  // False: sets NZCV directly to 4 (Z=1, so EQ)
        "cset %w1, eq\n"          // 1
        : "=r"(cond_lt), "=r"(cond_eq)
        :
        : "x0", "d0", "d1", "cc"
    );
    out->cond_lt = cond_lt;
    out->cond_eq = cond_eq;

    // 4. NEON element insertion and extraction (ins, umov, smov):
    uint32_t u_extracted;
    int64_t s_extracted;
    __asm__ volatile (
        "mov w0, #100\n"
        "ins v0.s[0], w0\n"       // ins from GPR -> v0.s[0] = 100
        "ins v1.s[2], v0.s[0]\n"  // ins vector-to-vector -> v1.s[2] = 100
        "umov %w0, v1.s[2]\n"     // umov unsigned -> 100
        "mov w1, #0xFB\n"         // -5 signed byte
        "ins v2.b[3], w1\n"       // ins byte
        "smov %1, v2.b[3]\n"      // smov signed -> -5LL
        : "=r"(u_extracted), "=r"(s_extracted)
        :
        : "x0", "w1", "v0", "v1", "v2"
    );
    out->u_extracted = u_extracted;
    out->s_extracted = s_extracted;

    // 5. Saturating NEON arithmetic (sqadd, sqsub, sqrdmulh):
    uint32_t sat_add, sat_sub, sat_mul;
    __asm__ volatile (
        "mov x0, #0x7FFFFFFF\n"
        "dup v3.2s, w0\n"
        "mov x1, #100\n"
        "dup v4.2s, w1\n"
        "sqadd v5.2s, v3.2s, v4.2s\n"    // Saturates to 0x7FFFFFFF
        "umov %w0, v5.s[0]\n"
        "mov x0, #0x80000000\n"
        "dup v6.2s, w0\n"
        "sqsub v7.2s, v6.2s, v4.2s\n"    // Saturates to 0x80000000
        "umov %w1, v7.s[0]\n"
        "mov x0, #0x4000\n"              // 16384 (0.5 in Q15)
        "dup v8.4h, w0\n"
        "sqrdmulh v9.4h, v8.4h, v8.4h\n" // 8192 (0.25 in Q15)
        "umov %w2, v9.h[0]\n"
        : "=r"(sat_add), "=r"(sat_sub), "=r"(sat_mul)
        :
        : "x0", "x1", "v3", "v4", "v5", "v6", "v7", "v8", "v9"
    );
    out->sat_add = sat_add;
    out->sat_sub = sat_sub;
    out->sat_mul = sat_mul;

    // 6. JavaScript ToInt32 Conversion (fjcvtzs):
    uint32_t js_val, js_exact;
    double d42 = 42.0;
    __asm__ volatile (
        "fjcvtzs %w0, %d2\n"             // 42.0 -> 42, ZF=1 (exact)
        "cset %w1, eq\n"                 // 1
        : "=r"(js_val), "=r"(js_exact)
        : "w"(d42)
        : "cc"
    );
    out->js_val = js_val;
    out->js_exact = js_exact;
}

int main() {
    std::printf("======================================================================\n");
    std::printf("       ASGARD-5877 ARM64 NEW INSTRUCTIONS STEP-BY-STEP AUDIT         \n");
    std::printf("======================================================================\n\n");

    DemoResults res = {};
    execute_new_arm64_instructions(&res);

    bool all_ok = true;

    // Step 1: MOVN
    std::printf("[STEP 1] MOVN (Move with NOT):\n");
    std::printf("         movn x0, #0      -> 0x%016llX (expected: 0xFFFFFFFFFFFFFFFF)\n", (unsigned long long)res.m1);
    std::printf("         movn w1, #0x1f   -> 0x%08X         (expected: 0xFFFFFFE0)\n", res.m2);
    bool step1_ok = (res.m1 == 0xFFFFFFFFFFFFFFFFULL && res.m2 == 0xFFFFFFE0U);
    std::printf("         Status: %s\n\n", step1_ok ? "[PASS] OK" : "[FAIL] MISMATCH");
    all_ok &= step1_ok;

    // Step 2: FCVT with Rounding
    std::printf("[STEP 2] FCVT Float-to-Int with Rounding Modes (input = 1.5):\n");
    std::printf("         fcvtas (Away)    -> %lld (expected: 2)\n", (long long)res.as_val);
    std::printf("         fcvtms (Floor)   -> %lld (expected: 1)\n", (long long)res.ms_val);
    std::printf("         fcvtns (Nearest) -> %lld (expected: 2)\n", (long long)res.ns_val);
    std::printf("         fcvtps (Ceil)    -> %lld (expected: 2)\n", (long long)res.ps_val);
    std::printf("         fcvtau (-1.5)    -> %llu (expected: 0, saturates unsigned)\n", (unsigned long long)res.au_val);
    bool step2_ok = (res.as_val == 2 && res.ms_val == 1 && res.ns_val == 2 && res.ps_val == 2 && res.au_val == 0);
    std::printf("         Status: %s\n\n", step2_ok ? "[PASS] OK" : "[FAIL] MISMATCH");
    all_ok &= step2_ok;

    // Step 3: FCCMP
    std::printf("[STEP 3] FCCMP (Floating Conditional Compare):\n");
    std::printf("         True cond (1.0 < 2.0)  -> LT flag set: %u (expected: 1)\n", res.cond_lt);
    std::printf("         False cond fallback    -> EQ flag set: %u (expected: 1, via #4 nzcv)\n", res.cond_eq);
    bool step3_ok = (res.cond_lt == 1 && res.cond_eq == 1);
    std::printf("         Status: %s\n\n", step3_ok ? "[PASS] OK" : "[FAIL] MISMATCH");
    all_ok &= step3_ok;

    // Step 4: INS, UMOV, SMOV
    std::printf("[STEP 4] NEON Scalar <-> Vector Lane Transfer:\n");
    std::printf("         ins + umov (100)      -> %u   (expected: 100)\n", res.u_extracted);
    std::printf("         ins + smov (-5 byte)  -> %lld    (expected: -5, sign-extended)\n", (long long)res.s_extracted);
    bool step4_ok = (res.u_extracted == 100 && res.s_extracted == -5);
    std::printf("         Status: %s\n\n", step4_ok ? "[PASS] OK" : "[FAIL] MISMATCH");
    all_ok &= step4_ok;

    // Step 5: Saturating NEON
    std::printf("[STEP 5] NEON Saturating Arithmetic (DSP):\n");
    std::printf("         sqadd (0x7FFFFFFF + 100) -> 0x%08X (expected: 0x7FFFFFFF)\n", res.sat_add);
    std::printf("         sqsub (0x80000000 - 100) -> 0x%08X (expected: 0x80000000)\n", res.sat_sub);
    std::printf("         sqrdmulh (0.5 * 0.5)     -> 0x%04X     (expected: 0x2000 = 0.25 Q15)\n", res.sat_mul);
    bool step5_ok = (res.sat_add == 0x7FFFFFFFU && res.sat_sub == 0x80000000U && res.sat_mul == 0x2000U);
    std::printf("         Status: %s\n\n", step5_ok ? "[PASS] OK" : "[FAIL] MISMATCH");
    all_ok &= step5_ok;

    // Step 6: FJCVTZS
    std::printf("[STEP 6] FJCVTZS (JavaScript ToInt32 Conversion):\n");
    std::printf("         fjcvtzs 42.0 -> value: %u, exact (ZF): %u (expected: 42, 1)\n", res.js_val, res.js_exact);
    bool step6_ok = (res.js_val == 42 && res.js_exact == 1);
    std::printf("         Status: %s\n\n", step6_ok ? "[PASS] OK" : "[FAIL] MISMATCH");
    all_ok &= step6_ok;

    std::printf("======================================================================\n");
    if (all_ok) {
        std::printf("  [+] ALL ARM64 NEW INSTRUCTIONS VERIFIED AND PASSED SUCCESSFULLY!    \n");
    } else {
        std::printf("  [-] ONE OR MORE VERIFICATION STEPS FAILED!                         \n");
    }
    std::printf("======================================================================\n");

    return all_ok ? 0 : 1;
}
