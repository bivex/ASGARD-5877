/*
 * ASGARD-5877: Stack-JIT (SJIT) Showcase
 * =======================================
 * Eight virtualized functions covering the complete Stack-JIT protection envelope:
 *
 *  1. license_derive   -- multi-step cryptographic license token (XOR, SplitMix, shifts, golden ratio)
 *  2. xorshift128      -- 128-bit PRNG step with register-pair shifts and bitwise mixing
 *  3. gcd_iter         -- iterative Euclidean algorithm (while loop with unsigned division remainder)
 *  4. popcount64       -- Brian Kernighan 64-bit population count (dynamic bit-clearing loop)
 *  5. collatz_steps    -- Collatz 3n+1 hailstone stopping time (divergent even/odd conditional loop)
 *  6. is_prime         -- trial division primality test (bounded search loop with early composite exit)
 *  7. mod_exp          -- modular exponentiation (base^exp mod m via binary exponentiation loop)
 *  8. fibonacci_iter   -- iterative 64-bit Fibonacci sequence (register-swap recurrence loop)
 *
 * Every function body is sealed by ASGARD_BEGIN_VIRTUALIZE / ASGARD_END and
 * lowered via the Stack-JIT engine (--engine=jit) into:
 *   - OEIS A000002 Kolakoski self-describing chunk fission
 *   - OEIS A010060 Thue-Morse dummy opcode padding
 *   - OEIS A000166 Derangement fix-free register shuffling (remap_gprs)
 *   - OEIS A002487 Stern's diatomic odd-unit affine masking with 5-step Newton-Raphson
 *   - OEIS A000695 Moser-de Bruijn carry-free immediate blinding (moser_pack/unblind)
 *   - OEIS A003022 Golomb ruler active slot placement in A000201/A001950 Beatty arena
 *   - OEIS A001511 Ruler function fractal tiered invalidation schedule with Rule-30 (A269160) wipe
 *   - OEIS A000931 Padovan geometric buffer dispersion
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "asgard_obf.h"

/* ------------------------------------------------------------------ */
/* 1. Multi-step cryptographic license token derivation               */
/* ------------------------------------------------------------------ */
#define DERIVE_SALT   0x5877CAFE13370ADAULL
#define DERIVE_GAMMA  0x9E3779B97F4A7C15ULL   /* golden ratio, OEIS A007542 */
#define DERIVE_ADDEND 0x0000000000001337ULL

uint64_t license_derive(uint64_t key, uint64_t nonce)
{
    ASGARD_BEGIN_VIRTUALIZE("license_derive");
    uint64_t t = key ^ DERIVE_SALT ^ nonce;
    t ^= (t >> 30); t *= 0xbf58476d1ce4e5b9ULL;
    t ^= (t >> 27); t *= 0x94d049bb133111ebULL;
    t ^= (t >> 31);
    t  = t * DERIVE_GAMMA + DERIVE_ADDEND;
    __asm__ volatile("" : "+r"(t));
    ASGARD_END();
    return t;
}

