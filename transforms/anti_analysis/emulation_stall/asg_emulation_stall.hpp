#pragma once
#ifndef ASGARD_PORTABILITY_PREAMBLE
#define ASGARD_PORTABILITY_PREAMBLE
#include <stddef.h>
#if defined(__cplusplus)
#include <cstdint>
#else
#include <stdint.h>
#endif
#if defined(_MSC_VER) && !defined(__clang__)
#if defined(__cplusplus)
extern "C" __declspec(dllimport) void* __stdcall GetCurrentProcess(void);
extern "C" __declspec(dllimport) int __stdcall FlushInstructionCache(void*, const void*, size_t);
#define ASG_NOINLINE [[msvc::noinline]]
#else
#define ASG_NOINLINE
#endif
#define ASG_EXPECT(c, e) (c)
#define ASG_FORCEINLINE __forceinline
#define ASG_CLEAR_CACHE(addr, len) FlushInstructionCache(GetCurrentProcess(), (const void*)(addr), (size_t)(len))
#if defined(__cplusplus)
static inline uint64_t asg_mul_mod64(uint64_t a, uint64_t b, uint64_t m) {
    uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
    uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
    uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;
    uint64_t mid = p1 + (p0 >> 32);
    uint64_t lo = (p0 & 0xFFFFFFFFULL) | ((mid + p2) << 32);
    uint64_t hi = p3 + (mid >> 32) + (((mid & 0xFFFFFFFFULL) + p2) >> 32);
    uint64_t rem = 0;
    for (int i = 127; i >= 0; --i) {
        rem = (rem << 1) | (i >= 64 ? ((hi >> (i - 64)) & 1) : ((lo >> i) & 1));
        if (rem >= m) rem -= m;
    }
    return rem;
}
#define ASG_MUL_MOD(a, b, m) asg_mul_mod64((a), (b), (m))
#endif
#else
#define ASG_EXPECT(c, e) __builtin_expect((c), (e))
#define ASG_FORCEINLINE __attribute__((always_inline))
#define ASG_NOINLINE __attribute__((noinline))
#define ASG_CLEAR_CACHE(addr, len) __builtin___clear_cache((char*)(addr), (char*)(addr) + (len))
#define ASG_MUL_MOD(a, b, m) static_cast<uint64_t>((static_cast<__uint128_t>(a) * (b)) % (m))
#endif
#endif
// ============================================================================

// ASGARD-5877: Computational Stalling (CPU-bound Anti-Emulation)

// Raises the emulation slowdown factor Ω to force sandbox timeout.

//   RswTimeLock<N,M,A>           – N sequential squarings mod M (depth Θ(N))

//   ChebyshevChaoticMap<N,M,X0>   – Discrete Chebyshev chaotic attractor mod M

//   ErgodicPolyTimeLock<N,C,X0>   – Rivest-Knuth cubic ergodic permutation poly mod 2^64

//   TwoAdicNewtonSolver<...>      – 2-adic Hensel-Newton singular polynomial solver mod 2^64

//   PowHashPuzzle<D>             – D leading-zero-bit PoW with GF(2^64) inner loop

//   CompStallGuard<N,D,M,A,XN>   – composite guard (RSW then PoW)

// ============================================================================

#include <cstdint>

#include <cstring>

namespace asgard::emulation_stall {
                                   
                                   template <uint64_t N, uint64_t M, uint64_t A>
                                   struct RswTimeLock {
                                                           static_assert((N > 0x0000000000000000ULL), "N must be positive");
                                                           static_assert((M > 0x0000000000000003ULL), "M must be > 3");
                                                           [[nodiscard]] static uint64_t run() noexcept {
                                                           
                                                               uint64_t x = (A % M);
                                                               for (size_t i = 0x0000000000000000ULL; i < N; ++i) {
                                                               
                                                                   x = ASG_MUL_MOD(x, x, M);
                                                               }
                                                               return x;
                                                           }
                                                           [[nodiscard]] static bool verify(uint64_t result, uint64_t expected_x_n) noexcept {
                                                           
                                                               return ((result ^ expected_x_n) == 0x0000000000000000ULL);
                                                           }
                                                           
                                   };
                                   
                                   template <uint64_t N, uint64_t M, uint64_t X0>
                                   struct ChebyshevChaoticMap {
                                                                   static_assert((N > 0x0000000000000000ULL), "N must be positive");
                                                                   static_assert((M > 0x0000000000000003ULL), "M must be > 3");
                                                                   [[nodiscard]] static uint64_t run() noexcept {
                                                                   
                                                                    uint64_t x = (X0 % M);
                                                                    for (size_t i = 0x0000000000000000ULL; i < N; ++i) {
                                                                    
                                                                    uint64_t x2 = ((x * x) % M);
                                                                    x = (((0x0000000000000002ULL * x2) + (M - 0x0000000000000001ULL)) % M);
                                                                    }
                                                                    return x;
                                                                   }
                                                                   [[nodiscard]] static bool verify(uint64_t result, uint64_t expected_x_n) noexcept {
                                                                   
                                                                    return ((result ^ expected_x_n) == 0x0000000000000000ULL);
                                                                   }
                                                                   
                                   };
                                   
                                   template <uint64_t N, uint64_t C, uint64_t X0>
                                   struct ErgodicPolyTimeLock {
                                                                   static_assert((N > 0x0000000000000000ULL), "N must be positive");
                                                                   [[nodiscard]] static uint64_t run() noexcept {
                                                                   
                                                                    uint64_t x = X0;
                                                                    for (size_t i = 0x0000000000000000ULL; i < N; ++i) {
                                                                    
                                                                    uint64_t x2 = (x * x);
                                                                    uint64_t x3 = (x2 * x);
                                                                    x = (((x + (x2 << 0x0000000000000001ULL)) + (x3 << 0x0000000000000002ULL)) + C);
                                                                    }
                                                                    return x;
                                                                   }
                                                                   [[nodiscard]] static bool verify(uint64_t result, uint64_t expected_x_n) noexcept {
                                                                   
                                                                    return ((result ^ expected_x_n) == 0x0000000000000000ULL);
                                                                   }
                                                                   
                                   };
                                   
