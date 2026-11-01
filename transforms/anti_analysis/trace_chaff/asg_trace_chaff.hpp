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
#else
#define ASG_EXPECT(c, e) __builtin_expect((c), (e))
#define ASG_FORCEINLINE __attribute__((always_inline))
#define ASG_NOINLINE __attribute__((noinline))
#define ASG_CLEAR_CACHE(addr, len) __builtin___clear_cache((char*)(addr), (char*)(addr) + (len))
#endif
#endif
// ============================================================================

// ASGARD-5877: Tech-2608 (arXiv:2608.20628)

// Anti-Trace-Synthesis & Memory Chaffing Runtime

// Thwarts BinMirror/LLM behavioral specification synthesis via:

//   1. Shadow Memory Chaff Pool with volatile decoys

//   2. Register-entangled memory reads and writes

//   3. Opaque-guarded side-effects indistinguishable from guest memory

// ============================================================================

#include <cstdint>

#include <cstddef>

#include <array>

namespace asgard::trace_chaff {
                               
                               template <size_t PoolSize = 4096>
                               struct alignas(64) ChaffMemoryPool {
                                                                    static_assert(((PoolSize & (PoolSize - 1)) == 0), "PoolSize must be power-of-two");
                                                                    static_assert((PoolSize >= 64), "PoolSize must be at least 64 bytes");
                                                                    alignas(64) volatile uint64_t storage[PoolSize / sizeof(uint64_t)]{0};
                                                                    static inline constexpr size_t MASK_WORDS = ((PoolSize / sizeof(uint64_t)) - 1);
                                                                    ASG_FORCEINLINE inline void emit_chaff_store(uint64_t reg_a, uint64_t reg_b, uint64_t k_dyn, uint64_t salt) noexcept {
                                                                    
                                                                    const size_t slot = (static_cast<size_t>((reg_a ^ salt)) & MASK_WORDS);
                                                                    const uint64_t val = (((reg_a * 0x9e3779b97f4a7c15ULL) + (reg_b * 0xbf58476d1ce4e5b9ULL)) ^ (k_dyn + salt));
                                                                    storage[slot] = val;
                                                                    }
                                                                    ASG_FORCEINLINE inline uint64_t emit_chaff_load(uint64_t reg_src, uint64_t salt) const noexcept {
                                                                    
                                                                    const size_t slot = (static_cast<size_t>((reg_src ^ salt)) & MASK_WORDS);
                                                                    return storage[slot];
                                                                    }
                                                                    
                               };

} // namespace asgard::trace_chaff
