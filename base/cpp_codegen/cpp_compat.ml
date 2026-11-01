(* Cpp_compat — canonical portability preamble for every emitted C/C++ artifact.

   Defines the ASG_* macro family so that generated runtimes compile
   identically under MSVC 19+, GCC and Clang:

     ASG_EXPECT (c, e)      branch-expect hint   ( __builtin_expect / identity )
     ASG_FORCEINLINE        forced inlining      ( __forceinline / attribute )
     ASG_NOINLINE           inlining barrier     ( [[msvc::noinline]] / attribute )
     ASG_CLEAR_CACHE(a, l)  instruction-cache invalidation after writing code
                            ( FlushInstructionCache / __builtin___clear_cache )

   The block is idempotent (include-guarded). Prepend it first in every
   generated header or translation unit that uses these macros. *)
let preamble : string =
{|#ifndef ASGARD_PORTABILITY_PREAMBLE
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
|}