                                   template <uint64_t STEPS, uint64_t X_INIT, uint64_t C0, uint64_t C1, uint64_t C2, uint64_t C3>
                                   struct TwoAdicNewtonSolver {
                                                                   static_assert((STEPS > 0x0000000000000000ULL), "STEPS must be positive");
                                                                   [[nodiscard]] static uint64_t run() noexcept {
                                                                   
                                                                    uint64_t x = X_INIT;
                                                                    for (size_t step = 0x0000000000000000ULL; step < STEPS; ++step) {
                                                                    
                                                                    uint64_t x2 = (x * x);
                                                                    uint64_t fx = (C0 + (x * (C1 + (x * (C2 + (x * C3))))));
                                                                    uint64_t dfx = ((C1 + ((x << 0x0000000000000001ULL) * C2)) + ((0x0000000000000003ULL * x2) * C3));
                                                                    uint64_t inv = dfx;
                                                                    inv = (inv * (0x0000000000000002ULL - (dfx * inv)));
                                                                    inv = (inv * (0x0000000000000002ULL - (dfx * inv)));
                                                                    inv = (inv * (0x0000000000000002ULL - (dfx * inv)));
                                                                    inv = (inv * (0x0000000000000002ULL - (dfx * inv)));
                                                                    inv = (inv * (0x0000000000000002ULL - (dfx * inv)));
                                                                    uint64_t delta = (fx * inv);
                                                                    x = (x - delta);
                                                                    }
                                                                    return x;
                                                                   }
                                                                   [[nodiscard]] static bool verify(uint64_t result, uint64_t expected_x_star) noexcept {
                                                                   
                                                                    return ((result ^ expected_x_star) == 0x0000000000000000ULL);
                                                                   }
                                                                   
                                   };
                                   
                                   template <uint32_t D>
                                   struct PowHashPuzzle {
                                                             static_assert(((D >= 0x0000000000000008ULL) && (D <= 0x0000000000000028ULL)), "difficulty must be in [8,40]");
                                                             static inline constexpr uint64_t MASK = ((D == 0x0000000000000040ULL) ? (~0x0000000000000000ULL) : ((0x0000000000000001ULL << D) - 0x0000000000000001ULL));
                                                             [[nodiscard]] static uint64_t mix_round(uint64_t state) noexcept {
                                                             
                                                                 uint64_t acc = 0x0000000000000000ULL;
                                                                 uint64_t a_gf = state;
                                                                 uint64_t b_gf = 0x9e3779b97f4a7c15ULL;
                                                                 for (size_t bit = 0x0000000000000000ULL; bit < 0x0000000000000040ULL; ++bit) {
                                                                 
                                                                    if ((b_gf & 0x0000000000000001ULL) == 0x0000000000000001ULL) {
                                                                    
                                                                    acc ^= a_gf;
                                                                    }
                                                                    uint64_t carry = ((a_gf >> 0x000000000000003fULL) & 0x0000000000000001ULL);
                                                                    a_gf = (a_gf << 0x0000000000000001ULL);
                                                                    if (carry == 0x0000000000000001ULL) {
                                                                    
                                                                    a_gf ^= 0xc4ceb9fe1a85ec53ULL;
                                                                    }
                                                                    b_gf = (b_gf >> 0x0000000000000001ULL);
                                                                 }
                                                                 acc ^= ((acc >> 0x000000000000001eULL) * 0xbf58476d1ce4e5b9ULL);
                                                                 acc ^= ((acc >> 0x000000000000001bULL) * 0x94d049bb133111ebULL);
                                                                 return (acc ^ (acc >> 0x000000000000001fULL));
                                                             }
                                                             [[nodiscard]] static uint64_t solve(uint64_t seed, uint64_t target_tag) noexcept {
                                                             
                                                                 for (size_t nonce = 0x0000000000000000ULL; nonce < 0x7fffffffffffffffULL; ++nonce) {
                                                                 
                                                                    uint64_t state = (seed ^ nonce);
                                                                    for (size_t r = 0x0000000000000000ULL; r < 0x0000000000000010ULL; ++r) {
                                                                    
                                                                    state = mix_round(state);
                                                                    }
                                                                    if (((state & MASK) == 0x0000000000000000ULL) && ((state >> 0x0000000000000020ULL) == target_tag)) {
                                                                    
                                                                    return state;
                                                                    }
                                                                 }
                                                                 return 0x0000000000000000ULL;
                                                             }
                                                             
                                   };
                                   
                                   template <uint64_t N, uint32_t D, uint64_t M, uint64_t A, uint64_t XN>
                                   struct CompStallGuard {
                                                              [[nodiscard]] static bool run_and_verify(uint64_t pow_seed, uint64_t pow_tag) noexcept {
                                                              
                                                                  const uint64_t rsw_result = RswTimeLock<N, M, A>::run();
                                                                  if (!RswTimeLock<N, M, A>::verify(rsw_result, XN)) {
                                                                  
                                                                    return false;
                                                                  }
                                                                  const uint64_t pow_result = PowHashPuzzle<D>::solve((pow_seed ^ rsw_result), pow_tag);
                                                                  return (pow_result != 0x0000000000000000ULL);
                                                              }
                                                              
                                   };

} // namespace asgard::emulation_stall
