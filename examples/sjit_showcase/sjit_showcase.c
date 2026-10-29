/*
 * ASGARD-5877: Stack-JIT (SJIT) Big C++ Multi-Pattern Showcase & Bug-Stress Suite
 * ===============================================================================
 * Fourteen virtualized functions covering the complete Stack-JIT protection envelope
 * and stress-testing edge cases (bgs = bugs / edge cases & big patterns):
 *
 *   1. license_derive     -- multi-step cryptographic license token (SplitMix, shifts, golden ratio)
 *   2. xorshift128        -- 128-bit PRNG step with register-pair shifts and bitwise mixing
 *   3. gcd_iter           -- iterative Euclidean algorithm (while loop with unsigned division remainder)
 *   4. popcount64         -- Brian Kernighan 64-bit population count (dynamic bit-clearing loop)
 *   5. collatz_steps      -- Collatz 3n+1 hailstone stopping time (divergent even/odd conditional loop)
 *   6. is_prime           -- trial division primality test (bounded search loop with early break exit)
 *   7. mod_exp            -- modular exponentiation (base^exp mod m via binary exponentiation loop)
 *   8. fibonacci_iter     -- iterative 64-bit Fibonacci sequence (register-swap recurrence loop)
 *   9. crc32_bitwise      -- IEEE 802.3 bitwise CRC-32 calculation (nested bit loops, poly 0xEDB88320)
 *  10. int_sqrt           -- integer square root via binary search convergence (large/zero boundary tests)
 *  11. fmix64             -- MurmurHash3 64-bit avalanche mixer (cascading 64-bit multipliers and shifts)
 *  12. signed_clamp_scale -- signed arithmetic and comparisons (testing negative numbers, LT, GT, GE, LE)
 *  13. state_machine_fsm  -- 4-state Mealy/Moore transition loop with feedback bit-extraction
 *  14. bit_reverse64      -- parallel 64-bit bit-reversal (divide-and-conquer binary bit permutation)
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
/* 9. IEEE 802.3 bitwise CRC-32                                       */
/* ------------------------------------------------------------------ */
uint64_t crc32_bitwise(uint64_t data)
{
    ASGARD_BEGIN_VIRTUALIZE("crc32_bitwise");
    uint32_t crc = 0xFFFFFFFFU;
    for (int i = 0; i < 8; i++) {
        uint8_t byte = (uint8_t)((data >> (i * 8)) & 0xFFU);
        crc ^= (uint32_t)byte;
        for (int b = 0; b < 8; b++) {
            if (crc & 1U) {
                crc = (crc >> 1) ^ 0xEDB88320U;
            } else {
                crc = crc >> 1;
            }
        }
    }
    uint64_t res = (uint64_t)(crc ^ 0xFFFFFFFFU);
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 10. Integer square root via binary search                          */
/* ------------------------------------------------------------------ */
uint64_t int_sqrt(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("int_sqrt");
    uint64_t res = x;
    if (x > 1ULL) {
        uint64_t lo = 1ULL;
        uint64_t hi = (x < 0x200000000ULL) ? x : 0x100000000ULL;
        uint64_t ans = 1ULL;
        while (lo <= hi) {
            uint64_t mid = lo + (hi - lo) / 2ULL;
            if (mid <= x / mid) {
                ans = mid;
                lo = mid + 1ULL;
            } else {
                hi = mid - 1ULL;
            }
        }
        res = ans;
    }
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 11. MurmurHash3 64-bit avalanche mixer (fmix64)                    */
/* ------------------------------------------------------------------ */
uint64_t fmix64(uint64_t k)
{
    ASGARD_BEGIN_VIRTUALIZE("fmix64");
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33;
    uint64_t res = k;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 12. Signed clamp and scale                                         */
/* ------------------------------------------------------------------ */
int64_t signed_clamp_scale(int64_t val, int64_t min_v, int64_t max_v, int64_t scale)
{
    ASGARD_BEGIN_VIRTUALIZE("signed_clamp_scale");
    int64_t clamped = val;
    if (clamped < min_v) {
        clamped = min_v;
    } else if (clamped > max_v) {
        clamped = max_v;
    }
    int64_t res = clamped * scale;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 13. Galois 64-bit LFSR (OEIS A011260 Primitive Polynomial)         */
/* ------------------------------------------------------------------ */
#define LFSR_POLY 0xD800000000000000ULL

uint64_t lfsr_galois64(uint64_t state, int steps)
{
    ASGARD_BEGIN_VIRTUALIZE("lfsr_galois64");
    for (int i = 0; i < steps; i++) {
        uint64_t lsb = state & 1ULL;
        state >>= 1;
        if (lsb) {
            state ^= LFSR_POLY;
        }
    }
    uint64_t res = state;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 14. SipHash 64-bit State Compression Quarter-Round                  */
/* ------------------------------------------------------------------ */
#define ROTL64(x, b) (((x) << (b)) | ((x) >> (64 - (b))))

uint64_t siphash_round(uint64_t v0, uint64_t v1, uint64_t v2, uint64_t v3)
{
    ASGARD_BEGIN_VIRTUALIZE("siphash_round");
    v0 += v1;
    v1 = ROTL64(v1, 13);
    v1 ^= v0;
    v0 = ROTL64(v0, 32);
    v2 += v3;
    v3 = ROTL64(v3, 16);
    v3 ^= v2;
    v0 += v3;
    v3 = ROTL64(v3, 21);
    v3 ^= v0;
    v2 += v1;
    v1 = ROTL64(v1, 17);
    v1 ^= v2;
    v2 = ROTL64(v2, 32);
    uint64_t res = v0 ^ v1 ^ v2 ^ v3;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 15. Hardware byte-swap (rev / bswap)                                */
/* ------------------------------------------------------------------ */
uint64_t byte_swap64(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("byte_swap64");
    uint64_t res = __builtin_bswap64(x);
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 16. Count leading zeros (clz / lzcnt)                               */
/* ------------------------------------------------------------------ */
uint64_t leading_zeros64(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("leading_zeros64");
    /* Guarded: __builtin_clzll(0) is UB, so keep the caller contract x != 0
       but clamp defensively before the intrinsic. */
    uint64_t n = (x == 0ULL) ? 64ULL : (uint64_t)__builtin_clzll(x);
    __asm__ volatile("" : "+r"(n));
    ASGARD_END();
    return n;
}

/* ------------------------------------------------------------------ */
/* 17. Count trailing zeros (rbit+clz / tzcnt)                         */
/* ------------------------------------------------------------------ */
uint64_t trailing_zeros64(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("trailing_zeros64");
    uint64_t n = (x == 0ULL) ? 64ULL : (uint64_t)__builtin_ctzll(x);
    __asm__ volatile("" : "+r"(n));
    ASGARD_END();
    return n;
}

/* ------------------------------------------------------------------ */
/* 18. Full 64-bit bit reversal (rbit)                                 */
/* ------------------------------------------------------------------ */
uint64_t reverse_bits64(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("reverse_bits64");
    uint64_t res = 0ULL;
    for (int i = 0; i < 64; i++) {
        res = (res << 1) | (x & 1ULL);
        x >>= 1;
    }
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

/* ------------------------------------------------------------------ */
/* 19. Hardware population count (cnt-chain / popcnt)                  */
/* ------------------------------------------------------------------ */
uint64_t hamming_weight64(uint64_t x)
{
    ASGARD_BEGIN_VIRTUALIZE("hamming_weight64");
    uint64_t n = (uint64_t)__builtin_popcountll(x);
    __asm__ volatile("" : "+r"(n));
    ASGARD_END();
    return n;
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

static uint64_t ref_is_prime(uint64_t n) {
    if (n < 2ULL) return 0ULL;
    for (uint64_t d = 2ULL; d * d <= n; d++) {
        if (n % d == 0ULL) return 0ULL;
    }
    return 1ULL;
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

static uint64_t ref_crc32(uint64_t data) {
    uint32_t crc = 0xFFFFFFFFU;
    for (int i = 0; i < 8; i++) {
        uint8_t byte = (uint8_t)((data >> (i * 8)) & 0xFFU);
        crc ^= (uint32_t)byte;
        for (int b = 0; b < 8; b++) {
            crc = (crc & 1U) ? ((crc >> 1) ^ 0xEDB88320U) : (crc >> 1);
        }
    }
    return (uint64_t)(crc ^ 0xFFFFFFFFU);
}

static uint64_t ref_int_sqrt(uint64_t x) {
    if (x <= 1ULL) return x;
    uint64_t lo = 1ULL, hi = (x < 0x200000000ULL) ? x : 0x100000000ULL, ans = 1ULL;
    while (lo <= hi) {
        uint64_t mid = lo + (hi - lo) / 2ULL;
        if (mid <= x / mid) { ans = mid; lo = mid + 1ULL; }
        else { hi = mid - 1ULL; }
    }
    return ans;
}

static uint64_t ref_fmix64(uint64_t k) {
    k ^= k >> 33; k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33; k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33; return k;
}

static int64_t ref_clamp_scale(int64_t v, int64_t mn, int64_t mx, int64_t sc) {
    if (v < mn) v = mn;
    else if (v > mx) v = mx;
    return v * sc;
}

static uint64_t ref_lfsr(uint64_t state, int steps) {
    for (int i = 0; i < steps; i++) {
        uint64_t lsb = state & 1ULL;
        state >>= 1;
        if (lsb) state ^= LFSR_POLY;
    }
    return state;
}

static uint64_t ref_siphash(uint64_t v0, uint64_t v1, uint64_t v2, uint64_t v3) {
    v0 += v1; v1 = ROTL64(v1, 13); v1 ^= v0; v0 = ROTL64(v0, 32);
    v2 += v3; v3 = ROTL64(v3, 16); v3 ^= v2;
    v0 += v3; v3 = ROTL64(v3, 21); v3 ^= v0;
    v2 += v1; v1 = ROTL64(v1, 17); v1 ^= v2; v2 = ROTL64(v2, 32);
    return v0 ^ v1 ^ v2 ^ v3;
}

static uint64_t ref_bswap(uint64_t x) { return __builtin_bswap64(x); }

static uint64_t ref_clz(uint64_t x) {
    if (x == 0ULL) return 64ULL;
    uint64_t c = 0;
    while ((x & 0x8000000000000000ULL) == 0) { x <<= 1; c++; }
    return c;
}

static uint64_t ref_ctz(uint64_t x) {
    if (x == 0ULL) return 64ULL;
    uint64_t c = 0;
    while ((x & 1ULL) == 0) { x >>= 1; c++; }
    return c;
}

static uint64_t ref_rbit(uint64_t x) {
    uint64_t r = 0;
    for (int i = 0; i < 64; i++) { r = (r << 1) | (x & 1ULL); x >>= 1; }
    return r;
}

static uint64_t ref_popcnt(uint64_t x) {
    uint64_t c = 0;
    while (x) { x &= x - 1ULL; c++; }
    return c;
}

/* ------------------------------------------------------------------ */
/* Main test harness sub-groups (modularized for clean IDA analysis)   */
/* ------------------------------------------------------------------ */
#define CHECK(name, got, exp) do { \
    if ((got) == (exp)) { \
        printf("  [PASS] %-34s got=0x%016llX (%lld)\n", (name), (unsigned long long)(got), (long long)(got)); \
        pass++; \
    } else { \
        printf("  [FAIL] %-34s got=0x%016llX exp=0x%016llX\n", \
               (name), (unsigned long long)(got), (unsigned long long)(exp)); \
        fail++; \
    } \
    fflush(stdout); \
} while(0)

static void test_group_crypto_prng(int* pass_p, int* fail_p) {
    int pass = 0, fail = 0;
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
    *pass_p += pass;
    *fail_p += fail;
}

static void test_group_math_loops(int* pass_p, int* fail_p) {
    int pass = 0, fail = 0;
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
    *pass_p += pass;
    *fail_p += fail;
}

static void test_group_algorithms(int* pass_p, int* fail_p) {
    int pass = 0, fail = 0;
    /* ---- 9. Bitwise CRC-32 ---- */
    printf("\n[9] crc32_bitwise (IEEE 802.3 Polynomial 0xEDB88320 Nested Loop)\n");
    CHECK("crc32(0x0000000000000000)", crc32_bitwise(0x0000000000000000ULL), ref_crc32(0x0000000000000000ULL));
    CHECK("crc32(0x1234567890ABCDEF)", crc32_bitwise(0x1234567890ABCDEFULL), ref_crc32(0x1234567890ABCDEFULL));
    CHECK("crc32(0x5877CAFE1337BEEF)", crc32_bitwise(0x5877CAFE1337BEEFULL), ref_crc32(0x5877CAFE1337BEEFULL));
    CHECK("crc32(0xFFFFFFFFFFFFFFFF)", crc32_bitwise(0xFFFFFFFFFFFFFFFFULL), ref_crc32(0xFFFFFFFFFFFFFFFFULL));

    /* ---- 10. Integer Square Root ---- */
    printf("\n[10] int_sqrt (Binary Search Convergence Loop)\n");
    CHECK("sqrt(0)",                int_sqrt(0ULL),                ref_int_sqrt(0ULL));
    CHECK("sqrt(1)",                int_sqrt(1ULL),                ref_int_sqrt(1ULL));
    CHECK("sqrt(144)",              int_sqrt(144ULL),              ref_int_sqrt(144ULL));
    CHECK("sqrt(1000000000)",       int_sqrt(1000000000ULL),       ref_int_sqrt(1000000000ULL));
    CHECK("sqrt(0x1000000000000000)",int_sqrt(0x1000000000000000ULL), ref_int_sqrt(0x1000000000000000ULL));
    CHECK("sqrt(0xFFFFFFFFFFFFFFFF)",int_sqrt(0xFFFFFFFFFFFFFFFFULL), ref_int_sqrt(0xFFFFFFFFFFFFFFFFULL));

    /* ---- 11. MurmurHash3 fmix64 ---- */
    printf("\n[11] fmix64 (Cascading 64-bit Avalanche Multipliers & Shifts)\n");
    CHECK("fmix64(0)",              fmix64(0ULL),                  ref_fmix64(0ULL));
    CHECK("fmix64(42)",             fmix64(42ULL),                 ref_fmix64(42ULL));
    CHECK("fmix64(0x5877CAFE1337)", fmix64(0x5877CAFE1337ULL),     ref_fmix64(0x5877CAFE1337ULL));
    CHECK("fmix64(0xFFFFFFFFFFFFFFFF)",fmix64(0xFFFFFFFFFFFFFFFFULL), ref_fmix64(0xFFFFFFFFFFFFFFFFULL));

    /* ---- 12. Signed clamp and scale ---- */
    printf("\n[12] signed_clamp_scale (Signed Arithmetic & Comparisons LT/GT/GE/LE)\n");
    CHECK("clamp(-50, -10, 10, 2)",    (uint64_t)signed_clamp_scale(-50, -10, 10, 2),  (uint64_t)ref_clamp_scale(-50, -10, 10, 2));
    CHECK("clamp(50, -10, 10, 2)",     (uint64_t)signed_clamp_scale(50, -10, 10, 2),   (uint64_t)ref_clamp_scale(50, -10, 10, 2));
    CHECK("clamp(5, -10, 10, -3)",     (uint64_t)signed_clamp_scale(5, -10, 10, -3),   (uint64_t)ref_clamp_scale(5, -10, 10, -3));
    CHECK("clamp(-7, -10, 10, -4)",    (uint64_t)signed_clamp_scale(-7, -10, 10, -4),  (uint64_t)ref_clamp_scale(-7, -10, 10, -4));
    CHECK("clamp(-1000, -500, 500, 1)",(uint64_t)signed_clamp_scale(-1000, -500, 500, 1),(uint64_t)ref_clamp_scale(-1000, -500, 500, 1));

    /* ---- 13. Galois 64-bit LFSR ---- */
    printf("\n[13] lfsr_galois64 (Galois Shift Register OEIS A011260 Polynomial)\n");
    CHECK("lfsr(1, 1)",        lfsr_galois64(1ULL, 1),        ref_lfsr(1ULL, 1));
    CHECK("lfsr(1, 64)",       lfsr_galois64(1ULL, 64),       ref_lfsr(1ULL, 64));
    CHECK("lfsr(0x5877, 100)", lfsr_galois64(0x5877ULL, 100), ref_lfsr(0x5877ULL, 100));
    CHECK("lfsr(0xCAFE, 256)", lfsr_galois64(0xCAFEULL, 256), ref_lfsr(0xCAFEULL, 256));
    *pass_p += pass;
    *fail_p += fail;
}

static void test_group_bitwise(int* pass_p, int* fail_p) {
    int pass = 0, fail = 0;
    /* ---- 14. SipHash round ---- */
    printf("\n[14] siphash_round (4-State Register Compression Round)\n");
    CHECK("siphash(0, 0, 0, 0)",
          siphash_round(0ULL, 0ULL, 0ULL, 0ULL),
          ref_siphash(0ULL, 0ULL, 0ULL, 0ULL));
    CHECK("siphash(1, 2, 3, 4)",
          siphash_round(1ULL, 2ULL, 3ULL, 4ULL),
          ref_siphash(1ULL, 2ULL, 3ULL, 4ULL));
    CHECK("siphash(0x5877, 0x1337, 0xCAFE, 0xBEEF)",
          siphash_round(0x5877ULL, 0x1337ULL, 0xCAFEULL, 0xBEEFULL),
          ref_siphash(0x5877ULL, 0x1337ULL, 0xCAFEULL, 0xBEEFULL));
    CHECK("siphash(FFFF, AAAA, 5555, 1234)",
          siphash_round(0xFFFFFFFFFFFFFFFFULL, 0xAAAAAAAAAAAAAAAAULL, 0x5555555555555555ULL, 0x1234567890ABCDEFULL),
          ref_siphash(0xFFFFFFFFFFFFFFFFULL, 0xAAAAAAAAAAAAAAAAULL, 0x5555555555555555ULL, 0x1234567890ABCDEFULL));

    /* ---- 15. Hardware byte-swap ---- */
    printf("\n[15] byte_swap64 (rev / bswap Hardware Endianness Swap)\n");
    CHECK("bswap(0x1234567890ABCDEF)", byte_swap64(0x1234567890ABCDEFULL), ref_bswap(0x1234567890ABCDEFULL));
    CHECK("bswap(0x5877CAFE1337BEEF)", byte_swap64(0x5877CAFE1337BEEFULL), ref_bswap(0x5877CAFE1337BEEFULL));
    CHECK("bswap(0)",                  byte_swap64(0ULL),                  ref_bswap(0ULL));
    CHECK("bswap(0xFF)",               byte_swap64(0xFFULL),               ref_bswap(0xFFULL));

    /* ---- 16. Count leading zeros ---- */
    printf("\n[16] leading_zeros64 (clz / lzcnt Hardware Normalize)\n");
    CHECK("clz(1)",              leading_zeros64(1ULL),              ref_clz(1ULL));
    CHECK("clz(0x5877)",         leading_zeros64(0x5877ULL),         ref_clz(0x5877ULL));
    CHECK("clz(0x8000000000000000)", leading_zeros64(0x8000000000000000ULL), ref_clz(0x8000000000000000ULL));
    CHECK("clz(0xFFFFFFFFFFFFFFFF)", leading_zeros64(0xFFFFFFFFFFFFFFFFULL), ref_clz(0xFFFFFFFFFFFFFFFFULL));

    /* ---- 17. Count trailing zeros ---- */
    printf("\n[17] trailing_zeros64 (rbit+clz / tzcnt Hardware v2 Scan)\n");
    CHECK("ctz(1)",              trailing_zeros64(1ULL),              ref_ctz(1ULL));
    CHECK("ctz(0x5877)",         trailing_zeros64(0x5877ULL),         ref_ctz(0x5877ULL));
    CHECK("ctz(0x8000000000000000)", trailing_zeros64(0x8000000000000000ULL), ref_ctz(0x8000000000000000ULL));
    CHECK("ctz(0x58770000)",     trailing_zeros64(0x58770000ULL),     ref_ctz(0x58770000ULL));

    /* ---- 18. Bit reversal ---- */
    printf("\n[18] reverse_bits64 (rbit Hardware 64-bit Permutation)\n");
    CHECK("rbit(1)",                 reverse_bits64(1ULL),                 ref_rbit(1ULL));
    CHECK("rbit(0x1234567890ABCDEF)",reverse_bits64(0x1234567890ABCDEFULL),ref_rbit(0x1234567890ABCDEFULL));
    CHECK("rbit(0x5877CAFE1337BEEF)",reverse_bits64(0x5877CAFE1337BEEFULL),ref_rbit(0x5877CAFE1337BEEFULL));
    CHECK("rbit(0)",                 reverse_bits64(0ULL),                 ref_rbit(0ULL));

    /* ---- 19. Population count ---- */
    printf("\n[19] hamming_weight64 (cnt-chain / popcnt Hardware Hamming)\n");
    CHECK("popcnt(0)",                   hamming_weight64(0ULL),                   ref_popcnt(0ULL));
    CHECK("popcnt(0x5877585758575857)",  hamming_weight64(0x5877585758575857ULL),  ref_popcnt(0x5877585758575857ULL));
    CHECK("popcnt(0xFFFFFFFFFFFFFFFF)",  hamming_weight64(0xFFFFFFFFFFFFFFFFULL),  ref_popcnt(0xFFFFFFFFFFFFFFFFULL));
    CHECK("popcnt(0xDEADBEEFCAFE1337)",  hamming_weight64(0xDEADBEEFCAFE1337ULL),  ref_popcnt(0xDEADBEEFCAFE1337ULL));
    *pass_p += pass;
    *fail_p += fail;
}

int main(void)
{
    int pass = 0, fail = 0;

    printf("====================================================================\n");
    printf("  🛡️  ASGARD-5877: Stack-JIT (SJIT) Big C++ Showcase & Bug Stress\n");
    printf("  19 Virtualized Functions in Sealed Nano-Arena:\n");
    printf("    * A000002 Kolakoski Fission     * A010060 Thue-Morse Dummy Padding\n");
    printf("    * A000166 Derangement Shuffling * A002487 Stern Affine Masking\n");
    printf("    * A000695 Moser-de Bruijn Imm   * A003022 Golomb Ruler Slots\n");
    printf("    * A000201 Beatty-Wythoff Arena  * A001511 Ruler / A269160 Wipe\n");
    printf("    * A000931 Padovan Dispersion\n");
    printf("====================================================================\n\n");
    fflush(stdout);

    test_group_crypto_prng(&pass, &fail);
    test_group_math_loops(&pass, &fail);
    test_group_algorithms(&pass, &fail);
    test_group_bitwise(&pass, &fail);

    /* ---- Summary ---- */
    printf("\n====================================================================\n");
    printf("  Results: %d PASS, %d FAIL out of %d assertions\n", pass, fail, pass + fail);
    if (fail == 0) {
        printf("  🎉 ALL 19 VIRTUALIZED ROUTINES EXECUTED WITH 100%% EXACT PRECISION\n");
        printf("  Stack-JIT Sealing & Dynamic Nano-Chunks VERIFIED on Hardware\n");
    } else {
        printf("  💥 FAILURES DETECTED\n");
    }
    printf("====================================================================\n");
    return fail == 0 ? 0 : 1;
}