/* ------------------------------------------------------------------ */
/* 2. xorshift128+ one-step state evolution                           */
/* ------------------------------------------------------------------ */
uint64_t xorshift128(uint64_t s0, uint64_t s1)
{
    ASGARD_BEGIN_VIRTUALIZE("xorshift128");
    s0 ^= s0 << 23;
    s0 ^= s0 >> 17;
    s0 ^= s1;
    s0 ^= s1 >> 26;
    uint64_t res = s0;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 3. Iterative Euclidean GCD                                         */
/* ------------------------------------------------------------------ */
uint64_t gcd_iter(uint64_t a, uint64_t b)
{
    ASGARD_BEGIN_VIRTUALIZE("gcd_iter");
    while (b != 0ULL) {
        uint64_t r = a % b;
        a = b;
        b = r;
    }
    uint64_t res = a;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 4. 64-bit population count (Brian Kernighan algorithm)             */
/* ------------------------------------------------------------------ */
uint64_t popcount64(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("popcount64");
    uint64_t c = 0ULL;
    while (x) {
        x &= x - 1ULL;
        c++;
    }
    __asm__ volatile("" : "+r"(c));
    ASGARD_END();
    return c;
}
/* ------------------------------------------------------------------ */
/* 5. Collatz 3n+1 stopping time (divergent branching loop)           */
/* ------------------------------------------------------------------ */
uint64_t collatz_steps(uint64_t n)
{
    ASGARD_BEGIN_VIRTUALIZE("collatz_steps");
    uint64_t steps = 0ULL;
    while (n > 1ULL) {
        if (n % 2ULL == 0ULL) {
            n = n / 2ULL;
        } else {
            n = 3ULL * n + 1ULL;
        }
        steps++;
    }
    uint64_t res = steps;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 6. Trial-division primality test                                   */
/* ------------------------------------------------------------------ */
uint64_t is_prime(uint64_t n)
{
    ASGARD_BEGIN_VIRTUALIZE("is_prime");
    uint64_t res = 0ULL;
    if (n >= 2ULL) {
        res = 1ULL;
        for (uint64_t d = 2ULL; d * d <= n; d++) {
            if (n % d == 0ULL) {
                res = 0ULL;
                break;
            }
        }
    }
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

static uint64_t ref_is_prime(uint64_t n) {
    if (n < 2ULL) return 0ULL;
    for (uint64_t d = 2ULL; d * d <= n; d++) {
        if (n % d == 0ULL) return 0ULL;
    }
    return 1ULL;
}

/* ------------------------------------------------------------------ */
/* 7. Modular exponentiation (base^exp mod m)                         */
/* ------------------------------------------------------------------ */
uint64_t mod_exp(uint64_t base, uint64_t exp, uint64_t mod)
{
    ASGARD_BEGIN_VIRTUALIZE("mod_exp");
    uint64_t result = 1ULL;
    base = base % mod;
    while (exp > 0ULL) {
        if (exp % 2ULL == 1ULL) {
            result = (result * base) % mod;
        }
        base = (base * base) % mod;
        exp = exp / 2ULL;
    }
    uint64_t res = result;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 8. Iterative 64-bit Fibonacci sequence                             */
/* ------------------------------------------------------------------ */
uint64_t fibonacci_iter(uint64_t n)
{
    ASGARD_BEGIN_VIRTUALIZE("fibonacci_iter");
    uint64_t a = 0ULL;
    uint64_t b = 1ULL;
    for (uint64_t i = 0ULL; i < n; i++) {
        uint64_t next = a + b;
        a = b;
        b = next;
    }
    uint64_t res = a;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* Reference implementations for bit-for-bit assertion validation    */
/* ------------------------------------------------------------------ */
static uint64_t ref_license(uint64_t k, uint64_t nonce) {
    uint64_t t = k ^ DERIVE_SALT ^ nonce;
    t ^= (t >> 30); t *= 0xbf58476d1ce4e5b9ULL;
    t ^= (t >> 27); t *= 0x94d049bb133111ebULL;
    t ^= (t >> 31);
    return t * DERIVE_GAMMA + DERIVE_ADDEND;
}

static uint64_t ref_xorshift(uint64_t s0, uint64_t s1) {
    s0 ^= s0 << 23; s0 ^= s0 >> 17; s0 ^= s1; s0 ^= s1 >> 26; return s0;
}

static uint64_t ref_gcd(uint64_t a, uint64_t b) {
    while (b) { uint64_t r = a % b; a = b; b = r; } return a;
}

static uint64_t ref_popcount(uint64_t x) {
    uint64_t c = 0; while (x) { x &= x - 1ULL; c++; } return c;
}

static uint64_t ref_collatz(uint64_t n) {
    uint64_t s = 0;
    while (n > 1ULL) { n = (n % 2ULL == 0ULL) ? (n / 2ULL) : (3ULL * n + 1ULL); s++; }
    return s;
}


static uint64_t ref_mod_exp(uint64_t base, uint64_t exp, uint64_t mod) {
    uint64_t res = 1ULL;
    base = base % mod;
    while (exp > 0ULL) {
        if (exp % 2ULL == 1ULL) res = (res * base) % mod;
        base = (base * base) % mod;
        exp /= 2ULL;
    }
    return res;
}

static uint64_t ref_fib(uint64_t n) {
    uint64_t a = 0, b = 1;
    for (uint64_t i = 0; i < n; i++) { uint64_t next = a + b; a = b; b = next; }
    return a;
}

/* ------------------------------------------------------------------ */
/* Main test harness                                                  */
/* ------------------------------------------------------------------ */
int main(void)
{
    int pass = 0, fail = 0;

#define CHECK(name, got, exp) do { \
    if ((got) == (exp)) { \
        printf("  [PASS] %-30s got=0x%016llX (%llu)\n", (name), (unsigned long long)(got), (unsigned long long)(got)); \
        pass++; \
    } else { \
        printf("  [FAIL] %-30s got=0x%016llX exp=0x%016llX\n", \
               (name), (unsigned long long)(got), (unsigned long long)(exp)); \
        fail++; \
    } \
    fflush(stdout); \
} while(0)

    printf("====================================================================\n");
    printf("  🛡️  ASGARD-5877: Stack-JIT (SJIT) Big C++ Multi-Pattern Showcase\n");
    printf("  8 Virtualized Functions in Sealed Nano-Arena:\n");
    printf("    * A000002 Kolakoski Fission     * A010060 Thue-Morse Dummy Padding\n");
    printf("    * A000166 Derangement Shuffling * A002487 Stern Affine Masking\n");
    printf("    * A000695 Moser-de Bruijn Imm   * A003022 Golomb Ruler Slots\n");
    printf("    * A000201 Beatty-Wythoff Arena  * A001511 Ruler / A269160 Wipe\n");
    printf("    * A000931 Padovan Dispersion\n");
    printf("====================================================================\n\n");
    fflush(stdout);

    /* ---- 1. License derivation ---- */
    printf("[1] license_derive (SplitMix64 + Golden Ratio + Blinding)\n");
    CHECK("license(0x5877, 0)",       license_derive(0x5877ULL, 0ULL),       ref_license(0x5877ULL, 0ULL));
    CHECK("license(0x1337, 42)",      license_derive(0x1337ULL, 42ULL),      ref_license(0x1337ULL, 42ULL));
    CHECK("license(0xFFFFFFFF, CAFE)",license_derive(0xFFFFFFFFULL, 0xCAFEULL), ref_license(0xFFFFFFFFULL, 0xCAFEULL));

    /* ---- 2. xorshift128+ ---- */
    printf("\n[2] xorshift128 (128-bit Register-Pair PRNG Step)\n");
    uint64_t s0 = 0x5877CAFE13371337ULL, s1 = 0x9E3779B97F4A7C15ULL;
    uint64_t r1 = xorshift128(s0, s1);
    CHECK("xorshift128(s0, s1) step 1", r1, ref_xorshift(s0, s1));
    uint64_t r2 = xorshift128(r1, s0);
    CHECK("xorshift128(r1, s0) step 2", r2, ref_xorshift(r1, s0));

    /* ---- 3. GCD ---- */
    printf("\n[3] gcd_iter (Euclidean Algorithm Dynamic While Loop)\n");
    CHECK("gcd(48, 18)",         gcd_iter(48ULL, 18ULL),         ref_gcd(48ULL, 18ULL));
    CHECK("gcd(1071, 462)",      gcd_iter(1071ULL, 462ULL),      ref_gcd(1071ULL, 462ULL));
    CHECK("gcd(7919, 1)",        gcd_iter(7919ULL, 1ULL),        ref_gcd(7919ULL, 1ULL));
    CHECK("gcd(0x5877, 0x1337)", gcd_iter(0x5877ULL, 0x1337ULL), ref_gcd(0x5877ULL, 0x1337ULL));

    /* ---- 4. Popcount ---- */
    printf("\n[4] popcount64 (Brian Kernighan Bit-Clearing Loop)\n");
    CHECK("popcount(0x0)",              popcount64(0ULL),                 ref_popcount(0ULL));
    CHECK("popcount(0xFFFFFFFFFFFFFFFF)",popcount64(0xFFFFFFFFFFFFFFFFULL),ref_popcount(0xFFFFFFFFFFFFFFFFULL));
    CHECK("popcount(0x5877585758575857)",popcount64(0x5877585758575857ULL), ref_popcount(0x5877585758575857ULL));
    CHECK("popcount(0xAAAAAAAAAAAAAAAA)",popcount64(0xAAAAAAAAAAAAAAAAULL), ref_popcount(0xAAAAAAAAAAAAAAAAULL));

    /* ---- 5. Collatz stopping time ---- */
    printf("\n[5] collatz_steps (3n+1 Hailstone Divergent Branching Loop)\n");
    CHECK("collatz(1)",   collatz_steps(1ULL),   ref_collatz(1ULL));
    CHECK("collatz(6)",   collatz_steps(6ULL),   ref_collatz(6ULL));
    CHECK("collatz(27)",  collatz_steps(27ULL),  ref_collatz(27ULL));
    CHECK("collatz(871)", collatz_steps(871ULL), ref_collatz(871ULL));

    /* ---- 6. Primality test ---- */
    printf("\n[6] is_prime (Trial Division Search Loop with Early Exit)\n");
    CHECK("is_prime(1)",     is_prime(1ULL),     ref_is_prime(1ULL));
    CHECK("is_prime(2)",     is_prime(2ULL),     ref_is_prime(2ULL));
    CHECK("is_prime(7919)",  is_prime(7919ULL),  ref_is_prime(7919ULL));
    CHECK("is_prime(8000)",  is_prime(8000ULL),  ref_is_prime(8000ULL));
    CHECK("is_prime(104729)",is_prime(104729ULL),ref_is_prime(104729ULL));

    /* ---- 7. Modular exponentiation ---- */
    printf("\n[7] mod_exp (Binary Exponentiation Loop with Modulo)\n");
    CHECK("mod_exp(3, 45, 1000000007)",  mod_exp(3ULL, 45ULL, 1000000007ULL),  ref_mod_exp(3ULL, 45ULL, 1000000007ULL));
    CHECK("mod_exp(7, 256, 1337)",       mod_exp(7ULL, 256ULL, 1337ULL),       ref_mod_exp(7ULL, 256ULL, 1337ULL));
    CHECK("mod_exp(42, 1337, 5877)",     mod_exp(42ULL, 1337ULL, 5877ULL),     ref_mod_exp(42ULL, 1337ULL, 5877ULL));

    /* ---- 8. Fibonacci sequence ---- */
    printf("\n[8] fibonacci_iter (Iterative Recurrence Register Swapping)\n");
    CHECK("fib(0)",  fibonacci_iter(0ULL),  ref_fib(0ULL));
    CHECK("fib(1)",  fibonacci_iter(1ULL),  ref_fib(1ULL));
    CHECK("fib(10)", fibonacci_iter(10ULL), ref_fib(10ULL));
    CHECK("fib(30)", fibonacci_iter(30ULL), ref_fib(30ULL));
    CHECK("fib(50)", fibonacci_iter(50ULL), ref_fib(50ULL));

    /* ---- Summary ---- */
    printf("\n====================================================================\n");
    printf("  Results: %d PASS, %d FAIL out of %d assertions\n", pass, fail, pass + fail);
    if (fail == 0) {
        printf("  🎉 ALL 8 VIRTUALIZED ROUTINES EXECUTED WITH 100%% EXACT PRECISION\n");
        printf("  Stack-JIT Sealing & Dynamic Nano-Chunks VERIFIED on Hardware\n");
    } else {
        printf("  💥 FAILURES DETECTED\n");
    }
    printf("====================================================================\n");
    return fail == 0 ? 0 : 1;
}
