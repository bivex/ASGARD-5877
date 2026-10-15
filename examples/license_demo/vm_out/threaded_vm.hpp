// [ASGARD Tech-2608] Anti-Trace-Synthesis & Memory Chaffing Active
#include "asg_tech_2608.hpp"

// [ASGARD Tech-2603] Anti-VPC-Tracking & Non-Linear Dispatch Active
#include "asg_tech_2603.hpp"

// [ASGARD Tech-2601] ABI-Compliant Exception Handling Shadowing Active
// Shadow Allocation: 32 bytes | Interceptor: tech_2601_interceptor
#include "asg_tech_2601.hpp"

#pragma once

#if __has_include("vanguard/platform_compat.hpp")
#include "vanguard/platform_compat.hpp"
#include "vanguard/crypto_primitives.hpp"
#include "vanguard/sanitization.hpp"
#else
#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Platform Compatibility Layer
// Supports Clang, GCC, and MSVC across macOS, Linux, and Windows.
// ============================================================================

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <atomic>
#include <bit>
#include <cstring>
#include <algorithm>
#include <cmath>

#if !defined(_WIN32) && !defined(_WIN64)
#include <dlfcn.h>
#endif

#if !defined(RTLD_DEFAULT)
#define RTLD_DEFAULT ((void*)0)
#endif

#if defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#elif defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#include <time.h>
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
#endif
#ifndef CLOCK_REALTIME
#define CLOCK_REALTIME 0
#endif
static inline int clock_gettime(int, struct timespec* ts) {
    if (!ts) return -1;
    LARGE_INTEGER freq, counter;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&counter);
    ts->tv_sec = (time_t)(counter.QuadPart / freq.QuadPart);
    ts->tv_nsec = (long)(((counter.QuadPart % freq.QuadPart) * 1000000000LL) / freq.QuadPart);
    return 0;
}
#endif

#if defined(_MSC_VER) && !defined(__clang__)
#include <intrin.h>
#include <malloc.h>
#ifndef __attribute__
#define __attribute__(x)
#endif
#ifndef __builtin_expect
#define __builtin_expect(expr, c) (expr)
#endif
#ifndef __builtin_bswap16
#define __builtin_bswap16(x) _byteswap_ushort(x)
#endif
#ifndef __builtin_bswap32
#define __builtin_bswap32(x) _byteswap_ulong(x)
#endif
#ifndef __builtin_bswap64
#define __builtin_bswap64(x) _byteswap_uint64(x)
#endif
#ifndef __builtin_alloca
#define __builtin_alloca(x) _alloca(x)
#endif
static inline int __builtin_clz(uint32_t x) { return std::countl_zero(x); }
static inline int __builtin_clzll(uint64_t x) { return std::countl_zero(x); }
static inline int __builtin_ctz(uint32_t x) { return std::countr_zero(x); }
static inline int __builtin_ctzll(uint64_t x) { return std::countr_zero(x); }
static inline int __builtin_popcount(uint32_t x) { return std::popcount(x); }
static inline int __builtin_popcountll(uint64_t x) { return std::popcount(x); }
static inline uint64_t __builtin_ia32_rdtsc() {
#if defined(_M_X64) || defined(_M_IX86)
    return __rdtsc();
#elif defined(_M_ARM64)
    return (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    return 0;
#endif
}
#define __ATOMIC_RELAXED 0
#define __ATOMIC_CONSUME 1
#define __ATOMIC_ACQUIRE 2
#define __ATOMIC_RELEASE 3
#define __ATOMIC_ACQ_REL 4
#define __ATOMIC_SEQ_CST 5

template <typename T>
static inline T __atomic_load_n(const volatile T* ptr, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).load();
}
template <typename T, typename V>
static inline void __atomic_store_n(volatile T* ptr, V val, int) {
    std::atomic_ref<T>(*const_cast<T*>(ptr)).store(static_cast<T>(val));
}
template <typename T, typename V>
static inline T __atomic_exchange_n(volatile T* ptr, V val, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).exchange(static_cast<T>(val));
}
template <typename T, typename V>
static inline bool __atomic_compare_exchange_n(volatile T* ptr, T* expected, V desired, bool, int, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).compare_exchange_strong(*expected, static_cast<T>(desired));
}
template <typename T, typename V>
static inline T __atomic_fetch_add(volatile T* ptr, V val, int) {
    return std::atomic_ref<T>(*const_cast<T*>(ptr)).fetch_add(static_cast<T>(val));
}
static inline void __atomic_thread_fence(int) {
    std::atomic_thread_fence(std::memory_order_seq_cst);
}
#endif

#if defined(__GNUC__) || defined(__clang__)
#define ASG_CALL_NOINLINE __attribute__((noinline))
#elif defined(_MSC_VER)
#define ASG_CALL_NOINLINE __declspec(noinline)
#else
#define ASG_CALL_NOINLINE
#endif

#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Cryptographic Primitives & Dynamic Resolution
// FNV-1a, Mach-O Dyld Exports Trie Resolver, Dynamic Symbol Decryption
// ============================================================================

#ifndef ASGARD_CRYPTO_PRIMITIVES_DEFINED
#define ASGARD_CRYPTO_PRIMITIVES_DEFINED
#define ASGARD_API_HASH_RESOLVER_DEFINED 1

static constexpr inline uint32_t asgard_fnv1a_const(const char* str, uint32_t hash = 0x811C9DC5U) noexcept {
    return (*str == 0) ? hash : asgard_fnv1a_const(str + 1, (hash ^ static_cast<uint8_t>(*str)) * 0x01000193U);
}

static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    if (!s1 || !s2) return (s1 == s2) ? 0 : (s1 ? 1 : -1);
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

#if defined(__APPLE__) && defined(__MACH__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static inline uint64_t asg_read_uleb128(const uint8_t** p) noexcept {
    uint64_t result = 0;
    int shift = 0;
    while (1) {
        uint8_t byte = *(*p)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static inline void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) noexcept {
    const uint8_t* p = node;
    uint64_t terminal_size = asg_read_uleb128(&p);
    if (terminal_size > 0 && cur_h == target_h) {
        uint64_t flags = asg_read_uleb128(&p);
        if ((flags & 0x08) == 0) {
            uint64_t addr = asg_read_uleb128(&p);
            return (void*)(addr + base);
        }
        return nullptr;
    }
    p += terminal_size;
    uint8_t child_count = *p++;
    for (uint8_t i = 0; i < child_count; i++) {
        uint32_t child_h = cur_h;
        while (*p) {
            child_h = (child_h ^ (uint8_t)*p++) * 0x01000193U;
        }
        p++; /* skip null terminator */
        uint64_t child_offset = asg_read_uleb128(&p);
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static inline void* asgard_resolve_by_api_hash(uint32_t target_hash) noexcept {
    if (target_hash == 0) return nullptr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* hdr = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command* cmd = (const struct load_command*)(hdr + 1);
        uintptr_t linkedit_base = 0;
        uint32_t dataoff = 0;
        for (uint32_t c = 0; c < hdr->ncmds; c++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                if (asg_strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_base = seg->vmaddr + slide - seg->fileoff;
                }
            } else if (cmd->cmd == 0x80000033 /* LC_DYLD_EXPORTS_TRIE */) {
                const struct linkedit_data_command* lc = (const struct linkedit_data_command*)cmd;
                dataoff = lc->dataoff;
            }
            cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
        }
        if (linkedit_base && dataoff) {
            const uint8_t* trie = (const uint8_t*)(linkedit_base + dataoff);
            void* resolved = asg_find_sym_in_trie(trie, trie, 0x811c9dc5U, target_hash, (uintptr_t)hdr);
            if (resolved) return resolved;
        }
    }
    return nullptr;
}
#else
static inline void* asgard_resolve_by_api_hash(uint32_t) noexcept { return nullptr; }
#endif

typedef struct {
    uint32_t hash;
    uint32_t alt_hash;
    uint16_t len;
    uint8_t enc_bytes[64];
} asgard_ext_sym_t;

static inline void asg_decrypt_sym(const asgard_ext_sym_t* sym, char* out_buf, size_t out_cap) noexcept {
    size_t n = sym->len < out_cap - 1 ? sym->len : out_cap - 1;
    for (size_t i = 0; i < n; i++) {
        uint8_t k = (uint8_t)(0x5A ^ ((i * 17 + 0x33) & 0xFF));
        out_buf[i] = (char)(sym->enc_bytes[i] ^ k);
    }
    out_buf[n] = '\0';
}

struct AsgardConstantEntry {
    uint32_t hash;
    uint32_t alt_hash;
    const uint8_t* enc_data;
    uint8_t* dec_data;
    size_t size;
    uint32_t xor_key;
    volatile int ready;
};

#endif // ASGARD_CRYPTO_PRIMITIVES_DEFINED

#pragma once
// ============================================================================
// ASGARD-5877 Vanguard Runtime: Memory Sanitization & Anti-Forensics
// Ephemeral Memory Scrubbing, Rolling Noise Invalidation, Canary Verification
// ============================================================================

#ifndef ASGARD_SANITIZATION_DEFINED
#define ASGARD_SANITIZATION_DEFINED

#define SCRUB_WORD(ptr, val) do { \
    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
} while(0)

namespace asgard_sanitization {

static inline void scrub_memory_range(volatile uint64_t* ptr, size_t count, uint64_t noise_seed) noexcept {
    if (!ptr || count == 0) return;
    for (size_t i = 0; i < count; ++i) {
        ptr[i] = (noise_seed * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL ^ (uint64_t)i;
    }
}

static inline void ephemeral_wipe_buffer(void* ptr, size_t byte_count) noexcept {
    if (!ptr || byte_count == 0) return;
    volatile uint8_t* p = reinterpret_cast<volatile uint8_t*>(ptr);
    for (size_t i = 0; i < byte_count; ++i) {
        p[i] = static_cast<uint8_t>(0x5A ^ ((i * 37 + 0x7F) & 0xFF));
    }
    for (size_t i = 0; i < byte_count; ++i) {
        p[i] = 0;
    }
}

} // namespace asgard_sanitization

#endif // ASGARD_SANITIZATION_DEFINED

#endif

#define ASGARD_VECTOR_ISA 1

#if defined(__aarch64__)
#include <arm_neon.h>
#elif defined(__x86_64__)
#include <immintrin.h>
#endif

#pragma once
// =========================================================================

// ASGARD-5877: RESIDUE NUMBER SYSTEM (RNS-4) & GARNER CRT ARITHMETIC

// Non-Linear Diophantine Residue Channels for Anti-SMT Hardening

// =========================================================================

#include <stdint.h>

namespace asgard_rns {
                      
                      static constexpr uint64_t M1 = 0x0000000000010001ULL;
                      
                      static constexpr uint64_t M2 = 0x000000000000fff1ULL;
                      
                      static constexpr uint64_t M3 = 0x000000000000ffefULL;
                      
                      static constexpr uint64_t M4 = 0x000000000000ffd9ULL;
                      
                      static constexpr uint64_t INV_M1_M2 = 0x000000000000eff2ULL;
                      
                      static constexpr uint64_t INV_M1_M3 = 0x0000000000000e38ULL;
                      
                      static constexpr uint64_t INV_M1_M4 = 0x0000000000002cc6ULL;
                      
                      static constexpr uint64_t INV_M2_M3 = 0x0000000000007ff8ULL;
                      
                      static constexpr uint64_t INV_M2_M4 = 0x000000000000f530ULL;
                      
                      static constexpr uint64_t INV_M3_M4 = 0x0000000000005168ULL;
                      
                      struct RNSVal {
                                         uint64_t r1;
                                         uint64_t r2;
                                         uint64_t r3;
                                         uint64_t r4;
                                         
                      };
                      
                      static __attribute__((always_inline)) inline RNSVal encode(uint64_t x) noexcept {
                      
                          return { (x % M1), (x % M2), (x % M3), (x % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline RNSVal add(RNSVal a, RNSVal b) noexcept {
                      
                          return { ((a.r1 + b.r1) % M1), ((a.r2 + b.r2) % M2), ((a.r3 + b.r3) % M3), ((a.r4 + b.r4) % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline RNSVal sub(RNSVal a, RNSVal b) noexcept {
                      
                          return { (((a.r1 + M1) - (b.r1 % M1)) % M1), (((a.r2 + M2) - (b.r2 % M2)) % M2), (((a.r3 + M3) - (b.r3 % M3)) % M3), (((a.r4 + M4) - (b.r4 % M4)) % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline RNSVal mul(RNSVal a, RNSVal b) noexcept {
                      
                          return { ((a.r1 * (b.r1 % M1)) % M1), ((a.r2 * (b.r2 % M2)) % M2), ((a.r3 * (b.r3 % M3)) % M3), ((a.r4 * (b.r4 % M4)) % M4) };
                      }
                      
                      static __attribute__((always_inline)) inline uint64_t decode(RNSVal r) noexcept {
                      
                          uint64_t v1 = r.r1;
                          uint64_t diff2 = (((r.r2 + M2) - (v1 % M2)) % M2);
                          uint64_t v2 = ((diff2 * INV_M1_M2) % M2);
                          uint64_t diff1_3 = (((r.r3 + M3) - (v1 % M3)) % M3);
                          uint64_t term1_3 = ((diff1_3 * INV_M1_M3) % M3);
                          uint64_t diff2_3 = (((term1_3 + M3) - (v2 % M3)) % M3);
                          uint64_t v3 = ((diff2_3 * INV_M2_M3) % M3);
                          uint64_t diff1_4 = (((r.r4 + M4) - (v1 % M4)) % M4);
                          uint64_t term1_4 = ((diff1_4 * INV_M1_M4) % M4);
                          uint64_t diff2_4 = (((term1_4 + M4) - (v2 % M4)) % M4);
                          uint64_t term2_4 = ((diff2_4 * INV_M2_M4) % M4);
                          uint64_t diff3_4 = (((term2_4 + M4) - (v3 % M4)) % M4);
                          uint64_t v4 = ((diff3_4 * INV_M3_M4) % M4);
                          uint64_t term_v2 = (v2 * M1);
                          uint64_t term_v3 = (v3 * (M1 * M2));
                          uint64_t term_v4 = (v4 * ((M1 * M2) * M3));
                          return (((v1 + term_v2) + term_v3) + term_v4);
                      }

} // namespace asgard_rns


#pragma once
// AUTO-GENERATED BY ASGARD-5877 TYPED C++20 EDSL

#include <cstdint>

namespace asgard::branchless_vip {
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t is_zero_u64(uint64_t d) noexcept {
                                  
                                      return (0x0000000000000001ULL - ((d | (0x0000000000000000ULL - d)) >> 0x000000000000003fULL));
                                  }
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t is_ult_u64(uint64_t x, uint64_t y) noexcept {
                                  
                                      uint64_t diff = (x - y);
                                      uint64_t borrow = (((~x) & y) | (((~x) | y) & diff));
                                      return (borrow >> 0x000000000000003fULL);
                                  }
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t is_slt_u64(uint64_t x, uint64_t y) noexcept {
                                  
                                      constexpr uint64_t SIGN_BIT = 0x8000000000000000ULL;
                                      return is_ult_u64((x ^ SIGN_BIT), (y ^ SIGN_BIT));
                                  }
                                  
                                  __attribute__((always_inline)) inline constexpr uint64_t select_vip(uint64_t cond_bit, uint64_t target_vip, uint64_t fallthrough_vip) noexcept {
                                  
                                      return (fallthrough_vip + (cond_bit * (target_vip - fallthrough_vip)));
                                  }

} // namespace asgard::branchless_vip



#pragma once
// AUTO-GENERATED BY ASGARD-5877 TYPED C++20 EDSL

#include <cstdint>

namespace asgard::chameleon_vm {
                                
                                struct alignas(32) DelayedCommitCtx {
                                
                                    uint64_t regs[32];
                                    uint32_t pending_reg;
                                    uint32_t has_pending;
                                    uint64_t pending_val;
                                    uint64_t pending_mask;
                                    
                                };
                                
                                __attribute__((always_inline)) inline void exec_chameleon_delayed_step(DelayedCommitCtx& ctx, uint32_t dst_reg, uint64_t x, uint64_t y, uint64_t w_xor, uint64_t w_and, uint64_t w_or, uint64_t next_mask) noexcept {
                                
                                    // 1. Commit result of PREVIOUS instruction (T-1) to break single-handler I/O oracle
                                    if (0 != ctx.has_pending) {
                                                                   ctx.regs[ctx.pending_reg] = (ctx.pending_val ^ ctx.pending_mask);
                                    }
                                    // 2. Evaluate universal polymorphic Chameleon ALU kernel for step T
                                    uint64_t tx = ((x ^ y) * w_xor);
                                    uint64_t ta = ((x & y) * w_and);
                                    uint64_t to = ((x | y) * w_or);
                                    uint64_t res = ((ta + tx) + to);
                                    // 3. Latch masked result into delayed pipeline queue for step T+1
                                    ctx.pending_reg = dst_reg;
                                    ctx.pending_mask = next_mask;
                                    ctx.pending_val = (next_mask ^ res);
                                    ctx.has_pending = 1;
                                }
                                
                                __attribute__((always_inline)) inline void flush_chameleon_pipeline(DelayedCommitCtx& ctx) noexcept {
                                
                                    if (ctx.has_pending != 0) {
                                                                   ctx.regs[ctx.pending_reg] = (ctx.pending_mask ^ ctx.pending_val);
                                                                   ctx.has_pending = 0;
                                    }
                                }

} // namespace asgard::chameleon_vm



#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#elif defined(__linux__) || defined(ASGARD_TARGET_LINUX)
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winternl.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

#if defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
#ifndef _PID_T_DEFINED
#define _PID_T_DEFINED
typedef int pid_t;
#endif
#endif

#define ASGARD_DIRECT_SYSCALLS_ENABLED 1

namespace asgard_syscalls {

#if (defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)) && (defined(__arm64__) || defined(__aarch64__))
// Direct Darwin ARM64 Syscall Stub (SVC #0x80 with BSD class 0x2000000)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0");
    __asm__ volatile("svc #0x80" : "=r"(x0) : "r"(x16) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    register int64_t x3  __asm__("x3")  = a4;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2), "r"(x3) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    register int64_t x3  __asm__("x3")  = a4;
    register int64_t x4  __asm__("x4")  = a5;
    register int64_t x5  __asm__("x5")  = a6;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
    return x0;
}
#elif defined(__x86_64__)
// Direct x86_64 Syscall Stub (syscall instruction)
#elif defined(__x86_64__)
// Direct x86_64 Syscall Stub (syscall instruction)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    register int64_t r10 __asm__("r10") = a4;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2), "d"(a3), "r"(r10) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int64_t num = (sys_num < 0x2000000) ? (0x2000000 | sys_num) : sys_num;
#else
    int64_t num = sys_num;
#endif
    int64_t ret;
    register int64_t r10 __asm__("r10") = a4;
    register int64_t r8  __asm__("r8")  = a5;
    register int64_t r9  __asm__("r9")  = a6;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(num), "D"(a1), "S"(a2), "d"(a3), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory", "cc");
    return ret;
}
#elif defined(__linux__) && (defined(__arm64__) || defined(__aarch64__))
// Linux AArch64 Direct Syscalls (SVC #0 with x8 syscall number)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0");
    __asm__ volatile("svc #0" : "=r"(x0) : "r"(x8) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    register int64_t x2 __asm__("x2") = a3;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    register int64_t x2 __asm__("x2") = a3;
    register int64_t x3 __asm__("x3") = a4;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory", "cc");
    return x0;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    register int64_t x8 __asm__("x8") = sys_num;
    register int64_t x0 __asm__("x0") = a1;
    register int64_t x1 __asm__("x1") = a2;
    register int64_t x2 __asm__("x2") = a3;
    register int64_t x3 __asm__("x3") = a4;
    register int64_t x4 __asm__("x4") = a5;
    register int64_t x5 __asm__("x5") = a6;
    __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
    return x0;
}
#elif defined(__linux__) && (defined(__riscv) || defined(__riscv__))
// Linux RISC-V Direct Syscalls (ECALL with a7 syscall number, return in a0)
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0");
    __asm__ volatile("ecall" : "=r"(a0_reg) : "r"(a7_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    register int64_t a2_reg __asm__("a2") = a3;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg), "r"(a2_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    register int64_t a2_reg __asm__("a2") = a3;
    register int64_t a3_reg __asm__("a3") = a4;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg), "r"(a2_reg), "r"(a3_reg) : "memory");
    return a0_reg;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    register int64_t a7_reg __asm__("a7") = sys_num;
    register int64_t a0_reg __asm__("a0") = a1;
    register int64_t a1_reg __asm__("a1") = a2;
    register int64_t a2_reg __asm__("a2") = a3;
    register int64_t a3_reg __asm__("a3") = a4;
    register int64_t a4_reg __asm__("a4") = a5;
    register int64_t a5_reg __asm__("a5") = a6;
    __asm__ volatile("ecall" : "+r"(a0_reg) : "r"(a7_reg), "r"(a1_reg), "r"(a2_reg), "r"(a3_reg), "r"(a4_reg), "r"(a5_reg) : "memory");
    return a0_reg;
}
#else
static inline int64_t direct_syscall_0(int64_t s) noexcept { (void)s; return 0; }
static inline int64_t direct_syscall_1(int64_t s, int64_t a) noexcept { (void)s; (void)a; return 0; }
static inline int64_t direct_syscall_2(int64_t s, int64_t a, int64_t b) noexcept { (void)s; (void)a; (void)b; return 0; }
static inline int64_t direct_syscall_3(int64_t s, int64_t a, int64_t b, int64_t c) noexcept { (void)s; (void)a; (void)b; (void)c; return 0; }
static inline int64_t direct_syscall_4(int64_t s, int64_t a, int64_t b, int64_t c, int64_t d) noexcept { (void)s; (void)a; (void)b; (void)c; (void)d; return 0; }
static inline int64_t direct_syscall_6(int64_t s, int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f) noexcept { (void)s; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; return 0; }
#endif

static inline pid_t sys_getpid() noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    return (pid_t)direct_syscall_0(20); // SYS_getpid
#elif defined(__linux__) && defined(__x86_64__)
    return (pid_t)direct_syscall_0(39); // SYS_getpid
#elif (defined(__linux__) || defined(ASGARD_TARGET_LINUX)) && (defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__))
    return (pid_t)direct_syscall_0(172); // SYS_getpid
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
    return (pid_t)GetCurrentProcessId();
#else
    return 0;
#endif
}

static inline int64_t sys_write(int fd, const void* buf, size_t count) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    return direct_syscall_3(4, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif defined(__linux__) && defined(__x86_64__)
    return direct_syscall_3(1, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif (defined(__linux__) || defined(ASGARD_TARGET_LINUX)) && (defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__))
    return direct_syscall_3(64, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
    HANDLE h = (fd == 1) ? GetStdHandle(STD_OUTPUT_HANDLE) :
               (fd == 2) ? GetStdHandle(STD_ERROR_HANDLE) : (HANDLE)(intptr_t)fd;
    if (h == NULL || h == INVALID_HANDLE_VALUE) return -1;
    DWORD written = 0;
    if (WriteFile(h, buf, (DWORD)count, &written, NULL)) return (int64_t)written;
    return -1;
#else
    return 0;
#endif
}

static inline void sys_exit(int status) noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    direct_syscall_1(1, (int64_t)status); // SYS_exit
#elif defined(__linux__) && defined(__x86_64__)
    direct_syscall_1(60, (int64_t)status); // SYS_exit
#elif (defined(__linux__) || defined(ASGARD_TARGET_LINUX)) && (defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__))
    direct_syscall_1(93, (int64_t)status); // SYS_exit
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
    ExitProcess((UINT)status);
#else
    _exit(status);
#endif
}

static inline bool sys_check_debugger_present() noexcept {
#if defined(__APPLE__) || defined(ASGARD_TARGET_DARWIN)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)sys_getpid() };
    struct kinfo_proc kinfo = {};
    size_t ksize = sizeof(kinfo);
    int64_t res = direct_syscall_6(202, (int64_t)mib, 4, (int64_t)&kinfo, (int64_t)&ksize, 0, 0);
    if (res == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {
        return true;
    }
    return false;
#elif defined(__linux__) || defined(ASGARD_TARGET_LINUX)
    int fd = -1;
#if defined(__x86_64__)
    fd = (int)direct_syscall_2(2, (int64_t)"/proc/self/status", 0);
#elif defined(__arm64__) || defined(__aarch64__) || defined(__riscv) || defined(__riscv__)
    fd = (int)direct_syscall_4(56, -100, (int64_t)"/proc/self/status", 0, 0);
#endif
    if (fd < 0) return false;
    char buf[512];
    int64_t n = direct_syscall_3(0, (int64_t)fd, (int64_t)buf, sizeof(buf) - 1);
    direct_syscall_1(3, (int64_t)fd);
    if (n <= 0) return false;
    buf[n] = '\0';
    for (int64_t i = 0; i + 11 < n; ++i) {
        if (buf[i] == 'T' && buf[i+1] == 'r' && buf[i+2] == 'a' && buf[i+3] == 'c' &&
            buf[i+4] == 'e' && buf[i+5] == 'r' && buf[i+6] == 'P' && buf[i+7] == 'i' &&
            buf[i+8] == 'd' && buf[i+9] == ':') {
            int64_t j = i + 10;
            while (j < n && (buf[j] == ' ' || buf[j] == '\t')) j++;
            if (j < n && buf[j] > '0' && buf[j] <= '9') return true;
        }
    }
    return false;
#elif defined(_WIN32) || defined(ASGARD_TARGET_WINDOWS)
#if defined(_M_X64) || defined(__x86_64__)
    // Stealth PEB interrogation on x64: GS:[0x60]
    const uint8_t* peb = (const uint8_t*)__readgsqword(0x60);
    if (peb) {
        // PEB.BeingDebugged at offset +0x02
        if (peb[2] != 0) return true;
        // PEB.NtGlobalFlag at offset +0xBC
        const uint32_t nt_global_flag = *(const uint32_t*)(peb + 0xBC);
        // 0x70 = FLG_HEAP_ENABLE_TAIL_CHECK | FLG_HEAP_ENABLE_FREE_CHECK | FLG_HEAP_VALIDATE_PARAMETERS
        if ((nt_global_flag & 0x70) == 0x70) return true;
    }
#elif defined(_M_IX86) || defined(__i386__)
    // Stealth PEB interrogation on x86: FS:[0x30]
    const uint8_t* peb = (const uint8_t*)__readfsdword(0x30);
    if (peb) {
        if (peb[2] != 0) return true;
        const uint32_t nt_global_flag = *(const uint32_t*)(peb + 0x68);
        if ((nt_global_flag & 0x70) == 0x70) return true;
    }
#endif
    return IsDebuggerPresent() != 0;
#else
    return false;
#endif
}

} // namespace asgard_syscalls


#pragma once
#include <stdint.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#include <mach-o/dyld.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

namespace asgard_anti_emulation {

static inline __attribute__((always_inline)) uint64_t evaluate_emulation_differential() noexcept {
    uint64_t penalty = 0;

#if defined(__x86_64__) || defined(_M_X64)
    // 1. CPUID Hypervisor Discovery & Cycle Ratio Probe
#if defined(_MSC_VER)
    int cpuInfo[4] = { 0 };
    __cpuid(cpuInfo, 1);
    if ((cpuInfo[2] >> 31) & 1) {
        penalty ^= 0x5877CAFEBABE1337ULL; // Hypervisor bit detected
    }
    uint64_t t0 = __rdtsc();
    for (int i = 0; i < 64; ++i) { YieldProcessor(); }
    uint64_t t1 = __rdtsc();
    if ((t1 - t0) > 25000ULL) {
        penalty ^= 0xDEADBEEF5A5A1337ULL; // Emulation slow-path detected
    }
#else
    uint32_t eax = 1, ebx = 0, ecx = 0, edx = 0;
    __asm__ volatile("cpuid" : "+a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx));
    if ((ecx >> 31) & 1) {
        penalty ^= 0x5877CAFEBABE1337ULL; // Hypervisor bit detected
    }

    // 2. TSC vs Execution Latency Ratio (QEMU/Unicorn JIT emulators have >50x jitter)
    uint64_t t0 = __builtin_ia32_rdtsc();
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    uint64_t t1 = __builtin_ia32_rdtsc();
    if ((t1 - t0) > 25000ULL) {
        penalty ^= 0xDEADBEEF5A5A1337ULL; // Emulation slow-path detected
    }
#endif
#if defined(_WIN32)
    // Secondary differential via QueryPerformanceCounter
    LARGE_INTEGER q0, q1, freq;
    if (QueryPerformanceFrequency(&freq) && QueryPerformanceCounter(&q0)) {
        for (int i = 0; i < 32; ++i) { YieldProcessor(); }
        QueryPerformanceCounter(&q1);
        if (q1.QuadPart == q0.QuadPart && (t1 - t0) > 1000ULL) {
            penalty ^= 0x5877AABBCCDDEEFFULL;
        }
    }
#endif
#elif defined(__aarch64__) || defined(_M_ARM64)
    // ARM64 Virtual Counter Overhead & Multi-Source Jitter Probe
    uint64_t t0, t1;
#if defined(_MSC_VER)
    t0 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
    for (int i = 0; i < 64; ++i) { __nop(); }
    t1 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
#endif
    if ((t1 - t0) > 30000ULL) {
        penalty ^= 0xFEEDFACE5877CAFEULL;
    }
#if defined(__APPLE__)
    // Multi-source differential verification (detecting timer spoofing / freeze)
    uint64_t m0 = mach_absolute_time();
    for (int i = 0; i < 32; ++i) { __asm__ volatile("nop"); }
    uint64_t m1 = mach_absolute_time();
    if (m1 == m0 && (t1 - t0) > 1000ULL) {
        penalty ^= 0x5877AABBCCDDEEFFULL;
    }
#endif
#endif

#if defined(__APPLE__)
    // In-memory DBI & Dynamic Instrumentation Detection (Frida, Gum, Substrate)
    uint32_t img_count = _dyld_image_count();
    for (uint32_t i = 0; i < img_count; ++i) {
        const char* name = _dyld_get_image_name(i);
        if (name) {
            for (const char* p = name; *p != '\0'; ++p) {
                // "frida"
                if ((p[0] == 'f' || p[0] == 'F') &&
                    (p[1] == 'r' || p[1] == 'R') &&
                    (p[2] == 'i' || p[2] == 'I') &&
                    (p[3] == 'd' || p[3] == 'D') &&
                    (p[4] == 'a' || p[4] == 'A')) {
                    penalty ^= 0xFA15ECAFE1337BEEULL;
                    break;
                }
                // "gum-"
                if ((p[0] == 'g' || p[0] == 'G') &&
                    (p[1] == 'u' || p[1] == 'U') &&
                    (p[2] == 'm' || p[2] == 'M') &&
                    p[3] == '-') {
                    penalty ^= 0xFA15ECAFE1337BEEULL;
                    break;
                }
                // "substrate"
                if ((p[0] == 's' || p[0] == 'S') &&
                    (p[1] == 'u' || p[1] == 'U') &&
                    (p[2] == 'b' || p[2] == 'B') &&
                    (p[3] == 's' || p[3] == 'S') &&
                    (p[4] == 't' || p[4] == 'T') &&
                    (p[5] == 'r' || p[5] == 'R') &&
                    (p[6] == 'a' || p[6] == 'A') &&
                    (p[7] == 't' || p[7] == 'T') &&
                    (p[8] == 'e' || p[8] == 'E')) {
                    penalty ^= 0xFA15ECAFE1337BEEULL;
                    break;
                }
            }
        }
    }
#endif

    return penalty;
}

} // namespace asgard_anti_emulation


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <sys/mman.h>
#include <pthread.h>
#include <unistd.h>
#elif defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#if !defined(ASGARD_API_HASH_RESOLVER_DEFINED) && !defined(ASGARD_CRYPTO_PRIMITIVES_DEFINED)
#define ASGARD_API_HASH_RESOLVER_DEFINED 1
#define ASGARD_CRYPTO_PRIMITIVES_DEFINED 1
static inline int asg_strcmp(const char* s1, const char* s2) noexcept {
    if (!s1 || !s2) return (s1 == s2) ? 0 : (s1 ? 1 : -1);
    while (*s1 && (*s1 == *s2)) { s1++; s2++; }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

#if defined(__APPLE__) && defined(__MACH__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

static inline uint64_t asg_read_uleb128(const uint8_t** p) noexcept {
    uint64_t result = 0;
    int shift = 0;
    while (1) {
        uint8_t byte = *(*p)++;
        result |= ((uint64_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) break;
        shift += 7;
    }
    return result;
}

static inline void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) noexcept {
    const uint8_t* p = node;
    uint64_t terminal_size = asg_read_uleb128(&p);
    if (terminal_size > 0 && cur_h == target_h) {
        uint64_t flags = asg_read_uleb128(&p);
        if ((flags & 0x08) == 0) {
            uint64_t addr = asg_read_uleb128(&p);
            return (void*)(addr + base);
        }
        return nullptr;
    }
    p += terminal_size;
    uint8_t child_count = *p++;
    for (uint8_t i = 0; i < child_count; i++) {
        uint32_t child_h = cur_h;
        while (*p) {
            child_h = (child_h ^ (uint8_t)*p++) * 0x01000193U;
        }
        p++;
        uint64_t child_offset = asg_read_uleb128(&p);
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static inline void* asgard_resolve_by_api_hash(uint32_t target_hash) noexcept {
    if (target_hash == 0) return nullptr;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header_64* hdr = (const struct mach_header_64*)_dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command* cmd = (const struct load_command*)(hdr + 1);
        uintptr_t linkedit_base = 0;
        uint32_t dataoff = 0;
        for (uint32_t c = 0; c < hdr->ncmds; c++) {
            if (cmd->cmd == LC_SEGMENT_64) {
                const struct segment_command_64* seg = (const struct segment_command_64*)cmd;
                if (asg_strcmp(seg->segname, "__LINKEDIT") == 0) {
                    linkedit_base = seg->vmaddr + slide - seg->fileoff;
                }
            } else if (cmd->cmd == 0x80000033 /* LC_DYLD_EXPORTS_TRIE */) {
                const struct linkedit_data_command* lc = (const struct linkedit_data_command*)cmd;
                dataoff = lc->dataoff;
            }
            cmd = (const struct load_command*)((const char*)cmd + cmd->cmdsize);
        }
        if (linkedit_base && dataoff) {
            const uint8_t* trie = (const uint8_t*)(linkedit_base + dataoff);
            void* resolved = asg_find_sym_in_trie(trie, trie, 0x811c9dc5U, target_hash, (uintptr_t)hdr);
            if (resolved) return resolved;
        }
    }
    return nullptr;
}
#else
static inline void* asgard_resolve_by_api_hash(uint32_t) noexcept { return nullptr; }
#endif
#endif

namespace asgard_memory {

struct DualMappedBuffer {
    void* rw_alias = nullptr; // Writable view for self-consumption / patching
    const void* rx_alias = nullptr; // Executable view for execution
    size_t size = 0;

    static inline bool is_supported() noexcept {
#if defined(__APPLE__)
        return true;
#elif defined(__linux__) && defined(MFD_CLOEXEC)
        return true;
#elif defined(_WIN32)
        return true;
#else
        return false;
#endif
    }

    static DualMappedBuffer allocate(size_t required_size) noexcept {
        DualMappedBuffer buf = {};
        size_t page_sz = 4096;

#if defined(_WIN32)
        SYSTEM_INFO si;
        GetSystemInfo(&si);
        if (si.dwPageSize) page_sz = (size_t)si.dwPageSize;
#elif defined(__APPLE__) || defined(__linux__)
        long sc_ps = sysconf(_SC_PAGESIZE);
        if (sc_ps > 0) page_sz = (size_t)sc_ps;
#endif
        buf.size = (required_size + page_sz - 1) & ~(page_sz - 1);

#if defined(__APPLE__)
#if defined(MAP_JIT)
        void* jptr = mmap(NULL, buf.size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
        if (jptr != MAP_FAILED) {
            buf.rw_alias = jptr;
            buf.rx_alias = jptr;
            return buf;
        }
#endif
        typedef kern_return_t (*asg_vm_alloc_fn_t)(vm_map_t, vm_address_t*, vm_size_t, int);
        typedef kern_return_t (*asg_vm_remap_fn_t)(vm_map_t, vm_address_t*, vm_size_t, vm_address_t, int, vm_map_t, vm_address_t, boolean_t, vm_prot_t*, vm_prot_t*, vm_inherit_t);
        typedef kern_return_t (*asg_vm_prot_fn_t)(vm_map_t, vm_address_t, vm_size_t, boolean_t, vm_prot_t);
        typedef kern_return_t (*asg_vm_dealloc_fn_t)(vm_map_t, vm_address_t, vm_size_t);
        static asg_vm_alloc_fn_t p_vm_alloc = nullptr;
        static asg_vm_remap_fn_t p_vm_remap = nullptr;
        static asg_vm_prot_fn_t  p_vm_prot  = nullptr;
        static asg_vm_dealloc_fn_t p_vm_dealloc = nullptr;
        if (!p_vm_alloc) p_vm_alloc = (asg_vm_alloc_fn_t)asgard_resolve_by_api_hash(0xA0E735E5U /* _vm_allocate */);
        if (!p_vm_remap) p_vm_remap = (asg_vm_remap_fn_t)asgard_resolve_by_api_hash(0xF034F085U /* _vm_remap */);
        if (!p_vm_prot)  p_vm_prot  = (asg_vm_prot_fn_t)asgard_resolve_by_api_hash(0x9857D42CU /* _vm_protect */);
        if (!p_vm_dealloc) p_vm_dealloc = (asg_vm_dealloc_fn_t)asgard_resolve_by_api_hash(0xE86CA72AU /* _vm_deallocate */);

        vm_address_t rw_addr = 0;
        if (p_vm_alloc && p_vm_alloc(mach_task_self(), &rw_addr, buf.size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (p_vm_remap && p_vm_remap(mach_task_self(), &rx_addr, buf.size, 0, VM_FLAGS_ANYWHERE,
                          mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                if (p_vm_prot && p_vm_prot(mach_task_self(), rx_addr, buf.size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) {
                    buf.rw_alias = (void*)rw_addr;
                    buf.rx_alias = (const void*)rx_addr;
                    return buf;
                }
            }
            if (p_vm_dealloc) p_vm_dealloc(mach_task_self(), rw_addr, buf.size);
        }
#elif defined(__linux__) && defined(MFD_CLOEXEC)
        int fd = memfd_create("asgard_dual_wx", MFD_CLOEXEC);
        if (fd >= 0) {
            if (ftruncate(fd, buf.size) == 0) {
                buf.rw_alias = mmap(NULL, buf.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                buf.rx_alias = mmap(NULL, buf.size, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
                close(fd);
                if (buf.rw_alias != MAP_FAILED && buf.rx_alias != MAP_FAILED) return buf;
            }
            close(fd);
        }
#elif defined(_WIN32)
        HANDLE hMap = CreateFileMappingW(INVALID_HANDLE_VALUE, NULL, PAGE_EXECUTE_READWRITE, 0, (DWORD)buf.size, NULL);
        if (hMap != NULL) {
            buf.rw_alias = MapViewOfFile(hMap, FILE_MAP_READ | FILE_MAP_WRITE, 0, 0, buf.size);
            buf.rx_alias = MapViewOfFile(hMap, FILE_MAP_READ | FILE_MAP_EXECUTE, 0, 0, buf.size);
            CloseHandle(hMap);
            if (buf.rw_alias != NULL && buf.rx_alias != NULL) {
                return buf;
            }
            if (buf.rw_alias != NULL) UnmapViewOfFile(buf.rw_alias);
            if (buf.rx_alias != NULL) UnmapViewOfFile((void*)buf.rx_alias);
            buf.rw_alias = nullptr;
            buf.rx_alias = nullptr;
        }
#endif
        return buf;
    }

    void release() noexcept {
#if defined(__APPLE__)
        if (rw_alias == rx_alias && rw_alias != nullptr) {
            munmap(rw_alias, size);
        } else {
            typedef kern_return_t (*asg_vm_dealloc_fn_t)(vm_map_t, vm_address_t, vm_size_t);
            static asg_vm_dealloc_fn_t p_vm_dealloc = nullptr;
            if (!p_vm_dealloc) p_vm_dealloc = (asg_vm_dealloc_fn_t)asgard_resolve_by_api_hash(0xE86CA72AU /* _vm_deallocate */);
            if (p_vm_dealloc) {
                if (rw_alias) p_vm_dealloc(mach_task_self(), (vm_address_t)rw_alias, size);
                if (rx_alias) p_vm_dealloc(mach_task_self(), (vm_address_t)rx_alias, size);
            }
        }
#elif defined(__linux__)
        if (rw_alias && rw_alias != MAP_FAILED) munmap(rw_alias, size);
        if (rx_alias && rx_alias != MAP_FAILED) munmap((void*)rx_alias, size);
#elif defined(_WIN32)
        if (rw_alias != nullptr) UnmapViewOfFile(rw_alias);
        if (rx_alias != nullptr) UnmapViewOfFile((void*)rx_alias);
#endif
        rw_alias = nullptr;
        rx_alias = nullptr;
        size = 0;
    }
};

} // namespace asgard_memory


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif
#endif

#if defined(ASGARD_SMC_STRICT)
#  if !defined(__APPLE__) && (!defined(__linux__) || !defined(MFD_CLOEXEC)) && !defined(_WIN32)
#    error "ASGARD Security Violation: Strict SMC requested (max_security profile), but target platform does not support dual-mapping W^X memory aliasing!"
#  endif
#endif

namespace asgard_smc {

enum SmcStatus : uint32_t {
    SMC_STATUS_NOT_EXECUTED = 0,
    SMC_STATUS_ACTIVE       = 1,
    SMC_STATUS_DEGRADED     = 2,
    SMC_STATUS_FAILED       = 3
};

inline volatile uint32_t g_smc_status = SMC_STATUS_NOT_EXECUTED;

static inline __attribute__((always_inline)) uint32_t get_smc_status() noexcept {
    return g_smc_status;
}

static inline __attribute__((always_inline)) const char* get_smc_status_string() noexcept {
    switch (g_smc_status) {
        case SMC_STATUS_ACTIVE:   return "FULL_SMC";
        case SMC_STATUS_DEGRADED: return "DEGRADED_NO_DUAL_MAP";
        case SMC_STATUS_FAILED:   return "FAILED_VERIFICATION";
        default:                  return "NOT_EXECUTED";
    }
}

static inline __attribute__((always_inline)) bool is_smc_active() noexcept {
    return g_smc_status == SMC_STATUS_ACTIVE;
}

static inline __attribute__((always_inline)) bool is_smc_degraded() noexcept {
    return g_smc_status == SMC_STATUS_DEGRADED;
}

// Introspective Self-Modifying Code (SMC) + Hardware Timing Probe (Morse & Kojsik, 2026)
static inline __attribute__((always_inline)) uint64_t execute_introspective_smc_probe(uint64_t seed) noexcept {
    uint64_t penalty = 0;
    asgard_memory::DualMappedBuffer buf = asgard_memory::DualMappedBuffer::allocate(4096);
    if (!buf.rw_alias || !buf.rx_alias) {
#if defined(ASGARD_SMC_STRICT)
        g_smc_status = SMC_STATUS_FAILED;
#if defined(ASGARD_DEBUG_DIAGNOSTICS)
        fprintf(stderr, "[SMC_ERROR] Strict SMC required by max_security profile, but dual-mapping buffer allocation failed!\n");
#endif
        return 0xDEAD53C0CAFE0001ULL; // Non-zero penalty that corrupts VM context and forces abort/divergence
#else
        g_smc_status = SMC_STATUS_DEGRADED;
#if defined(ASGARD_DEBUG_DIAGNOSTICS)
        fprintf(stderr, "[SMC_WARN] Dual-mapping unsupported or failed; SMC degraded gracefully.\n");
#endif
        return 0; // If dual-mapping is unsupported and not in strict mode, degrade gracefully
#endif
    }

#if defined(__aarch64__) || defined(_M_ARM64)
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif
    // Emit ARM64:
    // movz w0, #0x5877, lsl #0  -> 0x528b0ee0
    // add w0, w0, #0x12         -> 0x11004800
    // ret                       -> 0xd65f03c0
    uint32_t* code_rw = (uint32_t*)buf.rw_alias;
    code_rw[0] = 0x528b0ee0; // movz w0, #0x5877
    code_rw[1] = 0x11004800; // add w0, w0, #0x12
    code_rw[2] = 0xd65f03c0; // ret

    uint64_t t0;
#if defined(_MSC_VER)
    t0 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
#endif

    // Dynamic Self-Modification via RW alias: mutate immediate in add (bits 10..21)
    uint32_t imm_val = (uint32_t)(seed & 0x7F);
    code_rw[1] = 0x11000000 | (imm_val << 10);

    // Hardware icache invalidation & pipeline clear
#if defined(__APPLE__)
    sys_dcache_flush(buf.rw_alias, 16);
    sys_icache_invalidate((void*)buf.rx_alias, 16);
    pthread_jit_write_protect_np(1);
#elif defined(_WIN32)
    FlushInstructionCache(GetCurrentProcess(), (void*)buf.rx_alias, 16);
#else
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);
#endif

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif

    uint64_t t1;
#if defined(_MSC_VER)
    t1 = (uint64_t)_ReadStatusReg(ARM64_CNTVCT);
#else
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
#endif

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL; // JIT/hypervisor emulation slow-path
    }
#elif defined(__x86_64__) || defined(_M_X64)
    // Emit x86_64:
    // mov eax, 0x5877  -> B8 77 58 00 00
    // add eax, 0x12    -> 05 12 00 00 00
    // ret              -> C3
    uint8_t* code_rw = (uint8_t*)buf.rw_alias;
    code_rw[0] = 0xB8; code_rw[1] = 0x77; code_rw[2] = 0x58; code_rw[3] = 0x00; code_rw[4] = 0x00;
    code_rw[5] = 0x05; code_rw[6] = 0x12; code_rw[7] = 0x00; code_rw[8] = 0x00; code_rw[9] = 0x00;
    code_rw[10] = 0xC3;

#if defined(_MSC_VER)
    uint64_t t0 = __rdtsc();
#else
    uint64_t t0 = __builtin_ia32_rdtsc();
#endif

    // Dynamic Self-Modification via RW alias
    uint8_t imm_val = (uint8_t)(seed & 0x7F);
    code_rw[6] = imm_val;

    // Hardware icache invalidation & pipeline clear
#if defined(_WIN32)
    FlushInstructionCache(GetCurrentProcess(), (void*)buf.rx_alias, 16);
#else
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);
#endif

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

#if defined(_MSC_VER)
    uint64_t t1 = __rdtsc();
#else
    uint64_t t1 = __builtin_ia32_rdtsc();
#endif

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL;
    }
#else
#if defined(ASGARD_SMC_STRICT)
    penalty ^= 0xDEAD53C0CAFE0002ULL;
#endif
#endif

    buf.release();
    if (penalty != 0) {
        g_smc_status = SMC_STATUS_FAILED;
    } else {
        g_smc_status = SMC_STATUS_ACTIVE;
    }
    return penalty;
}

} // namespace asgard_smc


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <mach/thread_status.h>
#include <mach/vm_map.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#elif defined(__linux__)
#include <stdio.h>
#include <string.h>
#include <link.h>
#elif defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace asgard_mem_integrity {

static inline __attribute__((always_inline)) uint64_t compute_section_integrity_hash() noexcept {
    uint64_t h = 0x5877CAFE1337BEEFULL;

#if defined(__APPLE__)
    const struct mach_header_64* mh = (const struct mach_header_64*)_dyld_get_image_header(0);
    if (mh) {
        unsigned long text_sz = 0;
        uint8_t* text_p = getsectiondata(mh, "__TEXT", "__text", &text_sz);
        if (text_p && text_sz > 0) {
            size_t sample = text_sz < 65536 ? text_sz : 65536;
            for (size_t i = 0; i + 8 <= sample; i += 32) {
                uint64_t w = *reinterpret_cast<const uint64_t*>(text_p + i);
                h ^= w * 0x9E3779B97F4A7C15ULL;
                h = (h << 13) | (h >> 51);
                h *= 0x100000001B3ULL;
            }
        }
        unsigned long const_sz = 0;
        uint8_t* const_p = getsectiondata(mh, "__TEXT", "__const", &const_sz);
        if (const_p && const_sz > 0) {
            size_t sample = const_sz < 16384 ? const_sz : 16384;
            for (size_t i = 0; i + 8 <= sample; i += 32) {
                uint64_t w = *reinterpret_cast<const uint64_t*>(const_p + i);
                h ^= w * 0xBF58476D1CE4E5B9ULL;
                h = (h << 17) | (h >> 47);
            }
        }
    }
#elif defined(__linux__) && !defined(_MSC_VER)
    struct PhdrContext {
        uint64_t hash;
        bool found;
    } pctx = { h, false };

    dl_iterate_phdr([](struct dl_phdr_info* info, size_t, void* data) -> int {
        auto* ctx = reinterpret_cast<PhdrContext*>(data);
        if (ctx->found) return 1;
        for (int i = 0; i < info->dlpi_phnum; ++i) {
            const ElfW(Phdr)& ph = info->dlpi_phdr[i];
            if (ph.p_type == PT_LOAD && (ph.p_flags & PF_X)) {
                const uint8_t* base = reinterpret_cast<const uint8_t*>(info->dlpi_addr + ph.p_vaddr);
                size_t sz = ph.p_filesz < 65536 ? ph.p_filesz : 65536;
                for (size_t j = 0; j + 8 <= sz; j += 32) {
                    uint64_t w = *reinterpret_cast<const uint64_t*>(base + j);
                    ctx->hash ^= w * 0x9E3779B97F4A7C15ULL;
                    ctx->hash = (ctx->hash << 13) | (ctx->hash >> 51);
                    ctx->hash *= 0x100000001B3ULL;
                }
                ctx->found = true;
            }
        }
        return ctx->found ? 1 : 0;
    }, &pctx);
    h = pctx.hash;
#elif defined(_WIN32)
    HMODULE hMod = GetModuleHandleA(nullptr);
    if (hMod) {
        const uint8_t* base = reinterpret_cast<const uint8_t*>(hMod);
        const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if (dos->e_magic == IMAGE_DOS_SIGNATURE) {
            const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
            if (nt->Signature == IMAGE_NT_SIGNATURE) {
                const auto* sec = IMAGE_FIRST_SECTION(nt);
                for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++sec) {
                    if ((sec->Characteristics & IMAGE_SCN_MEM_EXECUTE) && !(sec->Characteristics & IMAGE_SCN_MEM_WRITE)) {
                        const uint8_t* p = base + sec->VirtualAddress;
                        size_t sz = sec->Misc.VirtualSize < 65536 ? sec->Misc.VirtualSize : 65536;
                        for (size_t j = 0; j + 8 <= sz; j += 32) {
                            uint64_t w = *reinterpret_cast<const uint64_t*>(p + j);
                            h ^= w * 0x9E3779B97F4A7C15ULL;
                            h = (h << 13) | (h >> 51);
                            h *= 0x100000001B3ULL;
                        }
                    }
                }
            }
        }
    }
#endif

    return h ^ (h >> 31);
}

// MEM-SBOM Style Memory Forensics & Injection Scanner
static inline __attribute__((always_inline)) uint64_t evaluate_memory_integrity() noexcept {
    uint64_t penalty = 0;

    // 1. Executable Section Dynamic Drift Check
    static uint64_t initial_sect_hash = 0;
    uint64_t current_sect_hash = compute_section_integrity_hash();
    if (initial_sect_hash == 0) {
        initial_sect_hash = current_sect_hash;
    } else if (current_sect_hash != initial_sect_hash) {
        penalty ^= 0x5877BAADC0DEDEADULL;
    }

#if defined(__APPLE__)
    // 2. Thread Debug Register Inspection (DR0-DR3 / DBGBVR detection)
    mach_port_t thread = mach_thread_self();
#if defined(__aarch64__) && defined(ARM_DEBUG_STATE64)
    arm_debug_state64_t dbg_state = {};
    mach_msg_type_number_t count = ARM_DEBUG_STATE64_COUNT;
    if (thread_get_state(thread, ARM_DEBUG_STATE64, (thread_state_t)&dbg_state, &count) == KERN_SUCCESS) {
        for (int i = 0; i < 16; ++i) {
            if (dbg_state.__bcr[i] & 1) { // Breakpoint control enabled
                penalty ^= 0xCAFEBABE00000001ULL ^ ((uint64_t)i << 32);
            }
        }
    }
#elif defined(__x86_64__) && defined(x86_DEBUG_STATE64)
    x86_debug_state64_t dbg_state = {};
    mach_msg_type_number_t count = x86_DEBUG_STATE64_COUNT;
    if (thread_get_state(thread, x86_DEBUG_STATE64, (thread_state_t)&dbg_state, &count) == KERN_SUCCESS) {
        if (dbg_state.__dr7 & 0x000000FF) { // DR0-DR3 active
            penalty ^= 0xCAFEBABE00000002ULL;
        }
    }
#endif
    mach_port_deallocate(mach_task_self(), thread);

    // 3. Suspicious Anonymous RWX Memory Scanner (Anti-Frida / Shellcode Injection)
    vm_address_t address = 0;
    vm_size_t size = 0;
    mach_port_t object_name = MACH_PORT_NULL;
    struct vm_region_basic_info_64 info = {};
    mach_msg_type_number_t info_cnt = VM_REGION_BASIC_INFO_COUNT_64;
    int suspicious_rwx = 0;
    while (vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &info_cnt, &object_name) == KERN_SUCCESS) {
        if ((info.protection & VM_PROT_WRITE) && (info.protection & VM_PROT_EXECUTE)) {
            suspicious_rwx++;
        }
        address += size;
    }
    if (suspicious_rwx > 2) {
        penalty ^= 0x5877F81DA0000001ULL;
    }
#elif defined(__linux__)
    FILE* fp = fopen("/proc/self/maps", "r");
    if (fp) {
        char line[512];
        while (fgets(line, sizeof(line), fp)) {
            if (strstr(line, "rwxp")) { // Anonymous RWX page
                penalty ^= 0x5877F81DA0000002ULL;
                break;
            }
        }
        fclose(fp);
    }
#elif defined(_WIN32)
    // Thread Debug Register Inspection (DR0-DR3 / DR7 detection)
    CONTEXT dbg_ctx = {};
    dbg_ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    if (GetThreadContext(GetCurrentThread(), &dbg_ctx)) {
#if defined(_M_ARM64) || defined(__aarch64__)
        for (size_t b = 0; b < sizeof(dbg_ctx.Bcr)/sizeof(dbg_ctx.Bcr[0]); ++b) {
            if (dbg_ctx.Bcr[b] & 1) {
                penalty ^= 0xCAFEBABE00000002ULL;
                break;
            }
        }
#elif defined(_M_X64) || defined(_M_IX86) || defined(__x86_64__) || defined(__i386__)
        if (dbg_ctx.Dr7 & 0x000000FF) {
            penalty ^= 0xCAFEBABE00000002ULL;
        }
#endif
    }

    // Suspicious Anonymous RWX Memory Scanner (VirtualQuery)
    MEMORY_BASIC_INFORMATION mbi = {};
    const uint8_t* addr = nullptr;
    int suspicious_rwx = 0;
    while (VirtualQuery((LPCVOID)addr, &mbi, sizeof(mbi)) == sizeof(mbi)) {
        if ((mbi.State == MEM_COMMIT) && (mbi.Protect == PAGE_EXECUTE_READWRITE)) {
            suspicious_rwx++;
        }
        addr = (const uint8_t*)mbi.BaseAddress + mbi.RegionSize;
        if (addr == nullptr || mbi.RegionSize == 0) break;
    }
    if (suspicious_rwx > 2) {
        penalty ^= 0x5877F81DA0000003ULL;
    }
#endif

    return penalty;
}

} // namespace asgard_mem_integrity


#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <signal.h>
#include <string.h>
#include <atomic>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/thread_act.h>
#include <sys/ucontext.h>
#elif defined(__linux__)
#include <ucontext.h>
#endif

#define ASGARD_NANOMITES_ENABLED 1

namespace asgard_nanomites {

struct NanomiteEntry {
    uint32_t trap_id;
    uint64_t target_true;
    uint64_t target_false;
    uint64_t key;
};

// Cryptographically keyed 64-bit Murmur3 Finalizer Mix
static inline uint64_t murmur3_mix64(uint64_t k) noexcept {
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33;
    return k;
}

class NanomiteDispatcher {
public:
    static constexpr size_t TABLE_CAPACITY = 2048;
    NanomiteEntry table[TABLE_CAPACITY];
    volatile uint32_t current_trap_id = 0;
    volatile uint32_t current_condition = 0;
    volatile uint64_t resolved_target = 0;
    volatile uint64_t traps_handled = 0;
    uint32_t seed = 0x5877CAFEU;
    bool installed = false;

    void register_nanomite(uint32_t trap_id, uint64_t t_true, uint64_t t_false, uint64_t key) noexcept {
        size_t idx = (size_t)(trap_id % TABLE_CAPACITY);
        table[idx].trap_id = trap_id;
        table[idx].target_true = t_true ^ key;
        table[idx].target_false = t_false ^ key;
        table[idx].key = key;
    }

    uint64_t resolve_target(uint32_t trap_id, uint32_t cond, uint64_t pc_val) noexcept {
        volatile uint64_t mixed = murmur3_mix64(pc_val ^ (uint64_t)seed);
        (void)mixed;
        size_t idx = (size_t)(trap_id % TABLE_CAPACITY);
        if (table[idx].trap_id == trap_id) {
            uint64_t enc = cond ? table[idx].target_true : table[idx].target_false;
            return enc ^ table[idx].key;
        }
        return 0;
    }
};

/* P0-02a: The SIGTRAP / VEH handler executes synchronously on the trapping
   thread, so all per-trap communication state (current_trap_id, current_condition,
   resolved_target, the keyed nanomite table) is thread-local. This removes the
   inter-thread data race when several threads run virtualized nanomite code
   concurrently without any locking on the hot path. */
static thread_local NanomiteDispatcher g_nanomite_dispatcher;

#if defined(__APPLE__)
static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    g_nanomite_dispatcher.installed = true;
}
#elif defined(_WIN32)
static LONG WINAPI nanomite_vectored_handler(PEXCEPTION_POINTERS pExceptionInfo) {
    if (pExceptionInfo && pExceptionInfo->ExceptionRecord) {
        DWORD code = pExceptionInfo->ExceptionRecord->ExceptionCode;
        if (code == EXCEPTION_BREAKPOINT || code == EXCEPTION_ILLEGAL_INSTRUCTION) {
            uint64_t pc_val = 0;
#if defined(_M_X64) || defined(__x86_64__)
            if (pExceptionInfo->ContextRecord) {
                pc_val = (uint64_t)pExceptionInfo->ContextRecord->Rip;
            }
#elif defined(_M_ARM64) || defined(__aarch64__)
            if (pExceptionInfo->ContextRecord) {
                pc_val = (uint64_t)pExceptionInfo->ContextRecord->Pc;
            }
#endif
            g_nanomite_dispatcher.traps_handled = g_nanomite_dispatcher.traps_handled + 1;
            uint32_t tid = g_nanomite_dispatcher.current_trap_id;
            uint32_t cond = g_nanomite_dispatcher.current_condition;
            g_nanomite_dispatcher.resolved_target = g_nanomite_dispatcher.resolve_target(tid, cond, pc_val);
#if defined(_M_X64) || defined(__x86_64__)
            if (code == EXCEPTION_BREAKPOINT && pExceptionInfo->ContextRecord) {
                pExceptionInfo->ContextRecord->Rip += 1;
            }
#elif defined(_M_ARM64) || defined(__aarch64__)
            if (code == EXCEPTION_BREAKPOINT && pExceptionInfo->ContextRecord) {
                pExceptionInfo->ContextRecord->Pc += 4;
            }
#endif
            return EXCEPTION_CONTINUE_EXECUTION;
        }
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    /* Process-wide one-shot guard: per-thread dispatchers must not re-register
       the VEH chain on every thread (leaks handlers under heavy threading). */
    static std::atomic<bool> g_veh_installed{false};
    if (!g_veh_installed.exchange(true)) {
        AddVectoredExceptionHandler(1, nanomite_vectored_handler);
    }
    g_nanomite_dispatcher.installed = true;
}
#elif defined(__linux__) && !defined(_MSC_VER)
static void nanomite_trap_handler(int sig, siginfo_t* info, void* ucontext_ptr) {
    (void)sig; (void)info;
    uint64_t pc_val = 0;
#if defined(__APPLE__)
    ucontext_t* uc = (ucontext_t*)ucontext_ptr;
#if defined(__arm64__) || defined(__aarch64__)
    if (uc && uc->uc_mcontext) {
        pc_val = (uint64_t)uc->uc_mcontext->__ss.__pc;
    }
#elif defined(__x86_64__)
    if (uc && uc->uc_mcontext) {
        pc_val = (uint64_t)uc->uc_mcontext->__ss.__rip;
    }
#endif
#elif defined(__linux__)
    ucontext_t* uc = (ucontext_t*)ucontext_ptr;
#if defined(__arm64__) || defined(__aarch64__)
    if (uc) {
        pc_val = (uint64_t)uc->uc_mcontext.pc;
    }
#elif defined(__x86_64__)
    if (uc) {
        pc_val = (uint64_t)uc->uc_mcontext.gregs[REG_RIP];
    }
#endif
#endif

    g_nanomite_dispatcher.traps_handled = g_nanomite_dispatcher.traps_handled + 1;
    uint32_t tid = g_nanomite_dispatcher.current_trap_id;
    uint32_t cond = g_nanomite_dispatcher.current_condition;
    g_nanomite_dispatcher.resolved_target = g_nanomite_dispatcher.resolve_target(tid, cond, pc_val);
}

static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    /* Process-wide one-shot guard: sigaction() is process-wide, so per-thread
       dispatchers only need to install the signal handler once. */
    static std::atomic<bool> g_sigaction_installed{false};
    if (!g_sigaction_installed.exchange(true)) {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_sigaction = nanomite_trap_handler;
        sa.sa_flags = SA_SIGINFO;
        sigemptyset(&sa.sa_mask);
        sigaction(SIGTRAP, &sa, NULL);
        sigaction(SIGILL, &sa, NULL);
    }
    g_nanomite_dispatcher.installed = true;
}
#else
static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    g_nanomite_dispatcher.installed = true;
}
#endif

} // namespace asgard_nanomites


// GPU-Synthesized MBA Substitution Matrix (SAC Diffusion: 53.08%)

static constexpr uint64_t GPU_MBA_FWD_MATRIX[16][16] = {
    {
        0x0e673520c475b909ULL,
        0x0470bcb48ea6c400ULL,
        0x7b66b38d8a4ab412ULL,
        0x7559f5ee279ee87dULL,
        0x4ab7ee276c98967eULL,
        0x5d2ac89ccacdd09bULL,
        0x2d99defbbf016502ULL,
        0x769a65d585a3c137ULL,
        0x260e56879fec17faULL,
        0x560fb6676feb4fa8ULL,
        0x35638b095abdce07ULL,
        0x6adbed845dbbf173ULL,
        0x2bf953299cf718ecULL,
        0x5d251745ec9ad916ULL,
        0x7441fbc3142c433aULL,
        0x02d9f8a54e6cab4eULL
    },
    {
        0x0000000000000000ULL,
        0x08cfcd9a01cef68dULL,
        0x3a6f8ff83aa93d0cULL,
        0x6565eb8a8d226ee4ULL,
        0x362e582758e18921ULL,
        0x5cb679c303b3ad78ULL,
        0x1009fcaf89d19891ULL,
        0x002bcebeff4a9439ULL,
        0x6aba6301730f0481ULL,
        0x72483f4a2c871797ULL,
        0x55eab74851dc8c9eULL,
        0x3e6abdbbb2b9acdaULL,
        0x69fe72bdb6955f79ULL,
        0x1b4977c5f48037cfULL,
        0x131e560214225ba0ULL,
        0x10b83aaefba4d7f4ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x373a9f999166f0c5ULL,
        0x33c25c351f0a8f33ULL,
        0x447b634fda9ee1a0ULL,
        0x507c0963c7f18022ULL,
        0x1dd94e315378f40dULL,
        0x554d7bdb977dd4c7ULL,
        0x7c448f3232dfd151ULL,
        0x268859d733185350ULL,
        0x42425bbcabf1c65cULL,
        0x39fd33b6d5ffac20ULL,
        0x1ff45ac4d3c20497ULL,
        0x46b505c2b968dc37ULL,
        0x688201cffbb6a126ULL,
        0x6bc681f077b1fdfdULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x5bdcb14e44f6b30dULL,
        0x3fe296effe032234ULL,
        0x1808de43a663e35dULL,
        0x69551c93c71aab2dULL,
        0x69503d7cdd95429fULL,
        0x0fa83f58cea03e13ULL,
        0x2b51f349cebe36f5ULL,
        0x4bbebda9109ee455ULL,
        0x6c37a3d9fe71f0daULL,
        0x49e9dd54a55b7957ULL,
        0x11398500efb0a256ULL,
        0x058c161a85cbd810ULL,
        0x1dcf4a8ff49c7471ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x3bac529e5d402637ULL,
        0x6d037bf66e9d32f8ULL,
        0x0fec6813c79b60e8ULL,
        0x17855b7eabe3d5e2ULL,
        0x50faee47ea4ce201ULL,
        0x127a3045aefe9f59ULL,
        0x3ec1e2a91715f477ULL,
        0x5c000a7d079ba575ULL,
        0x1dc9ecc565bfa32cULL,
        0x560ecf569dd0aa54ULL,
        0x49a84f30e50bc907ULL,
        0x480d6a5592f7b02fULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x1b925647d09d9761ULL,
        0x613b43884a28cbadULL,
        0x5a558b416f969d60ULL,
        0x6c100e5c415a6239ULL,
        0x0940e555d94f9407ULL,
        0x509ac926db111e5fULL,
        0x1f44431233366c5aULL,
        0x359a3ae9f263c04aULL,
        0x0a021d19c604c7d7ULL,
        0x2ca842e4e3cc2ac0ULL,
        0x0e512d8b1cd85756ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x41beb9ce66b514c3ULL,
        0x25ee87b1abe1772fULL,
        0x5f0355fe0968da7cULL,
        0x34a96e308fda18afULL,
        0x27031cbed2351052ULL,
        0x1623eb5bad177219ULL,
        0x3344dbf0e4db7ff2ULL,
        0x3938bdf25dc22e21ULL,
        0x735df4a7f42d16fdULL,
        0x3778ca039b7d8eb3ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x62eebc3bc2a824d3ULL,
        0x64f2b2d5185ac126ULL,
        0x5b602116cec968d2ULL,
        0x42cf6c2554b403f9ULL,
        0x4ffb6fdf1942a7e0ULL,
        0x5423de9732dd0b3aULL,
        0x066ce614af983486ULL,
        0x7fd8660edef70dfdULL,
        0x1502f3d6d4a60da0ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x34a4e11a6f3ef5f7ULL,
        0x4dc0c79de1d9d4bcULL,
        0x181eda8e6c49ba26ULL,
        0x7392eb73d4c95f91ULL,
        0x482ae213ae536f4bULL,
        0x6981c5226d603ee4ULL,
        0x4afa29ed6cb6d9fbULL,
        0x0638193726038d23ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x26382e04053546f1ULL,
        0x29675ab24458d38aULL,
        0x288403cb72ef56b0ULL,
        0x58cbd6a978e82eb5ULL,
        0x11a86b37b5b63150ULL,
        0x47978881a6d62612ULL,
        0x1163246185e00992ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x2533b30c4bdbbb99ULL,
        0x68fe1442542dcf62ULL,
        0x42e9e831ef4bf4ddULL,
        0x57d066adc04bbb6eULL,
        0x0a7c8a721f2bdf34ULL,
        0x11528ce200bb4f8eULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x6ad6c27c10432141ULL,
        0x7e128cfae4c12badULL,
        0x3816ad5880bf3076ULL,
        0x458c7c64b3a75028ULL,
        0x59ee7c147f256709ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x302c21c8b0da91afULL,
        0x58a68b3be002acebULL,
        0x514c0ce3ccc79780ULL,
        0x35c393359ef8a857ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x66cf394b56bbf7b9ULL,
        0x48fc85d69e913031ULL,
        0x2489f434ab5326baULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x03c4f424e3d85be9ULL,
        0x422ca3a9be4dcd29ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x086c32eaa257ee27ULL
    }
};

static constexpr uint64_t GPU_MBA_INV_MATRIX[16][16] = {
    {
        0x8defd94eba0fa539ULL,
        0x1187f300f4dacc00ULL,
        0x871cfcf832a989e6ULL,
        0xc9a3b70967d9477dULL,
        0x9b68c776e51768a2ULL,
        0xc82de2b6fcba8498ULL,
        0xa93851de41ebf635ULL,
        0x8b8b7a7051dea3f7ULL,
        0x2ca3fcf9e0764e0fULL,
        0xa9f0c79e26b5e4c0ULL,
        0x541606098e8b71f7ULL,
        0x093db57b2b718d9fULL,
        0xeab8484309cd8f9cULL,
        0x9a8921561c9b5a7fULL,
        0x7f6e1a5d6e2a2c30ULL,
        0x22e4c2a3f1730c26ULL
    },
    {
        0x0000000000000000ULL,
        0x4e7604f688c8bc45ULL,
        0x01d306f6e45340f4ULL,
        0x77da1750617af3b0ULL,
        0xd7971d4f77540f7dULL,
        0x9afc95fd3879bf38ULL,
        0x4a1192f3953f623dULL,
        0x0bdf3175665b453eULL,
        0x6ce04eace652ed4eULL,
        0x748b42623f18cd59ULL,
        0x376f3126a876c6a9ULL,
        0x7a50bb0c014f19c8ULL,
        0xa6d8d6eeeb350fdfULL,
        0xcc9c11c2aee13b09ULL,
        0x6621b45240ad69ddULL,
        0xb5c41d12d431038cULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xae39a0154ddf0e0dULL,
        0x446e341d2f4e0bcdULL,
        0x9f4ab26615c0d0a4ULL,
        0x38b8fbe3adfe9b0dULL,
        0x8227a5e377011637ULL,
        0x87ade94c8f2f504bULL,
        0x51bc19051b096c4bULL,
        0x054c20b04d1dd9fdULL,
        0x49ae07cac8f9d477ULL,
        0x8d259f5a9c88e650ULL,
        0xc18358cf90992c19ULL,
        0x7a370da7c58f8302ULL,
        0x8fd668e7952d3473ULL,
        0x6c7612f126b625e0ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xbb28853e0fc753c5ULL,
        0x8b6c149100a7ffe4ULL,
        0xff19614d483e62efULL,
        0x410f98f05aa20314ULL,
        0x6368c115668a970bULL,
        0xa591c009d3cbb1acULL,
        0x9fb9af31b5c71a28ULL,
        0xbaeb15829257b7cfULL,
        0x1b761ffb6f04d3c6ULL,
        0x918ace93b842180cULL,
        0xd27eff883b31b2d1ULL,
        0x85c0b7522726d220ULL,
        0x28aa0a6416c61689ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x7459450025366f87ULL,
        0x67d15e49d01bba38ULL,
        0x6885fff459679df0ULL,
        0xf5cba086f464e3f6ULL,
        0x585a5984a637476bULL,
        0x917359466db58fa9ULL,
        0x49b989db3ac1da1dULL,
        0xd1c403e411800008ULL,
        0x9030c936fa24ce17ULL,
        0x79afaec2311a1be1ULL,
        0x1b2c1812d1fe26d9ULL,
        0xc03c7e96eca71086ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x47cffebe9fd34ca1ULL,
        0x26b71d9f266073d1ULL,
        0xe67dbd42ebd49e1bULL,
        0x31a585ebf43c991fULL,
        0x27a5c71486d9d3d0ULL,
        0x73e9aea40cc73f22ULL,
        0x91a4181007a98d4aULL,
        0x0ed024db6c288b4bULL,
        0x18617afd7307ff51ULL,
        0x74f4657d0c10ad96ULL,
        0x0633874e0af65571ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xcdc47f46a03f3bebULL,
        0x0660199cbae2c4d9ULL,
        0x06b15c213557f73aULL,
        0xb7c216a6b250cfd1ULL,
        0x8b53d291cdb1d55bULL,
        0x7b1a1816a8e93d8dULL,
        0xcfb2c5708892e87bULL,
        0xa4211026c1463f56ULL,
        0xfe94a03cbac747f2ULL,
        0x9f2df1b2dbac9803ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x2974fd884ffbd35bULL,
        0xb58687259cf70ef2ULL,
        0x6699dd5df841b3c2ULL,
        0x028012f317374105ULL,
        0x7a076f0d1c67f904ULL,
        0x0d798c1c94f9e0c3ULL,
        0x4a72b4dd03d5916fULL,
        0x547fd7830968cd24ULL,
        0x4a22c4bea0b368ebULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x5eecc77958605bc7ULL,
        0x6e81a99061ccc39cULL,
        0x58e882654472d20eULL,
        0xe5090c672067646dULL,
        0x8a795bbc23acc8d8ULL,
        0x1a90a35023eae44aULL,
        0xc6bb1abba2e6c939ULL,
        0xccec10e4e7222ecbULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xe84675e4aa7eea11ULL,
        0x7ab17f86c2132446ULL,
        0x0337cef3427fbc84ULL,
        0x3f25a379b5dc7e77ULL,
        0x3dedf28b5c54933fULL,
        0x5303b127725883cfULL,
        0x32f10ed48027b2c8ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xfab42c23b27368a9ULL,
        0xdb46e78b3fb006ceULL,
        0xb83fa48a797ba1abULL,
        0x135b9fb3de04e19dULL,
        0x99b64d2ef9128b17ULL,
        0x333a518a59700d6aULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x608cf5bbe49a6ec1ULL,
        0x03c8165e9c30305dULL,
        0x95c35f446a450e83ULL,
        0x2cc8792eb6624cfdULL,
        0x776cd685d8cd196fULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x559662f7a3dd654fULL,
        0x5c4b496092e737d3ULL,
        0xe1b23f29cbd38615ULL,
        0x6b1f1a1c819b0724ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xe35d2cdc9846de89ULL,
        0x333bd555bdd6182fULL,
        0xaa77d231d54c0cf9ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0xa7b89d47d89c2c59ULL,
        0x6ac88544d35eefa9ULL
    },
    {
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x0000000000000000ULL,
        0x1826bd493944a197ULL
    }
};


namespace vanguard_threaded_vm {
                                
                                static const asgard_ext_sym_t g_external_symbols[] = {
                                    {
                                        0x00000000U,
                                        0x00000000U,
                                        0,
                                        { 0 }
                                    }
                                };
                                
                                static AsgardConstantEntry g_asgard_constants[] = {
                                    { 0x00000000U, 0x00000000U, nullptr, nullptr, 0x0000000000000000ULL, 0x00000000U, 1 }
                                };
                                
                                static inline void* asgard_resolve_constant(uint32_t hash, uint32_t alt_hash) noexcept {
    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {
        AsgardConstantEntry* c = &g_asgard_constants[i];
        if (c->size > 0) {
            if (c->hash == hash ||
                (alt_hash != 0 && c->hash == alt_hash) ||
                (c->alt_hash != 0 && (c->alt_hash == hash || c->alt_hash == alt_hash))) {
                if (__builtin_expect(!c->ready, 0)) {
                    for (size_t j = 0; j < c->size; ++j) {
                        uint8_t k = (uint8_t)(((c->xor_key >> ((j & 3) * 8)) ^ (j * 0x5D + 0x33)) & 0xFF);
                        c->dec_data[j] = (uint8_t)(c->enc_data[j] ^ k);
                    }
                    c->dec_data[c->size] = 0;
                    c->ready = 1;
                }
                return (void*)c->dec_data;
            }
        }
    }
    return nullptr;
}

static inline void* asgard_resolve_constant_name(const char* name) noexcept {
    if (!name || name[0] == '\0') return nullptr;
    uint32_t h = 0x811C9DC5U;
    const char* p = name;
    while (*p) {
        h = (h ^ (uint8_t)*p++) * 0x01000193U;
    }
    uint32_t ah = 0;
    if (name[0] == '_') {
        ah = 0x811C9DC5U;
        p = name + 1;
        while (*p) {
            ah = (ah ^ (uint8_t)*p++) * 0x01000193U;
        }
    }
    return asgard_resolve_constant(h, ah);
}

static inline void* asgard_resolve_sym_idx(int32_t sym_idx) noexcept {
    if (sym_idx < 0 || (size_t)sym_idx >= sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        return nullptr;
    }
    const asgard_ext_sym_t* sym = &g_external_symbols[sym_idx];
    if (sym->len == 0) return nullptr;

    void* sym_ptr = asgard_resolve_constant(sym->hash, sym->alt_hash);
    if (sym_ptr) return sym_ptr;

#if defined(__APPLE__) && defined(__MACH__)
    sym_ptr = asgard_resolve_by_api_hash(sym->hash);
    if (!sym_ptr && sym->alt_hash != 0) {
        sym_ptr = asgard_resolve_by_api_hash(sym->alt_hash);
    }
    if (sym_ptr) return sym_ptr;
#endif

    char dec_name[64];
    asg_decrypt_sym(sym, dec_name, sizeof(dec_name));
    if (!sym_ptr) sym_ptr = asgard_resolve_constant_name(dec_name);

#if defined(__APPLE__) && defined(__MACH__)
    if (!sym_ptr) {
        typedef void* (*dlsym_fn_t)(void*, const char*);
        dlsym_fn_t dyn_dlsym = (dlsym_fn_t)asgard_resolve_by_api_hash(0xE628BBCDU /* FNV1a("_dlsym") */);
        if (dyn_dlsym) {
            sym_ptr = dyn_dlsym((void*)-2, dec_name);
            if (!sym_ptr && dec_name[0] == '_') sym_ptr = dyn_dlsym((void*)-2, dec_name + 1);
            if (!sym_ptr) {
                char alt[66];
                alt[0] = '_';
                memcpy(alt + 1, dec_name, sym->len + 1);
                sym_ptr = dyn_dlsym((void*)-2, alt);
            }
        }
    }
#elif defined(_WIN32) || defined(_WIN64)
    if (!sym_ptr) {
        HMODULE hMain = GetModuleHandleA(NULL);
        sym_ptr = (void*)GetProcAddress(hMain, dec_name);
        if (!sym_ptr && dec_name[0] == '_') sym_ptr = (void*)GetProcAddress(hMain, dec_name + 1);
        if (!sym_ptr) {
            char alt[66];
            alt[0] = '_';
            memcpy(alt + 1, dec_name, sym->len + 1);
            sym_ptr = (void*)GetProcAddress(hMain, alt);
        }
    }
#else
    if (!sym_ptr) {
        sym_ptr = dlsym(RTLD_DEFAULT, dec_name);
        if (!sym_ptr && dec_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, dec_name + 1);
        if (!sym_ptr) {
            char alt[66];
            alt[0] = '_';
            memcpy(alt + 1, dec_name, sym->len + 1);
            sym_ptr = dlsym(RTLD_DEFAULT, alt);
        }
    }
#endif

    volatile char* p = dec_name;
    while (*p) *p++ = 0;

    return sym_ptr;
}
                                
                                namespace asgard_whitebox {
                                                           
                                                           static const uint32_t T0_0[256] = {
                                                               0xf5377b72U,
                                                               0x2a3b3600U,
                                                               0xc91fcc48U,
                                                               0xd638e02fU,
                                                               0x6cb3729cU,
                                                               0xf429ecc8U,
                                                               0x027e0c83U,
                                                               0x55d6375dU,
                                                               0x3dfd87b9U,
                                                               0x1613d55bU,
                                                               0xabae8031U,
                                                               0x878723ffU,
                                                               0x1f951a0bU,
                                                               0x69e8f153U,
                                                               0x1d880e70U,
                                                               0x6d64edf1U,
                                                               0xa054bcdcU,
                                                               0x12d388ecU,
                                                               0xb82c4f07U,
                                                               0xe75a9410U,
                                                               0x5bbec135U,
                                                               0x92f5b4e8U,
                                                               0xb12ac7ffU,
                                                               0x4f6b9902U,
                                                               0x76c7a3c7U,
                                                               0xe2e1dfe5U,
                                                               0xa8f63595U,
                                                               0xbf7b6b96U,
                                                               0x5f81d7feU,
                                                               0x2d49a550U,
                                                               0x6bd0416bU,
                                                               0x7512e728U,
                                                               0x91e86322U,
                                                               0xab182214U,
                                                               0x06069152U,
                                                               0x7cbb6781U,
                                                               0xec010cedU,
                                                               0xdcf4075cU,
                                                               0x18d0f2a7U,
                                                               0x8073a195U,
                                                               0x2fac9389U,
                                                               0xaf664887U,
                                                               0x5b434073U,
                                                               0xebafa9beU,
                                                               0xf2f064c9U,
                                                               0xb50bd78eU,
                                                               0xbc0eb265U,
                                                               0xef4fe416U,
                                                               0x2f3df48fU,
                                                               0x7ab48ebbU,
                                                               0x598b2505U,
                                                               0xbc4058b3U,
                                                               0x7f298e36U,
                                                               0x91fe1fbfU,
                                                               0x09ff4d41U,
                                                               0x2afbbb11U,
                                                               0x446b94e3U,
                                                               0xeddc8cfaU,
                                                               0x67bf0f18U,
                                                               0xdc86ab07U,
                                                               0xfa49434fU,
                                                               0x94c27466U,
                                                               0x1c5366c0U,
                                                               0xbd54996eU,
                                                               0xee5f30f0U,
                                                               0xc8c035caU,
                                                               0xb798ff2aU,
                                                               0xcdcecb7dU,
                                                               0xc21e8f3aU,
                                                               0x4448ea68U,
                                                               0x1e823b43U,
                                                               0x1f06388eU,
                                                               0x75f9ced8U,
                                                               0x6ae4059aU,
                                                               0x8df107f7U,
                                                               0x4a121b5dU,
                                                               0xb16347c0U,
                                                               0x63fde1a7U,
                                                               0x1ffe8bc3U,
                                                               0xb0fa198dU,
                                                               0x02245f79U,
                                                               0xe359ce65U,
                                                               0xffb8128cU,
                                                               0x075e6348U,
                                                               0xf3df9279U,
                                                               0x88a76797U,
                                                               0x9268ddedU,
                                                               0x89eeb91bU,
                                                               0xeb4a9033U,
                                                               0x2902da65U,
                                                               0x28f3077fU,
                                                               0xc0d88f0eU,
                                                               0xa1fb9bb0U,
                                                               0xfca9292dU,
                                                               0xc7d0664dU,
                                                               0x32d0ff2bU,
                                                               0xaac97e4aU,
                                                               0x1740cffdU,
                                                               0x8dc82e70U,
                                                               0x8544f0e4U,
                                                               0xa3635536U,
                                                               0x2db0dffeU,
                                                               0x49ace470U,
                                                               0xffa55f0aU,
                                                               0x1d88a9e9U,
                                                               0x1041f016U,
                                                               0x543fa5f3U,
                                                               0x3a97d8fbU,
                                                               0x06fee681U,
                                                               0x2649e0e1U,
                                                               0xeee07949U,
                                                               0xbfae7fbeU,
                                                               0x9797f46cU,
                                                               0x6be0e2efU,
                                                               0xa16e1356U,
                                                               0xc3535770U,
                                                               0x5d7ffd91U,
                                                               0x5d19ba5aU,
                                                               0xb7135580U,
                                                               0x720cdbaeU,
                                                               0x78a63384U,
                                                               0x1a201057U,
                                                               0x59fb1d20U,
                                                               0xeaaa88d6U,
                                                               0x789a46bbU,
                                                               0x1f101c13U,
                                                               0xf6485a3aU,
                                                               0x7527e130U,
                                                               0x6c7912adU,
                                                               0xb5b4a553U,
                                                               0xaa199082U,
                                                               0x95e80a2bU,
                                                               0x9837d6e9U,
                                                               0x01100e80U,
                                                               0x07ebd818U,
                                                               0x0751f8eaU,
                                                               0x56882873U,
                                                               0x05196e90U,
                                                               0x00cb7a74U,
                                                               0x116319daU,
                                                               0xe4701a5fU,
                                                               0x9e3d7c78U,
                                                               0x622189a5U,
                                                               0x0c5b162eU,
                                                               0x84931d73U,
                                                               0xe7a6578dU,
                                                               0x8ead4610U,
                                                               0xfffd2eadU,
                                                               0x17edad79U,
                                                               0xb824ac3fU,
                                                               0xab3890f6U,
                                                               0xc1583631U,
                                                               0x734a275fU,
                                                               0x97902d3fU,
                                                               0x58cb467dU,
                                                               0x25f7cd7eU,
                                                               0x0fd9037fU,
                                                               0xb3d6c67cU,
                                                               0x65b1da0eU,
                                                               0xc0009f77U,
                                                               0x623c262aU,
                                                               0xc97fdc1aU,
                                                               0x5ae9c46aU,
                                                               0x60a8b3cbU,
                                                               0x1ca6a151U,
                                                               0xe0174fd6U,
                                                               0x8144b1b3U,
                                                               0xb2954af1U,
                                                               0x54c8fa6bU,
                                                               0x5e71e3e3U,
                                                               0x258356c5U,
                                                               0x06d4e44eU,
                                                               0xfdf19170U,
                                                               0xbf0d1ac9U,
                                                               0xafbd8a2bU,
                                                               0xb9f4dc3fU,
                                                               0x8127ca61U,
                                                               0x3dde6351U,
                                                               0xabd2fcb2U,
                                                               0xc2c5415fU,
                                                               0x25d59befU,
                                                               0xe375d9f7U,
                                                               0xc651d010U,
                                                               0x59a0bc46U,
                                                               0xb3a025a8U,
                                                               0x6556a8ebU,
                                                               0x318422f5U,
                                                               0xe954acd8U,
                                                               0x9dc2e7bfU,
                                                               0x0df8faf2U,
                                                               0x2bc66f38U,
                                                               0x3d2dff3cU,
                                                               0xeb4c6f8cU,
                                                               0x5fce1b7eU,
                                                               0x60e8d87dU,
                                                               0xfa27a16bU,
                                                               0xb4299e08U,
                                                               0x15ff1cdaU,
                                                               0xeb10a552U,
                                                               0x4c5ad655U,
                                                               0x3f0272bdU,
                                                               0xdbf94be5U,
                                                               0xea46cefeU,
                                                               0x24f7fa1fU,
                                                               0xe1cf5bc4U,
                                                               0x56178a27U,
                                                               0x1f868d93U,
                                                               0x9704e1edU,
                                                               0x09785446U,
                                                               0xad32a062U,
                                                               0xb58b89d4U,
                                                               0x601e5746U,
                                                               0x21195159U,
                                                               0x015d8265U,
                                                               0xed4d26f0U,
                                                               0xdd6f5f06U,
                                                               0xe038c319U,
                                                               0x65da7c1bU,
                                                               0x2c810e67U,
                                                               0x6b44a9e2U,
                                                               0xc3a4785bU,
                                                               0xa96cf154U,
                                                               0x66cfdf76U,
                                                               0x89dac9ccU,
                                                               0x85ee6559U,
                                                               0x75f59a80U,
                                                               0x98f0c2d5U,
                                                               0xbb46c38aU,
                                                               0xb3247feeU,
                                                               0x81a847f4U,
                                                               0x614f4c82U,
                                                               0x946294deU,
                                                               0xb09941f0U,
                                                               0xe41d3666U,
                                                               0x2243a029U,
                                                               0xbbd2a10fU,
                                                               0x63d18af3U,
                                                               0x792eb91dU,
                                                               0xf34870dfU,
                                                               0xd68f598eU,
                                                               0x98a60089U,
                                                               0x145dea85U,
                                                               0xca8fd77eU,
                                                               0x6508e253U,
                                                               0xcc84b443U,
                                                               0x18589846U,
                                                               0x7592d393U,
                                                               0x0f2ed720U,
                                                               0xe21e9f8eU,
                                                               0x4fbf7cafU,
                                                               0x0060a625U,
                                                               0x75758c27U,
                                                               0xa98dd85eU,
                                                               0x453e4985U,
                                                               0x21f74a20U,
                                                               0x99cdf9e3U
                                                           };
                                                           
                                                           static const uint32_t T0_1[256] = {
                                                               0x45c5c39dU,
                                                               0x7f4d1ac8U,
                                                               0xd5ae3549U,
                                                               0xbe86ececU,
                                                               0x84e4088dU,
                                                               0x12040f89U,
                                                               0x508d84b2U,
                                                               0x14316cf1U,
                                                               0x2aed1560U,
                                                               0x54490f32U,
                                                               0x0c22a425U,
                                                               0x7d6759acU,
                                                               0x819f6c25U,
                                                               0x5b6bf135U,
                                                               0x3f2afe2bU,
                                                               0xaaf4dbe5U,
                                                               0x00baa407U,
                                                               0xefc8915dU,
                                                               0x42170536U,
                                                               0x4fbf0874U,
                                                               0x5d0a4391U,
                                                               0x45641333U,
                                                               0x8f64cd28U,
                                                               0xca65b26eU,
                                                               0x91b27eacU,
                                                               0x8a2ca62eU,
                                                               0x8e447278U,
                                                               0x7187adf0U,
                                                               0xb037785eU,
                                                               0xd1b37c22U,
                                                               0x8b9ab2d2U,
                                                               0xfc7a9d5fU,
                                                               0xf1fc0f0fU,
                                                               0x854559edU,
                                                               0x8ac68114U,
                                                               0x72a46312U,
                                                               0x1b97a321U,
                                                               0x3af9a2d8U,
                                                               0x4f58cdddU,
                                                               0xa4cfead3U,
                                                               0x2bcea9bcU,
                                                               0x786762dcU,
                                                               0xb7c900a5U,
                                                               0x4a002a32U,
                                                               0x8d3aeccfU,
                                                               0x965d1cccU,
                                                               0xafe5ca2cU,
                                                               0x031f5a03U,
                                                               0x2df0a5d3U,
                                                               0x1b11ca8bU,
                                                               0x4f6b0439U,
                                                               0xff6f1bb0U,
                                                               0x9355e361U,
                                                               0xc8e5828bU,
                                                               0xb3448817U,
                                                               0x79744babU,
                                                               0x6dcfe3aaU,
                                                               0x51d6866cU,
                                                               0x0ab2b515U,
                                                               0x364bee1cU,
                                                               0xe68b7b64U,
                                                               0x8a7ab730U,
                                                               0xf1af47d0U,
                                                               0x331c4f42U,
                                                               0xda526618U,
                                                               0x34f5bdfdU,
                                                               0x49aeedabU,
                                                               0x3b6bfb48U,
                                                               0x6432cca5U,
                                                               0xcb0aa547U,
                                                               0xb37e1066U,
                                                               0xaf5ecf26U,
                                                               0x992d2f17U,
                                                               0x0de30c2fU,
                                                               0xc18fd1a9U,
                                                               0xea5f7f99U,
                                                               0xf859f6f3U,
                                                               0x07152b41U,
                                                               0x87c2e720U,
                                                               0xd6842c67U,
                                                               0xae1b29cdU,
                                                               0x3db2cb97U,
                                                               0x6d2c2bb6U,
                                                               0x48beb2d3U,
                                                               0x0802cc41U,
                                                               0x8fa171e1U,
                                                               0x7daa1b92U,
                                                               0xc8da489fU,
                                                               0x18c0b9caU,
                                                               0x7d379f3dU,
                                                               0x635d6964U,
                                                               0xaa509b92U,
                                                               0x437afe67U,
                                                               0x356da613U,
                                                               0xa516e735U,
                                                               0x462fd1f8U,
                                                               0x371d1e86U,
                                                               0x30210b6eU,
                                                               0xcfd8c1a0U,
                                                               0x98fdb58aU,
                                                               0x1c1d13d8U,
                                                               0x2c231427U,
                                                               0x8be05cb6U,
                                                               0x69ba49d7U,
                                                               0xdec8f75dU,
                                                               0xdab5a34fU,
                                                               0xf599e899U,
                                                               0xd0752220U,
                                                               0x60918124U,
                                                               0xa6c6a470U,
                                                               0xaf81b1aeU,
                                                               0xd50a9191U,
                                                               0x47f9194aU,
                                                               0x6f9a0ba4U,
                                                               0x40ff858bU,
                                                               0x8f2f4e6fU,
                                                               0x4ea95cffU,
                                                               0x819ba112U,
                                                               0x0d64c299U,
                                                               0x93332325U,
                                                               0x3ed4de8eU,
                                                               0x05116256U,
                                                               0xa37912a0U,
                                                               0x68fe7cc1U,
                                                               0xde86cce8U,
                                                               0xb64143cbU,
                                                               0x2f38b487U,
                                                               0x60b70ccbU,
                                                               0x49af6aeeU,
                                                               0x640854f8U,
                                                               0xb8ca9cc7U,
                                                               0x4a5146b8U,
                                                               0xd3d05d0cU,
                                                               0x719c4a31U,
                                                               0x2252e7b4U,
                                                               0xef357217U,
                                                               0xda6b20eeU,
                                                               0x4aef62d3U,
                                                               0x46675d81U,
                                                               0x1ca7cca2U,
                                                               0xaba217b1U,
                                                               0x049a5880U,
                                                               0x5a9dcbf1U,
                                                               0x21966149U,
                                                               0x4a4eb03cU,
                                                               0xc0521580U,
                                                               0x4066811bU,
                                                               0xf48662e5U,
                                                               0x2c486520U,
                                                               0xa195e2f5U,
                                                               0x24875af4U,
                                                               0x7a3c53b0U,
                                                               0x304d52b9U,
                                                               0x369d82dcU,
                                                               0x2cc5cd38U,
                                                               0xd5504b9dU,
                                                               0x649994a6U,
                                                               0x579c4ce9U,
                                                               0x58a4b50fU,
                                                               0xd43c0363U,
                                                               0x8824d992U,
                                                               0x342850a1U,
                                                               0xd5266ab1U,
                                                               0xd4b074e8U,
                                                               0x7120eff9U,
                                                               0xb0cbb65aU,
                                                               0x4e40eebeU,
                                                               0x023b7945U,
                                                               0xe6a9ee7aU,
                                                               0x8045b617U,
                                                               0x39dda1c2U,
                                                               0x951949a6U,
                                                               0xbb76b1a5U,
                                                               0x3039805eU,
                                                               0x2c65b8e2U,
                                                               0xbac7dcdaU,
                                                               0x8d60f09eU,
                                                               0x5d5ff6f5U,
                                                               0xe2e2151bU,
                                                               0xea259c63U,
                                                               0x005f17ddU,
                                                               0x97d59bb8U,
                                                               0x6aa2ad0aU,
                                                               0x161abb1bU,
                                                               0x4bd87fd6U,
                                                               0x8f56ed11U,
                                                               0x164c3183U,
                                                               0x4ec338deU,
                                                               0xec14e760U,
                                                               0xe289c4e1U,
                                                               0x978232fcU,
                                                               0xd1f96257U,
                                                               0xd6ddf666U,
                                                               0x5312458eU,
                                                               0xa2d0c944U,
                                                               0x639d72d8U,
                                                               0x15ad51b7U,
                                                               0x4d84adaaU,
                                                               0x48f7816cU,
                                                               0xbd246cfcU,
                                                               0x75437a4cU,
                                                               0x1bc09bf0U,
                                                               0x5d71b8ccU,
                                                               0xeadd66dcU,
                                                               0xfcaab5b5U,
                                                               0xf77eeb1dU,
                                                               0x0febf48fU,
                                                               0xc6343619U,
                                                               0x023a29f6U,
                                                               0x53766a52U,
                                                               0x30b53241U,
                                                               0x97957bb3U,
                                                               0xf8ce2adcU,
                                                               0x62c04d34U,
                                                               0x85ab59b4U,
                                                               0xdb1a1b62U,
                                                               0xd0008603U,
                                                               0x56151a45U,
                                                               0x39fd75c2U,
                                                               0x1afea0acU,
                                                               0xbe301d46U,
                                                               0xc205c0f3U,
                                                               0xf72fb4a1U,
                                                               0x2180aae2U,
                                                               0x6a974a87U,
                                                               0x019641a4U,
                                                               0x2074557bU,
                                                               0x944bf4efU,
                                                               0x1ccabe4fU,
                                                               0x86515a9dU,
                                                               0xb98287c7U,
                                                               0x96de5e65U,
                                                               0x85e22dbdU,
                                                               0x15d4418dU,
                                                               0x1820c2bbU,
                                                               0x8ec514e8U,
                                                               0xe0c50977U,
                                                               0x86cf2095U,
                                                               0xde472e03U,
                                                               0x6487730fU,
                                                               0x0c944dcaU,
                                                               0x09413fa8U,
                                                               0x1f259f02U,
                                                               0x72deec09U,
                                                               0x79cdbb07U,
                                                               0xe99f675eU,
                                                               0x4e3f799cU,
                                                               0xc8a05e54U,
                                                               0x1e03a130U,
                                                               0x6c118fe1U,
                                                               0x1d0e5bccU,
                                                               0x21609a40U,
                                                               0x8ccd7aa7U,
                                                               0xa250bbf9U,
                                                               0x0959d996U,
                                                               0x956aee1aU
                                                           };
                                                           
                                                           static const uint32_t T0_2[256] = {
                                                               0x115c102fU,
                                                               0x06d04a7bU,
                                                               0xacd97846U,
                                                               0xf612b4efU,
                                                               0xed6e7220U,
                                                               0xd9e35c27U,
                                                               0xb565cc37U,
                                                               0xce6e3d62U,
                                                               0xe50afbf4U,
                                                               0xd59723aaU,
                                                               0x13c76796U,
                                                               0xb7f4d7aeU,
                                                               0x1d47a42bU,
                                                               0x5c62f036U,
                                                               0x1c332f0bU,
                                                               0x6c9b8913U,
                                                               0x78d1b051U,
                                                               0x04b0cbb8U,
                                                               0x6b458d2bU,
                                                               0x87da15e9U,
                                                               0x65ca7564U,
                                                               0x86121209U,
                                                               0x80581b78U,
                                                               0x166ea937U,
                                                               0x46399da2U,
                                                               0xe3849468U,
                                                               0x30d2eb8dU,
                                                               0x0360de4eU,
                                                               0xcf31b170U,
                                                               0x9adaf0dcU,
                                                               0x36c1132dU,
                                                               0x3490b774U,
                                                               0x8e473c52U,
                                                               0xba09b75dU,
                                                               0xa9591821U,
                                                               0x4461614cU,
                                                               0xae3a88d8U,
                                                               0x252cbe21U,
                                                               0x35b656e2U,
                                                               0x98205ceaU,
                                                               0x832a4c72U,
                                                               0x2f81be1bU,
                                                               0x3e6a4d8aU,
                                                               0xbe8f16efU,
                                                               0x95ee5307U,
                                                               0x0b36fccaU,
                                                               0x4537fffaU,
                                                               0x2d4919cfU,
                                                               0xfa5d9409U,
                                                               0x70eb1490U,
                                                               0x4aa38819U,
                                                               0x4fc78e31U,
                                                               0x15a1911eU,
                                                               0x97eca3f7U,
                                                               0x44fc60edU,
                                                               0x912a797fU,
                                                               0xb105ff6eU,
                                                               0x4df76938U,
                                                               0x78684ed5U,
                                                               0xd0f1239eU,
                                                               0xdc8321c8U,
                                                               0xdbd2a6dcU,
                                                               0x7311f9c9U,
                                                               0x5b0e115dU,
                                                               0x5b06945dU,
                                                               0xdee3f841U,
                                                               0x86897ae9U,
                                                               0x5de0c71fU,
                                                               0x3de493d5U,
                                                               0xa5a79030U,
                                                               0x4733fdf9U,
                                                               0x24f2ca7eU,
                                                               0x9a220342U,
                                                               0x1bd671b4U,
                                                               0x1f50259bU,
                                                               0x12ba84aaU,
                                                               0x0e0bc4a8U,
                                                               0xb8adc226U,
                                                               0xf847fbadU,
                                                               0x51fe8eddU,
                                                               0x0b0cb8feU,
                                                               0x68d29981U,
                                                               0x44a4ce6cU,
                                                               0x7d366516U,
                                                               0x1c73d797U,
                                                               0x387c4f8eU,
                                                               0x8da8ff5fU,
                                                               0xffb08c95U,
                                                               0xf3dd3885U,
                                                               0xfeed81bcU,
                                                               0xd353d546U,
                                                               0x974f8616U,
                                                               0x7b46e34dU,
                                                               0x05c9cb94U,
                                                               0x3b0b340fU,
                                                               0x0e2a272bU,
                                                               0x127b099bU,
                                                               0xff355a33U,
                                                               0x44196cc2U,
                                                               0x2eb69db2U,
                                                               0x62e65b97U,
                                                               0x372530acU,
                                                               0xe104adc9U,
                                                               0x6a706fa7U,
                                                               0x95ae64dcU,
                                                               0x04ca9b1aU,
                                                               0xe361b610U,
                                                               0xe2ca277eU,
                                                               0xf1267aecU,
                                                               0x9b6a6afeU,
                                                               0x5bf3bcb9U,
                                                               0x27e84348U,
                                                               0x79c9bb98U,
                                                               0xd982b83cU,
                                                               0xb9d8b593U,
                                                               0x0d64204eU,
                                                               0xd3ced314U,
                                                               0x83a86cc8U,
                                                               0x813338f1U,
                                                               0x2a89f5e9U,
                                                               0x95671d86U,
                                                               0x259e5a08U,
                                                               0x6843fea6U,
                                                               0xfd3988f9U,
                                                               0x672b4539U,
                                                               0x8b311a72U,
                                                               0xd157c2d3U,
                                                               0xa88e1638U,
                                                               0x6d3f4002U,
                                                               0xf0f3f4ffU,
                                                               0xbae67e38U,
                                                               0xcefec1bdU,
                                                               0x842b8b13U,
                                                               0x7139bb45U,
                                                               0xdb2df777U,
                                                               0x625894f4U,
                                                               0xa8cb3734U,
                                                               0x98283063U,
                                                               0xa675bc99U,
                                                               0xb8889785U,
                                                               0x4f2494c0U,
                                                               0x3454efb6U,
                                                               0x1059172cU,
                                                               0xd0795f42U,
                                                               0x858ad429U,
                                                               0x405fe70bU,
                                                               0x015d6f25U,
                                                               0x0b132732U,
                                                               0xb0b1ac32U,
                                                               0x1e92dbcdU,
                                                               0x86913a89U,
                                                               0xa852bad2U,
                                                               0xf2588b47U,
                                                               0x88d2e0b1U,
                                                               0xabfdb0cbU,
                                                               0x978c9df7U,
                                                               0x5d0696b7U,
                                                               0xe9608a19U,
                                                               0x56ec8abfU,
                                                               0x6de12ed3U,
                                                               0x3c69f251U,
                                                               0x6463eb16U,
                                                               0xc5045cbbU,
                                                               0xe6228002U,
                                                               0x067f06adU,
                                                               0x105eb8b5U,
                                                               0xb19b5c58U,
                                                               0x77aea3f5U,
                                                               0x7726e2e1U,
                                                               0x0d5bfd96U,
                                                               0x204255cdU,
                                                               0x8905716dU,
                                                               0x9bff8375U,
                                                               0xc2caf789U,
                                                               0xbbd91fd7U,
                                                               0xd27bc128U,
                                                               0xc1c857f5U,
                                                               0x52a43d97U,
                                                               0xfb574112U,
                                                               0x1505bed5U,
                                                               0x3fa2cba4U,
                                                               0xb7951ed3U,
                                                               0x1ec417f1U,
                                                               0x12f982ccU,
                                                               0xebb21c0bU,
                                                               0x2a7106bbU,
                                                               0xc82f6dbfU,
                                                               0xfbcb4ad5U,
                                                               0xad53a836U,
                                                               0xd41ad762U,
                                                               0xd7aa431dU,
                                                               0xd5cfd04fU,
                                                               0x73442b6cU,
                                                               0xa1cd3d70U,
                                                               0x73253467U,
                                                               0x4e1313b8U,
                                                               0x466a9dc2U,
                                                               0x83d13fabU,
                                                               0xca19b862U,
                                                               0x0736c507U,
                                                               0x3d5e36cdU,
                                                               0xff43da42U,
                                                               0x1b80b9dfU,
                                                               0xf8037cabU,
                                                               0x4c6e44d1U,
                                                               0x52d2abd4U,
                                                               0x52cff8f6U,
                                                               0xeb5bf668U,
                                                               0x14fb257fU,
                                                               0xadf774a7U,
                                                               0x60c12c1bU,
                                                               0x30c94a45U,
                                                               0x6ed4120bU,
                                                               0xf4433533U,
                                                               0x390892e5U,
                                                               0x8f89796cU,
                                                               0xbef39f5fU,
                                                               0xd74e66c5U,
                                                               0x9a3b353cU,
                                                               0x6062c1ffU,
                                                               0x70505c59U,
                                                               0xefe199a4U,
                                                               0x18231e5aU,
                                                               0x857f9546U,
                                                               0xee0a9b81U,
                                                               0x9569500eU,
                                                               0x59391db5U,
                                                               0x987425e7U,
                                                               0xc52c0849U,
                                                               0x85de5057U,
                                                               0x5f37742dU,
                                                               0x2f6e9553U,
                                                               0x055e7846U,
                                                               0x724e2a60U,
                                                               0x721cee7bU,
                                                               0xdf32042dU,
                                                               0x835c6f23U,
                                                               0xa03d4082U,
                                                               0x2b0bb908U,
                                                               0x637467c5U,
                                                               0x86df8a5fU,
                                                               0x135836d4U,
                                                               0x849a8c0bU,
                                                               0x8c8de868U,
                                                               0x61902ffbU,
                                                               0xbd3b8c86U,
                                                               0x3323dd72U,
                                                               0x6eb401edU,
                                                               0xd2165a89U,
                                                               0x66c58c5dU,
                                                               0x64dc16d7U,
                                                               0xda12f1e9U,
                                                               0xf690c4b8U,
                                                               0xa25a2c47U,
                                                               0x797e29a8U,
                                                               0x0de3aaa8U
                                                           };
                                                           
                                                           static const uint32_t T0_3[256] = {
                                                               0x6052e03fU,
                                                               0x11a155bcU,
                                                               0x425558bbU,
                                                               0xe814619fU,
                                                               0x711c173bU,
                                                               0x5a4561e5U,
                                                               0xbf9af1f4U,
                                                               0xf43ee176U,
                                                               0x08e80bf8U,
                                                               0x3d68c12aU,
                                                               0x487b49eaU,
                                                               0x35d196f9U,
                                                               0xe02307deU,
                                                               0xa04f2e6aU,
                                                               0xf5668e88U,
                                                               0x54480466U,
                                                               0x1dd4dfa5U,
                                                               0xa484ba1cU,
                                                               0x1f009ca3U,
                                                               0x19bb4f3fU,
                                                               0xb7082c08U,
                                                               0x270431adU,
                                                               0xb77a5228U,
                                                               0x3edcb4b1U,
                                                               0x5f4b67d6U,
                                                               0x8997a2b9U,
                                                               0xbbe653daU,
                                                               0xf236a246U,
                                                               0xb10a005aU,
                                                               0xd52192bcU,
                                                               0x2f4701a6U,
                                                               0xcb2ade60U,
                                                               0x3b2ade69U,
                                                               0xbdcce996U,
                                                               0xaab5a1c6U,
                                                               0xd00af65fU,
                                                               0xab0fd31aU,
                                                               0xcb25bb7cU,
                                                               0xa0fd6461U,
                                                               0xaa770bbbU,
                                                               0x6976bc11U,
                                                               0xdeeb805eU,
                                                               0x62ff99aeU,
                                                               0x5a15f225U,
                                                               0x59d8bf1cU,
                                                               0x422a2b48U,
                                                               0x6d1b0fa5U,
                                                               0x48a1a8a4U,
                                                               0x0bae53b9U,
                                                               0xd5336855U,
                                                               0x2fc496c3U,
                                                               0xe80ffddfU,
                                                               0x387d317fU,
                                                               0x658d44f1U,
                                                               0x9b9de952U,
                                                               0xa0f6842eU,
                                                               0x8904a15eU,
                                                               0xf6688d6fU,
                                                               0x90bff35fU,
                                                               0x328fbf75U,
                                                               0x4ecd757eU,
                                                               0x21825b5fU,
                                                               0xd8fa36eeU,
                                                               0x901940d5U,
                                                               0x5ca24a96U,
                                                               0x742c112eU,
                                                               0x58ef2e2dU,
                                                               0x56a9d9c1U,
                                                               0xe83fd74aU,
                                                               0x7d57c635U,
                                                               0x313ac246U,
                                                               0x85534aecU,
                                                               0x55778ec4U,
                                                               0x32b90625U,
                                                               0x7a615877U,
                                                               0x58717adcU,
                                                               0xd76772e2U,
                                                               0xcc6c72b5U,
                                                               0xadf78935U,
                                                               0x36017816U,
                                                               0x49c0a101U,
                                                               0x07b5040cU,
                                                               0xf3e5b0d3U,
                                                               0xf7b28704U,
                                                               0x476004b5U,
                                                               0x9c80706eU,
                                                               0xca6fecf2U,
                                                               0xd43e5255U,
                                                               0xa9fbdd1dU,
                                                               0xe1708a03U,
                                                               0xe64cf7a7U,
                                                               0x6f22984dU,
                                                               0x2637bb85U,
                                                               0x874ffab0U,
                                                               0x7dd55ba2U,
                                                               0x9704a450U,
                                                               0x42bb1875U,
                                                               0x5c6002bbU,
                                                               0x283ac379U,
                                                               0xe6ebe7e3U,
                                                               0x8667002dU,
                                                               0xa9af344bU,
                                                               0xdf169183U,
                                                               0x1ea0e8beU,
                                                               0xc4edc0cdU,
                                                               0x0b708ff9U,
                                                               0x9c5ddcbbU,
                                                               0x96d9b22bU,
                                                               0x6f69d828U,
                                                               0xf900688eU,
                                                               0xdace3e0aU,
                                                               0xa9b1e3f7U,
                                                               0xd6f04656U,
                                                               0xb357b07fU,
                                                               0x34f17e70U,
                                                               0x53ac6880U,
                                                               0x7ac1f42dU,
                                                               0x1ba2848fU,
                                                               0x94867c6cU,
                                                               0x0d67a6b5U,
                                                               0xc072440cU,
                                                               0x7d69fa8dU,
                                                               0x194fe2cfU,
                                                               0x3e9f92a0U,
                                                               0xd99eace0U,
                                                               0x6642f159U,
                                                               0x2b3666e2U,
                                                               0x32134c31U,
                                                               0x85a1a645U,
                                                               0xfc3431dcU,
                                                               0xbb68476fU,
                                                               0x4de40135U,
                                                               0x1cae6330U,
                                                               0x50420782U,
                                                               0xdb756e57U,
                                                               0xadc5c8c8U,
                                                               0x211938c6U,
                                                               0xadcfebbfU,
                                                               0xc872433eU,
                                                               0x87b4b00eU,
                                                               0x6c12c787U,
                                                               0xbc28f729U,
                                                               0xe8109b0dU,
                                                               0xd1abf2ccU,
                                                               0xb0c6f03bU,
                                                               0x40432966U,
                                                               0x54774419U,
                                                               0x7f3955e5U,
                                                               0x79d6d394U,
                                                               0x415424f8U,
                                                               0x0432e85eU,
                                                               0x283afb58U,
                                                               0xe2fb44c4U,
                                                               0xf7eef0b8U,
                                                               0x6d31c8c3U,
                                                               0x0590888fU,
                                                               0x3335c458U,
                                                               0x216f2d7fU,
                                                               0xee8a75f9U,
                                                               0xb64a3d49U,
                                                               0xc15c3486U,
                                                               0xbb0cec1fU,
                                                               0x085e6fe8U,
                                                               0xcf532d59U,
                                                               0x860afe84U,
                                                               0x2c02fa6dU,
                                                               0xa8f11277U,
                                                               0xc59d204aU,
                                                               0x4f5877a6U,
                                                               0xfd59dcf9U,
                                                               0xa327e420U,
                                                               0x2ebad5eaU,
                                                               0x3263532cU,
                                                               0x78101636U,
                                                               0x2d974bbbU,
                                                               0x3c5671f3U,
                                                               0x66222f0cU,
                                                               0x259e425cU,
                                                               0x3c47d36eU,
                                                               0x5ed36991U,
                                                               0x63fa68e5U,
                                                               0xfead5165U,
                                                               0xee5084f4U,
                                                               0x084e4748U,
                                                               0xd92e5968U,
                                                               0x61c95810U,
                                                               0x3bd8e8eaU,
                                                               0x95164280U,
                                                               0x6a320024U,
                                                               0x70a41e21U,
                                                               0x62df5c43U,
                                                               0x4a7d56e9U,
                                                               0xea5362c5U,
                                                               0x9cdf86a8U,
                                                               0x7d10e636U,
                                                               0x154b1b3dU,
                                                               0x3dc77041U,
                                                               0x88a84243U,
                                                               0xd7ab0380U,
                                                               0x24e4d665U,
                                                               0xf755131eU,
                                                               0x168db675U,
                                                               0xf39863abU,
                                                               0xaf01d11cU,
                                                               0x1e807c55U,
                                                               0xbc05bea5U,
                                                               0xf75a171fU,
                                                               0x36359affU,
                                                               0xbe6ba98fU,
                                                               0xa74e742bU,
                                                               0x46366ef2U,
                                                               0x364f1850U,
                                                               0x4550c9b4U,
                                                               0xa5ddccd3U,
                                                               0x04053fabU,
                                                               0x6fd32631U,
                                                               0x19899516U,
                                                               0x1a7006e8U,
                                                               0x5e29984cU,
                                                               0x3e358fccU,
                                                               0xa510f725U,
                                                               0xd29c8ad3U,
                                                               0x26658403U,
                                                               0x74d9b9fdU,
                                                               0xa66d3203U,
                                                               0x938a3e69U,
                                                               0xf6f97bf4U,
                                                               0x01fd3031U,
                                                               0xbfd05250U,
                                                               0xf65028e7U,
                                                               0x73138c86U,
                                                               0xf0296d0aU,
                                                               0xb4441bbeU,
                                                               0x9b89371dU,
                                                               0x3c3bd13eU,
                                                               0xc401b37fU,
                                                               0xc30d8c57U,
                                                               0xc6966546U,
                                                               0x4d3d7b0dU,
                                                               0xca5de637U,
                                                               0xf67f2d37U,
                                                               0x8b643314U,
                                                               0x5200e2caU,
                                                               0x2de7df09U,
                                                               0xe2a09c5cU,
                                                               0x9f4bea40U,
                                                               0x468b96c4U,
                                                               0xc1459225U,
                                                               0xcf8526d0U,
                                                               0x0edc7ef1U,
                                                               0x8a5a7a5eU,
                                                               0xfc1f8394U,
                                                               0x942ba9a5U,
                                                               0xed19f642U,
                                                               0x809082bfU,
                                                               0xb01d7c05U
                                                           };
                                                           
                                                           static const uint32_t T1_0[256] = {
                                                               0x587debc2U,
                                                               0xa008b538U,
                                                               0xabda7736U,
                                                               0xf1002e61U,
                                                               0x95638fa5U,
                                                               0x7bd85f0bU,
                                                               0xba170af4U,
                                                               0xafb6a5a0U,
                                                               0x9b08560bU,
                                                               0x84624136U,
                                                               0x9547d75cU,
                                                               0x7713e946U,
                                                               0x0b607906U,
                                                               0x206f56fcU,
                                                               0xcf499ba0U,
                                                               0x48dc3a40U,
                                                               0x592a2ca1U,
                                                               0x53426830U,
                                                               0x76db2994U,
                                                               0xbdf4290eU,
                                                               0x65d4f92dU,
                                                               0x4591b61bU,
                                                               0xa2d9cfeaU,
                                                               0xee4585bcU,
                                                               0x57ceaedeU,
                                                               0xc7df9199U,
                                                               0xfff4b9fcU,
                                                               0x5c6a01cfU,
                                                               0xe66b9dbdU,
                                                               0x80476be7U,
                                                               0x31762ba7U,
                                                               0x86f27106U,
                                                               0xb93d3847U,
                                                               0xd4ad052cU,
                                                               0x00c7d707U,
                                                               0x780f0716U,
                                                               0x64b84959U,
                                                               0x49aa01d7U,
                                                               0x92f76dc8U,
                                                               0x06c28c93U,
                                                               0x3e6d2ec2U,
                                                               0x423386edU,
                                                               0x41138027U,
                                                               0x615eee82U,
                                                               0x19faace8U,
                                                               0xed600b38U,
                                                               0x72992cfeU,
                                                               0x9f90c79dU,
                                                               0x3ab32542U,
                                                               0x642a56b6U,
                                                               0x02771edbU,
                                                               0x117ae054U,
                                                               0xe3493394U,
                                                               0x644ae9efU,
                                                               0x33ad4a4aU,
                                                               0x08189ae7U,
                                                               0xa57a59c2U,
                                                               0x20d8fc3dU,
                                                               0x6a79affaU,
                                                               0xb9a9b740U,
                                                               0x211a9b94U,
                                                               0x1fb18d20U,
                                                               0x102ca338U,
                                                               0x0807a301U,
                                                               0x20015b15U,
                                                               0xafcb5c4fU,
                                                               0x0a029a8fU,
                                                               0xa6d870e8U,
                                                               0x826939edU,
                                                               0xb1f112b6U,
                                                               0xb87d6b96U,
                                                               0x4cddb071U,
                                                               0x41965c84U,
                                                               0xe75aff38U,
                                                               0x879fe7d5U,
                                                               0x0f654ab9U,
                                                               0x83c2ea49U,
                                                               0x74985358U,
                                                               0x1897660aU,
                                                               0x37707988U,
                                                               0x2997f747U,
                                                               0x4393e3c7U,
                                                               0xe6ebbfa5U,
                                                               0x65d665e8U,
                                                               0x35f341edU,
                                                               0x45fec0dfU,
                                                               0xf9e626deU,
                                                               0xf26162deU,
                                                               0x5c2207bdU,
                                                               0xdf5ec7ffU,
                                                               0xfbdd703aU,
                                                               0xf19e6c47U,
                                                               0x33314895U,
                                                               0xeb3f2bf5U,
                                                               0x093c2ba8U,
                                                               0xd11d8ce3U,
                                                               0x886c9efaU,
                                                               0x4b348e8fU,
                                                               0x4cd656bbU,
                                                               0xe40f6bafU,
                                                               0xe033df57U,
                                                               0x80265a35U,
                                                               0xe6c49fd1U,
                                                               0xc049a6cdU,
                                                               0xb9dc411bU,
                                                               0xcb7004e5U,
                                                               0x42725cbdU,
                                                               0x0e23a908U,
                                                               0xd4f9a535U,
                                                               0xb668684bU,
                                                               0x06a298c8U,
                                                               0x01a72750U,
                                                               0x860f7dadU,
                                                               0x89a59dcfU,
                                                               0xbc9e2bffU,
                                                               0xcf142da0U,
                                                               0x2822b45eU,
                                                               0xc312af84U,
                                                               0x663be194U,
                                                               0x1316a95bU,
                                                               0x10d7d3c4U,
                                                               0xca6a5d6dU,
                                                               0x085c2fc6U,
                                                               0x07dabee4U,
                                                               0x931a71ddU,
                                                               0xc63f8ba1U,
                                                               0x861924f2U,
                                                               0xed0402c7U,
                                                               0x7776bf10U,
                                                               0xbde7ca2cU,
                                                               0xbd0b8720U,
                                                               0xe171f1a5U,
                                                               0x26f4988fU,
                                                               0x8d92471bU,
                                                               0x0a3f099aU,
                                                               0xeec96614U,
                                                               0xe5bcb451U,
                                                               0x16349107U,
                                                               0x4e8daa78U,
                                                               0x6e312b2bU,
                                                               0x229ec8eeU,
                                                               0x5e4dabfeU,
                                                               0x89af1bdeU,
                                                               0xdb92b99bU,
                                                               0x0777acd1U,
                                                               0x9444b737U,
                                                               0xcc7ea43fU,
                                                               0x51be4bceU,
                                                               0xdfb778b4U,
                                                               0x9dbf3556U,
                                                               0xc02eeb29U,
                                                               0x8bcaf596U,
                                                               0x915dc13dU,
                                                               0x8d4c6a7cU,
                                                               0x9ba3c285U,
                                                               0x0fdac1f3U,
                                                               0x6c5639f6U,
                                                               0x4678a102U,
                                                               0x3011f837U,
                                                               0x42837fbfU,
                                                               0x82bc7f87U,
                                                               0xe2e920abU,
                                                               0xcddb0386U,
                                                               0xae5176acU,
                                                               0x90c3f85bU,
                                                               0xeffc8ebfU,
                                                               0x99cc5c0bU,
                                                               0xc61bd247U,
                                                               0x618ab85aU,
                                                               0x7d180477U,
                                                               0xc98ced95U,
                                                               0x63be3067U,
                                                               0xbb7a18deU,
                                                               0xe369e53dU,
                                                               0x84de8f8dU,
                                                               0x63509139U,
                                                               0xf7041774U,
                                                               0x1a0b520bU,
                                                               0xcab0564bU,
                                                               0xe53f4ea1U,
                                                               0xcc151581U,
                                                               0xbcbcce61U,
                                                               0x9b28290aU,
                                                               0x8602f7a4U,
                                                               0xbb822b1dU,
                                                               0x8c43beaeU,
                                                               0xd7fcf441U,
                                                               0x98bb86e9U,
                                                               0xa19b31d4U,
                                                               0xe98f7519U,
                                                               0x0039d653U,
                                                               0x33901b43U,
                                                               0xe7ba99c1U,
                                                               0x827c31e2U,
                                                               0xdc007afeU,
                                                               0x604c92e7U,
                                                               0x0ba311b1U,
                                                               0xcf4b1f22U,
                                                               0x9f1d9252U,
                                                               0xf43dae94U,
                                                               0xf5908d4dU,
                                                               0x5e6281d4U,
                                                               0x10e9be4cU,
                                                               0xbd53fbaaU,
                                                               0x960106a4U,
                                                               0x7cd281b4U,
                                                               0x7f1ccb13U,
                                                               0xcd4af3a4U,
                                                               0xe02641bdU,
                                                               0xcbbdd74eU,
                                                               0x32639ed3U,
                                                               0x04ab214fU,
                                                               0xe5588cfeU,
                                                               0xb555c60bU,
                                                               0x46d5a421U,
                                                               0xebf98b3eU,
                                                               0x4f5f148aU,
                                                               0xa748e9deU,
                                                               0xa01a32ebU,
                                                               0x2f757aecU,
                                                               0x7f889755U,
                                                               0x26fb40b4U,
                                                               0xe49fedcdU,
                                                               0x41567673U,
                                                               0x25c7485eU,
                                                               0x32761788U,
                                                               0xb34b08feU,
                                                               0xb84323e7U,
                                                               0x5aa51337U,
                                                               0xc1f51090U,
                                                               0xf8c8ccf3U,
                                                               0xc528e89aU,
                                                               0x488ee335U,
                                                               0x7ba09163U,
                                                               0xf43644e8U,
                                                               0x0f59e123U,
                                                               0x45e22e7cU,
                                                               0x14d589dbU,
                                                               0x7f2ade13U,
                                                               0x99948e1cU,
                                                               0x87c8a6b9U,
                                                               0x2dfe6908U,
                                                               0xff4f1534U,
                                                               0x61ea798aU,
                                                               0xa06e6ce5U,
                                                               0xebf25efaU,
                                                               0x6004600dU,
                                                               0xf31e24afU,
                                                               0xef4a5d84U,
                                                               0x5c9c0e5aU,
                                                               0xac7cd126U,
                                                               0x746e2cdeU,
                                                               0xd210037bU,
                                                               0x2711b674U,
                                                               0xd172ad75U,
                                                               0xd436f8b8U
                                                           };
                                                           
                                                           static const uint32_t T1_1[256] = {
                                                               0xeb108bb2U,
                                                               0xc4f2e4b2U,
                                                               0x301f1c3eU,
                                                               0x070976d2U,
                                                               0xe755eb96U,
                                                               0xdf355ed4U,
                                                               0x32354b0fU,
                                                               0xcea532d6U,
                                                               0x81be5943U,
                                                               0xc111ff0fU,
                                                               0x6f06ed0eU,
                                                               0xa1b468a0U,
                                                               0x1a3137edU,
                                                               0xbbf50993U,
                                                               0x4e88ec06U,
                                                               0xfbe9a5e7U,
                                                               0xd9c10dbfU,
                                                               0x4024d3baU,
                                                               0xef5d9e2cU,
                                                               0x3ae585f9U,
                                                               0x92daa51cU,
                                                               0x6392a983U,
                                                               0xb6ba5c0cU,
                                                               0x37a71a46U,
                                                               0x3b92bf9aU,
                                                               0xbe80f924U,
                                                               0x2b51e968U,
                                                               0xbc0c14b9U,
                                                               0x6850f09eU,
                                                               0xe56fe7c3U,
                                                               0xf92b5364U,
                                                               0x5da7ae9fU,
                                                               0x3280c98dU,
                                                               0x94fe69cfU,
                                                               0xa9feadffU,
                                                               0x76d02606U,
                                                               0x296c4f7cU,
                                                               0x087cbad2U,
                                                               0x297623c0U,
                                                               0x19c3df2cU,
                                                               0x7ec0fe40U,
                                                               0x5a468571U,
                                                               0x55e7b2b3U,
                                                               0xc659c03cU,
                                                               0x100aaa55U,
                                                               0xb7da4886U,
                                                               0x33cff3b5U,
                                                               0x7fe82993U,
                                                               0x8ccc7659U,
                                                               0x1deeb2f0U,
                                                               0x0437210cU,
                                                               0x2760f21fU,
                                                               0x26e5022aU,
                                                               0xe5609e18U,
                                                               0x1fa3d62cU,
                                                               0x8d1f46edU,
                                                               0x479b1d0cU,
                                                               0xbec08decU,
                                                               0xb1a0aa07U,
                                                               0x1cdd87a4U,
                                                               0x08695b72U,
                                                               0x20542e27U,
                                                               0x3257f227U,
                                                               0x06afdb35U,
                                                               0x55b8d0e4U,
                                                               0x0fa691d0U,
                                                               0xd9cfd904U,
                                                               0x0c75b994U,
                                                               0xe7c74a90U,
                                                               0xf07c63faU,
                                                               0x4129c2aeU,
                                                               0x702a5cb9U,
                                                               0xa057ff30U,
                                                               0xb2afe9f8U,
                                                               0x92aa1fc5U,
                                                               0xee13bb24U,
                                                               0xfe40daa0U,
                                                               0xbb2b2ed2U,
                                                               0xaf577082U,
                                                               0x35fd065aU,
                                                               0xfca261fbU,
                                                               0xbc9815bdU,
                                                               0x77573bc7U,
                                                               0x9c1716bfU,
                                                               0x237e68deU,
                                                               0x39caab45U,
                                                               0xe67f840dU,
                                                               0xc32f27ffU,
                                                               0x4ac86a87U,
                                                               0x39a6c889U,
                                                               0xb5d004e7U,
                                                               0x6ee3b598U,
                                                               0xd0588b4eU,
                                                               0x41f8ccbfU,
                                                               0x763db9bbU,
                                                               0xd6079f8eU,
                                                               0x2cbff94fU,
                                                               0x650541bdU,
                                                               0x6a81f45bU,
                                                               0x308cc103U,
                                                               0x0b507d98U,
                                                               0x3b4d49b4U,
                                                               0x16ff70eaU,
                                                               0x519fda55U,
                                                               0x4797889bU,
                                                               0x3645a083U,
                                                               0xe4c0fb3dU,
                                                               0x11ee812aU,
                                                               0xbfeb6562U,
                                                               0x7ce1948eU,
                                                               0xdb396005U,
                                                               0x1109c394U,
                                                               0xf86f76e4U,
                                                               0x90b82b1dU,
                                                               0x1ce46bb9U,
                                                               0x4449e6a8U,
                                                               0x8224afccU,
                                                               0x4d0df799U,
                                                               0x85808501U,
                                                               0xbc2e6269U,
                                                               0xd50a7f21U,
                                                               0xfcf42eeeU,
                                                               0xae79ffb0U,
                                                               0xe709e4d5U,
                                                               0x60fa77b0U,
                                                               0x1e2b3f67U,
                                                               0xbd3c9473U,
                                                               0x41033a69U,
                                                               0x7c9dc92aU,
                                                               0xdd7b8c8fU,
                                                               0xe6bda91eU,
                                                               0x802f57ceU,
                                                               0x919c0d4bU,
                                                               0x097122f3U,
                                                               0xd89a58baU,
                                                               0x3a30b24cU,
                                                               0x66335fd5U,
                                                               0xad43dbf7U,
                                                               0xe47e63deU,
                                                               0x1ae42f72U,
                                                               0x04c931a4U,
                                                               0x9d06e400U,
                                                               0xfad10d59U,
                                                               0x6cb5c6a0U,
                                                               0x9ec30f17U,
                                                               0x308d911eU,
                                                               0x7ae17e90U,
                                                               0xfadb7532U,
                                                               0xd4e78846U,
                                                               0x94217accU,
                                                               0xbc33bb26U,
                                                               0x630c9c13U,
                                                               0x02901434U,
                                                               0xf9bbaeabU,
                                                               0xf523571eU,
                                                               0xedc8dab8U,
                                                               0xef87249cU,
                                                               0x98b17caeU,
                                                               0x8912d4c8U,
                                                               0x15792fadU,
                                                               0xc0a02e78U,
                                                               0x0f50d2d5U,
                                                               0x67d31fc7U,
                                                               0xdf44ea9cU,
                                                               0xdfbc7143U,
                                                               0xff716d82U,
                                                               0x2e50bc38U,
                                                               0x960bb640U,
                                                               0x1800fc69U,
                                                               0x18fa8399U,
                                                               0xfbf78c55U,
                                                               0x45685e7dU,
                                                               0x213a8714U,
                                                               0xad349053U,
                                                               0xcd0355eeU,
                                                               0x323cee83U,
                                                               0x9d148559U,
                                                               0xaf590428U,
                                                               0xd19eab94U,
                                                               0x3103c561U,
                                                               0x3c002090U,
                                                               0xcac8608aU,
                                                               0x8fca619cU,
                                                               0x879eb4f9U,
                                                               0xeaefbfa1U,
                                                               0xbda196fcU,
                                                               0x81276883U,
                                                               0x623c3b74U,
                                                               0xaf1f0e4aU,
                                                               0xe9f9a009U,
                                                               0x3b921a6bU,
                                                               0x1b06846fU,
                                                               0xef628e83U,
                                                               0x78ef5195U,
                                                               0x9a3b1cf3U,
                                                               0x88c4eb51U,
                                                               0x56a90adaU,
                                                               0x7a084664U,
                                                               0x33fc960eU,
                                                               0x753f7810U,
                                                               0xef01d1e8U,
                                                               0xb9b5a056U,
                                                               0xd0195e37U,
                                                               0xd2fd33baU,
                                                               0x0d04561dU,
                                                               0x7386fc07U,
                                                               0x7cf1b171U,
                                                               0xb1436203U,
                                                               0x10ac3b0bU,
                                                               0x176d34d7U,
                                                               0xfd26f6e2U,
                                                               0x4b8e3ad7U,
                                                               0x64bad756U,
                                                               0x1ae7bb3aU,
                                                               0x0aaa7458U,
                                                               0xa0764377U,
                                                               0xb28be745U,
                                                               0xd3b8c663U,
                                                               0xe30d458eU,
                                                               0x673ecaafU,
                                                               0xb5f8b823U,
                                                               0x4a3bb76aU,
                                                               0xa0091bcaU,
                                                               0x53421e39U,
                                                               0xf93ed6e6U,
                                                               0xa627f173U,
                                                               0x96496cafU,
                                                               0x81e7a11dU,
                                                               0x2c45e7a9U,
                                                               0xa0928b70U,
                                                               0x29355685U,
                                                               0xdeaec61aU,
                                                               0xd1b48b43U,
                                                               0x5f1fe9c9U,
                                                               0xaf6c9bc6U,
                                                               0x40c7deb7U,
                                                               0x821c362eU,
                                                               0xf6c03479U,
                                                               0xc7ba1fa8U,
                                                               0xcd315f34U,
                                                               0x5c456d7cU,
                                                               0x774d3f32U,
                                                               0x2ca8af2bU,
                                                               0x86813983U,
                                                               0xcc974956U,
                                                               0x202a9ef7U,
                                                               0x101414b2U,
                                                               0x191cf1fcU,
                                                               0x5b3fc539U,
                                                               0x31c4c2f5U,
                                                               0x9a7cce53U,
                                                               0x3719e079U,
                                                               0xd873d518U,
                                                               0x9f8fd733U,
                                                               0xfb34a874U,
                                                               0xa79ba5c8U
                                                           };
                                                           
                                                           static const uint32_t T1_2[256] = {
                                                               0xb1d06b93U,
                                                               0x374d9d9bU,
                                                               0xd3a2eaf4U,
                                                               0x9b671c33U,
                                                               0x578f72efU,
                                                               0x5585a65dU,
                                                               0xee98d3e1U,
                                                               0xd8672abbU,
                                                               0xebac145cU,
                                                               0x3dda7452U,
                                                               0x44c6f573U,
                                                               0x79df8d60U,
                                                               0xbe5b9be7U,
                                                               0xd7333ed1U,
                                                               0xc42f3096U,
                                                               0x0f851c76U,
                                                               0x8d965ec7U,
                                                               0xf9260112U,
                                                               0xb49bdb3aU,
                                                               0xf863658cU,
                                                               0xd2b3540aU,
                                                               0xc3f5464dU,
                                                               0x11a9fac3U,
                                                               0x3b8e1231U,
                                                               0x40c538e7U,
                                                               0xcef80752U,
                                                               0xd5f71b42U,
                                                               0xb1849610U,
                                                               0x878c3006U,
                                                               0x7e806572U,
                                                               0xebb767eeU,
                                                               0x7a13a57cU,
                                                               0x8308f6c9U,
                                                               0x45dcf342U,
                                                               0x697e4321U,
                                                               0x99b2f378U,
                                                               0x9849dd18U,
                                                               0x7c0da2c4U,
                                                               0xb04f56d6U,
                                                               0x5e1ad374U,
                                                               0xa4da21deU,
                                                               0xdcd680b2U,
                                                               0x1d2f852eU,
                                                               0x72c362b6U,
                                                               0xf24775beU,
                                                               0x7f231943U,
                                                               0xf75bf207U,
                                                               0x020d4463U,
                                                               0x7411cc0eU,
                                                               0x8bb0ac02U,
                                                               0x17f04edbU,
                                                               0x5e5c43feU,
                                                               0x6573e12eU,
                                                               0xb3f54b34U,
                                                               0x126f2388U,
                                                               0x9d6854e7U,
                                                               0x75ae6b13U,
                                                               0x4330ac52U,
                                                               0xc47c8565U,
                                                               0x249bfa7eU,
                                                               0xfa2fdb96U,
                                                               0x7c64f475U,
                                                               0x2e79a06cU,
                                                               0x1ee818bcU,
                                                               0xb7c17a4cU,
                                                               0x312fad56U,
                                                               0xe64ff677U,
                                                               0x6540e5e3U,
                                                               0x25f2aea7U,
                                                               0x574342fbU,
                                                               0xa0a851ddU,
                                                               0x634639f1U,
                                                               0x62967391U,
                                                               0x5f929cc6U,
                                                               0x6697f05bU,
                                                               0x23f92feaU,
                                                               0xf8724017U,
                                                               0x372eddf6U,
                                                               0x2a280553U,
                                                               0x8fbf203dU,
                                                               0x22dcf9adU,
                                                               0xa6b0bad8U,
                                                               0xa76a6a7dU,
                                                               0xa2a75c50U,
                                                               0x43f9285cU,
                                                               0x038b8eacU,
                                                               0x8aa95698U,
                                                               0xf70bdfe1U,
                                                               0xded89e11U,
                                                               0x88598eb9U,
                                                               0xf7942de5U,
                                                               0x7d7951dfU,
                                                               0x09386904U,
                                                               0x9d813775U,
                                                               0x83ec5cf0U,
                                                               0x27ea1c07U,
                                                               0x9708e50fU,
                                                               0x947e8f28U,
                                                               0x2dee6210U,
                                                               0x631fc644U,
                                                               0x741c3c21U,
                                                               0x2b25b0e7U,
                                                               0x10164c3bU,
                                                               0x82550aa5U,
                                                               0x7e88af1fU,
                                                               0x64b88132U,
                                                               0xfe7bcc9dU,
                                                               0x81f5670cU,
                                                               0xcdb5b8bcU,
                                                               0xc1688a25U,
                                                               0x6d1f4857U,
                                                               0xf612475cU,
                                                               0x5baed83cU,
                                                               0xef9a9677U,
                                                               0x92b02e0aU,
                                                               0xa4d500c7U,
                                                               0xa7e6da7bU,
                                                               0xc7874fcbU,
                                                               0x1567a27eU,
                                                               0x9f81b9e6U,
                                                               0xfafb5fb9U,
                                                               0x7350a3a4U,
                                                               0x17f7aa59U,
                                                               0xe3bb8d9dU,
                                                               0x877701ceU,
                                                               0xaee8c2deU,
                                                               0xd31d4543U,
                                                               0xa3ec8a0bU,
                                                               0x03710c39U,
                                                               0xa2cb057dU,
                                                               0x5affd084U,
                                                               0x838f73bbU,
                                                               0x911e8813U,
                                                               0x4b603804U,
                                                               0x2fc11baeU,
                                                               0x7204c1ffU,
                                                               0x1153db9bU,
                                                               0xfbd13ea9U,
                                                               0x3ee45bdfU,
                                                               0x51ad1132U,
                                                               0x7cb5d95bU,
                                                               0x65c17112U,
                                                               0x3400e19eU,
                                                               0x7d3854ebU,
                                                               0x8fb9aa36U,
                                                               0xf8b317aeU,
                                                               0xd571d3fbU,
                                                               0xb3f8322eU,
                                                               0xb395c1b3U,
                                                               0xa5e9a767U,
                                                               0x4b0a2e97U,
                                                               0x8359658bU,
                                                               0x885096ffU,
                                                               0x2b7f9e6bU,
                                                               0xe692025cU,
                                                               0x113a9a29U,
                                                               0xe0e36e32U,
                                                               0x8b8babcbU,
                                                               0xeefd5bc9U,
                                                               0x71245bc8U,
                                                               0xda1784dfU,
                                                               0x13ceff72U,
                                                               0x793d72dfU,
                                                               0xd1de2c00U,
                                                               0x7d8ad604U,
                                                               0xbfaa0499U,
                                                               0x52a91d3fU,
                                                               0x6607addeU,
                                                               0x9e32c334U,
                                                               0x038cdfb7U,
                                                               0xea5d78d4U,
                                                               0xdcc003e5U,
                                                               0x16259310U,
                                                               0xfea2bd15U,
                                                               0x1fd51b78U,
                                                               0x2f8e04e1U,
                                                               0x30d6135bU,
                                                               0x7a24e04bU,
                                                               0x307d25a3U,
                                                               0x3303f117U,
                                                               0x66dc2f42U,
                                                               0xce4bfac4U,
                                                               0xb0f5d6fdU,
                                                               0x41bf310fU,
                                                               0x786cc539U,
                                                               0x35eb94e0U,
                                                               0x3260e8ecU,
                                                               0x91f6744cU,
                                                               0xfbf7ac35U,
                                                               0xe638e313U,
                                                               0xdb60a319U,
                                                               0xf06ba4d2U,
                                                               0xf429dcbcU,
                                                               0x0a3f506cU,
                                                               0xb1677215U,
                                                               0xd41a5edbU,
                                                               0xbcfca4f2U,
                                                               0x8dc2b2c1U,
                                                               0x2c895d8eU,
                                                               0x2ad32277U,
                                                               0x69df21e7U,
                                                               0x3e1b2fccU,
                                                               0xd0b0b59aU,
                                                               0xd6bad097U,
                                                               0xb8c95cecU,
                                                               0x708eaf4fU,
                                                               0xf70ff11dU,
                                                               0x04029ab9U,
                                                               0x874f8e81U,
                                                               0xa4653642U,
                                                               0xc03aa2c0U,
                                                               0xd6dfa846U,
                                                               0xe86bc492U,
                                                               0x8fce1966U,
                                                               0xa32e0f51U,
                                                               0x732f4364U,
                                                               0x46d182f5U,
                                                               0xf8d227f6U,
                                                               0xda50465eU,
                                                               0xfb569e27U,
                                                               0xabfafe5dU,
                                                               0x5ad4cd82U,
                                                               0x67917280U,
                                                               0xe1ff2d38U,
                                                               0xff1e1bc1U,
                                                               0xa2a00c68U,
                                                               0xcc18f9bfU,
                                                               0x6178e0ddU,
                                                               0xb9371ec4U,
                                                               0xa755da82U,
                                                               0x2757041fU,
                                                               0x770947e6U,
                                                               0x9aeab477U,
                                                               0xb0434ab0U,
                                                               0xdf9e5b3bU,
                                                               0xab1ce841U,
                                                               0xd6b03307U,
                                                               0x832b3ef1U,
                                                               0xd77042ceU,
                                                               0x3a50f235U,
                                                               0xd3a9dfdfU,
                                                               0xfb6bf9dbU,
                                                               0x63caa53eU,
                                                               0xa15d9421U,
                                                               0xff35921bU,
                                                               0x5e4e6e3dU,
                                                               0xc20e518bU,
                                                               0x531ea85aU,
                                                               0x82482951U,
                                                               0xc66b5f4aU,
                                                               0x799047f6U,
                                                               0x365f9b8bU,
                                                               0x53671571U,
                                                               0x156e58cfU,
                                                               0x01cd1772U,
                                                               0xb36aea7fU
                                                           };
                                                           
                                                           static const uint32_t T1_3[256] = {
                                                               0xc75ab505U,
                                                               0x2bae55aeU,
                                                               0xcd898202U,
                                                               0x93008577U,
                                                               0xdb021fafU,
                                                               0x8e2a67d8U,
                                                               0xfa1faf86U,
                                                               0x81378383U,
                                                               0x60db78c0U,
                                                               0xac383397U,
                                                               0x95be0d8dU,
                                                               0xdf7e8a3eU,
                                                               0x00de9d41U,
                                                               0xa57ef296U,
                                                               0x646c5a5cU,
                                                               0x346ee05aU,
                                                               0xe24c7529U,
                                                               0x9a9a0ab5U,
                                                               0xdd70a47aU,
                                                               0x0459adeeU,
                                                               0x7fa9c51cU,
                                                               0x2f0c0d3fU,
                                                               0x8a630791U,
                                                               0x62253141U,
                                                               0xa76f0854U,
                                                               0x89dcfd47U,
                                                               0x60b83631U,
                                                               0xd3117215U,
                                                               0x64c4cfb8U,
                                                               0x355ae694U,
                                                               0x96307e9eU,
                                                               0x87b4969cU,
                                                               0x22f7030bU,
                                                               0x30e2431bU,
                                                               0xc0fc1b82U,
                                                               0x118d7e3aU,
                                                               0x0d6475dfU,
                                                               0x95c2e69cU,
                                                               0xe5ae385eU,
                                                               0xf9a03a20U,
                                                               0x6588d0eeU,
                                                               0x90ad655eU,
                                                               0xb3658b9eU,
                                                               0xe26a0984U,
                                                               0x3ef32402U,
                                                               0x604d6e2dU,
                                                               0xf454a7d6U,
                                                               0x0c7ce1a2U,
                                                               0xbd83756dU,
                                                               0x10bec613U,
                                                               0x66147331U,
                                                               0xdd35ea43U,
                                                               0x3fe8de1bU,
                                                               0x3394b441U,
                                                               0x576689bdU,
                                                               0x84d1fab4U,
                                                               0xca081ae9U,
                                                               0x1eff7144U,
                                                               0x525d31edU,
                                                               0x68b105b5U,
                                                               0x5f21196bU,
                                                               0x08ab9773U,
                                                               0x020cf022U,
                                                               0xfb397795U,
                                                               0x5de8e64fU,
                                                               0x8e60cf54U,
                                                               0x3ef3c3c8U,
                                                               0x0084397cU,
                                                               0x223f192aU,
                                                               0xa9d72e0fU,
                                                               0x2e2ed869U,
                                                               0xf81bfd61U,
                                                               0x6ebb653aU,
                                                               0xc56ef3bdU,
                                                               0xc0f170b9U,
                                                               0xeae5d1d3U,
                                                               0x157226d0U,
                                                               0x33a07c1fU,
                                                               0x0d538097U,
                                                               0x84aadc80U,
                                                               0x5c296224U,
                                                               0x618c7cafU,
                                                               0x2ebbec90U,
                                                               0x0fa7fe96U,
                                                               0x4d132dc0U,
                                                               0x0f6e03e2U,
                                                               0xb93a8064U,
                                                               0x58071174U,
                                                               0x7b40ec4dU,
                                                               0xa31959a4U,
                                                               0x1e14be79U,
                                                               0xb497ff13U,
                                                               0xf770b5fdU,
                                                               0xe3093751U,
                                                               0xc90bf71bU,
                                                               0xb027bc55U,
                                                               0x29dd080dU,
                                                               0x453687a6U,
                                                               0x36149989U,
                                                               0x46a3217fU,
                                                               0x4da70793U,
                                                               0xd38ed8b6U,
                                                               0x0261b7d4U,
                                                               0x7e197bbbU,
                                                               0x8d811f05U,
                                                               0x7ab87a36U,
                                                               0x58012b45U,
                                                               0xe94c81bfU,
                                                               0xaa077557U,
                                                               0x043f8e41U,
                                                               0xcc3b9afeU,
                                                               0xb5393e5bU,
                                                               0xb0cf9e74U,
                                                               0xac97c59eU,
                                                               0xc23e1aebU,
                                                               0x95850339U,
                                                               0xea3a7cb7U,
                                                               0xf2ca589cU,
                                                               0xdb11c9c4U,
                                                               0x4699cd7fU,
                                                               0xd1c500fbU,
                                                               0xff6fffa0U,
                                                               0x9af7de1cU,
                                                               0x4ae40422U,
                                                               0x2569bbcdU,
                                                               0xecb079abU,
                                                               0xe8e43b1eU,
                                                               0x5f26410dU,
                                                               0xf1c6ca07U,
                                                               0xa30e652fU,
                                                               0x1b1b67d3U,
                                                               0xc9115f91U,
                                                               0xa47356b6U,
                                                               0x994f9de6U,
                                                               0x50f17acbU,
                                                               0x35f26b50U,
                                                               0xf9e2153fU,
                                                               0x75a8f68eU,
                                                               0xca34c40dU,
                                                               0xfc38a74bU,
                                                               0x6ff5002fU,
                                                               0x4f7fb905U,
                                                               0x54d1c260U,
                                                               0x359a4b2fU,
                                                               0x987ec3f0U,
                                                               0xc1f48e2dU,
                                                               0x49fdedb8U,
                                                               0x2ddf493dU,
                                                               0x8863ceb9U,
                                                               0x7df4cc77U,
                                                               0x259bab98U,
                                                               0x0232ce1dU,
                                                               0x323d37abU,
                                                               0xf08bc757U,
                                                               0x532d7375U,
                                                               0x60061097U,
                                                               0x3bba4125U,
                                                               0x49c045e0U,
                                                               0x1a7226b0U,
                                                               0x3b32507eU,
                                                               0x8fba91faU,
                                                               0x75ac8b02U,
                                                               0x36472356U,
                                                               0x6b6698a7U,
                                                               0xe1820208U,
                                                               0x7d1ece65U,
                                                               0xc9f768eaU,
                                                               0x4f5b6ad6U,
                                                               0x06755a47U,
                                                               0xdd525033U,
                                                               0x3bbdf5a8U,
                                                               0x101e148bU,
                                                               0x54f72f68U,
                                                               0xe3098dccU,
                                                               0x6d9806e6U,
                                                               0xeb3a1068U,
                                                               0x82bde139U,
                                                               0x6f584e08U,
                                                               0x917fe5edU,
                                                               0xcbad6292U,
                                                               0xec2b2d5eU,
                                                               0x053f0e3bU,
                                                               0xbc1b1795U,
                                                               0x914bfd9cU,
                                                               0x828c8f99U,
                                                               0xa1d7612aU,
                                                               0x5080be4cU,
                                                               0x7ad913b7U,
                                                               0x41dcf2a1U,
                                                               0xa6beea2eU,
                                                               0x6f08cfbaU,
                                                               0x1c3ee257U,
                                                               0xbca800ffU,
                                                               0x48ad584eU,
                                                               0x1da432fdU,
                                                               0x1d62bcbbU,
                                                               0x962e555cU,
                                                               0x363bf713U,
                                                               0x6a3fd400U,
                                                               0xaa0a6aa6U,
                                                               0x4ce02d7cU,
                                                               0xb60b7e82U,
                                                               0xf7afd7a5U,
                                                               0x76b2d836U,
                                                               0x40e139c7U,
                                                               0x6120531eU,
                                                               0x49dbae4dU,
                                                               0x1cb0614dU,
                                                               0xe0db3784U,
                                                               0x47553330U,
                                                               0x7c7a7e8eU,
                                                               0x7edfe94eU,
                                                               0x864188a6U,
                                                               0x20a9997cU,
                                                               0x361ec9ebU,
                                                               0x023a0b05U,
                                                               0xde979695U,
                                                               0xf212027cU,
                                                               0x5ccb13edU,
                                                               0x77b0f0edU,
                                                               0xf4fca59cU,
                                                               0x084c6ca2U,
                                                               0x5e7fd73bU,
                                                               0x2264bccdU,
                                                               0x48115164U,
                                                               0x61899fdeU,
                                                               0xdf982724U,
                                                               0x9fde104dU,
                                                               0x749e0e10U,
                                                               0x79371978U,
                                                               0x8c7550f7U,
                                                               0xe7c846dfU,
                                                               0x511698d0U,
                                                               0xc2da3691U,
                                                               0xa66e3218U,
                                                               0xd02ca231U,
                                                               0x3f1640e3U,
                                                               0x431ee7aeU,
                                                               0xb1f13252U,
                                                               0xba91f658U,
                                                               0x6cb7d1edU,
                                                               0x0a33af20U,
                                                               0x4011ac2fU,
                                                               0xae4deceaU,
                                                               0x03acf3c5U,
                                                               0x7e3c2023U,
                                                               0xa371beceU,
                                                               0xf09f4d2dU,
                                                               0x4fc52195U,
                                                               0xd700f950U,
                                                               0x64568faaU,
                                                               0x553b4d0fU,
                                                               0x61783c90U,
                                                               0x10553ac4U,
                                                               0x3e6b5545U,
                                                               0xf7aaf26bU
                                                           };
                                                           
                                                           static __attribute__((always_inline)) inline uint32_t rotl32(uint32_t x, uint32_t n) noexcept {
                                                           
                                                               return ((x << n) | (x >> (0x00000020U - n)));
                                                           }
                                                           
                                                           static __attribute__((always_inline)) inline uint32_t derive_seed() noexcept {
                                                           
                                                               const uint32_t s0 = 0x5466cdd9U;
                                                               uint32_t x0 = T0_0[(s0 & 0x000000ffU)];
                                                               uint32_t x1 = T0_1[((s0 >> 0x00000008U) & 0x000000ffU)];
                                                               uint32_t x2 = T0_2[((s0 >> 0x00000010U) & 0x000000ffU)];
                                                               uint32_t x3 = T0_3[((s0 >> 0x00000018U) & 0x000000ffU)];
                                                               uint32_t y0 = (rotl32(x0, 0x00000007U) ^ x1);
                                                               uint32_t y1 = (rotl32(x1, 0x0000000bU) ^ x2);
                                                               uint32_t y2 = (rotl32(x2, 0x00000013U) ^ x3);
                                                               uint32_t y3 = (rotl32(x3, 0x00000017U) ^ x0);
                                                               uint32_t z0 = T1_0[(y0 & 0x000000ffU)];
                                                               uint32_t z1 = T1_1[(y1 & 0x000000ffU)];
                                                               uint32_t z2 = T1_2[(y2 & 0x000000ffU)];
                                                               uint32_t z3 = T1_3[(y3 & 0x000000ffU)];
                                                               return (((z0 ^ z1) ^ z2) ^ z3);
                                                           }
                                
                                } // namespace asgard_whitebox
                                
                                static __attribute__((always_inline)) inline uint32_t asgard_wbox_derive_seed() noexcept {
                                
                                    return asgard_whitebox::derive_seed();
                                }
                                
                                // Randomized Architectural Register Map (π ∈ S_32)
                                
                                enum RegMap : uint8_t {
                                                           REG_RAX = 19,
                                                           REG_RCX = 1,
                                                           REG_RDX = 9,
                                                           REG_RBX = 3,
                                                           REG_RSP = 27,
                                                           REG_RBP = 5,
                                                           REG_RSI = 24,
                                                           REG_RDI = 29,
                                                           REG_R8 = 25,
                                                           REG_R9 = 4,
                                                           REG_R10 = 12,
                                                           REG_R11 = 2,
                                                           REG_R12 = 23,
                                                           REG_R13 = 6,
                                                           REG_R14 = 14,
                                                           REG_R15 = 7,
                                                           REG_VTMP0 = 30,
                                                           REG_VTMP1 = 13,
                                                           REG_VTMP2 = 17,
                                                           REG_VTMP3 = 21,
                                                           REG_VIP = 0,
                                                           REG_VSP = 11,
                                                           REG_VKEY = 18,
                                                           REG_VX18 = 26,
                                                           REG_VX19 = 31,
                                                           REG_VX20 = 20,
                                                           REG_VX21 = 10,
                                                           REG_VX22 = 22,
                                                           REG_VX23 = 28,
                                                           REG_VX24 = 16,
                                                           REG_VX25 = 15,
                                                           REG_VX26 = 8,
                                                           
                                };
                                
                                // 64-bit Cryptographic Key Derivation for Bytecode Offset (SplitMix64)
                                
                                __attribute__((always_inline)) inline static uint64_t key64_for_offset(uint32_t seed, size_t offset) noexcept {
                                
                                    uint64_t s64 = static_cast<uint64_t>(seed);
                                    uint64_t x0 = (((s64 << 0x0000000000000020ULL) | (s64 ^ 0x000000009e3779b9ULL)) ^ (static_cast<uint64_t>(offset) * 0x517cc1b727220a95ULL));
                                    uint64_t x1 = ((x0 ^ (x0 >> 0x000000000000001eULL)) * 0xbf58476d1ce4e5b9ULL);
                                    uint64_t x2 = ((x1 ^ (x1 >> 0x000000000000001bULL)) * 0x94d049bb133111ebULL);
                                    return (x2 ^ (x2 >> 0x000000000000001fULL));
                                }
                                
                                // Handlers Table Integrity Hash
                                
                                __attribute__((always_inline)) inline static uint64_t compute_handlers_hash(const uintptr_t* all_domains, size_t num_domains) noexcept {
                                
                                    uint64_t h = 0x5877cafebabe1337ULL;
                                    for (size_t d = 0x0000000000000000ULL; d < num_domains; ++d) {
                                    
                                        for (size_t op = 0x0000000000000000ULL; op < 0x0000000000000100ULL; ++op) {
                                        
                                            uint64_t ptr_val = static_cast<uint64_t>(all_domains[((d * 0x0000000000000100ULL) + op)]);
                                            h ^= (ptr_val * 0x9e3779b97f4a7c15ULL);
                                            h = ((h >> 0x000000000000001bULL) | (h << 0x0000000000000025ULL));
                                            h *= 0xbf58476d1ce4e5b9ULL;
                                        }
                                    }
                                    h ^= asgard_mem_integrity::compute_section_integrity_hash();
                                    return (h ^ (h >> 0x000000000000001fULL));
                                }
                                
                                // Blinded VMContext with Canary Guard Zones & Per-Slot Masking (P1-04b)
                                
                                struct VMContext {
                                                      static inline constexpr uint64_t CANARY_VAL = 0xcafebabe13375877ULL;
                                                      uint64_t canary_head = CANARY_VAL;
                                                      uint64_t mid_canaries[32];
                                                      uint64_t gprs[32];
                                                      uint64_t slot_masks[32];
                                                      uint64_t vregs[32][8];
                                                      uint64_t stack[512];
                                                      size_t sp;
                                                      uint64_t reg_mask;
                                                      uint32_t init_seed;
                                                      uint64_t poison_penalty;
                                                      uint64_t running_key;
                                                      bool cf;
                                                      bool zf;
                                                      bool sf;
                                                      bool of;
                                                      bool trapped;
                                                      size_t executed_instructions;
                                                      uint64_t canary_tail = CANARY_VAL;
                                                      static inline constexpr size_t REG_AFFINE_A = 17;
                                                      static inline constexpr size_t REG_AFFINE_B = 17;
                                                      static __attribute__((always_inline)) inline uint8_t reg_phys_idx(uint8_t i) noexcept {
                                                      
                                                          return static_cast<uint8_t>((((static_cast<size_t>((i & 31)) * REG_AFFINE_A) + REG_AFFINE_B) & 31));
                                                      }
                                                      __attribute__((always_inline)) inline void init(uint32_t seed = asgard_wbox_derive_seed()) noexcept {
                                                      
                                                          init_seed = seed;
                                                          poison_penalty = ((key64_for_offset(seed, 0x0000000000005877ULL) ^ 0xcaa7e1d8718bf877ULL) | 0x0000000000000001ULL);
                                                          running_key = (key64_for_offset(seed, 0x0000000013375877ULL) ^ 0xcafebabe13375877ULL);
                                                          reg_mask = (0x5a5a5a5a13375877ULL ^ (static_cast<uint64_t>(seed) * 0x9e3779b97f4a7c15ULL));
                                                          for (size_t i = 0x0000000000000000ULL; i < 0x0000000000000020ULL; ++i) {
                                                          
                                                              slot_masks[i] = (key64_for_offset(seed, (0x0000000000001000ULL + i)) ^ 0xa5a5a5a51337beefULL);
                                                              gprs[i] = (slot_masks[i] ^ reg_mask);
                                                              mid_canaries[i] = (CANARY_VAL ^ ((static_cast<uint64_t>(i) * 0x517cc1b727220a95ULL) ^ static_cast<uint64_t>(seed)));
                                                              vregs[i][0] = 0x0000000000000000ULL;
                                                              for (size_t v = 0x0000000000000001ULL; v < 0x0000000000000008ULL; ++v) {
                                                              
                                                                  vregs[i][v] = 0x0000000000000000ULL;
                                                              }
                                                          }
                                                          sp = 0x0000000000000000ULL;
                                                          cf = false;
                                                          zf = false;
                                                          sf = false;
                                                          of = false;
                                                          trapped = false;
                                                          executed_instructions = 0x0000000000000000ULL;
                                                          canary_head = CANARY_VAL;
                                                          canary_tail = CANARY_VAL;
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t advance_key_step(uint64_t k, uint8_t op, uint8_t dst, int64_t imm) noexcept {
                                                      
                                                          uint64_t x = (k ^ (((static_cast<uint64_t>(op) * 0x9e3779b97f4a7c15ULL) + (static_cast<uint64_t>(dst) << 0x0000000000000018ULL)) + static_cast<uint64_t>(imm)));
                                                          uint64_t rot = ((x >> 0x0000000000000017ULL) | (x << 0x0000000000000029ULL));
                                                          return ((rot * 0xbf58476d1ce4e5b9ULL) ^ 0x5877cafe1337beefULL);
                                                      }
                                                      __attribute__((always_inline)) inline void advance_running_key(uint8_t op, uint8_t dst, int64_t imm) noexcept {
                                                      
                                                          running_key = advance_key_step(running_key, op, dst, imm);
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t anchor_key(uint32_t seed, uint64_t off, uint64_t addr_hash = 0) noexcept {
                                                      
                                                          return (key64_for_offset((seed ^ 0x5bd1e995U), static_cast<size_t>((off ^ 0x0000000013375877ULL))) ^ addr_hash);
                                                      }
                                                      __attribute__((always_inline)) inline void reanchor_running_key(uint64_t off, uint64_t addr_hash = 0) noexcept {
                                                      
                                                          running_key = anchor_key(init_seed, off, addr_hash);
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t poly_hash64(uint64_t x) noexcept {
                                                      
                                                          uint64_t x1 = ((x ^ (x >> 0x000000000000001eULL)) * 0xbf58476d1ce4e5b9ULL);
                                                          uint64_t x2 = ((x1 ^ (x1 >> 0x000000000000001bULL)) * 0x94d049bb133111ebULL);
                                                          return (x2 ^ (x2 >> 0x000000000000001fULL));
                                                      }
                                                      static __attribute__((always_inline)) inline uint64_t branch_invariant_poly_update(uint64_t key, uint64_t delta, uint64_t poly_const) noexcept {
                                                      
                                                          uint64_t c = (poly_const | 0x0000000000000001ULL);
                                                          return poly_hash64((key ^ (c * delta)));
                                                      }
                                                      __attribute__((always_inline)) inline void apply_poly_merge_update(uint64_t delta, uint64_t poly_const) noexcept {
                                                      
                                                          running_key = branch_invariant_poly_update(running_key, delta, poly_const);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_vkey() const noexcept {
                                                      
                                                          return running_key;
                                                      }
                                                      __attribute__((always_inline)) inline bool verify_canaries() const noexcept {
                                                      
                                                          if ((canary_head != CANARY_VAL) || (canary_tail != CANARY_VAL)) {
                                                          
                                                              return false;
                                                          }
                                                          size_t frame = ((sp >> 0x0000000000000004ULL) & 0x000000000000001fULL);
                                                          uint64_t expected = ((CANARY_VAL ^ (static_cast<uint64_t>(frame) * 0x517cc1b727220a95ULL)) ^ static_cast<uint64_t>(init_seed));
                                                          return (mid_canaries[frame] == expected);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_reg(uint8_t i) const noexcept {
                                                      
                                                          size_t idx = static_cast<size_t>(reg_phys_idx(i));
                                                          return ((gprs[idx] ^ slot_masks[idx]) ^ reg_mask);
                                                      }
                                                      __attribute__((always_inline)) inline void set_reg(uint8_t i, uint64_t v) noexcept {
                                                      
                                                          size_t idx = static_cast<size_t>(reg_phys_idx(i));
                                                          uint64_t new_m = ((slot_masks[idx] ^ running_key) * 0x9e3779b97f4a7c15ULL);
                                                          slot_masks[idx] = new_m;
                                                          gprs[idx] = (v ^ (new_m ^ reg_mask));
                                                      }
                                                      __attribute__((always_inline)) inline void evolve_slot_mask(uint8_t i, uint32_t k) noexcept {
                                                      
                                                          size_t idx = static_cast<size_t>(reg_phys_idx(i));
                                                          uint64_t cur_val = (gprs[idx] ^ (slot_masks[idx] ^ reg_mask));
                                                          uint64_t delta = ((static_cast<uint64_t>(k) * 0x6a09e667f3bcc908ULL) ^ (static_cast<uint64_t>(idx) * 0x517cc1b727220a95ULL));
                                                          slot_masks[idx] = ((slot_masks[idx] ^ delta) * 0xbf58476d1ce4e5b9ULL);
                                                          gprs[idx] = (cur_val ^ (slot_masks[idx] ^ reg_mask));
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_vreg_lane(uint8_t i, size_t lane) const noexcept {
                                                      
                                                          return vregs[(i & 31)][(lane & 7)];
                                                      }
                                                      __attribute__((always_inline)) inline void set_vreg_lane(uint8_t i, size_t lane, uint64_t value) noexcept {
                                                      
                                                          vregs[(i & 31)][(lane & 7)] = value;
                                                      }
                                                      __attribute__((always_inline)) inline void set_vreg(uint8_t i, uint64_t lo, uint64_t hi) noexcept {
                                                      
                                                          vregs[(i & 31)][0] = lo;
                                                          vregs[(i & 31)][1] = hi;
                                                          for (size_t v = 0x0000000000000002ULL; v < 0x0000000000000008ULL; ++v) {
                                                          
                                                              vregs[(i & 31)][v] = 0x0000000000000000ULL;
                                                          }
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_rax() const noexcept {
                                                      
                                                          return get_reg(REG_RAX);
                                                      }
                                                      __attribute__((always_inline)) inline void set_rax(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_RAX, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_rdi() const noexcept {
                                                      
                                                          return get_reg(REG_RDI);
                                                      }
                                                      __attribute__((always_inline)) inline void set_rdi(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_RDI, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_rsi() const noexcept {
                                                      
                                                          return get_reg(REG_RSI);
                                                      }
                                                      __attribute__((always_inline)) inline void set_rsi(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_RSI, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_fs_base() const noexcept {
                                                      
                                                          return get_reg(REG_VX25);
                                                      }
                                                      __attribute__((always_inline)) inline void set_fs_base(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_VX25, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t get_gs_base() const noexcept {
                                                      
                                                          return get_reg(REG_VX26);
                                                      }
                                                      __attribute__((always_inline)) inline void set_gs_base(uint64_t v) noexcept {
                                                      
                                                          set_reg(REG_VX26, v);
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t rns_add(uint64_t a, uint64_t b) const noexcept {
                                                      
                                                          return asgard_rns::decode(asgard_rns::add(asgard_rns::encode(a), asgard_rns::encode(b)));
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t rns_sub(uint64_t a, uint64_t b) const noexcept {
                                                      
                                                          return asgard_rns::decode(asgard_rns::sub(asgard_rns::encode(a), asgard_rns::encode(b)));
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t rns_mul(uint64_t a, uint64_t b) const noexcept {
                                                      
                                                          return asgard_rns::decode(asgard_rns::mul(asgard_rns::encode(a), asgard_rns::encode(b)));
                                                      }
                                                      __attribute__((always_inline)) inline void evolve_mask(uint32_t k) noexcept {
                                                      
                                                          uint64_t delta = ((static_cast<uint64_t>(k) * 0x6a09e667f3bcc908ULL) ^ 0x0000000000001337ULL);
                                                          uint64_t old_mask = reg_mask;
                                                          uint64_t new_mask = ((reg_mask ^ delta) + 0x0000000000005877ULL);
                                                          for (size_t i = 0x0000000000000000ULL; i < 0x0000000000000020ULL; ++i) {
                                                          
                                                              gprs[i] = ((gprs[i] ^ old_mask) ^ new_mask);
                                                          }
                                                          reg_mask = new_mask;
                                                      }
                                                      __attribute__((always_inline)) inline void rotate_registers_epoch(uint32_t from_ep, uint32_t to_ep) noexcept {
                                                      
                                                          uint32_t tr = (((from_ep & 3) << 2) | (to_ep & 3));
                                                          switch (tr) {
                                                          
                                                            case 1: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(6)]);
                                                                break;
                                                            }
                                                            case 2: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(6)]);
                                                                break;
                                                            }
                                                            case 3: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(11)]);
                                                                break;
                                                            }
                                                            case 4: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(7)]);
                                                                break;
                                                            }
                                                            case 6: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(12)]);
                                                                break;
                                                            }
                                                            case 7: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(4)]);
                                                                break;
                                                            }
                                                            case 8: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(14)]);
                                                                break;
                                                            }
                                                            case 9: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(5)]);
                                                                break;
                                                            }
                                                            case 11: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(9)]);
                                                                break;
                                                            }
                                                            case 12: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(6)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(6)], slot_masks[reg_phys_idx(13)]);
                                                                break;
                                                            }
                                                            case 13: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(2)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(2)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(1)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(1)], slot_masks[reg_phys_idx(13)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(11)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(11)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(3)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(3)], slot_masks[reg_phys_idx(7)]);
                                                                break;
                                                            }
                                                            case 14: {
                                                            
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(3)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(3)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(14)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(14)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(4)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(4)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(1)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(1)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(15)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(15)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(12)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(12)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(6)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(6)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(8)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(8)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(10)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(10)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(7)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(7)]);
                                                                std::swap(gprs[reg_phys_idx(0)], gprs[reg_phys_idx(5)]);
                                                                std::swap(slot_masks[reg_phys_idx(0)], slot_masks[reg_phys_idx(5)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(9)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(9)]);
                                                                std::swap(gprs[reg_phys_idx(2)], gprs[reg_phys_idx(13)]);
                                                                std::swap(slot_masks[reg_phys_idx(2)], slot_masks[reg_phys_idx(13)]);
                                                                break;
                                                            }
                                                            default: {
                                                            
                                                                break;
                                                            }
                                                          }
                                                      }
                                                      static inline constexpr size_t STACK_SIZE = 512;
                                                      static inline constexpr size_t STACK_STRIDE = 193;
                                                      static inline constexpr size_t STACK_OFFSET = 11;
                                                      __attribute__((always_inline)) inline size_t scramble_stack_idx(size_t index) const noexcept {
                                                      
                                                          return static_cast<size_t>((((index * STACK_STRIDE) + STACK_OFFSET) & (STACK_SIZE - 1)));
                                                      }
                                                      __attribute__((always_inline)) inline void push(uint64_t v) noexcept {
                                                      
                                                          if (!verify_canaries()) {
                                                          
                                                              reg_mask ^= poison_penalty;
                                                              trapped = true;
                                                          }
                                                          if (sp < STACK_SIZE) {
                                                          
                                                              size_t phys_idx = scramble_stack_idx(sp);
                                                              uint64_t enc_mask = ((static_cast<uint64_t>(sp) * 0x9e3779b97f4a7c15ULL) ^ 0xa5a5a5a55a5a5a5aULL);
                                                              stack[phys_idx] = (v ^ enc_mask);
                                                              sp += 1;
                                                          }
                                                      }
                                                      __attribute__((always_inline)) inline uint64_t pop() noexcept {
                                                      
                                                          if (!verify_canaries()) {
                                                          
                                                              reg_mask ^= poison_penalty;
                                                              trapped = true;
                                                          }
                                                          if (sp > 0) {
                                                          
                                                              sp -= 1;
                                                              size_t phys_idx = scramble_stack_idx(sp);
                                                              uint64_t enc_mask = ((static_cast<uint64_t>(sp) * 0x9e3779b97f4a7c15ULL) ^ 0xa5a5a5a55a5a5a5aULL);
                                                              uint64_t val = (stack[phys_idx] ^ enc_mask);
                                                              stack[phys_idx] = (0xdeadbeefcafe1337ULL ^ enc_mask);
                                                              return val;
                                                          }
                                                          return 0x0000000000000000ULL;
                                                      }
                                                      uint64_t trace_digest = 0x53b7d9f7a1b4283eULL;
                                                      uint64_t bridge_state[16];
                                                          inline void morph_math_to_flow(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : trace_digest;
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_math_to_flow(regs, bridge_state, dig);
        trace_digest = bridge_rol64(dig, 13) ^ 0x5877CAFEULL;
#else
        (void)target_digest;
#endif
    }
                                                          inline void morph_flow_to_math(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : (bridge_rol64(trace_digest, 51) ^ 0x5877CAFEULL);
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_flow_to_math(bridge_state, regs, dig);
        trace_digest = dig;
#else
        (void)target_digest;
#endif
    }
                                                      
                                };
                                
                                // Flag Evaluation and Condition Check Helpers
                                
                                __attribute__((always_inline)) inline static bool eval_condition(const VMContext& ctx, uint8_t cond) noexcept {
                                
                                    switch (cond) {
                                                     case 0: {
                                                                  return ctx.zf;
                                                     }
                                                     case 1: {
                                                                  return (!ctx.zf);
                                                     }
                                                     case 2: {
                                                                  return ctx.cf;
                                                     }
                                                     case 3: {
                                                                  return (!ctx.cf);
                                                     }
                                                     case 4: {
                                                                  return (ctx.cf || ctx.zf);
                                                     }
                                                     case 5: {
                                                                  return ((!ctx.cf) && (!ctx.zf));
                                                     }
                                                     case 6: {
                                                                  return ctx.sf;
                                                     }
                                                     case 7: {
                                                                  return (!ctx.sf);
                                                     }
                                                     case 8: {
                                                                  return (ctx.sf != ctx.of);
                                                     }
                                                     case 9: {
                                                                  return (ctx.sf == ctx.of);
                                                     }
                                                     case 10: {
                                                                   return (ctx.zf || (ctx.sf != ctx.of));
                                                     }
                                                     case 11: {
                                                                   return ((!ctx.zf) && (ctx.sf == ctx.of));
                                                     }
                                                     case 12: {
                                                                   return ctx.of;
                                                     }
                                                     case 13: {
                                                                   return (!ctx.of);
                                                     }
                                                     case 14: {
                                                                   return true;
                                                     }
                                                     default: {
                                                                   return true;
                                                     }
                                    }
                                }
                                
                                __attribute__((always_inline)) inline static void compute_sub_flags(VMContext& ctx, uint64_t a, uint64_t b, uint32_t bits) noexcept {
                                
                                    if ((bits == 0) || (bits >= 64)) {
                                    
                                        uint64_t res = (a - b);
                                        ctx.zf = (res == 0x0000000000000000ULL);
                                        ctx.sf = (static_cast<int64_t>(res) < 0LL);
                                        ctx.cf = (a < b);
                                        ctx.of = ((((a ^ b) & (a ^ res)) >> 0x000000000000003fULL) != 0x0000000000000000ULL);
                                    } else {
                                                uint64_t mask = ((0x0000000000000001ULL << bits) - 0x0000000000000001ULL);
                                                uint64_t sign_bit = (0x0000000000000001ULL << (bits - 1));
                                                uint64_t a_val = (a & mask);
                                                uint64_t b_val = (b & mask);
                                                uint64_t res = ((a_val - b_val) & mask);
                                                ctx.zf = (res == 0x0000000000000000ULL);
                                                ctx.sf = ((res & sign_bit) != 0x0000000000000000ULL);
                                                ctx.cf = (a_val < b_val);
                                                ctx.of = ((((a_val ^ b_val) & (a_val ^ res)) & sign_bit) != 0x0000000000000000ULL);
                                    }
                                }
                                
                                __attribute__((always_inline)) inline static void compute_add_flags(VMContext& ctx, uint64_t a, uint64_t b, uint32_t bits) noexcept {
                                
                                    if ((bits == 0) || (bits >= 64)) {
                                    
                                        uint64_t res = (a + b);
                                        ctx.zf = (res == 0x0000000000000000ULL);
                                        ctx.sf = (static_cast<int64_t>(res) < 0LL);
                                        ctx.cf = (res < a);
                                        ctx.of = ((((~((a ^ b))) & (a ^ res)) >> 0x000000000000003fULL) != 0x0000000000000000ULL);
                                    } else {
                                                uint64_t mask = ((0x0000000000000001ULL << bits) - 0x0000000000000001ULL);
                                                uint64_t sign_bit = (0x0000000000000001ULL << (bits - 1));
                                                uint64_t a_val = (a & mask);
                                                uint64_t b_val = (b & mask);
                                                uint64_t res = ((a_val + b_val) & mask);
                                                ctx.zf = (res == 0x0000000000000000ULL);
                                                ctx.sf = ((res & sign_bit) != 0x0000000000000000ULL);
                                                ctx.cf = (res < a_val);
                                                ctx.of = ((((~((a_val ^ b_val))) & (a_val ^ res)) & sign_bit) != 0x0000000000000000ULL);
                                    }
                                }
                                
                                static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = asgard_wbox_derive_seed() /* seed = 0x79D1ADF1U */, bool scrub_source = false) {
                                
                                    if (ctx.reg_mask == 0x0000000000000000ULL) {
                                    
                                        ctx.init(seed);
                                    }
                                    asgard_nanomites::install_nanomite_handlers(seed);
                                    uint64_t full_hash = 0xfc0b8edeacc251dcULL;
                                    for (size_t i = 0x0000000000000000ULL; i < count; ++i) {
                                    
                                        full_hash = (((full_hash ^ bytecode[i]) * 0xbd612da8e8d7a6f7ULL) + ((uint64_t)(i)));
                                    }
                                    uint64_t hash_diff = (full_hash ^ 0xb92fa541ab45a8e4ULL);
                                    ctx.running_key ^= hash_diff;
                                    ctx.reg_mask ^= (hash_diff * 0x00005877cafebeefULL);
                                    if (hash_diff != 0x0000000000000000ULL) {
                                    
                                        ctx.trapped = true;
                                        return false;
                                    }
                                    if (asgard_syscalls::sys_check_debugger_present()) {
                                    
                                        ctx.reg_mask ^= 0xcafebabe13375877ULL;
                                        ctx.trapped = true;
                                        return false;
                                    }
                                    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
                                    if (emu_penalty != 0x0000000000000000ULL) {
                                    
                                        ctx.reg_mask ^= emu_penalty;
                                    }
                                    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe(((uint64_t)(seed)));
                                    if (smc_penalty != 0x0000000000000000ULL) {
                                    
                                        ctx.reg_mask ^= smc_penalty;
                                    }
                                    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();
                                    if (mem_penalty != 0x0000000000000000ULL) {
                                    
                                        ctx.reg_mask ^= mem_penalty;
                                    }
                                    uint64_t stack_buf[256];
                                    uint64_t* heap_work_bc = ((count <= 0x0000000000000100ULL) ? nullptr : ((uint64_t*)(malloc((count * sizeof(uint64_t))))));
                                    uint64_t* work_bc = ((count <= 0x0000000000000100ULL) ? stack_buf : heap_work_bc);
                                    if (__builtin_expect((!work_bc), 0)) {
                                    
                                        ctx.trapped = true;
                                        return false;
                                    }
                                    for (size_t i = 0x0000000000000000ULL; i < count; ++i) {
                                    
                                        work_bc[i] = (0x5877cafe1337beefULL ^ (((uint64_t)(seed)) + ((uint64_t)(i))));
                                    }
                                    size_t vIP_idx = 0x0000000000000000ULL;
                                    static const uint8_t domain_salt[4] = { 0x00, 0xA0, 0xB3, 0xB4 };
                                    static uintptr_t all_dispatch_domains[4][256];
    static bool dispatch_domains_ready = false;
    if (__builtin_expect(!dispatch_domains_ready, 0)) {
#if !defined(_MSC_VER) || defined(__clang__)
                                    static void* raw_domain0[256] = {
                                        &&H_DECOY_10,
                                        &&H_DECOY_5,
                                        &&H_FSQRT_D,
                                        &&H_DECOY_7,
                                        &&H_CCMN_RI,
                                        &&H_IDIV_RR,
                                        &&H_DECOY_11,
                                        &&H_DECOY_15,
                                        &&H_VSUB_VV,
                                        &&H_STORE_32,
                                        &&H_DECOY_5,
                                        &&H_IMULH_RR,
                                        &&H_DECOY_0,
                                        &&H_DECOY_15,
                                        &&H_DECOY_4,
                                        &&H_RET,
                                        &&H_FCVT,
                                        &&H_VMUL_VV,
                                        &&H_LOAD_S16,
                                        &&H_SET_FLAGS_R,
                                        &&H_FUSED_ADD_XOR_RRI,
                                        &&H_DECOY_0,
                                        &&H_STORE_64,
                                        &&H_DECOY_10,
                                        &&H_DECOY_5,
                                        &&H_VADD_VV,
                                        &&H_DECOY_0,
                                        &&H_RESOLVE_SYM,
                                        &&H_DECOY_15,
                                        &&H_DECOY_6,
                                        &&H_CLZ_RR,
                                        &&H_PMOVMSKB,
                                        &&H_DECOY_4,
                                        &&H_DECOY_8,
                                        &&H_VEC_SPLAT,
                                        &&H_DECOY_5,
                                        &&H_DECOY_0,
                                        &&H_DECOY_2,
                                        &&H_FUSED_CMP_CMOV,
                                        &&H_FUSED_XOR_ADD_RRI,
                                        &&H_DECOY_11,
                                        &&H_DECOY_14,
                                        &&H_FDIV_DD,
                                        &&H_AND_RR,
                                        &&H_DECOY_9,
                                        &&H_SAR_RI,
                                        &&H_BSWAP_RR,
                                        &&H_DECOY_4,
                                        &&H_VEC_IMM,
                                        &&H_STORE_8,
                                        &&H_ATOMIC_SWP,
                                        &&H_POPCNT_RR,
                                        &&H_FUSED_SUB_XOR_RRI,
                                        &&H_ATOMIC_CAS,
                                        &&H_CCMP_RI,
                                        &&H_DECOY_4,
                                        &&H_NOT_RR,
                                        &&H_OR_RI,
                                        &&H_DECOY_6,
                                        &&H_DECOY_0,
                                        &&H_DECOY_10,
                                        &&H_DECOY_6,
                                        &&H_DECOY_7,
                                        &&H_DECOY_7,
                                        &&H_LOAD_S32,
                                        &&H_FUSED_AND_OR_RRI,
                                        &&H_ROR_RI,
                                        &&H_DECOY_4,
                                        &&H_MOV_HIGH,
                                        &&H_DECOY_11,
                                        &&H_MOV_RR,
                                        &&H_DECOY_5,
                                        &&H_FSUB_DD,
                                        &&H_CALL_EXTERN,
                                        &&H_DECOY_12,
                                        &&H_DECOY_0,
                                        &&H_CCMP_RR,
                                        &&H_DECOY_11,
                                        &&H_CALL,
                                        &&H_DECOY_8,
                                        &&H_DECOY_11,
                                        &&H_SETCC,
                                        &&H_DECOY_4,
                                        &&H_LOAD_S8,
                                        &&H_LOAD_32,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_1,
                                        &&H_ADD_RI,
                                        &&H_SHR_RR,
                                        &&H_IJMP_R,
                                        &&H_FUSED_MOV_ADD_RRI,
                                        &&H_CMOV,
                                        &&H_DECOY_9,
                                        &&H_ADC_RR,
                                        &&H_DECOY_5,
                                        &&H_DECOY_1,
                                        &&H_DECOY_1,
                                        &&H_FUSED_ADD_IMUL_RRI,
                                        &&H_NOP,
                                        &&H_ATOMIC_STORE,
                                        &&H_DECOY_1,
                                        &&H_DECOY_12,
                                        &&H_LOAD_16,
                                        &&H_RBIT_RR,
                                        &&H_DECOY_10,
                                        &&H_ROR_RR,
                                        &&H_DECOY_8,
                                        &&H_DECOY_10,
                                        &&H_DECOY_6,
                                        &&H_SHR_RI,
                                        &&H_DECOY_6,
                                        &&H_DECOY_4,
                                        &&H_FCVTZU,
                                        &&H_DECOY_7,
                                        &&H_DECOY_0,
                                        &&H_ATOMIC_ADD,
                                        &&H_DECOY_11,
                                        &&H_VEC_CLEAR_UPPER,
                                        &&H_DECOY_0,
                                        &&H_SAR_RR,
                                        &&H_DECOY_6,
                                        &&H_IMUL_RR,
                                        &&H_XOR_RI,
                                        &&H_DECOY_12,
                                        &&H_CCMN_RR,
                                        &&H_IMUL_RI,
                                        &&H_DECOY_14,
                                        &&H_DECOY_10,
                                        &&H_XOR_RR,
                                        &&H_DECOY_11,
                                        &&H_CTZ_RR,
                                        &&H_BRIDGE_TO_MATH,
                                        &&H_DECOY_0,
                                        &&H_DECOY_13,
                                        &&H_DECOY_5,
                                        &&H_DECOY_4,
                                        &&H_DECOY_14,
                                        &&H_SUB_RR,
                                        &&H_SUB_RI,
                                        &&H_BRIDGE_TO_FLOW,
                                        &&H_VXOR_VV,
                                        &&H_DECOY_13,
                                        &&H_DECOY_3,
                                        &&H_DECOY_6,
                                        &&H_MOV_VR,
                                        &&H_DECOY_13,
                                        &&H_DECOY_3,
                                        &&H_FCMP_DD,
                                        &&H_ROL_RI,
                                        &&H_DECOY_13,
                                        &&H_DECOY_6,
                                        &&H_FENCE,
                                        &&H_DECOY_2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_9,
                                        &&H_DECOY_12,
                                        &&H_DECOY_11,
                                        &&H_DECOY_1,
                                        &&H_FUSED_SHL_ADD_RRI,
                                        &&H_DECOY_1,
                                        &&H_DECOY_0,
                                        &&H_DECOY_15,
                                        &&H_CMP_RR,
                                        &&H_DECOY_6,
                                        &&H_POP_R,
                                        &&H_DECOY_4,
                                        &&H_DECOY_11,
                                        &&H_ICALL_R,
                                        &&H_MOV_RI,
                                        &&H_PUSH_R,
                                        &&H_DECOY_1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_0,
                                        &&H_STORE_16,
                                        &&H_DECOY_11,
                                        &&H_VEC_STORE,
                                        &&H_MULH_RR,
                                        &&H_DECOY_9,
                                        &&H_JCC,
                                        &&H_DIV_RR,
                                        &&H_DECOY_4,
                                        &&H_VEC_MOV,
                                        &&H_DECOY_7,
                                        &&H_JMP,
                                        &&H_DECOY_7,
                                        &&H_DECOY_2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_SCVTF,
                                        &&H_DECOY_5,
                                        &&H_EXIT,
                                        &&H_NEG_RR,
                                        &&H_DECOY_0,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_DECOY_5,
                                        &&H_VEC_LOAD,
                                        &&H_SHL_RI,
                                        &&H_DECOY_14,
                                        &&H_DECOY_1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_13,
                                        &&H_ADD_RR,
                                        &&H_DECOY_15,
                                        &&H_DECOY_5,
                                        &&H_LOAD_64,
                                        &&H_GET_FLAGS_R,
                                        &&H_ADC_RI,
                                        &&H_DECOY_5,
                                        &&H_SBB_RI,
                                        &&H_VEC_EXT,
                                        &&H_DECOY_9,
                                        &&H_DECOY_4,
                                        &&H_DECOY_1,
                                        &&H_CMP_RI,
                                        &&H_DECOY_1,
                                        &&H_DECOY_10,
                                        &&H_FCVTZS,
                                        &&H_DECOY_8,
                                        &&H_UCVTF,
                                        &&H_DECOY_12,
                                        &&H_DECOY_12,
                                        &&H_DECOY_13,
                                        &&H_OR_RR,
                                        &&H_DECOY_2,
                                        &&H_FCSEL_VV,
                                        &&H_DECOY_15,
                                        &&H_DECOY_2,
                                        &&H_DECOY_0,
                                        &&H_FADD_DD,
                                        &&H_AND_RI,
                                        &&H_VEC_BINOP,
                                        &&H_SBB_RR,
                                        &&H_DECOY_12,
                                        &&H_DECOY_15,
                                        &&H_MOV_RV,
                                        &&H_DECOY_8,
                                        &&H_ROL_RR,
                                        &&H_DECOY_4,
                                        &&H_DECOY_3,
                                        &&H_DECOY_10,
                                        &&H_ATOMIC_LOAD,
                                        &&H_DECOY_2,
                                        &&H_SHL_RR,
                                        &&H_FMUL_DD,
                                        &&H_DECOY_3,
                                        &&H_LOAD_8,
                                        &&H_DECOY_3,
                                        &&H_DECOY_8,
                                        &&H_DECOY_12,
                                        &&H_VEC_ZERO_UPPER,
                                        &&H_DECOY_12
                                    };
                                    static void* raw_domain1[256] = {
                                        &&H_DECOY_8,
                                        &&H_DECOY_7,
                                        &&H_DECOY_6,
                                        &&H_CMP_RR_D1,
                                        &&H_DECOY_13,
                                        &&H_POP_R_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_2,
                                        &&H_ICALL_R_D1,
                                        &&H_MOV_RI_D1,
                                        &&H_PUSH_R_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_DECOY_7,
                                        &&H_STORE_16_D1,
                                        &&H_DECOY_2,
                                        &&H_VEC_STORE_D1,
                                        &&H_MULH_RR_D1,
                                        &&H_DECOY_0,
                                        &&H_JCC_D1,
                                        &&H_DIV_RR_D1,
                                        &&H_DECOY_11,
                                        &&H_VEC_MOV_D1,
                                        &&H_DECOY_14,
                                        &&H_JMP_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_9,
                                        &&H_DECOY_15,
                                        &&H_DECOY_8,
                                        &&H_SCVTF_D1,
                                        &&H_DECOY_12,
                                        &&H_EXIT_D1,
                                        &&H_DECOY_1,
                                        &&H_XOR_RR_D1,
                                        &&H_DECOY_2,
                                        &&H_CTZ_RR_D1,
                                        &&H_BRIDGE_TO_MATH_D1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_4,
                                        &&H_DECOY_12,
                                        &&H_DECOY_11,
                                        &&H_DECOY_5,
                                        &&H_SUB_RR_D1,
                                        &&H_SUB_RI_D1,
                                        &&H_BRIDGE_TO_FLOW_D1,
                                        &&H_VXOR_VV_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_10,
                                        &&H_DECOY_13,
                                        &&H_MOV_VR_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_10,
                                        &&H_FCMP_DD_D1,
                                        &&H_ROL_RI_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_13,
                                        &&H_FENCE_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_4,
                                        &&H_DECOY_0,
                                        &&H_DECOY_3,
                                        &&H_DECOY_2,
                                        &&H_DECOY_8,
                                        &&H_FUSED_SHL_ADD_RRI_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_3,
                                        &&H_DECOY_4,
                                        &&H_OR_RR_D1,
                                        &&H_DECOY_9,
                                        &&H_FCSEL_VV_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_9,
                                        &&H_DECOY_7,
                                        &&H_FADD_DD_D1,
                                        &&H_AND_RI_D1,
                                        &&H_VEC_BINOP_D1,
                                        &&H_SBB_RR_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_6,
                                        &&H_MOV_RV_D1,
                                        &&H_DECOY_15,
                                        &&H_ROL_RR_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_10,
                                        &&H_DECOY_1,
                                        &&H_ATOMIC_LOAD_D1,
                                        &&H_DECOY_9,
                                        &&H_SHL_RR_D1,
                                        &&H_FMUL_DD_D1,
                                        &&H_DECOY_10,
                                        &&H_LOAD_8_D1,
                                        &&H_DECOY_10,
                                        &&H_DECOY_15,
                                        &&H_DECOY_3,
                                        &&H_VEC_ZERO_UPPER_D1,
                                        &&H_DECOY_3,
                                        &&H_NEG_RR_D1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_10,
                                        &&H_DECOY_14,
                                        &&H_DECOY_12,
                                        &&H_VEC_LOAD_D1,
                                        &&H_SHL_RI_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_8,
                                        &&H_DECOY_2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_DECOY_12,
                                        &&H_DECOY_4,
                                        &&H_ADD_RR_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_LOAD_64_D1,
                                        &&H_GET_FLAGS_R_D1,
                                        &&H_ADC_RI_D1,
                                        &&H_DECOY_12,
                                        &&H_SBB_RI_D1,
                                        &&H_VEC_EXT_D1,
                                        &&H_DECOY_0,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8,
                                        &&H_CMP_RI_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_FCVTZS_D1,
                                        &&H_DECOY_15,
                                        &&H_UCVTF_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_15,
                                        &&H_VEC_SPLAT_D1,
                                        &&H_DECOY_12,
                                        &&H_DECOY_7,
                                        &&H_DECOY_9,
                                        &&H_FUSED_CMP_CMOV_D1,
                                        &&H_FUSED_XOR_ADD_RRI_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_5,
                                        &&H_FDIV_DD_D1,
                                        &&H_AND_RR_D1,
                                        &&H_DECOY_0,
                                        &&H_SAR_RI_D1,
                                        &&H_BSWAP_RR_D1,
                                        &&H_DECOY_11,
                                        &&H_VEC_IMM_D1,
                                        &&H_STORE_8_D1,
                                        &&H_ATOMIC_SWP_D1,
                                        &&H_POPCNT_RR_D1,
                                        &&H_FUSED_SUB_XOR_RRI_D1,
                                        &&H_ATOMIC_CAS_D1,
                                        &&H_CCMP_RI_D1,
                                        &&H_DECOY_11,
                                        &&H_NOT_RR_D1,
                                        &&H_OR_RI_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_7,
                                        &&H_DECOY_1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_14,
                                        &&H_DECOY_14,
                                        &&H_DECOY_1,
                                        &&H_DECOY_12,
                                        &&H_FSQRT_D_D1,
                                        &&H_DECOY_14,
                                        &&H_CCMN_RI_D1,
                                        &&H_IDIV_RR_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_6,
                                        &&H_VSUB_VV_D1,
                                        &&H_STORE_32_D1,
                                        &&H_DECOY_12,
                                        &&H_IMULH_RR_D1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_6,
                                        &&H_DECOY_11,
                                        &&H_RET_D1,
                                        &&H_FCVT_D1,
                                        &&H_VMUL_VV_D1,
                                        &&H_LOAD_S16_D1,
                                        &&H_SET_FLAGS_R_D1,
                                        &&H_FUSED_ADD_XOR_RRI_D1,
                                        &&H_DECOY_7,
                                        &&H_STORE_64_D1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_12,
                                        &&H_VADD_VV_D1,
                                        &&H_DECOY_7,
                                        &&H_RESOLVE_SYM_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_13,
                                        &&H_CLZ_RR_D1,
                                        &&H_PMOVMSKB_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_FUSED_ADD_IMUL_RRI_D1,
                                        &&H_NOP_D1,
                                        &&H_ATOMIC_STORE_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_3,
                                        &&H_LOAD_16_D1,
                                        &&H_RBIT_RR_D1,
                                        &&H_DECOY_1,
                                        &&H_ROR_RR_D1,
                                        &&H_DECOY_15,
                                        &&H_DECOY_1,
                                        &&H_DECOY_13,
                                        &&H_SHR_RI_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_11,
                                        &&H_FCVTZU_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_7,
                                        &&H_ATOMIC_ADD_D1,
                                        &&H_DECOY_2,
                                        &&H_VEC_CLEAR_UPPER_D1,
                                        &&H_DECOY_7,
                                        &&H_SAR_RR_D1,
                                        &&H_DECOY_13,
                                        &&H_IMUL_RR_D1,
                                        &&H_XOR_RI_D1,
                                        &&H_DECOY_3,
                                        &&H_CCMN_RR_D1,
                                        &&H_IMUL_RI_D1,
                                        &&H_DECOY_5,
                                        &&H_LOAD_S32_D1,
                                        &&H_FUSED_AND_OR_RRI_D1,
                                        &&H_ROR_RI_D1,
                                        &&H_DECOY_11,
                                        &&H_MOV_HIGH_D1,
                                        &&H_DECOY_2,
                                        &&H_MOV_RR_D1,
                                        &&H_DECOY_12,
                                        &&H_FSUB_DD_D1,
                                        &&H_CALL_EXTERN_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_CCMP_RR_D1,
                                        &&H_DECOY_2,
                                        &&H_CALL_D1,
                                        &&H_DECOY_15,
                                        &&H_DECOY_2,
                                        &&H_SETCC_D1,
                                        &&H_DECOY_11,
                                        &&H_LOAD_S8_D1,
                                        &&H_LOAD_32_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_9,
                                        &&H_DECOY_8,
                                        &&H_ADD_RI_D1,
                                        &&H_SHR_RR_D1,
                                        &&H_IJMP_R_D1,
                                        &&H_FUSED_MOV_ADD_RRI_D1,
                                        &&H_CMOV_D1,
                                        &&H_DECOY_0,
                                        &&H_ADC_RR_D1,
                                        &&H_DECOY_12
                                    };
                                    static void* raw_domain2[256] = {
                                        &&H_JCC_D2,
                                        &&H_DECOY_4,
                                        &&H_MULH_RR_D2,
                                        &&H_VEC_STORE_D2,
                                        &&H_DECOY_12,
                                        &&H_VEC_MOV_D2,
                                        &&H_DECOY_5,
                                        &&H_DIV_RR_D2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_13,
                                        &&H_DECOY_8,
                                        &&H_JMP_D2,
                                        &&H_EXIT_D2,
                                        &&H_DECOY_0,
                                        &&H_SCVTF_D2,
                                        &&H_DECOY_8,
                                        &&H_CMP_RR_D2,
                                        &&H_DECOY_10,
                                        &&H_DECOY_1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_0,
                                        &&H_DECOY_15,
                                        &&H_POP_R_D2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_6,
                                        &&H_PUSH_R_D2,
                                        &&H_MOV_RI_D2,
                                        &&H_ICALL_R_D2,
                                        &&H_DECOY_0,
                                        &&H_STORE_16_D2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_MOV_VR_D2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8,
                                        &&H_ROL_RI_D2,
                                        &&H_FCMP_DD_D2,
                                        &&H_DECOY_14,
                                        &&H_DECOY_8,
                                        &&H_DECOY_3,
                                        &&H_FENCE_D2,
                                        &&H_FUSED_SHL_ADD_RRI_D2,
                                        &&H_DECOY_12,
                                        &&H_DECOY_12,
                                        &&H_DECOY_3,
                                        &&H_CTZ_RR_D2,
                                        &&H_DECOY_6,
                                        &&H_XOR_RR_D2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_10,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_BRIDGE_TO_MATH_D2,
                                        &&H_SUB_RI_D2,
                                        &&H_SUB_RR_D2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_11,
                                        &&H_DECOY_8,
                                        &&H_DECOY_8,
                                        &&H_VXOR_VV_D2,
                                        &&H_BRIDGE_TO_FLOW_D2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_15,
                                        &&H_ROL_RR_D2,
                                        &&H_DECOY_15,
                                        &&H_SHL_RR_D2,
                                        &&H_DECOY_13,
                                        &&H_ATOMIC_LOAD_D2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_8,
                                        &&H_LOAD_8_D2,
                                        &&H_DECOY_4,
                                        &&H_FMUL_DD_D2,
                                        &&H_DECOY_1,
                                        &&H_VEC_ZERO_UPPER_D2,
                                        &&H_DECOY_13,
                                        &&H_DECOY_15,
                                        &&H_OR_RR_D2,
                                        &&H_DECOY_8,
                                        &&H_DECOY_13,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_DECOY_10,
                                        &&H_FCSEL_VV_D2,
                                        &&H_DECOY_9,
                                        &&H_VEC_BINOP_D2,
                                        &&H_AND_RI_D2,
                                        &&H_FADD_DD_D2,
                                        &&H_DECOY_7,
                                        &&H_MOV_RV_D2,
                                        &&H_DECOY_10,
                                        &&H_DECOY_13,
                                        &&H_SBB_RR_D2,
                                        &&H_ADC_RI_D2,
                                        &&H_GET_FLAGS_R_D2,
                                        &&H_LOAD_64_D2,
                                        &&H_DECOY_12,
                                        &&H_DECOY_14,
                                        &&H_VEC_EXT_D2,
                                        &&H_SBB_RI_D2,
                                        &&H_DECOY_12,
                                        &&H_DECOY_6,
                                        &&H_CMP_RI_D2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_11,
                                        &&H_UCVTF_D2,
                                        &&H_DECOY_3,
                                        &&H_FCVTZS_D2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_12,
                                        &&H_DECOY_14,
                                        &&H_DECOY_1,
                                        &&H_NEG_RR_D2,
                                        &&H_DECOY_3,
                                        &&H_SHL_RI_D2,
                                        &&H_VEC_LOAD_D2,
                                        &&H_DECOY_12,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_DECOY_12,
                                        &&H_DECOY_8,
                                        &&H_DECOY_4,
                                        &&H_ADD_RR_D2,
                                        &&H_DECOY_14,
                                        &&H_DECOY_12,
                                        &&H_POPCNT_RR_D2,
                                        &&H_ATOMIC_SWP_D2,
                                        &&H_STORE_8_D2,
                                        &&H_VEC_IMM_D2,
                                        &&H_DECOY_9,
                                        &&H_CCMP_RI_D2,
                                        &&H_ATOMIC_CAS_D2,
                                        &&H_FUSED_SUB_XOR_RRI_D2,
                                        &&H_DECOY_5,
                                        &&H_DECOY_1,
                                        &&H_OR_RI_D2,
                                        &&H_NOT_RR_D2,
                                        &&H_DECOY_12,
                                        &&H_DECOY_2,
                                        &&H_DECOY_7,
                                        &&H_DECOY_1,
                                        &&H_DECOY_10,
                                        &&H_VEC_SPLAT_D2,
                                        &&H_DECOY_9,
                                        &&H_DECOY_11,
                                        &&H_FUSED_XOR_ADD_RRI_D2,
                                        &&H_FUSED_CMP_CMOV_D2,
                                        &&H_DECOY_3,
                                        &&H_DECOY_7,
                                        &&H_AND_RR_D2,
                                        &&H_FDIV_DD_D2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_2,
                                        &&H_DECOY_9,
                                        &&H_BSWAP_RR_D2,
                                        &&H_SAR_RI_D2,
                                        &&H_DECOY_0,
                                        &&H_SET_FLAGS_R_D2,
                                        &&H_LOAD_S16_D2,
                                        &&H_VMUL_VV_D2,
                                        &&H_FCVT_D2,
                                        &&H_DECOY_15,
                                        &&H_STORE_64_D2,
                                        &&H_DECOY_1,
                                        &&H_FUSED_ADD_XOR_RRI_D2,
                                        &&H_RESOLVE_SYM_D2,
                                        &&H_DECOY_11,
                                        &&H_VADD_VV_D2,
                                        &&H_DECOY_12,
                                        &&H_PMOVMSKB_D2,
                                        &&H_CLZ_RR_D2,
                                        &&H_DECOY_7,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_FSQRT_D_D2,
                                        &&H_DECOY_6,
                                        &&H_DECOY_1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_6,
                                        &&H_IDIV_RR_D2,
                                        &&H_CCMN_RI_D2,
                                        &&H_IMULH_RR_D2,
                                        &&H_DECOY_0,
                                        &&H_STORE_32_D2,
                                        &&H_VSUB_VV_D2,
                                        &&H_RET_D2,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_7,
                                        &&H_DECOY_5,
                                        &&H_DECOY_2,
                                        &&H_FCVTZU_D2,
                                        &&H_DECOY_11,
                                        &&H_DECOY_5,
                                        &&H_VEC_CLEAR_UPPER_D2,
                                        &&H_DECOY_12,
                                        &&H_ATOMIC_ADD_D2,
                                        &&H_XOR_RI_D2,
                                        &&H_IMUL_RR_D2,
                                        &&H_DECOY_7,
                                        &&H_SAR_RR_D2,
                                        &&H_DECOY_3,
                                        &&H_IMUL_RI_D2,
                                        &&H_CCMN_RR_D2,
                                        &&H_DECOY_3,
                                        &&H_NOP_D2,
                                        &&H_FUSED_ADD_IMUL_RRI_D2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_8,
                                        &&H_LOAD_16_D2,
                                        &&H_DECOY_7,
                                        &&H_DECOY_2,
                                        &&H_ATOMIC_STORE_D2,
                                        &&H_DECOY_13,
                                        &&H_ROR_RR_D2,
                                        &&H_DECOY_11,
                                        &&H_RBIT_RR_D2,
                                        &&H_DECOY_11,
                                        &&H_SHR_RI_D2,
                                        &&H_DECOY_7,
                                        &&H_DECOY_1,
                                        &&H_LOAD_S8_D2,
                                        &&H_DECOY_15,
                                        &&H_SETCC_D2,
                                        &&H_DECOY_2,
                                        &&H_DECOY_6,
                                        &&H_DECOY_13,
                                        &&H_DECOY_3,
                                        &&H_LOAD_32_D2,
                                        &&H_FUSED_MOV_ADD_RRI_D2,
                                        &&H_IJMP_R_D2,
                                        &&H_SHR_RR_D2,
                                        &&H_ADD_RI_D2,
                                        &&H_DECOY_10,
                                        &&H_ADC_RR_D2,
                                        &&H_DECOY_10,
                                        &&H_CMOV_D2,
                                        &&H_DECOY_9,
                                        &&H_ROR_RI_D2,
                                        &&H_FUSED_AND_OR_RRI_D2,
                                        &&H_LOAD_S32_D2,
                                        &&H_DECOY_10,
                                        &&H_MOV_RR_D2,
                                        &&H_DECOY_12,
                                        &&H_MOV_HIGH_D2,
                                        &&H_DECOY_5,
                                        &&H_DECOY_7,
                                        &&H_CALL_EXTERN_D2,
                                        &&H_FSUB_DD_D2,
                                        &&H_DECOY_13,
                                        &&H_CALL_D2,
                                        &&H_DECOY_12,
                                        &&H_CCMP_RR_D2
                                    };
                                    static void* raw_domain3[256] = {
                                        &&H_DIV_RR_D1,
                                        &&H_DECOY_13,
                                        &&H_VEC_MOV_D1,
                                        &&H_DECOY_0,
                                        &&H_VEC_STORE_D1,
                                        &&H_MULH_RR_D1,
                                        &&H_DECOY_10,
                                        &&H_JCC_D1,
                                        &&H_DECOY_10,
                                        &&H_SCVTF_D1,
                                        &&H_DECOY_14,
                                        &&H_EXIT_D1,
                                        &&H_JMP_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_3,
                                        &&H_DECOY_9,
                                        &&H_DECOY_15,
                                        &&H_POP_R_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_4,
                                        &&H_DECOY_2,
                                        &&H_DECOY_1,
                                        &&H_DECOY_0,
                                        &&H_CMP_RR_D1,
                                        &&H_DECOY_10,
                                        &&H_DECOY_9,
                                        &&H_STORE_16_D1,
                                        &&H_DECOY_4,
                                        &&H_ICALL_R_D1,
                                        &&H_MOV_RI_D1,
                                        &&H_PUSH_R_D1,
                                        &&H_DECOY_2,
                                        &&H_FCMP_DD_D1,
                                        &&H_ROL_RI_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_15,
                                        &&H_DECOY_7,
                                        &&H_MOV_VR_D1,
                                        &&H_DECOY_14,
                                        &&H_DECOY_4,
                                        &&H_DECOY_5,
                                        &&H_DECOY_4,
                                        &&H_DECOY_10,
                                        &&H_FUSED_SHL_ADD_RRI_D1,
                                        &&H_FENCE_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_14,
                                        &&H_DECOY_10,
                                        &&H_BRIDGE_TO_MATH_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_6,
                                        &&H_DECOY_14,
                                        &&H_DECOY_11,
                                        &&H_XOR_RR_D1,
                                        &&H_DECOY_12,
                                        &&H_CTZ_RR_D1,
                                        &&H_BRIDGE_TO_FLOW_D1,
                                        &&H_VXOR_VV_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_12,
                                        &&H_DECOY_5,
                                        &&H_DECOY_15,
                                        &&H_SUB_RR_D1,
                                        &&H_SUB_RI_D1,
                                        &&H_DECOY_3,
                                        &&H_ATOMIC_LOAD_D1,
                                        &&H_DECOY_11,
                                        &&H_SHL_RR_D1,
                                        &&H_DECOY_9,
                                        &&H_ROL_RR_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_4,
                                        &&H_DECOY_1,
                                        &&H_DECOY_5,
                                        &&H_VEC_ZERO_UPPER_D1,
                                        &&H_DECOY_5,
                                        &&H_FMUL_DD_D1,
                                        &&H_DECOY_4,
                                        &&H_LOAD_8_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_11,
                                        &&H_FCSEL_VV_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_11,
                                        &&H_DECOY_13,
                                        &&H_DECOY_13,
                                        &&H_DECOY_14,
                                        &&H_OR_RR_D1,
                                        &&H_SBB_RR_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_8,
                                        &&H_MOV_RV_D1,
                                        &&H_DECOY_1,
                                        &&H_FADD_DD_D1,
                                        &&H_AND_RI_D1,
                                        &&H_VEC_BINOP_D1,
                                        &&H_DECOY_14,
                                        &&H_SBB_RI_D1,
                                        &&H_VEC_EXT_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_6,
                                        &&H_LOAD_64_D1,
                                        &&H_GET_FLAGS_R_D1,
                                        &&H_ADC_RI_D1,
                                        &&H_DECOY_3,
                                        &&H_FCVTZS_D1,
                                        &&H_DECOY_1,
                                        &&H_UCVTF_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_2,
                                        &&H_CMP_RI_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_14,
                                        &&H_VEC_LOAD_D1,
                                        &&H_SHL_RI_D1,
                                        &&H_DECOY_7,
                                        &&H_NEG_RR_D1,
                                        &&H_DECOY_1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_8,
                                        &&H_DECOY_14,
                                        &&H_DECOY_6,
                                        &&H_ADD_RR_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_2,
                                        &&H_DECOY_12,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_FUSED_SUB_XOR_RRI_D1,
                                        &&H_ATOMIC_CAS_D1,
                                        &&H_CCMP_RI_D1,
                                        &&H_DECOY_13,
                                        &&H_VEC_IMM_D1,
                                        &&H_STORE_8_D1,
                                        &&H_ATOMIC_SWP_D1,
                                        &&H_POPCNT_RR_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_15,
                                        &&H_DECOY_0,
                                        &&H_DECOY_0,
                                        &&H_NOT_RR_D1,
                                        &&H_OR_RI_D1,
                                        &&H_DECOY_7,
                                        &&H_DECOY_1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_11,
                                        &&H_FUSED_CMP_CMOV_D1,
                                        &&H_FUSED_XOR_ADD_RRI_D1,
                                        &&H_DECOY_5,
                                        &&H_DECOY_9,
                                        &&H_VEC_SPLAT_D1,
                                        &&H_DECOY_6,
                                        &&H_DECOY_2,
                                        &&H_SAR_RI_D1,
                                        &&H_BSWAP_RR_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_12,
                                        &&H_DECOY_15,
                                        &&H_FDIV_DD_D1,
                                        &&H_AND_RR_D1,
                                        &&H_FUSED_ADD_XOR_RRI_D1,
                                        &&H_DECOY_9,
                                        &&H_STORE_64_D1,
                                        &&H_DECOY_3,
                                        &&H_FCVT_D1,
                                        &&H_VMUL_VV_D1,
                                        &&H_LOAD_S16_D1,
                                        &&H_SET_FLAGS_R_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_15,
                                        &&H_CLZ_RR_D1,
                                        &&H_PMOVMSKB_D1,
                                        &&H_DECOY_6,
                                        &&H_VADD_VV_D1,
                                        &&H_DECOY_1,
                                        &&H_RESOLVE_SYM_D1,
                                        &&H_CCMN_RI_D1,
                                        &&H_IDIV_RR_D1,
                                        &&H_DECOY_4,
                                        &&H_DECOY_8,
                                        &&H_DECOY_11,
                                        &&H_DECOY_6,
                                        &&H_FSQRT_D_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_9,
                                        &&H_DECOY_8,
                                        &&H_DECOY_13,
                                        &&H_RET_D1,
                                        &&H_VSUB_VV_D1,
                                        &&H_STORE_32_D1,
                                        &&H_DECOY_6,
                                        &&H_IMULH_RR_D1,
                                        &&H_ATOMIC_ADD_D1,
                                        &&H_DECOY_4,
                                        &&H_VEC_CLEAR_UPPER_D1,
                                        &&H_DECOY_9,
                                        &&H_DECOY_5,
                                        &&H_FCVTZU_D1,
                                        &&H_DECOY_8,
                                        &&H_DECOY_1,
                                        &&H_DECOY_5,
                                        &&H_CCMN_RR_D1,
                                        &&H_IMUL_RI_D1,
                                        &&H_DECOY_7,
                                        &&H_SAR_RR_D1,
                                        &&H_DECOY_7,
                                        &&H_IMUL_RR_D1,
                                        &&H_XOR_RI_D1,
                                        &&H_ATOMIC_STORE_D1,
                                        &&H_DECOY_10,
                                        &&H_DECOY_5,
                                        &&H_LOAD_16_D1,
                                        &&H_DECOY_2,
                                        &&H_DECOY_2,
                                        &&H_FUSED_ADD_IMUL_RRI_D1,
                                        &&H_NOP_D1,
                                        &&H_DECOY_3,
                                        &&H_DECOY_15,
                                        &&H_SHR_RI_D1,
                                        &&H_DECOY_15,
                                        &&H_RBIT_RR_D1,
                                        &&H_DECOY_11,
                                        &&H_ROR_RR_D1,
                                        &&H_DECOY_9,
                                        &&H_LOAD_32_D1,
                                        &&H_DECOY_11,
                                        &&H_DECOY_11,
                                        &&H_DECOY_10,
                                        &&H_DECOY_12,
                                        &&H_SETCC_D1,
                                        &&H_DECOY_5,
                                        &&H_LOAD_S8_D1,
                                        &&H_CMOV_D1,
                                        &&H_DECOY_2,
                                        &&H_ADC_RR_D1,
                                        &&H_DECOY_14,
                                        &&H_ADD_RI_D1,
                                        &&H_SHR_RR_D1,
                                        &&H_IJMP_R_D1,
                                        &&H_FUSED_MOV_ADD_RRI_D1,
                                        &&H_MOV_HIGH_D1,
                                        &&H_DECOY_4,
                                        &&H_MOV_RR_D1,
                                        &&H_DECOY_14,
                                        &&H_LOAD_S32_D1,
                                        &&H_FUSED_AND_OR_RRI_D1,
                                        &&H_ROR_RI_D1,
                                        &&H_DECOY_5,
                                        &&H_CCMP_RR_D1,
                                        &&H_DECOY_4,
                                        &&H_CALL_D1,
                                        &&H_DECOY_1,
                                        &&H_FSUB_DD_D1,
                                        &&H_CALL_EXTERN_D1,
                                        &&H_DECOY_13,
                                        &&H_DECOY_1
                                    };
                                    static void** raw_all_domains[4] = { raw_domain0, raw_domain1, raw_domain2, raw_domain3 };
                                            for (size_t d = 0; d < 4; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = (uintptr_t)raw_all_domains[d][o] ^ k_slot;
                *(reinterpret_cast<volatile uintptr_t*>(&raw_all_domains[d][o])) = k_slot ^ 0xDEADBEEF5A5A5A5AULL;
            }
        }
#else
        for (size_t d = 0; d < 4; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = ((uintptr_t)(d * 256 + o) + 0x1337) ^ k_slot;
            }
        }
#endif
        dispatch_domains_ready = true;
    }
                                    uint64_t g_handlers_hash = compute_handlers_hash(((const uintptr_t*)(all_dispatch_domains)), 4);
                                        uint64_t word = 0;
    uint64_t k_dyn = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;
    size_t next_canary_step = 47 + ((uint64_t)seed & 0x3FULL);

#if defined(_MSC_VER) && !defined(__clang__)
    #define DISPATCH_OPCODE() do { \
        goto DISPATCH_MSVC; \
    } while(0)
#else
    #define DISPATCH_OPCODE() do { \
        uint8_t domain_idx = (uint8_t)((k_dyn >> 32) % 4); \
        uint8_t permuted_slot = (uint8_t)(op ^ domain_salt[domain_idx]); \
        uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)domain_idx * 256ULL + (uintptr_t)permuted_slot) * 0x6A09E667F3BCC908ULL); \
        void* target = (void*)(all_dispatch_domains[domain_idx][permuted_slot] ^ k_slot); \
        goto *target; \
    } while(0)
#endif

    #define FETCH_NEXT() do { \
        if (__builtin_expect(vIP_idx >= count, 0)) goto EXIT_VM; \
        if (__builtin_expect(ctx.executed_instructions > (count * 10000ULL + 1000000ULL), 0)) { \
            ctx.trapped = true; \
            goto EXIT_VM; \
        } \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
        k_dyn = k_pos ^ ctx.running_key; \
        if (__builtin_expect(ctx.executed_instructions >= next_canary_step, 0)) { \
            if (__builtin_expect(!ctx.verify_canaries(), 0)) { \
                ctx.reg_mask ^= (0xCAFEBABE13375877ULL ^ (k_dyn * 0x9E3779B97F4A7C15ULL)) | 1ULL; \
            } \
            next_canary_step = ctx.executed_instructions + 47 + ((k_dyn >> 21) & 0x7FULL); \
        } \
        work_bc[vIP_idx] = bytecode[vIP_idx]; \
        word = work_bc[vIP_idx] ^ k_dyn; \
        SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL); \
        vIP_idx++; \
        op = (uint8_t)(((word + 0xFFULL) - (word | 0xFFULL))); \
        dst = (uint8_t)((((word >> 8) + 0x1FULL) - ((word >> 8) | 0x1FULL))); \
        src = (uint8_t)((((word >> 13) + 0x1FULL) - ((word >> 13) | 0x1FULL))); \
        imm = (int64_t)((int32_t)((((word >> 18) + 0xFFFFFFFFULL) - ((word >> 18) | 0xFFFFFFFFULL)))); \
        ctx.evolve_mask((uint32_t)k_dyn); \
        ctx.evolve_slot_mask(dst, (uint32_t)k_dyn); \
        ctx.advance_running_key(op, dst, imm); \
        DISPATCH_OPCODE(); \
    } while(0)
                                    ctx.reanchor_running_key(0x0000000000000000ULL);
                                    #if defined(_MSC_VER) && !defined(__clang__)
    goto START_VM_MSVC;
    DISPATCH_MSVC: {
        uint8_t d_idx = (uint8_t)((k_dyn >> 32) % 4);
        uint8_t permuted_slot = (uint8_t)(op ^ domain_salt[d_idx]);
        switch ((uint32_t)d_idx * 256U + (uint32_t)permuted_slot) {
        case (0 * 256 + 0): goto H_DECOY_10;
        case (0 * 256 + 1): goto H_DECOY_5;
        case (0 * 256 + 2): goto H_FSQRT_D;
        case (0 * 256 + 3): goto H_DECOY_7;
        case (0 * 256 + 4): goto H_CCMN_RI;
        case (0 * 256 + 5): goto H_IDIV_RR;
        case (0 * 256 + 6): goto H_DECOY_11;
        case (0 * 256 + 7): goto H_DECOY_15;
        case (0 * 256 + 8): goto H_VSUB_VV;
        case (0 * 256 + 9): goto H_STORE_32;
        case (0 * 256 + 10): goto H_DECOY_5;
        case (0 * 256 + 11): goto H_IMULH_RR;
        case (0 * 256 + 12): goto H_DECOY_0;
        case (0 * 256 + 13): goto H_DECOY_15;
        case (0 * 256 + 14): goto H_DECOY_4;
        case (0 * 256 + 15): goto H_RET;
        case (0 * 256 + 16): goto H_FCVT;
        case (0 * 256 + 17): goto H_VMUL_VV;
        case (0 * 256 + 18): goto H_LOAD_S16;
        case (0 * 256 + 19): goto H_SET_FLAGS_R;
        case (0 * 256 + 20): goto H_FUSED_ADD_XOR_RRI;
        case (0 * 256 + 21): goto H_DECOY_0;
        case (0 * 256 + 22): goto H_STORE_64;
        case (0 * 256 + 23): goto H_DECOY_10;
        case (0 * 256 + 24): goto H_DECOY_5;
        case (0 * 256 + 25): goto H_VADD_VV;
        case (0 * 256 + 26): goto H_DECOY_0;
        case (0 * 256 + 27): goto H_RESOLVE_SYM;
        case (0 * 256 + 28): goto H_DECOY_15;
        case (0 * 256 + 29): goto H_DECOY_6;
        case (0 * 256 + 30): goto H_CLZ_RR;
        case (0 * 256 + 31): goto H_PMOVMSKB;
        case (0 * 256 + 32): goto H_DECOY_4;
        case (0 * 256 + 33): goto H_DECOY_8;
        case (0 * 256 + 34): goto H_VEC_SPLAT;
        case (0 * 256 + 35): goto H_DECOY_5;
        case (0 * 256 + 36): goto H_DECOY_0;
        case (0 * 256 + 37): goto H_DECOY_2;
        case (0 * 256 + 38): goto H_FUSED_CMP_CMOV;
        case (0 * 256 + 39): goto H_FUSED_XOR_ADD_RRI;
        case (0 * 256 + 40): goto H_DECOY_11;
        case (0 * 256 + 41): goto H_DECOY_14;
        case (0 * 256 + 42): goto H_FDIV_DD;
        case (0 * 256 + 43): goto H_AND_RR;
        case (0 * 256 + 44): goto H_DECOY_9;
        case (0 * 256 + 45): goto H_SAR_RI;
        case (0 * 256 + 46): goto H_BSWAP_RR;
        case (0 * 256 + 47): goto H_DECOY_4;
        case (0 * 256 + 48): goto H_VEC_IMM;
        case (0 * 256 + 49): goto H_STORE_8;
        case (0 * 256 + 50): goto H_ATOMIC_SWP;
        case (0 * 256 + 51): goto H_POPCNT_RR;
        case (0 * 256 + 52): goto H_FUSED_SUB_XOR_RRI;
        case (0 * 256 + 53): goto H_ATOMIC_CAS;
        case (0 * 256 + 54): goto H_CCMP_RI;
        case (0 * 256 + 55): goto H_DECOY_4;
        case (0 * 256 + 56): goto H_NOT_RR;
        case (0 * 256 + 57): goto H_OR_RI;
        case (0 * 256 + 58): goto H_DECOY_6;
        case (0 * 256 + 59): goto H_DECOY_0;
        case (0 * 256 + 60): goto H_DECOY_10;
        case (0 * 256 + 61): goto H_DECOY_6;
        case (0 * 256 + 62): goto H_DECOY_7;
        case (0 * 256 + 63): goto H_DECOY_7;
        case (0 * 256 + 64): goto H_LOAD_S32;
        case (0 * 256 + 65): goto H_FUSED_AND_OR_RRI;
        case (0 * 256 + 66): goto H_ROR_RI;
        case (0 * 256 + 67): goto H_DECOY_4;
        case (0 * 256 + 68): goto H_MOV_HIGH;
        case (0 * 256 + 69): goto H_DECOY_11;
        case (0 * 256 + 70): goto H_MOV_RR;
        case (0 * 256 + 71): goto H_DECOY_5;
        case (0 * 256 + 72): goto H_FSUB_DD;
        case (0 * 256 + 73): goto H_CALL_EXTERN;
        case (0 * 256 + 74): goto H_DECOY_12;
        case (0 * 256 + 75): goto H_DECOY_0;
        case (0 * 256 + 76): goto H_CCMP_RR;
        case (0 * 256 + 77): goto H_DECOY_11;
        case (0 * 256 + 78): goto H_CALL;
        case (0 * 256 + 79): goto H_DECOY_8;
        case (0 * 256 + 80): goto H_DECOY_11;
        case (0 * 256 + 81): goto H_SETCC;
        case (0 * 256 + 82): goto H_DECOY_4;
        case (0 * 256 + 83): goto H_LOAD_S8;
        case (0 * 256 + 84): goto H_LOAD_32;
        case (0 * 256 + 85): goto H_DECOY_2;
        case (0 * 256 + 86): goto H_DECOY_2;
        case (0 * 256 + 87): goto H_DECOY_1;
        case (0 * 256 + 88): goto H_ADD_RI;
        case (0 * 256 + 89): goto H_SHR_RR;
        case (0 * 256 + 90): goto H_IJMP_R;
        case (0 * 256 + 91): goto H_FUSED_MOV_ADD_RRI;
        case (0 * 256 + 92): goto H_CMOV;
        case (0 * 256 + 93): goto H_DECOY_9;
        case (0 * 256 + 94): goto H_ADC_RR;
        case (0 * 256 + 95): goto H_DECOY_5;
        case (0 * 256 + 96): goto H_DECOY_1;
        case (0 * 256 + 97): goto H_DECOY_1;
        case (0 * 256 + 98): goto H_FUSED_ADD_IMUL_RRI;
        case (0 * 256 + 99): goto H_NOP;
        case (0 * 256 + 100): goto H_ATOMIC_STORE;
        case (0 * 256 + 101): goto H_DECOY_1;
        case (0 * 256 + 102): goto H_DECOY_12;
        case (0 * 256 + 103): goto H_LOAD_16;
        case (0 * 256 + 104): goto H_RBIT_RR;
        case (0 * 256 + 105): goto H_DECOY_10;
        case (0 * 256 + 106): goto H_ROR_RR;
        case (0 * 256 + 107): goto H_DECOY_8;
        case (0 * 256 + 108): goto H_DECOY_10;
        case (0 * 256 + 109): goto H_DECOY_6;
        case (0 * 256 + 110): goto H_SHR_RI;
        case (0 * 256 + 111): goto H_DECOY_6;
        case (0 * 256 + 112): goto H_DECOY_4;
        case (0 * 256 + 113): goto H_FCVTZU;
        case (0 * 256 + 114): goto H_DECOY_7;
        case (0 * 256 + 115): goto H_DECOY_0;
        case (0 * 256 + 116): goto H_ATOMIC_ADD;
        case (0 * 256 + 117): goto H_DECOY_11;
        case (0 * 256 + 118): goto H_VEC_CLEAR_UPPER;
        case (0 * 256 + 119): goto H_DECOY_0;
        case (0 * 256 + 120): goto H_SAR_RR;
        case (0 * 256 + 121): goto H_DECOY_6;
        case (0 * 256 + 122): goto H_IMUL_RR;
        case (0 * 256 + 123): goto H_XOR_RI;
        case (0 * 256 + 124): goto H_DECOY_12;
        case (0 * 256 + 125): goto H_CCMN_RR;
        case (0 * 256 + 126): goto H_IMUL_RI;
        case (0 * 256 + 127): goto H_DECOY_14;
        case (0 * 256 + 128): goto H_DECOY_10;
        case (0 * 256 + 129): goto H_XOR_RR;
        case (0 * 256 + 130): goto H_DECOY_11;
        case (0 * 256 + 131): goto H_CTZ_RR;
        case (0 * 256 + 132): goto H_BRIDGE_TO_MATH;
        case (0 * 256 + 133): goto H_DECOY_0;
        case (0 * 256 + 134): goto H_DECOY_13;
        case (0 * 256 + 135): goto H_DECOY_5;
        case (0 * 256 + 136): goto H_DECOY_4;
        case (0 * 256 + 137): goto H_DECOY_14;
        case (0 * 256 + 138): goto H_SUB_RR;
        case (0 * 256 + 139): goto H_SUB_RI;
        case (0 * 256 + 140): goto H_BRIDGE_TO_FLOW;
        case (0 * 256 + 141): goto H_VXOR_VV;
        case (0 * 256 + 142): goto H_DECOY_13;
        case (0 * 256 + 143): goto H_DECOY_3;
        case (0 * 256 + 144): goto H_DECOY_6;
        case (0 * 256 + 145): goto H_MOV_VR;
        case (0 * 256 + 146): goto H_DECOY_13;
        case (0 * 256 + 147): goto H_DECOY_3;
        case (0 * 256 + 148): goto H_FCMP_DD;
        case (0 * 256 + 149): goto H_ROL_RI;
        case (0 * 256 + 150): goto H_DECOY_13;
        case (0 * 256 + 151): goto H_DECOY_6;
        case (0 * 256 + 152): goto H_FENCE;
        case (0 * 256 + 153): goto H_DECOY_2;
        case (0 * 256 + 154): goto H_DECOY_13;
        case (0 * 256 + 155): goto H_DECOY_9;
        case (0 * 256 + 156): goto H_DECOY_12;
        case (0 * 256 + 157): goto H_DECOY_11;
        case (0 * 256 + 158): goto H_DECOY_1;
        case (0 * 256 + 159): goto H_FUSED_SHL_ADD_RRI;
        case (0 * 256 + 160): goto H_DECOY_1;
        case (0 * 256 + 161): goto H_DECOY_0;
        case (0 * 256 + 162): goto H_DECOY_15;
        case (0 * 256 + 163): goto H_CMP_RR;
        case (0 * 256 + 164): goto H_DECOY_6;
        case (0 * 256 + 165): goto H_POP_R;
        case (0 * 256 + 166): goto H_DECOY_4;
        case (0 * 256 + 167): goto H_DECOY_11;
        case (0 * 256 + 168): goto H_ICALL_R;
        case (0 * 256 + 169): goto H_MOV_RI;
        case (0 * 256 + 170): goto H_PUSH_R;
        case (0 * 256 + 171): goto H_DECOY_1;
        case (0 * 256 + 172): goto H_DECOY_1;
        case (0 * 256 + 173): goto H_DECOY_0;
        case (0 * 256 + 174): goto H_STORE_16;
        case (0 * 256 + 175): goto H_DECOY_11;
        case (0 * 256 + 176): goto H_VEC_STORE;
        case (0 * 256 + 177): goto H_MULH_RR;
        case (0 * 256 + 178): goto H_DECOY_9;
        case (0 * 256 + 179): goto H_JCC;
        case (0 * 256 + 180): goto H_DIV_RR;
        case (0 * 256 + 181): goto H_DECOY_4;
        case (0 * 256 + 182): goto H_VEC_MOV;
        case (0 * 256 + 183): goto H_DECOY_7;
        case (0 * 256 + 184): goto H_JMP;
        case (0 * 256 + 185): goto H_DECOY_7;
        case (0 * 256 + 186): goto H_DECOY_2;
        case (0 * 256 + 187): goto H_DECOY_8;
        case (0 * 256 + 188): goto H_DECOY_1;
        case (0 * 256 + 189): goto H_SCVTF;
        case (0 * 256 + 190): goto H_DECOY_5;
        case (0 * 256 + 191): goto H_EXIT;
        case (0 * 256 + 192): goto H_NEG_RR;
        case (0 * 256 + 193): goto H_DECOY_0;
        case (0 * 256 + 194): goto H_DECOY_3;
        case (0 * 256 + 195): goto H_DECOY_7;
        case (0 * 256 + 196): goto H_DECOY_5;
        case (0 * 256 + 197): goto H_VEC_LOAD;
        case (0 * 256 + 198): goto H_SHL_RI;
        case (0 * 256 + 199): goto H_DECOY_14;
        case (0 * 256 + 200): goto H_DECOY_1;
        case (0 * 256 + 201): goto H_DECOY_11;
        case (0 * 256 + 202): goto H_DECOY_1;
        case (0 * 256 + 203): goto H_DECOY_1;
        case (0 * 256 + 204): goto H_DECOY_5;
        case (0 * 256 + 205): goto H_DECOY_13;
        case (0 * 256 + 206): goto H_ADD_RR;
        case (0 * 256 + 207): goto H_DECOY_15;
        case (0 * 256 + 208): goto H_DECOY_5;
        case (0 * 256 + 209): goto H_LOAD_64;
        case (0 * 256 + 210): goto H_GET_FLAGS_R;
        case (0 * 256 + 211): goto H_ADC_RI;
        case (0 * 256 + 212): goto H_DECOY_5;
        case (0 * 256 + 213): goto H_SBB_RI;
        case (0 * 256 + 214): goto H_VEC_EXT;
        case (0 * 256 + 215): goto H_DECOY_9;
        case (0 * 256 + 216): goto H_DECOY_4;
        case (0 * 256 + 217): goto H_DECOY_1;
        case (0 * 256 + 218): goto H_CMP_RI;
        case (0 * 256 + 219): goto H_DECOY_1;
        case (0 * 256 + 220): goto H_DECOY_10;
        case (0 * 256 + 221): goto H_FCVTZS;
        case (0 * 256 + 222): goto H_DECOY_8;
        case (0 * 256 + 223): goto H_UCVTF;
        case (0 * 256 + 224): goto H_DECOY_12;
        case (0 * 256 + 225): goto H_DECOY_12;
        case (0 * 256 + 226): goto H_DECOY_13;
        case (0 * 256 + 227): goto H_OR_RR;
        case (0 * 256 + 228): goto H_DECOY_2;
        case (0 * 256 + 229): goto H_FCSEL_VV;
        case (0 * 256 + 230): goto H_DECOY_15;
        case (0 * 256 + 231): goto H_DECOY_2;
        case (0 * 256 + 232): goto H_DECOY_0;
        case (0 * 256 + 233): goto H_FADD_DD;
        case (0 * 256 + 234): goto H_AND_RI;
        case (0 * 256 + 235): goto H_VEC_BINOP;
        case (0 * 256 + 236): goto H_SBB_RR;
        case (0 * 256 + 237): goto H_DECOY_12;
        case (0 * 256 + 238): goto H_DECOY_15;
        case (0 * 256 + 239): goto H_MOV_RV;
        case (0 * 256 + 240): goto H_DECOY_8;
        case (0 * 256 + 241): goto H_ROL_RR;
        case (0 * 256 + 242): goto H_DECOY_4;
        case (0 * 256 + 243): goto H_DECOY_3;
        case (0 * 256 + 244): goto H_DECOY_10;
        case (0 * 256 + 245): goto H_ATOMIC_LOAD;
        case (0 * 256 + 246): goto H_DECOY_2;
        case (0 * 256 + 247): goto H_SHL_RR;
        case (0 * 256 + 248): goto H_FMUL_DD;
        case (0 * 256 + 249): goto H_DECOY_3;
        case (0 * 256 + 250): goto H_LOAD_8;
        case (0 * 256 + 251): goto H_DECOY_3;
        case (0 * 256 + 252): goto H_DECOY_8;
        case (0 * 256 + 253): goto H_DECOY_12;
        case (0 * 256 + 254): goto H_VEC_ZERO_UPPER;
        case (0 * 256 + 255): goto H_DECOY_12;
        case (1 * 256 + 0): goto H_DECOY_8;
        case (1 * 256 + 1): goto H_DECOY_7;
        case (1 * 256 + 2): goto H_DECOY_6;
        case (1 * 256 + 3): goto H_CMP_RR_D1;
        case (1 * 256 + 4): goto H_DECOY_13;
        case (1 * 256 + 5): goto H_POP_R_D1;
        case (1 * 256 + 6): goto H_DECOY_11;
        case (1 * 256 + 7): goto H_DECOY_2;
        case (1 * 256 + 8): goto H_ICALL_R_D1;
        case (1 * 256 + 9): goto H_MOV_RI_D1;
        case (1 * 256 + 10): goto H_PUSH_R_D1;
        case (1 * 256 + 11): goto H_DECOY_8;
        case (1 * 256 + 12): goto H_DECOY_8;
        case (1 * 256 + 13): goto H_DECOY_7;
        case (1 * 256 + 14): goto H_STORE_16_D1;
        case (1 * 256 + 15): goto H_DECOY_2;
        case (1 * 256 + 16): goto H_VEC_STORE_D1;
        case (1 * 256 + 17): goto H_MULH_RR_D1;
        case (1 * 256 + 18): goto H_DECOY_0;
        case (1 * 256 + 19): goto H_JCC_D1;
        case (1 * 256 + 20): goto H_DIV_RR_D1;
        case (1 * 256 + 21): goto H_DECOY_11;
        case (1 * 256 + 22): goto H_VEC_MOV_D1;
        case (1 * 256 + 23): goto H_DECOY_14;
        case (1 * 256 + 24): goto H_JMP_D1;
        case (1 * 256 + 25): goto H_DECOY_14;
        case (1 * 256 + 26): goto H_DECOY_9;
        case (1 * 256 + 27): goto H_DECOY_15;
        case (1 * 256 + 28): goto H_DECOY_8;
        case (1 * 256 + 29): goto H_SCVTF_D1;
        case (1 * 256 + 30): goto H_DECOY_12;
        case (1 * 256 + 31): goto H_EXIT_D1;
        case (1 * 256 + 32): goto H_DECOY_1;
        case (1 * 256 + 33): goto H_XOR_RR_D1;
        case (1 * 256 + 34): goto H_DECOY_2;
        case (1 * 256 + 35): goto H_CTZ_RR_D1;
        case (1 * 256 + 36): goto H_BRIDGE_TO_MATH_D1;
        case (1 * 256 + 37): goto H_DECOY_7;
        case (1 * 256 + 38): goto H_DECOY_4;
        case (1 * 256 + 39): goto H_DECOY_12;
        case (1 * 256 + 40): goto H_DECOY_11;
        case (1 * 256 + 41): goto H_DECOY_5;
        case (1 * 256 + 42): goto H_SUB_RR_D1;
        case (1 * 256 + 43): goto H_SUB_RI_D1;
        case (1 * 256 + 44): goto H_BRIDGE_TO_FLOW_D1;
        case (1 * 256 + 45): goto H_VXOR_VV_D1;
        case (1 * 256 + 46): goto H_DECOY_4;
        case (1 * 256 + 47): goto H_DECOY_10;
        case (1 * 256 + 48): goto H_DECOY_13;
        case (1 * 256 + 49): goto H_MOV_VR_D1;
        case (1 * 256 + 50): goto H_DECOY_4;
        case (1 * 256 + 51): goto H_DECOY_10;
        case (1 * 256 + 52): goto H_FCMP_DD_D1;
        case (1 * 256 + 53): goto H_ROL_RI_D1;
        case (1 * 256 + 54): goto H_DECOY_4;
        case (1 * 256 + 55): goto H_DECOY_13;
        case (1 * 256 + 56): goto H_FENCE_D1;
        case (1 * 256 + 57): goto H_DECOY_9;
        case (1 * 256 + 58): goto H_DECOY_4;
        case (1 * 256 + 59): goto H_DECOY_0;
        case (1 * 256 + 60): goto H_DECOY_3;
        case (1 * 256 + 61): goto H_DECOY_2;
        case (1 * 256 + 62): goto H_DECOY_8;
        case (1 * 256 + 63): goto H_FUSED_SHL_ADD_RRI_D1;
        case (1 * 256 + 64): goto H_DECOY_3;
        case (1 * 256 + 65): goto H_DECOY_3;
        case (1 * 256 + 66): goto H_DECOY_4;
        case (1 * 256 + 67): goto H_OR_RR_D1;
        case (1 * 256 + 68): goto H_DECOY_9;
        case (1 * 256 + 69): goto H_FCSEL_VV_D1;
        case (1 * 256 + 70): goto H_DECOY_6;
        case (1 * 256 + 71): goto H_DECOY_9;
        case (1 * 256 + 72): goto H_DECOY_7;
        case (1 * 256 + 73): goto H_FADD_DD_D1;
        case (1 * 256 + 74): goto H_AND_RI_D1;
        case (1 * 256 + 75): goto H_VEC_BINOP_D1;
        case (1 * 256 + 76): goto H_SBB_RR_D1;
        case (1 * 256 + 77): goto H_DECOY_3;
        case (1 * 256 + 78): goto H_DECOY_6;
        case (1 * 256 + 79): goto H_MOV_RV_D1;
        case (1 * 256 + 80): goto H_DECOY_15;
        case (1 * 256 + 81): goto H_ROL_RR_D1;
        case (1 * 256 + 82): goto H_DECOY_11;
        case (1 * 256 + 83): goto H_DECOY_10;
        case (1 * 256 + 84): goto H_DECOY_1;
        case (1 * 256 + 85): goto H_ATOMIC_LOAD_D1;
        case (1 * 256 + 86): goto H_DECOY_9;
        case (1 * 256 + 87): goto H_SHL_RR_D1;
        case (1 * 256 + 88): goto H_FMUL_DD_D1;
        case (1 * 256 + 89): goto H_DECOY_10;
        case (1 * 256 + 90): goto H_LOAD_8_D1;
        case (1 * 256 + 91): goto H_DECOY_10;
        case (1 * 256 + 92): goto H_DECOY_15;
        case (1 * 256 + 93): goto H_DECOY_3;
        case (1 * 256 + 94): goto H_VEC_ZERO_UPPER_D1;
        case (1 * 256 + 95): goto H_DECOY_3;
        case (1 * 256 + 96): goto H_NEG_RR_D1;
        case (1 * 256 + 97): goto H_DECOY_7;
        case (1 * 256 + 98): goto H_DECOY_10;
        case (1 * 256 + 99): goto H_DECOY_14;
        case (1 * 256 + 100): goto H_DECOY_12;
        case (1 * 256 + 101): goto H_VEC_LOAD_D1;
        case (1 * 256 + 102): goto H_SHL_RI_D1;
        case (1 * 256 + 103): goto H_DECOY_5;
        case (1 * 256 + 104): goto H_DECOY_8;
        case (1 * 256 + 105): goto H_DECOY_2;
        case (1 * 256 + 106): goto H_DECOY_8;
        case (1 * 256 + 107): goto H_DECOY_8;
        case (1 * 256 + 108): goto H_DECOY_12;
        case (1 * 256 + 109): goto H_DECOY_4;
        case (1 * 256 + 110): goto H_ADD_RR_D1;
        case (1 * 256 + 111): goto H_DECOY_6;
        case (1 * 256 + 112): goto H_DECOY_12;
        case (1 * 256 + 113): goto H_LOAD_64_D1;
        case (1 * 256 + 114): goto H_GET_FLAGS_R_D1;
        case (1 * 256 + 115): goto H_ADC_RI_D1;
        case (1 * 256 + 116): goto H_DECOY_12;
        case (1 * 256 + 117): goto H_SBB_RI_D1;
        case (1 * 256 + 118): goto H_VEC_EXT_D1;
        case (1 * 256 + 119): goto H_DECOY_0;
        case (1 * 256 + 120): goto H_DECOY_11;
        case (1 * 256 + 121): goto H_DECOY_8;
        case (1 * 256 + 122): goto H_CMP_RI_D1;
        case (1 * 256 + 123): goto H_DECOY_8;
        case (1 * 256 + 124): goto H_DECOY_1;
        case (1 * 256 + 125): goto H_FCVTZS_D1;
        case (1 * 256 + 126): goto H_DECOY_15;
        case (1 * 256 + 127): goto H_UCVTF_D1;
        case (1 * 256 + 128): goto H_DECOY_11;
        case (1 * 256 + 129): goto H_DECOY_15;
        case (1 * 256 + 130): goto H_VEC_SPLAT_D1;
        case (1 * 256 + 131): goto H_DECOY_12;
        case (1 * 256 + 132): goto H_DECOY_7;
        case (1 * 256 + 133): goto H_DECOY_9;
        case (1 * 256 + 134): goto H_FUSED_CMP_CMOV_D1;
        case (1 * 256 + 135): goto H_FUSED_XOR_ADD_RRI_D1;
        case (1 * 256 + 136): goto H_DECOY_2;
        case (1 * 256 + 137): goto H_DECOY_5;
        case (1 * 256 + 138): goto H_FDIV_DD_D1;
        case (1 * 256 + 139): goto H_AND_RR_D1;
        case (1 * 256 + 140): goto H_DECOY_0;
        case (1 * 256 + 141): goto H_SAR_RI_D1;
        case (1 * 256 + 142): goto H_BSWAP_RR_D1;
        case (1 * 256 + 143): goto H_DECOY_11;
        case (1 * 256 + 144): goto H_VEC_IMM_D1;
        case (1 * 256 + 145): goto H_STORE_8_D1;
        case (1 * 256 + 146): goto H_ATOMIC_SWP_D1;
        case (1 * 256 + 147): goto H_POPCNT_RR_D1;
        case (1 * 256 + 148): goto H_FUSED_SUB_XOR_RRI_D1;
        case (1 * 256 + 149): goto H_ATOMIC_CAS_D1;
        case (1 * 256 + 150): goto H_CCMP_RI_D1;
        case (1 * 256 + 151): goto H_DECOY_11;
        case (1 * 256 + 152): goto H_NOT_RR_D1;
        case (1 * 256 + 153): goto H_OR_RI_D1;
        case (1 * 256 + 154): goto H_DECOY_13;
        case (1 * 256 + 155): goto H_DECOY_7;
        case (1 * 256 + 156): goto H_DECOY_1;
        case (1 * 256 + 157): goto H_DECOY_13;
        case (1 * 256 + 158): goto H_DECOY_14;
        case (1 * 256 + 159): goto H_DECOY_14;
        case (1 * 256 + 160): goto H_DECOY_1;
        case (1 * 256 + 161): goto H_DECOY_12;
        case (1 * 256 + 162): goto H_FSQRT_D_D1;
        case (1 * 256 + 163): goto H_DECOY_14;
        case (1 * 256 + 164): goto H_CCMN_RI_D1;
        case (1 * 256 + 165): goto H_IDIV_RR_D1;
        case (1 * 256 + 166): goto H_DECOY_2;
        case (1 * 256 + 167): goto H_DECOY_6;
        case (1 * 256 + 168): goto H_VSUB_VV_D1;
        case (1 * 256 + 169): goto H_STORE_32_D1;
        case (1 * 256 + 170): goto H_DECOY_12;
        case (1 * 256 + 171): goto H_IMULH_RR_D1;
        case (1 * 256 + 172): goto H_DECOY_7;
        case (1 * 256 + 173): goto H_DECOY_6;
        case (1 * 256 + 174): goto H_DECOY_11;
        case (1 * 256 + 175): goto H_RET_D1;
        case (1 * 256 + 176): goto H_FCVT_D1;
        case (1 * 256 + 177): goto H_VMUL_VV_D1;
        case (1 * 256 + 178): goto H_LOAD_S16_D1;
        case (1 * 256 + 179): goto H_SET_FLAGS_R_D1;
        case (1 * 256 + 180): goto H_FUSED_ADD_XOR_RRI_D1;
        case (1 * 256 + 181): goto H_DECOY_7;
        case (1 * 256 + 182): goto H_STORE_64_D1;
        case (1 * 256 + 183): goto H_DECOY_1;
        case (1 * 256 + 184): goto H_DECOY_12;
        case (1 * 256 + 185): goto H_VADD_VV_D1;
        case (1 * 256 + 186): goto H_DECOY_7;
        case (1 * 256 + 187): goto H_RESOLVE_SYM_D1;
        case (1 * 256 + 188): goto H_DECOY_6;
        case (1 * 256 + 189): goto H_DECOY_13;
        case (1 * 256 + 190): goto H_CLZ_RR_D1;
        case (1 * 256 + 191): goto H_PMOVMSKB_D1;
        case (1 * 256 + 192): goto H_DECOY_8;
        case (1 * 256 + 193): goto H_DECOY_8;
        case (1 * 256 + 194): goto H_FUSED_ADD_IMUL_RRI_D1;
        case (1 * 256 + 195): goto H_NOP_D1;
        case (1 * 256 + 196): goto H_ATOMIC_STORE_D1;
        case (1 * 256 + 197): goto H_DECOY_8;
        case (1 * 256 + 198): goto H_DECOY_3;
        case (1 * 256 + 199): goto H_LOAD_16_D1;
        case (1 * 256 + 200): goto H_RBIT_RR_D1;
        case (1 * 256 + 201): goto H_DECOY_1;
        case (1 * 256 + 202): goto H_ROR_RR_D1;
        case (1 * 256 + 203): goto H_DECOY_15;
        case (1 * 256 + 204): goto H_DECOY_1;
        case (1 * 256 + 205): goto H_DECOY_13;
        case (1 * 256 + 206): goto H_SHR_RI_D1;
        case (1 * 256 + 207): goto H_DECOY_13;
        case (1 * 256 + 208): goto H_DECOY_11;
        case (1 * 256 + 209): goto H_FCVTZU_D1;
        case (1 * 256 + 210): goto H_DECOY_14;
        case (1 * 256 + 211): goto H_DECOY_7;
        case (1 * 256 + 212): goto H_ATOMIC_ADD_D1;
        case (1 * 256 + 213): goto H_DECOY_2;
        case (1 * 256 + 214): goto H_VEC_CLEAR_UPPER_D1;
        case (1 * 256 + 215): goto H_DECOY_7;
        case (1 * 256 + 216): goto H_SAR_RR_D1;
        case (1 * 256 + 217): goto H_DECOY_13;
        case (1 * 256 + 218): goto H_IMUL_RR_D1;
        case (1 * 256 + 219): goto H_XOR_RI_D1;
        case (1 * 256 + 220): goto H_DECOY_3;
        case (1 * 256 + 221): goto H_CCMN_RR_D1;
        case (1 * 256 + 222): goto H_IMUL_RI_D1;
        case (1 * 256 + 223): goto H_DECOY_5;
        case (1 * 256 + 224): goto H_LOAD_S32_D1;
        case (1 * 256 + 225): goto H_FUSED_AND_OR_RRI_D1;
        case (1 * 256 + 226): goto H_ROR_RI_D1;
        case (1 * 256 + 227): goto H_DECOY_11;
        case (1 * 256 + 228): goto H_MOV_HIGH_D1;
        case (1 * 256 + 229): goto H_DECOY_2;
        case (1 * 256 + 230): goto H_MOV_RR_D1;
        case (1 * 256 + 231): goto H_DECOY_12;
        case (1 * 256 + 232): goto H_FSUB_DD_D1;
        case (1 * 256 + 233): goto H_CALL_EXTERN_D1;
        case (1 * 256 + 234): goto H_DECOY_3;
        case (1 * 256 + 235): goto H_DECOY_7;
        case (1 * 256 + 236): goto H_CCMP_RR_D1;
        case (1 * 256 + 237): goto H_DECOY_2;
        case (1 * 256 + 238): goto H_CALL_D1;
        case (1 * 256 + 239): goto H_DECOY_15;
        case (1 * 256 + 240): goto H_DECOY_2;
        case (1 * 256 + 241): goto H_SETCC_D1;
        case (1 * 256 + 242): goto H_DECOY_11;
        case (1 * 256 + 243): goto H_LOAD_S8_D1;
        case (1 * 256 + 244): goto H_LOAD_32_D1;
        case (1 * 256 + 245): goto H_DECOY_9;
        case (1 * 256 + 246): goto H_DECOY_9;
        case (1 * 256 + 247): goto H_DECOY_8;
        case (1 * 256 + 248): goto H_ADD_RI_D1;
        case (1 * 256 + 249): goto H_SHR_RR_D1;
        case (1 * 256 + 250): goto H_IJMP_R_D1;
        case (1 * 256 + 251): goto H_FUSED_MOV_ADD_RRI_D1;
        case (1 * 256 + 252): goto H_CMOV_D1;
        case (1 * 256 + 253): goto H_DECOY_0;
        case (1 * 256 + 254): goto H_ADC_RR_D1;
        case (1 * 256 + 255): goto H_DECOY_12;
        case (2 * 256 + 0): goto H_JCC_D2;
        case (2 * 256 + 1): goto H_DECOY_4;
        case (2 * 256 + 2): goto H_MULH_RR_D2;
        case (2 * 256 + 3): goto H_VEC_STORE_D2;
        case (2 * 256 + 4): goto H_DECOY_12;
        case (2 * 256 + 5): goto H_VEC_MOV_D2;
        case (2 * 256 + 6): goto H_DECOY_5;
        case (2 * 256 + 7): goto H_DIV_RR_D2;
        case (2 * 256 + 8): goto H_DECOY_13;
        case (2 * 256 + 9): goto H_DECOY_13;
        case (2 * 256 + 10): goto H_DECOY_8;
        case (2 * 256 + 11): goto H_JMP_D2;
        case (2 * 256 + 12): goto H_EXIT_D2;
        case (2 * 256 + 13): goto H_DECOY_0;
        case (2 * 256 + 14): goto H_SCVTF_D2;
        case (2 * 256 + 15): goto H_DECOY_8;
        case (2 * 256 + 16): goto H_CMP_RR_D2;
        case (2 * 256 + 17): goto H_DECOY_10;
        case (2 * 256 + 18): goto H_DECOY_1;
        case (2 * 256 + 19): goto H_DECOY_8;
        case (2 * 256 + 20): goto H_DECOY_0;
        case (2 * 256 + 21): goto H_DECOY_15;
        case (2 * 256 + 22): goto H_POP_R_D2;
        case (2 * 256 + 23): goto H_DECOY_13;
        case (2 * 256 + 24): goto H_DECOY_6;
        case (2 * 256 + 25): goto H_PUSH_R_D2;
        case (2 * 256 + 26): goto H_MOV_RI_D2;
        case (2 * 256 + 27): goto H_ICALL_R_D2;
        case (2 * 256 + 28): goto H_DECOY_0;
        case (2 * 256 + 29): goto H_STORE_16_D2;
        case (2 * 256 + 30): goto H_DECOY_1;
        case (2 * 256 + 31): goto H_DECOY_8;
        case (2 * 256 + 32): goto H_DECOY_8;
        case (2 * 256 + 33): goto H_DECOY_8;
        case (2 * 256 + 34): goto H_MOV_VR_D2;
        case (2 * 256 + 35): goto H_DECOY_13;
        case (2 * 256 + 36): goto H_DECOY_11;
        case (2 * 256 + 37): goto H_DECOY_8;
        case (2 * 256 + 38): goto H_ROL_RI_D2;
        case (2 * 256 + 39): goto H_FCMP_DD_D2;
        case (2 * 256 + 40): goto H_DECOY_14;
        case (2 * 256 + 41): goto H_DECOY_8;
        case (2 * 256 + 42): goto H_DECOY_3;
        case (2 * 256 + 43): goto H_FENCE_D2;
        case (2 * 256 + 44): goto H_FUSED_SHL_ADD_RRI_D2;
        case (2 * 256 + 45): goto H_DECOY_12;
        case (2 * 256 + 46): goto H_DECOY_12;
        case (2 * 256 + 47): goto H_DECOY_3;
        case (2 * 256 + 48): goto H_CTZ_RR_D2;
        case (2 * 256 + 49): goto H_DECOY_6;
        case (2 * 256 + 50): goto H_XOR_RR_D2;
        case (2 * 256 + 51): goto H_DECOY_1;
        case (2 * 256 + 52): goto H_DECOY_10;
        case (2 * 256 + 53): goto H_DECOY_8;
        case (2 * 256 + 54): goto H_DECOY_1;
        case (2 * 256 + 55): goto H_BRIDGE_TO_MATH_D2;
        case (2 * 256 + 56): goto H_SUB_RI_D2;
        case (2 * 256 + 57): goto H_SUB_RR_D2;
        case (2 * 256 + 58): goto H_DECOY_15;
        case (2 * 256 + 59): goto H_DECOY_11;
        case (2 * 256 + 60): goto H_DECOY_8;
        case (2 * 256 + 61): goto H_DECOY_8;
        case (2 * 256 + 62): goto H_VXOR_VV_D2;
        case (2 * 256 + 63): goto H_BRIDGE_TO_FLOW_D2;
        case (2 * 256 + 64): goto H_DECOY_8;
        case (2 * 256 + 65): goto H_DECOY_15;
        case (2 * 256 + 66): goto H_ROL_RR_D2;
        case (2 * 256 + 67): goto H_DECOY_15;
        case (2 * 256 + 68): goto H_SHL_RR_D2;
        case (2 * 256 + 69): goto H_DECOY_13;
        case (2 * 256 + 70): goto H_ATOMIC_LOAD_D2;
        case (2 * 256 + 71): goto H_DECOY_1;
        case (2 * 256 + 72): goto H_DECOY_8;
        case (2 * 256 + 73): goto H_LOAD_8_D2;
        case (2 * 256 + 74): goto H_DECOY_4;
        case (2 * 256 + 75): goto H_FMUL_DD_D2;
        case (2 * 256 + 76): goto H_DECOY_1;
        case (2 * 256 + 77): goto H_VEC_ZERO_UPPER_D2;
        case (2 * 256 + 78): goto H_DECOY_13;
        case (2 * 256 + 79): goto H_DECOY_15;
        case (2 * 256 + 80): goto H_OR_RR_D2;
        case (2 * 256 + 81): goto H_DECOY_8;
        case (2 * 256 + 82): goto H_DECOY_13;
        case (2 * 256 + 83): goto H_DECOY_3;
        case (2 * 256 + 84): goto H_DECOY_7;
        case (2 * 256 + 85): goto H_DECOY_10;
        case (2 * 256 + 86): goto H_FCSEL_VV_D2;
        case (2 * 256 + 87): goto H_DECOY_9;
        case (2 * 256 + 88): goto H_VEC_BINOP_D2;
        case (2 * 256 + 89): goto H_AND_RI_D2;
        case (2 * 256 + 90): goto H_FADD_DD_D2;
        case (2 * 256 + 91): goto H_DECOY_7;
        case (2 * 256 + 92): goto H_MOV_RV_D2;
        case (2 * 256 + 93): goto H_DECOY_10;
        case (2 * 256 + 94): goto H_DECOY_13;
        case (2 * 256 + 95): goto H_SBB_RR_D2;
        case (2 * 256 + 96): goto H_ADC_RI_D2;
        case (2 * 256 + 97): goto H_GET_FLAGS_R_D2;
        case (2 * 256 + 98): goto H_LOAD_64_D2;
        case (2 * 256 + 99): goto H_DECOY_12;
        case (2 * 256 + 100): goto H_DECOY_14;
        case (2 * 256 + 101): goto H_VEC_EXT_D2;
        case (2 * 256 + 102): goto H_SBB_RI_D2;
        case (2 * 256 + 103): goto H_DECOY_12;
        case (2 * 256 + 104): goto H_DECOY_6;
        case (2 * 256 + 105): goto H_CMP_RI_D2;
        case (2 * 256 + 106): goto H_DECOY_2;
        case (2 * 256 + 107): goto H_DECOY_11;
        case (2 * 256 + 108): goto H_UCVTF_D2;
        case (2 * 256 + 109): goto H_DECOY_3;
        case (2 * 256 + 110): goto H_FCVTZS_D2;
        case (2 * 256 + 111): goto H_DECOY_1;
        case (2 * 256 + 112): goto H_DECOY_12;
        case (2 * 256 + 113): goto H_DECOY_14;
        case (2 * 256 + 114): goto H_DECOY_1;
        case (2 * 256 + 115): goto H_NEG_RR_D2;
        case (2 * 256 + 116): goto H_DECOY_3;
        case (2 * 256 + 117): goto H_SHL_RI_D2;
        case (2 * 256 + 118): goto H_VEC_LOAD_D2;
        case (2 * 256 + 119): goto H_DECOY_12;
        case (2 * 256 + 120): goto H_DECOY_6;
        case (2 * 256 + 121): goto H_DECOY_12;
        case (2 * 256 + 122): goto H_DECOY_12;
        case (2 * 256 + 123): goto H_DECOY_8;
        case (2 * 256 + 124): goto H_DECOY_4;
        case (2 * 256 + 125): goto H_ADD_RR_D2;
        case (2 * 256 + 126): goto H_DECOY_14;
        case (2 * 256 + 127): goto H_DECOY_12;
        case (2 * 256 + 128): goto H_POPCNT_RR_D2;
        case (2 * 256 + 129): goto H_ATOMIC_SWP_D2;
        case (2 * 256 + 130): goto H_STORE_8_D2;
        case (2 * 256 + 131): goto H_VEC_IMM_D2;
        case (2 * 256 + 132): goto H_DECOY_9;
        case (2 * 256 + 133): goto H_CCMP_RI_D2;
        case (2 * 256 + 134): goto H_ATOMIC_CAS_D2;
        case (2 * 256 + 135): goto H_FUSED_SUB_XOR_RRI_D2;
        case (2 * 256 + 136): goto H_DECOY_5;
        case (2 * 256 + 137): goto H_DECOY_1;
        case (2 * 256 + 138): goto H_OR_RI_D2;
        case (2 * 256 + 139): goto H_NOT_RR_D2;
        case (2 * 256 + 140): goto H_DECOY_12;
        case (2 * 256 + 141): goto H_DECOY_2;
        case (2 * 256 + 142): goto H_DECOY_7;
        case (2 * 256 + 143): goto H_DECOY_1;
        case (2 * 256 + 144): goto H_DECOY_10;
        case (2 * 256 + 145): goto H_VEC_SPLAT_D2;
        case (2 * 256 + 146): goto H_DECOY_9;
        case (2 * 256 + 147): goto H_DECOY_11;
        case (2 * 256 + 148): goto H_FUSED_XOR_ADD_RRI_D2;
        case (2 * 256 + 149): goto H_FUSED_CMP_CMOV_D2;
        case (2 * 256 + 150): goto H_DECOY_3;
        case (2 * 256 + 151): goto H_DECOY_7;
        case (2 * 256 + 152): goto H_AND_RR_D2;
        case (2 * 256 + 153): goto H_FDIV_DD_D2;
        case (2 * 256 + 154): goto H_DECOY_15;
        case (2 * 256 + 155): goto H_DECOY_2;
        case (2 * 256 + 156): goto H_DECOY_9;
        case (2 * 256 + 157): goto H_BSWAP_RR_D2;
        case (2 * 256 + 158): goto H_SAR_RI_D2;
        case (2 * 256 + 159): goto H_DECOY_0;
        case (2 * 256 + 160): goto H_SET_FLAGS_R_D2;
        case (2 * 256 + 161): goto H_LOAD_S16_D2;
        case (2 * 256 + 162): goto H_VMUL_VV_D2;
        case (2 * 256 + 163): goto H_FCVT_D2;
        case (2 * 256 + 164): goto H_DECOY_15;
        case (2 * 256 + 165): goto H_STORE_64_D2;
        case (2 * 256 + 166): goto H_DECOY_1;
        case (2 * 256 + 167): goto H_FUSED_ADD_XOR_RRI_D2;
        case (2 * 256 + 168): goto H_RESOLVE_SYM_D2;
        case (2 * 256 + 169): goto H_DECOY_11;
        case (2 * 256 + 170): goto H_VADD_VV_D2;
        case (2 * 256 + 171): goto H_DECOY_12;
        case (2 * 256 + 172): goto H_PMOVMSKB_D2;
        case (2 * 256 + 173): goto H_CLZ_RR_D2;
        case (2 * 256 + 174): goto H_DECOY_7;
        case (2 * 256 + 175): goto H_DECOY_6;
        case (2 * 256 + 176): goto H_DECOY_12;
        case (2 * 256 + 177): goto H_FSQRT_D_D2;
        case (2 * 256 + 178): goto H_DECOY_6;
        case (2 * 256 + 179): goto H_DECOY_1;
        case (2 * 256 + 180): goto H_DECOY_4;
        case (2 * 256 + 181): goto H_DECOY_6;
        case (2 * 256 + 182): goto H_IDIV_RR_D2;
        case (2 * 256 + 183): goto H_CCMN_RI_D2;
        case (2 * 256 + 184): goto H_IMULH_RR_D2;
        case (2 * 256 + 185): goto H_DECOY_0;
        case (2 * 256 + 186): goto H_STORE_32_D2;
        case (2 * 256 + 187): goto H_VSUB_VV_D2;
        case (2 * 256 + 188): goto H_RET_D2;
        case (2 * 256 + 189): goto H_DECOY_15;
        case (2 * 256 + 190): goto H_DECOY_0;
        case (2 * 256 + 191): goto H_DECOY_7;
        case (2 * 256 + 192): goto H_DECOY_5;
        case (2 * 256 + 193): goto H_DECOY_2;
        case (2 * 256 + 194): goto H_FCVTZU_D2;
        case (2 * 256 + 195): goto H_DECOY_11;
        case (2 * 256 + 196): goto H_DECOY_5;
        case (2 * 256 + 197): goto H_VEC_CLEAR_UPPER_D2;
        case (2 * 256 + 198): goto H_DECOY_12;
        case (2 * 256 + 199): goto H_ATOMIC_ADD_D2;
        case (2 * 256 + 200): goto H_XOR_RI_D2;
        case (2 * 256 + 201): goto H_IMUL_RR_D2;
        case (2 * 256 + 202): goto H_DECOY_7;
        case (2 * 256 + 203): goto H_SAR_RR_D2;
        case (2 * 256 + 204): goto H_DECOY_3;
        case (2 * 256 + 205): goto H_IMUL_RI_D2;
        case (2 * 256 + 206): goto H_CCMN_RR_D2;
        case (2 * 256 + 207): goto H_DECOY_3;
        case (2 * 256 + 208): goto H_NOP_D2;
        case (2 * 256 + 209): goto H_FUSED_ADD_IMUL_RRI_D2;
        case (2 * 256 + 210): goto H_DECOY_2;
        case (2 * 256 + 211): goto H_DECOY_8;
        case (2 * 256 + 212): goto H_LOAD_16_D2;
        case (2 * 256 + 213): goto H_DECOY_7;
        case (2 * 256 + 214): goto H_DECOY_2;
        case (2 * 256 + 215): goto H_ATOMIC_STORE_D2;
        case (2 * 256 + 216): goto H_DECOY_13;
        case (2 * 256 + 217): goto H_ROR_RR_D2;
        case (2 * 256 + 218): goto H_DECOY_11;
        case (2 * 256 + 219): goto H_RBIT_RR_D2;
        case (2 * 256 + 220): goto H_DECOY_11;
        case (2 * 256 + 221): goto H_SHR_RI_D2;
        case (2 * 256 + 222): goto H_DECOY_7;
        case (2 * 256 + 223): goto H_DECOY_1;
        case (2 * 256 + 224): goto H_LOAD_S8_D2;
        case (2 * 256 + 225): goto H_DECOY_15;
        case (2 * 256 + 226): goto H_SETCC_D2;
        case (2 * 256 + 227): goto H_DECOY_2;
        case (2 * 256 + 228): goto H_DECOY_6;
        case (2 * 256 + 229): goto H_DECOY_13;
        case (2 * 256 + 230): goto H_DECOY_3;
        case (2 * 256 + 231): goto H_LOAD_32_D2;
        case (2 * 256 + 232): goto H_FUSED_MOV_ADD_RRI_D2;
        case (2 * 256 + 233): goto H_IJMP_R_D2;
        case (2 * 256 + 234): goto H_SHR_RR_D2;
        case (2 * 256 + 235): goto H_ADD_RI_D2;
        case (2 * 256 + 236): goto H_DECOY_10;
        case (2 * 256 + 237): goto H_ADC_RR_D2;
        case (2 * 256 + 238): goto H_DECOY_10;
        case (2 * 256 + 239): goto H_CMOV_D2;
        case (2 * 256 + 240): goto H_DECOY_9;
        case (2 * 256 + 241): goto H_ROR_RI_D2;
        case (2 * 256 + 242): goto H_FUSED_AND_OR_RRI_D2;
        case (2 * 256 + 243): goto H_LOAD_S32_D2;
        case (2 * 256 + 244): goto H_DECOY_10;
        case (2 * 256 + 245): goto H_MOV_RR_D2;
        case (2 * 256 + 246): goto H_DECOY_12;
        case (2 * 256 + 247): goto H_MOV_HIGH_D2;
        case (2 * 256 + 248): goto H_DECOY_5;
        case (2 * 256 + 249): goto H_DECOY_7;
        case (2 * 256 + 250): goto H_CALL_EXTERN_D2;
        case (2 * 256 + 251): goto H_FSUB_DD_D2;
        case (2 * 256 + 252): goto H_DECOY_13;
        case (2 * 256 + 253): goto H_CALL_D2;
        case (2 * 256 + 254): goto H_DECOY_12;
        case (2 * 256 + 255): goto H_CCMP_RR_D2;
        case (3 * 256 + 0): goto H_DIV_RR_D1;
        case (3 * 256 + 1): goto H_DECOY_13;
        case (3 * 256 + 2): goto H_VEC_MOV_D1;
        case (3 * 256 + 3): goto H_DECOY_0;
        case (3 * 256 + 4): goto H_VEC_STORE_D1;
        case (3 * 256 + 5): goto H_MULH_RR_D1;
        case (3 * 256 + 6): goto H_DECOY_10;
        case (3 * 256 + 7): goto H_JCC_D1;
        case (3 * 256 + 8): goto H_DECOY_10;
        case (3 * 256 + 9): goto H_SCVTF_D1;
        case (3 * 256 + 10): goto H_DECOY_14;
        case (3 * 256 + 11): goto H_EXIT_D1;
        case (3 * 256 + 12): goto H_JMP_D1;
        case (3 * 256 + 13): goto H_DECOY_8;
        case (3 * 256 + 14): goto H_DECOY_3;
        case (3 * 256 + 15): goto H_DECOY_9;
        case (3 * 256 + 16): goto H_DECOY_15;
        case (3 * 256 + 17): goto H_POP_R_D1;
        case (3 * 256 + 18): goto H_DECOY_13;
        case (3 * 256 + 19): goto H_DECOY_4;
        case (3 * 256 + 20): goto H_DECOY_2;
        case (3 * 256 + 21): goto H_DECOY_1;
        case (3 * 256 + 22): goto H_DECOY_0;
        case (3 * 256 + 23): goto H_CMP_RR_D1;
        case (3 * 256 + 24): goto H_DECOY_10;
        case (3 * 256 + 25): goto H_DECOY_9;
        case (3 * 256 + 26): goto H_STORE_16_D1;
        case (3 * 256 + 27): goto H_DECOY_4;
        case (3 * 256 + 28): goto H_ICALL_R_D1;
        case (3 * 256 + 29): goto H_MOV_RI_D1;
        case (3 * 256 + 30): goto H_PUSH_R_D1;
        case (3 * 256 + 31): goto H_DECOY_2;
        case (3 * 256 + 32): goto H_FCMP_DD_D1;
        case (3 * 256 + 33): goto H_ROL_RI_D1;
        case (3 * 256 + 34): goto H_DECOY_6;
        case (3 * 256 + 35): goto H_DECOY_15;
        case (3 * 256 + 36): goto H_DECOY_7;
        case (3 * 256 + 37): goto H_MOV_VR_D1;
        case (3 * 256 + 38): goto H_DECOY_14;
        case (3 * 256 + 39): goto H_DECOY_4;
        case (3 * 256 + 40): goto H_DECOY_5;
        case (3 * 256 + 41): goto H_DECOY_4;
        case (3 * 256 + 42): goto H_DECOY_10;
        case (3 * 256 + 43): goto H_FUSED_SHL_ADD_RRI_D1;
        case (3 * 256 + 44): goto H_FENCE_D1;
        case (3 * 256 + 45): goto H_DECOY_3;
        case (3 * 256 + 46): goto H_DECOY_14;
        case (3 * 256 + 47): goto H_DECOY_10;
        case (3 * 256 + 48): goto H_BRIDGE_TO_MATH_D1;
        case (3 * 256 + 49): goto H_DECOY_9;
        case (3 * 256 + 50): goto H_DECOY_6;
        case (3 * 256 + 51): goto H_DECOY_14;
        case (3 * 256 + 52): goto H_DECOY_11;
        case (3 * 256 + 53): goto H_XOR_RR_D1;
        case (3 * 256 + 54): goto H_DECOY_12;
        case (3 * 256 + 55): goto H_CTZ_RR_D1;
        case (3 * 256 + 56): goto H_BRIDGE_TO_FLOW_D1;
        case (3 * 256 + 57): goto H_VXOR_VV_D1;
        case (3 * 256 + 58): goto H_DECOY_6;
        case (3 * 256 + 59): goto H_DECOY_12;
        case (3 * 256 + 60): goto H_DECOY_5;
        case (3 * 256 + 61): goto H_DECOY_15;
        case (3 * 256 + 62): goto H_SUB_RR_D1;
        case (3 * 256 + 63): goto H_SUB_RI_D1;
        case (3 * 256 + 64): goto H_DECOY_3;
        case (3 * 256 + 65): goto H_ATOMIC_LOAD_D1;
        case (3 * 256 + 66): goto H_DECOY_11;
        case (3 * 256 + 67): goto H_SHL_RR_D1;
        case (3 * 256 + 68): goto H_DECOY_9;
        case (3 * 256 + 69): goto H_ROL_RR_D1;
        case (3 * 256 + 70): goto H_DECOY_5;
        case (3 * 256 + 71): goto H_DECOY_4;
        case (3 * 256 + 72): goto H_DECOY_1;
        case (3 * 256 + 73): goto H_DECOY_5;
        case (3 * 256 + 74): goto H_VEC_ZERO_UPPER_D1;
        case (3 * 256 + 75): goto H_DECOY_5;
        case (3 * 256 + 76): goto H_FMUL_DD_D1;
        case (3 * 256 + 77): goto H_DECOY_4;
        case (3 * 256 + 78): goto H_LOAD_8_D1;
        case (3 * 256 + 79): goto H_DECOY_4;
        case (3 * 256 + 80): goto H_DECOY_11;
        case (3 * 256 + 81): goto H_FCSEL_VV_D1;
        case (3 * 256 + 82): goto H_DECOY_8;
        case (3 * 256 + 83): goto H_DECOY_11;
        case (3 * 256 + 84): goto H_DECOY_13;
        case (3 * 256 + 85): goto H_DECOY_13;
        case (3 * 256 + 86): goto H_DECOY_14;
        case (3 * 256 + 87): goto H_OR_RR_D1;
        case (3 * 256 + 88): goto H_SBB_RR_D1;
        case (3 * 256 + 89): goto H_DECOY_5;
        case (3 * 256 + 90): goto H_DECOY_8;
        case (3 * 256 + 91): goto H_MOV_RV_D1;
        case (3 * 256 + 92): goto H_DECOY_1;
        case (3 * 256 + 93): goto H_FADD_DD_D1;
        case (3 * 256 + 94): goto H_AND_RI_D1;
        case (3 * 256 + 95): goto H_VEC_BINOP_D1;
        case (3 * 256 + 96): goto H_DECOY_14;
        case (3 * 256 + 97): goto H_SBB_RI_D1;
        case (3 * 256 + 98): goto H_VEC_EXT_D1;
        case (3 * 256 + 99): goto H_DECOY_2;
        case (3 * 256 + 100): goto H_DECOY_6;
        case (3 * 256 + 101): goto H_LOAD_64_D1;
        case (3 * 256 + 102): goto H_GET_FLAGS_R_D1;
        case (3 * 256 + 103): goto H_ADC_RI_D1;
        case (3 * 256 + 104): goto H_DECOY_3;
        case (3 * 256 + 105): goto H_FCVTZS_D1;
        case (3 * 256 + 106): goto H_DECOY_1;
        case (3 * 256 + 107): goto H_UCVTF_D1;
        case (3 * 256 + 108): goto H_DECOY_5;
        case (3 * 256 + 109): goto H_DECOY_2;
        case (3 * 256 + 110): goto H_CMP_RI_D1;
        case (3 * 256 + 111): goto H_DECOY_2;
        case (3 * 256 + 112): goto H_DECOY_14;
        case (3 * 256 + 113): goto H_VEC_LOAD_D1;
        case (3 * 256 + 114): goto H_SHL_RI_D1;
        case (3 * 256 + 115): goto H_DECOY_7;
        case (3 * 256 + 116): goto H_NEG_RR_D1;
        case (3 * 256 + 117): goto H_DECOY_1;
        case (3 * 256 + 118): goto H_DECOY_4;
        case (3 * 256 + 119): goto H_DECOY_8;
        case (3 * 256 + 120): goto H_DECOY_14;
        case (3 * 256 + 121): goto H_DECOY_6;
        case (3 * 256 + 122): goto H_ADD_RR_D1;
        case (3 * 256 + 123): goto H_DECOY_8;
        case (3 * 256 + 124): goto H_DECOY_2;
        case (3 * 256 + 125): goto H_DECOY_12;
        case (3 * 256 + 126): goto H_DECOY_2;
        case (3 * 256 + 127): goto H_DECOY_2;
        case (3 * 256 + 128): goto H_FUSED_SUB_XOR_RRI_D1;
        case (3 * 256 + 129): goto H_ATOMIC_CAS_D1;
        case (3 * 256 + 130): goto H_CCMP_RI_D1;
        case (3 * 256 + 131): goto H_DECOY_13;
        case (3 * 256 + 132): goto H_VEC_IMM_D1;
        case (3 * 256 + 133): goto H_STORE_8_D1;
        case (3 * 256 + 134): goto H_ATOMIC_SWP_D1;
        case (3 * 256 + 135): goto H_POPCNT_RR_D1;
        case (3 * 256 + 136): goto H_DECOY_3;
        case (3 * 256 + 137): goto H_DECOY_15;
        case (3 * 256 + 138): goto H_DECOY_0;
        case (3 * 256 + 139): goto H_DECOY_0;
        case (3 * 256 + 140): goto H_NOT_RR_D1;
        case (3 * 256 + 141): goto H_OR_RI_D1;
        case (3 * 256 + 142): goto H_DECOY_7;
        case (3 * 256 + 143): goto H_DECOY_1;
        case (3 * 256 + 144): goto H_DECOY_9;
        case (3 * 256 + 145): goto H_DECOY_11;
        case (3 * 256 + 146): goto H_FUSED_CMP_CMOV_D1;
        case (3 * 256 + 147): goto H_FUSED_XOR_ADD_RRI_D1;
        case (3 * 256 + 148): goto H_DECOY_5;
        case (3 * 256 + 149): goto H_DECOY_9;
        case (3 * 256 + 150): goto H_VEC_SPLAT_D1;
        case (3 * 256 + 151): goto H_DECOY_6;
        case (3 * 256 + 152): goto H_DECOY_2;
        case (3 * 256 + 153): goto H_SAR_RI_D1;
        case (3 * 256 + 154): goto H_BSWAP_RR_D1;
        case (3 * 256 + 155): goto H_DECOY_13;
        case (3 * 256 + 156): goto H_DECOY_12;
        case (3 * 256 + 157): goto H_DECOY_15;
        case (3 * 256 + 158): goto H_FDIV_DD_D1;
        case (3 * 256 + 159): goto H_AND_RR_D1;
        case (3 * 256 + 160): goto H_FUSED_ADD_XOR_RRI_D1;
        case (3 * 256 + 161): goto H_DECOY_9;
        case (3 * 256 + 162): goto H_STORE_64_D1;
        case (3 * 256 + 163): goto H_DECOY_3;
        case (3 * 256 + 164): goto H_FCVT_D1;
        case (3 * 256 + 165): goto H_VMUL_VV_D1;
        case (3 * 256 + 166): goto H_LOAD_S16_D1;
        case (3 * 256 + 167): goto H_SET_FLAGS_R_D1;
        case (3 * 256 + 168): goto H_DECOY_8;
        case (3 * 256 + 169): goto H_DECOY_15;
        case (3 * 256 + 170): goto H_CLZ_RR_D1;
        case (3 * 256 + 171): goto H_PMOVMSKB_D1;
        case (3 * 256 + 172): goto H_DECOY_6;
        case (3 * 256 + 173): goto H_VADD_VV_D1;
        case (3 * 256 + 174): goto H_DECOY_1;
        case (3 * 256 + 175): goto H_RESOLVE_SYM_D1;
        case (3 * 256 + 176): goto H_CCMN_RI_D1;
        case (3 * 256 + 177): goto H_IDIV_RR_D1;
        case (3 * 256 + 178): goto H_DECOY_4;
        case (3 * 256 + 179): goto H_DECOY_8;
        case (3 * 256 + 180): goto H_DECOY_11;
        case (3 * 256 + 181): goto H_DECOY_6;
        case (3 * 256 + 182): goto H_FSQRT_D_D1;
        case (3 * 256 + 183): goto H_DECOY_8;
        case (3 * 256 + 184): goto H_DECOY_9;
        case (3 * 256 + 185): goto H_DECOY_8;
        case (3 * 256 + 186): goto H_DECOY_13;
        case (3 * 256 + 187): goto H_RET_D1;
        case (3 * 256 + 188): goto H_VSUB_VV_D1;
        case (3 * 256 + 189): goto H_STORE_32_D1;
        case (3 * 256 + 190): goto H_DECOY_6;
        case (3 * 256 + 191): goto H_IMULH_RR_D1;
        case (3 * 256 + 192): goto H_ATOMIC_ADD_D1;
        case (3 * 256 + 193): goto H_DECOY_4;
        case (3 * 256 + 194): goto H_VEC_CLEAR_UPPER_D1;
        case (3 * 256 + 195): goto H_DECOY_9;
        case (3 * 256 + 196): goto H_DECOY_5;
        case (3 * 256 + 197): goto H_FCVTZU_D1;
        case (3 * 256 + 198): goto H_DECOY_8;
        case (3 * 256 + 199): goto H_DECOY_1;
        case (3 * 256 + 200): goto H_DECOY_5;
        case (3 * 256 + 201): goto H_CCMN_RR_D1;
        case (3 * 256 + 202): goto H_IMUL_RI_D1;
        case (3 * 256 + 203): goto H_DECOY_7;
        case (3 * 256 + 204): goto H_SAR_RR_D1;
        case (3 * 256 + 205): goto H_DECOY_7;
        case (3 * 256 + 206): goto H_IMUL_RR_D1;
        case (3 * 256 + 207): goto H_XOR_RI_D1;
        case (3 * 256 + 208): goto H_ATOMIC_STORE_D1;
        case (3 * 256 + 209): goto H_DECOY_10;
        case (3 * 256 + 210): goto H_DECOY_5;
        case (3 * 256 + 211): goto H_LOAD_16_D1;
        case (3 * 256 + 212): goto H_DECOY_2;
        case (3 * 256 + 213): goto H_DECOY_2;
        case (3 * 256 + 214): goto H_FUSED_ADD_IMUL_RRI_D1;
        case (3 * 256 + 215): goto H_NOP_D1;
        case (3 * 256 + 216): goto H_DECOY_3;
        case (3 * 256 + 217): goto H_DECOY_15;
        case (3 * 256 + 218): goto H_SHR_RI_D1;
        case (3 * 256 + 219): goto H_DECOY_15;
        case (3 * 256 + 220): goto H_RBIT_RR_D1;
        case (3 * 256 + 221): goto H_DECOY_11;
        case (3 * 256 + 222): goto H_ROR_RR_D1;
        case (3 * 256 + 223): goto H_DECOY_9;
        case (3 * 256 + 224): goto H_LOAD_32_D1;
        case (3 * 256 + 225): goto H_DECOY_11;
        case (3 * 256 + 226): goto H_DECOY_11;
        case (3 * 256 + 227): goto H_DECOY_10;
        case (3 * 256 + 228): goto H_DECOY_12;
        case (3 * 256 + 229): goto H_SETCC_D1;
        case (3 * 256 + 230): goto H_DECOY_5;
        case (3 * 256 + 231): goto H_LOAD_S8_D1;
        case (3 * 256 + 232): goto H_CMOV_D1;
        case (3 * 256 + 233): goto H_DECOY_2;
        case (3 * 256 + 234): goto H_ADC_RR_D1;
        case (3 * 256 + 235): goto H_DECOY_14;
        case (3 * 256 + 236): goto H_ADD_RI_D1;
        case (3 * 256 + 237): goto H_SHR_RR_D1;
        case (3 * 256 + 238): goto H_IJMP_R_D1;
        case (3 * 256 + 239): goto H_FUSED_MOV_ADD_RRI_D1;
        case (3 * 256 + 240): goto H_MOV_HIGH_D1;
        case (3 * 256 + 241): goto H_DECOY_4;
        case (3 * 256 + 242): goto H_MOV_RR_D1;
        case (3 * 256 + 243): goto H_DECOY_14;
        case (3 * 256 + 244): goto H_LOAD_S32_D1;
        case (3 * 256 + 245): goto H_FUSED_AND_OR_RRI_D1;
        case (3 * 256 + 246): goto H_ROR_RI_D1;
        case (3 * 256 + 247): goto H_DECOY_5;
        case (3 * 256 + 248): goto H_CCMP_RR_D1;
        case (3 * 256 + 249): goto H_DECOY_4;
        case (3 * 256 + 250): goto H_CALL_D1;
        case (3 * 256 + 251): goto H_DECOY_1;
        case (3 * 256 + 252): goto H_FSUB_DD_D1;
        case (3 * 256 + 253): goto H_CALL_EXTERN_D1;
        case (3 * 256 + 254): goto H_DECOY_13;
        case (3 * 256 + 255): goto H_DECOY_1;

        default: goto EXIT_VM;
        }
    }
    START_VM_MSVC:
#endif
                                    FETCH_NEXT();
                                        #if defined(__x86_64__)
    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()
    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #elif defined(__aarch64__)
    #define PROBE_START() uint64_t _t0; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t0))
    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #elif defined(__riscv) || defined(__riscv__)
    #define PROBE_START() uint64_t _t0; __asm__ volatile("rdtime %0" : "=r"(_t0))
    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile("rdtime %0" : "=r"(_t1)); if ((_t1 - _t0) > 50000000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #else
    #define PROBE_START() uint64_t _t0 = 0
    #define PROBE_CHECK() do {} while(0)
    #endif

    H_NOP: { ctx.executed_instructions += 1; FETCH_NEXT(); }
    H_MOV_RR: { uint64_t _v = ctx.get_reg(src); ctx.set_reg(dst, _v); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RI: { uint64_t _imm_u64 = static_cast<uint64_t>(static_cast<uint32_t>(imm)); ctx.set_reg(dst, _imm_u64); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_HIGH: {
        uint32_t _low32 = static_cast<uint32_t>(ctx.get_reg(dst));
        ctx.set_reg(dst, (static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32) | static_cast<uint64_t>(_low32));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_NEG_RR: { PROBE_START(); ctx.set_reg(dst, 0ULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOT_RR: { PROBE_START(); ctx.set_reg(dst, 0xFFFFFFFFFFFFFFFFULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_BSWAP_RR: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t res;
        if (bits == 16) { res = (uint64_t)__builtin_bswap16((uint16_t)val); }
        else if (bits == 32) { res = (uint64_t)__builtin_bswap32((uint32_t)val); }
        else { res = __builtin_bswap64(val); }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CLZ_RR: {
        uint64_t val = ctx.get_reg(src); uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t _clz = (bits <= 32) ? (((uint32_t)mval == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz((uint32_t)mval) - (32 - bits)))
                                     : ((mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval));
        ctx.set_reg(dst, _clz);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CTZ_RR: {
        uint64_t _s = ctx.get_reg(src);
        uint32_t _bits = static_cast<uint32_t>(imm);
        uint64_t _mask = (_bits >= 64) ? ~0ULL : ((1ULL << _bits) - 1ULL);
        uint64_t _ms = _s & _mask;
        if (_bits <= 32) {
            uint32_t _v32 = static_cast<uint32_t>(_ms);
            ctx.set_reg(dst, (_v32 == 0) ? static_cast<uint64_t>(_bits) : static_cast<uint64_t>(__builtin_ctz(_v32)));
        } else {
            ctx.set_reg(dst, (_ms == 0) ? 64ULL : static_cast<uint64_t>(__builtin_ctzll(_ms)));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POPCNT_RR: {
        uint64_t _s = ctx.get_reg(src);
        uint32_t _b = static_cast<uint32_t>(imm);
        uint64_t _mask = (_b >= 64) ? ~0ULL : ((1ULL << _b) - 1ULL);
        uint64_t _ms = _s & _mask;
        uint64_t _res = (_b <= 32) ? static_cast<uint64_t>(__builtin_popcount(static_cast<uint32_t>(_ms))) : static_cast<uint64_t>(__builtin_popcountll(_ms));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RBIT_RR: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t res = 0;
        for (uint32_t i = 0; i < bits; ++i) {
            if ((val >> i) & 1ULL) { res |= (1ULL << (bits - 1 - i)); }
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, (((0x0000000000000002ULL * ((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0x5555555555555555ULL))) + ((ctx.get_reg(dst) ^ 0x5555555555555555ULL) - ((ctx.get_reg(dst) | 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)))) + (ctx.get_reg(src) & 0x5555555555555555ULL)) | (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0x5555555555555555ULL))) + ((ctx.get_reg(dst) ^ 0x5555555555555555ULL) - ((ctx.get_reg(dst) | 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)))) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + (0x0000000000000002ULL * ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL)))) ^ ((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) | ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) & ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))) + ((((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0x5555555555555555ULL))) + ((ctx.get_reg(dst) ^ 0x5555555555555555ULL) - ((ctx.get_reg(dst) | 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)))) + (ctx.get_reg(src) & 0x5555555555555555ULL)) | (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) + ((((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0x5555555555555555ULL))) + ((ctx.get_reg(dst) ^ 0x5555555555555555ULL) - ((ctx.get_reg(dst) | 0x5555555555555555ULL) - (ctx.get_reg(dst) & 0x5555555555555555ULL)))) + (ctx.get_reg(src) & 0x5555555555555555ULL)) & (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) + ctx.get_reg(src))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (((0x599f4992e7286269ULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x599f4992e728626aULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0xa660b66d18d79d98ULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, (((((((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL + (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) & (~((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) - ((~(((((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL + (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))))) & (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))) + ((((((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL + (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) ^ (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - ((((((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL + (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) | (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))) - (((((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL + (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))) * (0x0000000000000002ULL & (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) & (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d - static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI: {
        PROBE_START();
        uint64_t _d = ctx.get_reg(dst);
        ctx.set_reg(dst, _d * static_cast<uint64_t>(imm));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, (((((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x5e97bdf4819c84f9ULL) << 0x0000000000000021ULL)) ^ (((((((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * ((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) + ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) + 0x0000000000000001ULL)))))) + ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) | (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ULL)) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x5e97bdf4819c84f9ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x5e97bdf4819c84f9ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) | static_cast<uint64_t>(imm)) - (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR: { PROBE_START(); ctx.set_reg(dst, (((ctx.get_reg(dst) - (~(((~ctx.get_reg(dst)) | (~((~ctx.get_reg(src)))))))) | ((0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - (0x0000000000000002ULL * (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) + ((ctx.get_reg(dst) - (~(((~ctx.get_reg(dst)) | (~((~ctx.get_reg(src)))))))) & ((0x0000000000000002ULL * ((((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) ^ (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - (0x0000000000000002ULL * (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst))) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, ((_d | _i) - (_d ^ _i))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) ^ ((((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x000000007fffffffULL) * 0x25cd1a9c5246121fULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) ^ ((((((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((((ctx.get_reg(dst) + 0x5555555555555555ULL) - (ctx.get_reg(dst) | 0x5555555555555555ULL)) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(src) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)))))) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((((ctx.get_reg(dst) & 0x5555555555555555ULL) + (ctx.get_reg(src) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x000000007fffffffULL) * 0x25cd1a9c5246121fULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x25cd1a9c5246121fULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, ((_d + _i) - (_d & _i))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ROL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (v >> s) | (v << ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val << shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);
        ctx.set_reg(dst, v >> s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROL_RR: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RR: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RR: {
        uint64_t _res = ctx.get_reg(dst) << (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RR: {
        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RR: {
        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        if (b == 0) { ctx.trapped = true; goto EXIT_VM; }
        ctx.set_reg(dst, a / b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR: {
        int64_t _d = static_cast<int64_t>(ctx.get_reg(dst)), _s = static_cast<int64_t>(ctx.get_reg(src));
        if (_s == 0 || (_s == -1 && _d == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }
        int64_t _quot = (_s == -1) ? (-_d) : (_d / _s);
        ctx.set_reg(dst, static_cast<uint64_t>(_quot));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_MULH_RR: {
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((unsigned __int128)ctx.get_reg(dst) * (unsigned __int128)ctx.get_reg(src)) >> 64);
        #else
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;
        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMULH_RR: {
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((signed __int128)(int64_t)ctx.get_reg(dst) * (signed __int128)(int64_t)ctx.get_reg(src)) >> 64);
        #else
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;
        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;
        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;
        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;
        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;
        if (a < 0) res -= ub;
        if (b < 0) res -= ua;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI: {
        PROBE_START();
        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);
        uint64_t _imm = (uint64_t)imm;
        compute_sub_flags(ctx, ctx.get_reg(dst), _imm, bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR: {
        PROBE_START();
        uint32_t bits = static_cast<uint32_t>((word >> 50) & 0x7F);
        compute_sub_flags(ctx, ctx.get_reg(dst), ctx.get_reg(src), bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R: {
        uint64_t val = ctx.get_reg(dst);
        ctx.push(val);
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            uint64_t sp_val = cur_sp - 8ULL;
            ctx.set_reg(REG_RSP, sp_val);
            *reinterpret_cast<uint64_t*>(sp_val) = val;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POP_R: {
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        uint64_t val = 0;
        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            val = *reinterpret_cast<const uint64_t*>(cur_sp);
            ctx.set_reg(REG_RSP, cur_sp + 8ULL);
            ctx.pop();
        } else {
            val = ctx.pop();
        }
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a + b + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a + b + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RR: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RI: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RR: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_add_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RI: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_GET_FLAGS_R: {
        uint64_t f = 2ULL;
        f |= (uint64_t)ctx.cf;
        f |= ((uint64_t)ctx.zf << 6);
        f |= ((uint64_t)ctx.sf << 7);
        f |= ((uint64_t)ctx.of << 11);
        ctx.set_reg(dst, f);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SET_FLAGS_R: {
        uint64_t f = ctx.get_reg(src);
        ctx.cf = (f & 1ULL) != 0;
        ctx.zf = (f & 0x40ULL) != 0;
        ctx.sf = (f & 0x80ULL) != 0;
        ctx.of = (f & 0x800ULL) != 0;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JMP: {
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_JCC: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t base_vip = static_cast<uint64_t>(((word >> 0x0000000000000016ULL) & 0x00000000001fffffULL));
        uint64_t enc_delta = static_cast<uint64_t>(((word >> 0x000000000000002bULL) & 0x00000000001fffffULL));
        uint64_t salt = (((static_cast<uint64_t>(cond) * 0x0000000000005877ULL) ^ 0x000000001337beefULL) & 0x00000000001fffffULL);
        uint64_t delta = (enc_delta ^ salt);
        uint64_t t_true = (base_vip ^ delta);
        uint64_t t_false = base_vip;
        uint64_t c = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #else
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CMOV: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (ctx.get_reg(dst) & (~_m))));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_SETCC: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t val = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        ctx.set_reg(dst, val);
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CALL: {
        ctx.push(static_cast<uint64_t>(vIP_idx));
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_IJMP_R: {
        uint64_t target = ctx.get_reg(dst);
        if (target < count) {
                         vIP_idx = static_cast<size_t>(target);
} else {
            if (target != 0x0000000000000000ULL) {
                                                      #if defined(__x86_64__) || defined(_M_X64)
                                                      uint64_t a0 = ctx.get_reg(REG_RDI);
                                                      uint64_t a1 = ctx.get_reg(REG_RSI);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RCX);
                                                      uint64_t a4 = ctx.get_reg(REG_R8);
                                                      uint64_t a5 = ctx.get_reg(REG_R9);
                                                      #else
                                                      uint64_t a0 = ctx.get_reg(REG_RAX);
                                                      uint64_t a1 = ctx.get_reg(REG_RCX);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RBX);
                                                      uint64_t a4 = ctx.get_reg(REG_RSI);
                                                      uint64_t a5 = ctx.get_reg(REG_RDI);
                                                      #endif
                                                      typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                      indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);
                                                      uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                      ctx.set_reg(REG_RAX, ret_val);
                                                      goto EXIT_VM;
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_ICALL_R: {
        uint64_t target_ptr = ctx.get_reg(dst);
        if (target_ptr < count) {
                             ctx.push(static_cast<uint64_t>(vIP_idx));
                             vIP_idx = static_cast<size_t>(target_ptr);
} else {
            if (target_ptr != 0x0000000000000000ULL) {
                                                          #if defined(__x86_64__) || defined(_M_X64)
                                                          uint64_t a0 = ctx.get_reg(REG_RDI);
                                                          uint64_t a1 = ctx.get_reg(REG_RSI);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RCX);
                                                          uint64_t a4 = ctx.get_reg(REG_R8);
                                                          uint64_t a5 = ctx.get_reg(REG_R9);
                                                          #else
                                                          uint64_t a0 = ctx.get_reg(REG_RAX);
                                                          uint64_t a1 = ctx.get_reg(REG_RCX);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RBX);
                                                          uint64_t a4 = ctx.get_reg(REG_RSI);
                                                          uint64_t a5 = ctx.get_reg(REG_RDI);
                                                          #endif
                                                          typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                          indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);
                                                          uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                          ctx.set_reg(REG_RAX, ret_val);
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_RET: case_ret: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }
    H_EXIT: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }

    H_BRIDGE_TO_FLOW: {
        uint64_t _imm_flow = static_cast<uint64_t>(imm);
        ctx.morph_math_to_flow(_imm_flow);
        ctx.executed_instructions += 1;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH: {
        uint64_t _imm_math = static_cast<uint64_t>(imm);
        ctx.morph_flow_to_math(_imm_math);
        ctx.executed_instructions += 1;
        FETCH_NEXT();
    }
    H_FUSED_MOV_ADD_RRI: {
        uint64_t _base = ctx.get_reg(src);
        ctx.set_reg(dst, (_base + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) * static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) ^ static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _diff = (ctx.get_reg(dst) - ctx.get_reg(src));
        ctx.set_reg(dst, ((_diff | _imm) - (_diff & _imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI: {
        uint64_t _a = ctx.get_reg(dst);
        uint64_t _b = ctx.get_reg(src);
        uint64_t _x = ((_a + _b) - (0x0000000000000002ULL * (_a & _b)));
        ctx.set_reg(dst, (_x + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV: {
        uint64_t a = ctx.get_reg(dst);
        uint64_t b = static_cast<uint64_t>(imm);
        uint8_t cond = static_cast<uint8_t>(((word >> 0x0000000000000032ULL) & 0x000000000000000fULL));
        uint32_t bits = static_cast<uint32_t>(((word >> 0x0000000000000036ULL) & 0x000000000000007fULL));
        compute_sub_flags(ctx, a, b, bits);
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (a & (~_m))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_AND_OR_RRI: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _a = (ctx.get_reg(dst) & ctx.get_reg(src));
        ctx.set_reg(dst, ((_a + _imm) - (_a & _imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SHL_ADD_RRI: {
        uint64_t _shl = (ctx.get_reg(dst) << (static_cast<uint64_t>(imm) & 0x000000000000003fULL));
        uint64_t _s = ctx.get_reg(src);
        ctx.set_reg(dst, ((_shl ^ _s) + (0x0000000000000002ULL * (_shl & _s))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_VADD_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vd = vcombine_u64(vcreate_u64(d0), vcreate_u64(d1));
        uint64x2_t vs = vcombine_u64(vcreate_u64(s0), vcreate_u64(s1));
        uint64x2_t vr = vaddq_u64(vd, vs);
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vd = _mm_set_epi64x((int64_t)d1, (int64_t)d0);
        __m128i vs = _mm_set_epi64x((int64_t)s1, (int64_t)s0);
        __m128i vr = _mm_add_epi64(vd, vs);
        ctx.set_vreg(dst, (uint64_t)_mm_extract_epi64(vr, 0), (uint64_t)_mm_extract_epi64(vr, 1));
#else
        ctx.set_vreg(dst, d0 + s0, d1 + s1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VSUB_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 - s0; uint64_t _res1 = d1 - s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VMUL_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        ctx.set_vreg(dst, static_cast<uint64_t>(d0 * s0), static_cast<uint64_t>(d1 * s1));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VXOR_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vd = vcombine_u64(vcreate_u64(d0), vcreate_u64(d1));
        uint64x2_t vs = vcombine_u64(vcreate_u64(s0), vcreate_u64(s1));
        uint64x2_t vr = veorq_u64(vd, vs);
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vd = _mm_set_epi64x((int64_t)d1, (int64_t)d0);
        __m128i vs = _mm_set_epi64x((int64_t)s1, (int64_t)s0);
        __m128i vr = _mm_xor_si128(vd, vs);
        ctx.set_vreg(dst, (uint64_t)_mm_extract_epi64(vr, 0), (uint64_t)_mm_extract_epi64(vr, 1));
#else
        ctx.set_vreg(dst, d0 ^ s0, d1 ^ s1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_VEC_MOV: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        for (size_t i = 0; i < (bits + 63) / 64; ++i) ctx.set_vreg_lane(dst, i, ctx.get_vreg_lane(src, i));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_BINOP: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);
        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;
            uint64_t value = 0;
            if (elem == 1 && vop <= 2) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint32_t>(fr);
            } else if (elem == 1 && vop == 11) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));
            } else if (elem == 1 && vop == 12) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));
            } else if (elem == 2 && vop <= 2) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint64_t>(fr);
            } else if (elem == 2 && vop == 11) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));
            } else if (elem == 2 && vop == 12) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));
            } else {
                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));
                switch (vop) {
                    case 0: value = a + b; break;
                    case 1: value = a - b; break;
                    case 2: value = a * b; break;
                    case 3: value = a & b; break;
                    case 4: value = a | b; break;
                    case 5: value = a ^ b; break;
                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                    case 9: value = (a == b) ? mask : 0; break;
                    case 10: value = (sa > sb) ? mask : 0; break;
                    case 11: value = (sa < sb) ? a : b; break;
                    case 12: value = (sa > sb) ? a : b; break;
                    case 13: value = (a < b) ? a : b; break;
                    case 14: value = (a > b) ? a : b; break;
                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;
                    case 16: value = (~a) & b; break;
                    case 17: {
                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);
                        size_t half_idx = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 18: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 21: {
                        uint8_t ctrl = (uint8_t)(b & 0xff);
                        if (ctrl & 0x80) value = 0;
                        else {
                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        }
                        break;
                    }
                    case 23: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 24: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 25: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 26: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2 + 1;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 28: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = 0;
                        }
                        break;
                    }
                    case 29: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;
                        }
                        break;
                    }
                    case 30: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = ~0ULL;
                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;
                        else value = (uint64_t)(sa / sb);
                        break;
                    }
                    case 31: {
                        value = (b != 0) ? (a / b) : mask;
                        break;
                    }
                    case 32: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = a;
                        else if (sb == -1 && sa == min_val) value = 0;
                        else value = (uint64_t)(sa % sb);
                        break;
                    }
                    case 33: {
                        value = (b != 0) ? (a % b) : a;
                        break;
                    }
                    case 34: value = (a != b) ? mask : 0; break;
                    case 35: value = (sa <= sb) ? mask : 0; break;
                    case 36: value = (a < b) ? mask : 0; break;
                    case 37: value = (a <= b) ? mask : 0; break;
                    default: value = a ^ b; break;
                }
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_IMM: {
        uint64_t imm_val = imm & 0xffULL;
        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
            uint64_t value = 0;
            switch (vop) {
                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                case 21: {
                    size_t lane_in_128 = (bit / 32) % 4;
                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;
                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);
                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;
                    break;
                }
                case 22: {
                    size_t lane_idx = bit / lane_bits;
                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;
                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);
                    break;
                }
                default: value = a; break;
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_CLEAR_UPPER: {
        ctx.set_vreg_lane(dst, 2, 0ULL);
        ctx.set_vreg_lane(dst, 3, 0ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_ZERO_UPPER: {
        for (size_t i = 0; i < 16; ++i) {
            ctx.set_vreg_lane(i, 2, 0ULL);
            ctx.set_vreg_lane(i, 3, 0ULL);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PMOVMSKB: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        uint32_t num_bytes = bits / 8;
        uint64_t mask = 0;
        for (uint32_t b = 0; b < num_bytes; ++b) {
            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;
            if (byte_val & 0x80) mask |= (1ULL << b);
        }
        ctx.set_reg(dst, mask);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_LOAD: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_STORE: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_SPLAT: {
        uint32_t bits = (uint32_t)(imm & 0xffff);
        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);
        uint64_t val = ctx.get_reg(src);
        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);
        uint64_t val_masked = val & mask;
        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;
        for (uint32_t l = 0; l < num_lanes; ++l) {
            uint32_t pos = l * lane_bits;
            uint32_t chunk = pos / 64;
            uint32_t shift = pos % 64;
            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);
            uint64_t cur = ctx.get_vreg_lane(dst, chunk);
            cur = (cur & ~packed_mask) | (val_masked << shift);
            ctx.set_vreg_lane(dst, chunk, cur);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_EXT: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);
        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);
        if (bits == 0) bits = 128;
        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {
            size_t total_idx = (byte_idx % 16) + shift_bytes;
            uint64_t val = 0;
            if (total_idx < 16) {
                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);
                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            } else {
                size_t m_idx = total_idx - 16;
                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);
                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            }
            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);
            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);
            uint64_t clr = old_v & ~(0xffULL << shift);
            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_CALL_EXTERN: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        if (sym_ptr) {
            uint32_t sym_h = g_external_symbols[sym_idx].hash;
            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
            uint64_t a0 = ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RCX);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RBX);
            uint64_t a4 = ctx.get_reg(REG_RSI);
            uint64_t a5 = ctx.get_reg(REG_RDI);
            uint64_t a6 = ctx.get_reg(REG_R8);
            uint64_t a7 = ctx.get_reg(REG_R9);
            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));
            uint64_t ret_val = 0;
            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
                typedef int (*printf_fn_t)(const char*, ...);
                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
                typedef int (*fprintf_fn_t)(void*, const char*, ...);
                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
                typedef int (*sprintf_fn_t)(char*, const char*, ...);
                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
            } else {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
            }
            ctx.set_reg(REG_RAX, ret_val);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint64_t _v = 0;
        std::memcpy(&_v, reinterpret_cast<const void*>(_ptr), sizeof(uint64_t));
        ctx.set_reg(dst, _v);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint32_t _v32 = 0;
        std::memcpy(&_v32, reinterpret_cast<const void*>(_ptr), sizeof(uint32_t));
        ctx.set_reg(dst, (uint64_t)_v32);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_16: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_8: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint8_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S32: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int32_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S16: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S8: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int8_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint64_t _src_v = ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_src_v, sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint32_t _v32 = (uint32_t)ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_v32, sizeof(uint32_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16: {
        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;
        *reinterpret_cast<uint16_t*>(_target) = (uint16_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8: {
        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;
        *reinterpret_cast<uint8_t*>(_target) = (uint8_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        ctx.set_reg(dst, (uint64_t)sym_ptr);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) + std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) - std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) * std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        double r = a / b;
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSQRT_D: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        double r = std::sqrt(a);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.of = false;
        ctx.sf = (_a < _b);
        ctx.cf = (_a >= _b);
        ctx.zf = (_a == _b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS: {
        ctx.set_reg(dst, (uint64_t)(int64_t)std::bit_cast<double>(ctx.get_vreg_lane(src, 0)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF: {
        int64_t v = (int64_t)ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZU: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        ctx.set_reg(dst, (a < 0.0) ? 0ULL : (uint64_t)a);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_UCVTF: {
        uint64_t v = ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVT: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        float f32 = std::bit_cast<float>((uint32_t)a_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD: {
        uint64_t _addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        uint64_t _val = __atomic_load_n(reinterpret_cast<uint64_t*>(_addr), __ATOMIC_SEQ_CST);
        ctx.set_reg(dst, _val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE: {
        uint64_t _addr = ctx.get_reg(dst) + (uint64_t)imm;
        (void)__atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _exp = ctx.get_reg(src), _des = ctx.get_reg(REG_RAX);
        __atomic_compare_exchange_n(reinterpret_cast<uint64_t*>(_addr), &_exp, _des, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _exp);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _old = __atomic_fetch_add(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _old = __atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FENCE: { std::atomic_thread_fence(std::memory_order_seq_cst); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_VR: { ctx.set_vreg_lane(dst, 0, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RV: {
        uint64_t _val = ctx.get_vreg_lane(src, 0);
        uint64_t _buf[1];
        std::memcpy(_buf, (&_val), sizeof(uint64_t));
        ctx.set_reg(dst, _buf[0]);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FCSEL_VV: {
        if (eval_condition(ctx, static_cast<uint8_t>((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL))))) {
            uint64_t _v = ctx.get_vreg_lane(src, 0);
            ctx.set_vreg_lane(dst, 0, _v);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_DECOY_0: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((k_dyn ^ 0x0000000000005877ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, ((_d ^ 0x0000000000005877ULL) + ctx.reg_mask)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_1: { ctx.reg_mask ^= ((k_dyn + 0x0000000000001337ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) + static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_2: { ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0xbf58476d1ce4e5b9ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) * 0x0000000000009e37ULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_3: { ctx.reg_mask ^= ((k_dyn >> 13) | 0x0000000000000001ULL); ctx.set_reg(dst, ((ctx.get_reg(dst) << 3) | (ctx.get_reg(dst) >> 61))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_4: { uint64_t _s = ctx.get_reg(src); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x000000000000cafeULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_s ^ static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_5: { ctx.reg_mask ^= ((k_dyn * 0x0000000000005877ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) & (~ctx.get_reg(src)))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_6: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x00000000cafebabeULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_d | 0x00000000cafebabeULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_7: { ctx.reg_mask ^= ((k_dyn >> 5) | 0x0000000000000001ULL); ctx.set_reg(dst, ((ctx.get_reg(dst) >> 5) ^ static_cast<uint64_t>(imm))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_8: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((static_cast<uint64_t>(op) - 0x0000000000001337ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_d - 0x0000000000001337ULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_9: { uint64_t _rhs = (ctx.get_reg(src) + 0x0000000000000001ULL); ctx.reg_mask ^= ((static_cast<uint64_t>(op) ^ _rhs) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ _rhs)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_10: { uint64_t _m = (ctx.get_reg(dst) * 0x5851f42d4c957f2dULL); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * 0x0000000000006a09ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (_m + 0x0000000000000001ULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_11: { ctx.reg_mask ^= ((k_dyn * 0x517cc1b727220a95ULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (((ctx.get_reg(dst) << 7) | static_cast<uint64_t>(imm)) - ((ctx.get_reg(dst) << 7) & static_cast<uint64_t>(imm)))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_12: { ctx.reg_mask ^= ((k_dyn ^ 0x00000000deadbeefULL) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ 0x00000000deadbeefULL)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_13: { ctx.reg_mask ^= ((k_dyn ^ static_cast<uint64_t>(dst)) | 0x0000000000000001ULL); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (0x0000000000000002ULL * (ctx.get_reg(dst) & ctx.get_reg(src))))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_14: { uint64_t _adj = (static_cast<uint64_t>(imm) * 0x0000000000000003ULL); ctx.reg_mask ^= ((static_cast<uint64_t>(op) * _adj) | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) ^ _adj)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_15: { uint64_t _d = ctx.get_reg(dst); ctx.reg_mask ^= ((~(static_cast<uint64_t>(op))) | 0x0000000000000001ULL); ctx.set_reg(dst, (~_d)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY: { uint64_t _p = (((k_dyn * 0x00005877cafebeefULL) ^ (static_cast<uint64_t>(op) * 0x9e3779b97f4a7c15ULL)) ^ 0xdeadbeef5a5a5a5aULL); ctx.reg_mask ^= (_p | 0x0000000000000001ULL); ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.reg_mask)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOP_D1: { ctx.executed_instructions += 1; FETCH_NEXT(); }
    H_MOV_RR_D1: { uint64_t _v = ctx.get_reg(src); ctx.set_reg(dst, _v); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RI_D1: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_HIGH_D1: {
        uint64_t high_val = (uint64_t)(uint32_t)imm << 32;
        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_NEG_RR_D1: { PROBE_START(); ctx.set_reg(dst, 0ULL - ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOT_RR_D1: { PROBE_START(); uint64_t _v = ctx.get_reg(dst); ctx.set_reg(dst, _v ^ ~0ULL); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_BSWAP_RR_D1: {
        uint32_t bits = (uint32_t)imm;
        if (bits == 16) ctx.set_reg(dst, (uint64_t)__builtin_bswap16((uint16_t)ctx.get_reg(src)));
        else if (bits == 32) ctx.set_reg(dst, (uint64_t)__builtin_bswap32((uint32_t)ctx.get_reg(src)));
        else ctx.set_reg(dst, __builtin_bswap64(ctx.get_reg(src)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CLZ_RR_D1: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz(v32) - (32 - bits));
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CTZ_RR_D1: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)__builtin_ctz(v32);
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_ctzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POPCNT_RR_D1: {
        uint64_t _s = ctx.get_reg(src);
        uint32_t _b = static_cast<uint32_t>(imm);
        uint64_t _mask = (_b >= 64) ? ~0ULL : ((1ULL << _b) - 1ULL);
        uint64_t _ms = _s & _mask;
        uint64_t _res = (_b <= 32) ? static_cast<uint64_t>(__builtin_popcount(static_cast<uint32_t>(_ms))) : static_cast<uint64_t>(__builtin_popcountll(_ms));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RBIT_RR_D1: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t res = 0;
        for (uint32_t i = 0; i < bits; ++i) {
            if ((val >> i) & 1ULL) { res |= (1ULL << (bits - 1 - i)); }
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((0x0000000000000002ULL * ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((0x0000000000000002ULL * (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + ((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((0x0000000000000002ULL * (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + ((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x613af83860837087ULL) << 0x0000000000000021ULL)) ^ (((((((0x0000000000000002ULL * ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((0x0000000000000002ULL * (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + ((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((0x0000000000000002ULL * (((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ctx.get_reg(dst)))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + ((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + ((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x613af83860837087ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x613af83860837087ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI_D1: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ static_cast<uint64_t>(imm)) + (0x0000000000000002ULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) + (((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) + (((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x12551bef20f1ce61ULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) + (((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) + (((((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL) - (((~ctx.get_reg(dst)) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~(((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((~((ctx.get_reg(dst) ^ ctx.get_reg(src)))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x12551bef20f1ce61ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x12551bef20f1ce61ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI_D1: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d - static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR_D1: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI_D1: {
        PROBE_START();
        ctx.set_reg(dst, static_cast<uint64_t>(static_cast<int64_t>(ctx.get_reg(dst)) * imm));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x757650d9535ec6e5ULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL) ^ ((ctx.get_reg(src) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x757650d9535ec6e5ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x757650d9535ec6e5ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI_D1: { PROBE_START(); ctx.set_reg(dst, (((((0x875e26e3bae2489bULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x875e26e3bae2489aULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0x78a1d91c451db766ULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm)))) + 0x79c111a9f470ec7aULL) - 0x79c111a9f470ec7aULL)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR_D1: { PROBE_START(); ctx.set_reg(dst, ((((ctx.get_reg(dst) & 0x5555555555555555ULL) - (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) - (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~((~ctx.get_reg(src)))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL))) + (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & (~(((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))))) - ((~(((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) & ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) ^ ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) - ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) | ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL)))) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))) & ((((ctx.get_reg(dst) | ctx.get_reg(src)) & 0x5555555555555555ULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) & ctx.get_reg(src)) & 0xaaaaaaaaaaaaaaaaULL))))))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI_D1: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) & static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR_D1: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (ctx.get_reg(src) ^ 0xffffffffffffffffULL))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL))))))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (ctx.get_reg(src) ^ 0xffffffffffffffffULL))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL))))))) & 0x000000007fffffffULL) * 0x4441fd1d7bda901fULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (ctx.get_reg(src) ^ 0xffffffffffffffffULL))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL))))))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (ctx.get_reg(src) ^ 0xffffffffffffffffULL))) + ((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) - (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL))))))) & 0x000000007fffffffULL) * 0x4441fd1d7bda901fULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x4441fd1d7bda901fULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI_D1: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, ((_d + _i) - (_d & _i))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ROL_RI_D1: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val << shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI_D1: {
        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(imm & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI_D1: {
        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(imm & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROL_RR_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RR_D1: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RR_D1: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, v << s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RR_D1: {
        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RR_D1: {
        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR_D1: {
        uint64_t b = ctx.get_reg(src);
        if (__builtin_expect(!b, 0)) { ctx.trapped = true; goto EXIT_VM; }
        ctx.set_reg(dst, ctx.get_reg(dst) / b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR_D1: {
        int64_t _d = static_cast<int64_t>(ctx.get_reg(dst)), _s = static_cast<int64_t>(ctx.get_reg(src));
        if (_s == 0 || (_s == -1 && _d == INT64_MIN)) { ctx.trapped = true; goto EXIT_VM; }
        int64_t _quot = (_s == -1) ? (-_d) : (_d / _s);
        ctx.set_reg(dst, static_cast<uint64_t>(_quot));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_MULH_RR_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        #if defined(__SIZEOF_INT128__)
        unsigned __int128 _prod = (unsigned __int128)a * (unsigned __int128)b;
        uint64_t res = static_cast<uint64_t>(_prod >> 64);
        #else
        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
        uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;
        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;
        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMULH_RR_D1: {
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        #if defined(__SIZEOF_INT128__)
        signed __int128 _prod = (signed __int128)a * (signed __int128)b;
        uint64_t res = static_cast<uint64_t>(_prod >> 64);
        #else
        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;
        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;
        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;
        uint64_t p0 = a_lo * b_lo, p1 = a_lo * b_hi, p2 = a_hi * b_lo, p3 = a_hi * b_hi;
        uint64_t cy = ((p0 >> 32) + (uint32_t)p1 + (uint32_t)p2) >> 32;
        uint64_t res = p3 + (p1 >> 32) + (p2 >> 32) + cy;
        if (a < 0) res -= ub;
        if (b < 0) res -= ua;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI_D1: {
        PROBE_START();
        uint64_t _d = ctx.get_reg(dst);
        compute_sub_flags(ctx, _d, static_cast<uint64_t>(imm), static_cast<uint32_t>((word >> 50) & 0x7F));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR_D1: {
        PROBE_START();
        uint32_t bits = static_cast<uint32_t>((word >> 50) & 0x7F);
        compute_sub_flags(ctx, ctx.get_reg(dst), ctx.get_reg(src), bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R_D1: {
        uint64_t val = ctx.get_reg(dst);
        ctx.push(val);
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            uint64_t sp_val = cur_sp - 8ULL;
            ctx.set_reg(REG_RSP, sp_val);
            std::memcpy(reinterpret_cast<void*>(sp_val), &val, sizeof(uint64_t));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POP_R_D1: {
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        uint64_t val = 0;
        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            val = *reinterpret_cast<const uint64_t*>(cur_sp);
            ctx.set_reg(REG_RSP, cur_sp + 8ULL);
            ctx.pop();
        } else {
            val = ctx.pop();
        }
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RR_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t ab = a + b;
        uint64_t res = ab + c;
        ctx.cf = (ab < a) || (res < ab);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RI_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t c = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a + b) + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RR_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a - (b + borrow);
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RI_D1: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RR_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RI_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_sub_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RR_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_add_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RI_D1: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_add_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_GET_FLAGS_R_D1: {
        uint64_t f = 2ULL;
        if (ctx.cf) f |= 1ULL;
        if (ctx.zf) f |= 0x40ULL;
        if (ctx.sf) f |= 0x80ULL;
        if (ctx.of) f |= 0x800ULL;
        ctx.set_reg(dst, f);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SET_FLAGS_R_D1: {
        uint64_t f = ctx.get_reg(src);
        ctx.cf = static_cast<bool>(f & 1ULL);
        ctx.zf = static_cast<bool>(f & 0x40ULL);
        ctx.sf = static_cast<bool>(f & 0x80ULL);
        ctx.of = static_cast<bool>(f & 0x800ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JMP_D1: {
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_JCC_D1: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t base_vip = static_cast<uint64_t>(((word >> 0x0000000000000016ULL) & 0x00000000001fffffULL));
        uint64_t enc_delta = static_cast<uint64_t>(((word >> 0x000000000000002bULL) & 0x00000000001fffffULL));
        uint64_t salt = (((static_cast<uint64_t>(cond) * 0x0000000000005877ULL) ^ 0x000000001337beefULL) & 0x00000000001fffffULL);
        uint64_t delta = (enc_delta ^ salt);
        uint64_t t_true = (base_vip ^ delta);
        uint64_t t_false = base_vip;
        uint64_t c = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #else
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CMOV_D1: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (ctx.get_reg(dst) & (~_m))));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_SETCC_D1: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t val = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        ctx.set_reg(dst, val);
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CALL_D1: {
        ctx.push(static_cast<uint64_t>(vIP_idx));
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_IJMP_R_D1: {
        uint64_t target = ctx.get_reg(dst);
        size_t _t_idx = static_cast<size_t>(target);
        if (_t_idx < count) {
                         vIP_idx = _t_idx;
} else {
            if (target != 0x0000000000000000ULL) {
                                                      #if defined(__x86_64__) || defined(_M_X64)
                                                      uint64_t a0 = ctx.get_reg(REG_RDI);
                                                      uint64_t a1 = ctx.get_reg(REG_RSI);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RCX);
                                                      uint64_t a4 = ctx.get_reg(REG_R8);
                                                      uint64_t a5 = ctx.get_reg(REG_R9);
                                                      #else
                                                      uint64_t a0 = ctx.get_reg(REG_RAX);
                                                      uint64_t a1 = ctx.get_reg(REG_RCX);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RBX);
                                                      uint64_t a4 = ctx.get_reg(REG_RSI);
                                                      uint64_t a5 = ctx.get_reg(REG_RDI);
                                                      #endif
                                                      typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                      indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);
                                                      uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                      ctx.set_reg(REG_RAX, ret_val);
                                                      goto EXIT_VM;
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_ICALL_R_D1: {
        uint64_t target_ptr = ctx.get_reg(dst);
        if (target_ptr < count) {
                             ctx.push(static_cast<uint64_t>(vIP_idx));
                             vIP_idx = static_cast<size_t>(target_ptr);
} else {
            if (target_ptr != 0x0000000000000000ULL) {
                                                          #if defined(__x86_64__) || defined(_M_X64)
                                                          uint64_t a0 = ctx.get_reg(REG_RDI);
                                                          uint64_t a1 = ctx.get_reg(REG_RSI);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RCX);
                                                          uint64_t a4 = ctx.get_reg(REG_R8);
                                                          uint64_t a5 = ctx.get_reg(REG_R9);
                                                          #else
                                                          uint64_t a0 = ctx.get_reg(REG_RAX);
                                                          uint64_t a1 = ctx.get_reg(REG_RCX);
                                                          uint64_t a2 = ctx.get_reg(REG_RDX);
                                                          uint64_t a3 = ctx.get_reg(REG_RBX);
                                                          uint64_t a4 = ctx.get_reg(REG_RSI);
                                                          uint64_t a5 = ctx.get_reg(REG_RDI);
                                                          #endif
                                                          typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                          indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);
                                                          uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                          ctx.set_reg(REG_RAX, ret_val);
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_RET_D1: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }
    H_EXIT_D1: { if (ctx.sp > 512) {
                       ctx.trapped = true;
} ctx.executed_instructions += 1; goto EXIT_VM; }

    H_BRIDGE_TO_FLOW_D1: {
        ctx.morph_math_to_flow(static_cast<uint64_t>(imm));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH_D1: {
        uint64_t _imm_math = static_cast<uint64_t>(imm);
        ctx.morph_flow_to_math(_imm_math);
        ctx.executed_instructions += 1;
        FETCH_NEXT();
    }
    H_FUSED_MOV_ADD_RRI_D1: {
        uint64_t _base = ctx.get_reg(src);
        ctx.set_reg(dst, (_base + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI_D1: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _res = ((ctx.get_reg(dst) * _imm) + (ctx.get_reg(src) * _imm));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI_D1: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _sum = (ctx.get_reg(dst) + ctx.get_reg(src));
        ctx.set_reg(dst, ((_sum | _imm) - (_sum & _imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI_D1: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) - ctx.get_reg(src)) ^ static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI_D1: {
        uint64_t _a = ctx.get_reg(dst);
        uint64_t _b = ctx.get_reg(src);
        uint64_t _x = ((_a + _b) - (0x0000000000000002ULL * (_a & _b)));
        ctx.set_reg(dst, (_x + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV_D1: {
        uint64_t a = ctx.get_reg(dst);
        uint64_t b = static_cast<uint64_t>(imm);
        uint8_t cond = static_cast<uint8_t>(((word >> 0x0000000000000032ULL) & 0x000000000000000fULL));
        uint32_t bits = static_cast<uint32_t>(((word >> 0x0000000000000036ULL) & 0x000000000000007fULL));
        compute_sub_flags(ctx, a, b, bits);
        if (eval_condition(ctx, cond)) {
                                    ctx.set_reg(dst, ctx.get_reg(src));
}
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_AND_OR_RRI_D1: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _a = (ctx.get_reg(dst) & ctx.get_reg(src));
        ctx.set_reg(dst, ((_a + _imm) - (_a & _imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SHL_ADD_RRI_D1: {
        uint64_t _shl = (ctx.get_reg(dst) << (static_cast<uint64_t>(imm) & 0x000000000000003fULL));
        uint64_t _s = ctx.get_reg(src);
        ctx.set_reg(dst, ((_shl ^ _s) + (0x0000000000000002ULL * (_shl & _s))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_VADD_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 + s0; uint64_t _res1 = d1 + s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VSUB_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vr = vsubq_u64(vcombine_u64(vcreate_u64(d0), vcreate_u64(d1)), vcombine_u64(vcreate_u64(s0), vcreate_u64(s1)));
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vr = _mm_sub_epi64(_mm_set_epi64x((int64_t)d1, (int64_t)d0), _mm_set_epi64x((int64_t)s1, (int64_t)s0));
        ctx.set_vreg(dst, static_cast<uint64_t>(_mm_extract_epi64(vr, 0)), static_cast<uint64_t>(_mm_extract_epi64(vr, 1)));
#else
        uint64_t _r0 = d0 - s0, _r1 = d1 - s1; ctx.set_vreg(dst, _r0, _r1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VMUL_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        ctx.set_vreg(dst, static_cast<uint64_t>(d0 * s0), static_cast<uint64_t>(d1 * s1));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VXOR_VV_D1: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vr = veorq_u64(vcombine_u64(vcreate_u64(d0), vcreate_u64(d1)), vcombine_u64(vcreate_u64(s0), vcreate_u64(s1)));
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vr = _mm_xor_si128(_mm_set_epi64x((int64_t)d1, (int64_t)d0), _mm_set_epi64x((int64_t)s1, (int64_t)s0));
        ctx.set_vreg(dst, static_cast<uint64_t>(_mm_extract_epi64(vr, 0)), static_cast<uint64_t>(_mm_extract_epi64(vr, 1)));
#else
        uint64_t _r0 = d0 ^ s0, _r1 = d1 ^ s1; ctx.set_vreg(dst, _r0, _r1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_VEC_MOV_D1: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        for (size_t i = 0; i < (bits + 63) / 64; ++i) ctx.set_vreg_lane(dst, i, ctx.get_vreg_lane(src, i));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_BINOP_D1: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);
        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;
            uint64_t value = 0;
            if (elem == 1 && vop <= 2) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint32_t>(fr);
            } else if (elem == 1 && vop == 11) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));
            } else if (elem == 1 && vop == 12) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));
            } else if (elem == 2 && vop <= 2) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint64_t>(fr);
            } else if (elem == 2 && vop == 11) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));
            } else if (elem == 2 && vop == 12) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));
            } else {
                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));
                switch (vop) {
                    case 0: value = a + b; break;
                    case 1: value = a - b; break;
                    case 2: value = a * b; break;
                    case 3: value = a & b; break;
                    case 4: value = a | b; break;
                    case 5: value = a ^ b; break;
                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                    case 9: value = (a == b) ? mask : 0; break;
                    case 10: value = (sa > sb) ? mask : 0; break;
                    case 11: value = (sa < sb) ? a : b; break;
                    case 12: value = (sa > sb) ? a : b; break;
                    case 13: value = (a < b) ? a : b; break;
                    case 14: value = (a > b) ? a : b; break;
                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;
                    case 16: value = (~a) & b; break;
                    case 17: {
                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);
                        size_t half_idx = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 18: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 21: {
                        uint8_t ctrl = (uint8_t)(b & 0xff);
                        if (ctrl & 0x80) value = 0;
                        else {
                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        }
                        break;
                    }
                    case 23: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 24: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 25: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 26: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2 + 1;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 28: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = 0;
                        }
                        break;
                    }
                    case 29: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;
                        }
                        break;
                    }
                    case 30: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = ~0ULL;
                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;
                        else value = (uint64_t)(sa / sb);
                        break;
                    }
                    case 31: {
                        value = (b != 0) ? (a / b) : mask;
                        break;
                    }
                    case 32: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = a;
                        else if (sb == -1 && sa == min_val) value = 0;
                        else value = (uint64_t)(sa % sb);
                        break;
                    }
                    case 33: {
                        value = (b != 0) ? (a % b) : a;
                        break;
                    }
                    case 34: value = (a != b) ? mask : 0; break;
                    case 35: value = (sa <= sb) ? mask : 0; break;
                    case 36: value = (a < b) ? mask : 0; break;
                    case 37: value = (a <= b) ? mask : 0; break;
                    default: value = a ^ b; break;
                }
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_IMM_D1: {
        uint64_t imm_val = imm & 0xffULL;
        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
            uint64_t value = 0;
            switch (vop) {
                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                case 21: {
                    size_t lane_in_128 = (bit / 32) % 4;
                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;
                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);
                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;
                    break;
                }
                case 22: {
                    size_t lane_idx = bit / lane_bits;
                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;
                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);
                    break;
                }
                default: value = a; break;
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_CLEAR_UPPER_D1: {
        ctx.set_vreg_lane(dst, 2, 0ULL);
        ctx.set_vreg_lane(dst, 3, 0ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_ZERO_UPPER_D1: {
        for (size_t i = 0; i < 16; ++i) {
            ctx.set_vreg_lane(i, 2, 0ULL);
            ctx.set_vreg_lane(i, 3, 0ULL);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PMOVMSKB_D1: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        uint32_t num_bytes = bits / 8;
        uint64_t mask = 0;
        for (uint32_t b = 0; b < num_bytes; ++b) {
            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;
            if (byte_val & 0x80) mask |= (1ULL << b);
        }
        ctx.set_reg(dst, mask);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_LOAD_D1: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_STORE_D1: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_SPLAT_D1: {
        uint32_t bits = (uint32_t)(imm & 0xffff);
        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);
        uint64_t val = ctx.get_reg(src);
        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);
        uint64_t val_masked = val & mask;
        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;
        for (uint32_t l = 0; l < num_lanes; ++l) {
            uint32_t pos = l * lane_bits;
            uint32_t chunk = pos / 64;
            uint32_t shift = pos % 64;
            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);
            uint64_t cur = ctx.get_vreg_lane(dst, chunk);
            cur = (cur & ~packed_mask) | (val_masked << shift);
            ctx.set_vreg_lane(dst, chunk, cur);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_EXT_D1: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);
        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);
        if (bits == 0) bits = 128;
        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {
            size_t total_idx = (byte_idx % 16) + shift_bytes;
            uint64_t val = 0;
            if (total_idx < 16) {
                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);
                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            } else {
                size_t m_idx = total_idx - 16;
                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);
                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            }
            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);
            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);
            uint64_t clr = old_v & ~(0xffULL << shift);
            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_CALL_EXTERN_D1: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        if (sym_ptr) {
            uint32_t sym_h = g_external_symbols[sym_idx].hash;
            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
            uint64_t a0 = ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RCX);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RBX);
            uint64_t a4 = ctx.get_reg(REG_RSI);
            uint64_t a5 = ctx.get_reg(REG_RDI);
            uint64_t a6 = ctx.get_reg(REG_R8);
            uint64_t a7 = ctx.get_reg(REG_R9);
            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));
            uint64_t ret_val = 0;
            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
                typedef int (*printf_fn_t)(const char*, ...);
                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
                typedef int (*fprintf_fn_t)(void*, const char*, ...);
                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
                typedef int (*sprintf_fn_t)(char*, const char*, ...);
                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
            } else {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
            }
            ctx.set_reg(REG_RAX, ret_val);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64_D1: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, *reinterpret_cast<const uint64_t*>(addr));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32_D1: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_16_D1: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint16_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_8_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint8_t _v8 = 0;
        std::memcpy(&_v8, reinterpret_cast<const void*>(_ptr), sizeof(uint8_t));
        ctx.set_reg(dst, (uint64_t)_v8);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S32_D1: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int32_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S16_D1: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S8_D1: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int8_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32_D1: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint32_t _v32 = (uint32_t)ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_v32, sizeof(uint32_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint16_t*>(addr) = (uint16_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM_D1: {
        size_t _idx = static_cast<size_t>(imm);
        void* _p = asgard_resolve_sym_idx((int32_t)_idx);
        ctx.set_reg(dst, static_cast<uint64_t>(reinterpret_cast<uintptr_t>(_p)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD_D1: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) + std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD_D1: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a - _b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD_D1: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) * std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD_D1: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        double _q = (_b == 0.0) ? ((_a == 0.0) ? NAN : (std::signbit(_a) ^ std::signbit(_b) ? -INFINITY : INFINITY)) : (_a / _b);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_q), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSQRT_D_D1: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _root = (_a < 0.0) ? NAN : std::sqrt(_a);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_root), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD_D1: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.zf = (a == b);
        ctx.cf = (a >= b);
        ctx.sf = (a < b);
        ctx.of = false;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS_D1: {
        ctx.set_reg(dst, (uint64_t)(int64_t)std::bit_cast<double>(ctx.get_vreg_lane(src, 0)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF_D1: {
        int64_t _s = static_cast<int64_t>(ctx.get_reg(src));
        double _d = static_cast<double>(_s);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZU_D1: {
        double a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        if (a < 0.0) ctx.set_reg(dst, 0ULL); else ctx.set_reg(dst, (uint64_t)a);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_UCVTF_D1: {
        double _d = static_cast<double>(ctx.get_reg(src));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVT_D1: {
        float f32 = std::bit_cast<float>((uint32_t)ctx.get_vreg_lane(src, 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD_D1: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        ctx.set_reg(dst, ptr->load(std::memory_order_seq_cst));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE_D1: {
        uint64_t _addr = ctx.get_reg(dst) + (uint64_t)imm;
        (void)__atomic_exchange_n(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t expected = ctx.get_reg(src);
        uint64_t desired = ctx.get_reg(REG_RAX);
        ptr->compare_exchange_strong(expected, desired, std::memory_order_seq_cst);
        ctx.set_reg(src, expected);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD_D1: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t old = ptr->fetch_add(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP_D1: {
        uint64_t* ptr = reinterpret_cast<uint64_t*>(ctx.get_reg(dst) + (uint64_t)imm);
        uint64_t old = __atomic_load_n(ptr, __ATOMIC_RELAXED);
        uint64_t new_val = ctx.get_reg(src);
        while (!__atomic_compare_exchange_n(ptr, &old, new_val, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FENCE_D1: { std::atomic_thread_fence(std::memory_order_seq_cst); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_VR_D1: {
        uint64_t _val = (ctx.get_reg(src) ^ 0xa5a5a5a55a5a5a5aULL);
        ctx.set_vreg_lane(dst, 0, (_val ^ 0xa5a5a5a55a5a5a5aULL));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_MOV_RV_D1: {
        uint64_t _val = ctx.get_vreg_lane(src, 0);
        uint64_t _buf[1];
        std::memcpy(_buf, (&_val), sizeof(uint64_t));
        ctx.set_reg(dst, _buf[0]);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FCSEL_VV_D1: {
        uint8_t _c = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint64_t _s = ctx.get_vreg_lane(src, 0);
        if (eval_condition(ctx, _c)) ctx.set_vreg_lane(dst, 0, _s);
        ctx.executed_instructions++; FETCH_NEXT();
    }


    H_NOP_D2: { ctx.executed_instructions += 1; FETCH_NEXT(); }
    H_MOV_RR_D2: { uint64_t _v = ctx.get_reg(src); ctx.set_reg(dst, _v); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_RI_D2: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_HIGH_D2: {
        uint32_t _low32 = static_cast<uint32_t>(ctx.get_reg(dst));
        ctx.set_reg(dst, (static_cast<uint64_t>(static_cast<uint32_t>(imm)) << 32) | static_cast<uint64_t>(_low32));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_NEG_RR_D2: { PROBE_START(); ctx.set_reg(dst, static_cast<uint64_t>(-static_cast<int64_t>(ctx.get_reg(dst)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_NOT_RR_D2: { PROBE_START(); ctx.set_reg(dst, ~ctx.get_reg(dst)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_BSWAP_RR_D2: {
        uint32_t bits = (uint32_t)imm;
        if (bits == 16) ctx.set_reg(dst, (uint64_t)__builtin_bswap16((uint16_t)ctx.get_reg(src)));
        else if (bits == 32) ctx.set_reg(dst, (uint64_t)__builtin_bswap32((uint32_t)ctx.get_reg(src)));
        else ctx.set_reg(dst, __builtin_bswap64(ctx.get_reg(src)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CLZ_RR_D2: {
        uint64_t val = ctx.get_reg(src);
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = val & mask;
        uint64_t res;
        if (bits <= 32) {
            uint32_t v32 = (uint32_t)mval;
            res = (v32 == 0) ? (uint64_t)bits : (uint64_t)(__builtin_clz(v32) - (32 - bits));
        } else {
            res = (mval == 0) ? 64ULL : (uint64_t)__builtin_clzll(mval);
        }
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CTZ_RR_D2: {
        uint64_t _s = ctx.get_reg(src);
        uint32_t _bits = static_cast<uint32_t>(imm);
        uint64_t _mask = (_bits >= 64) ? ~0ULL : ((1ULL << _bits) - 1ULL);
        uint64_t _ms = _s & _mask;
        if (_bits <= 32) {
            uint32_t _v32 = static_cast<uint32_t>(_ms);
            ctx.set_reg(dst, (_v32 == 0) ? static_cast<uint64_t>(_bits) : static_cast<uint64_t>(__builtin_ctz(_v32)));
        } else {
            ctx.set_reg(dst, (_ms == 0) ? 64ULL : static_cast<uint64_t>(__builtin_ctzll(_ms)));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POPCNT_RR_D2: {
        uint32_t bits = (uint32_t)imm;
        uint64_t mask = (bits >= 64) ? ~0ULL : ((1ULL << bits) - 1ULL);
        uint64_t mval = ctx.get_reg(src) & mask;
        if (bits <= 32) {
            ctx.set_reg(dst, (uint64_t)__builtin_popcount((uint32_t)mval));
        } else {
            ctx.set_reg(dst, (uint64_t)__builtin_popcountll(mval));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RBIT_RR_D2: {
        uint64_t _val = ctx.get_reg(src); uint32_t _bits = static_cast<uint32_t>(imm);
        uint64_t _res = 0; uint32_t _i = 0;
        while (_i < _bits) {
            if ((_val >> _i) & 1ULL) _res |= (1ULL << (_bits - 1 - _i));
            _i++;
        }
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL | (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + (((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL | (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + (((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x375d07dfcf915b81ULL) << 0x0000000000000021ULL)) ^ (((((((0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL | (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + (((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (((((0x0000000000000002ULL & (ctx.get_reg(dst) | ctx.get_reg(src))) * (0x0000000000000002ULL | (ctx.get_reg(dst) | ctx.get_reg(src)))) + ((0x0000000000000002ULL & (~((ctx.get_reg(dst) | ctx.get_reg(src))))) * ((~0x0000000000000002ULL) & (ctx.get_reg(dst) | ctx.get_reg(src))))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) + (((((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src))))))) + (((((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (~((ctx.get_reg(dst) ^ ctx.get_reg(src))))) - ((~((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))) + (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) ^ (ctx.get_reg(dst) ^ ctx.get_reg(src))) - (((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) | (ctx.get_reg(dst) ^ ctx.get_reg(src))) - ((0x0000000000000002ULL * (ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) ^ ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & (~((ctx.get_reg(dst) + ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) + ctx.get_reg(src)))) & (ctx.get_reg(dst) + ctx.get_reg(src)))) + (((ctx.get_reg(dst) + ctx.get_reg(src)) ^ (ctx.get_reg(dst) + ctx.get_reg(src))) - (((ctx.get_reg(dst) + ctx.get_reg(src)) | (ctx.get_reg(dst) + ctx.get_reg(src))) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (ctx.get_reg(dst) + ctx.get_reg(src)))))))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x375d07dfcf915b81ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x375d07dfcf915b81ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI_D2: { PROBE_START(); ctx.set_reg(dst, (((0x84b83431ee7403fcULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x84b83431ee7403fdULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0x7b47cbce118bfc05ULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x0b040d01993aa23bULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & (~((ctx.get_reg(src) & 0x5555555555555555ULL)))) - ((~((ctx.get_reg(dst) & 0x5555555555555555ULL))) & (ctx.get_reg(src) & 0x5555555555555555ULL))) + (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) - (((ctx.get_reg(dst) & 0x5555555555555555ULL) | (ctx.get_reg(src) & 0x5555555555555555ULL)) - ((ctx.get_reg(dst) & 0x5555555555555555ULL) & (ctx.get_reg(src) & 0x5555555555555555ULL))))) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0x5555555555555555ULL)) + (((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL) & 0xaaaaaaaaaaaaaaaaULL)))))) - (ctx.get_reg(dst) - ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x0b040d01993aa23bULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x0b040d01993aa23bULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI_D2: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); uint64_t _i = static_cast<uint64_t>(imm); ctx.set_reg(dst, (_d + ((~_i) + 0x0000000000000001ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR_D2: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI_D2: {
        PROBE_START();
        uint64_t _d = ctx.get_reg(dst);
        ctx.set_reg(dst, _d * static_cast<uint64_t>(imm));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) & (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) & (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x0f3d1854b96065b7ULL) << 0x0000000000000021ULL)) ^ (((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) & (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) ^ ((((((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) & (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))))) + (((((((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & 0x5555555555555555ULL) & 0xaaaaaaaaaaaaaaaaULL)) ^ ((ctx.get_reg(src) - (ctx.get_reg(src) & (~0x5555555555555555ULL))) + ((ctx.get_reg(src) ^ 0x5555555555555555ULL) - ((ctx.get_reg(src) | 0x5555555555555555ULL) - (ctx.get_reg(src) & 0x5555555555555555ULL))))) ^ (((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~0xaaaaaaaaaaaaaaaaULL))) + ((ctx.get_reg(dst) ^ 0xaaaaaaaaaaaaaaaaULL) - ((ctx.get_reg(dst) | 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL)))) ^ ((ctx.get_reg(src) + 0xaaaaaaaaaaaaaaaaULL) - (ctx.get_reg(src) | 0xaaaaaaaaaaaaaaaaULL)))) + (0x0000000000000002ULL * (((ctx.get_reg(dst) & 0x5555555555555555ULL) ^ (ctx.get_reg(src) & 0x5555555555555555ULL)) & ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) + ((((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) | (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL)) + ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) & (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) & 0xaaaaaaaaaaaaaaaaULL) + (ctx.get_reg(src) & 0xaaaaaaaaaaaaaaaaULL))))))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x0f3d1854b96065b7ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x0f3d1854b96065b7ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI_D2: { PROBE_START(); uint64_t _d = ctx.get_reg(dst); ctx.set_reg(dst, (_d ^ static_cast<uint64_t>(imm))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL))))) ^ ((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL))))) & 0x000000007fffffffULL) * 0x1476d84870efdbbbULL) << 0x0000000000000021ULL)) ^ (((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL))))) ^ ((((((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((((ctx.get_reg(dst) & (~((ctx.get_reg(dst) & (~ctx.get_reg(src)))))) - ((ctx.get_reg(dst) ^ 0xffffffffffffffffULL) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL)))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ULL) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0xaaaaaaaaaaaaaaaaULL))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & (((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0x5555555555555555ULL)) + ((((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL) - (((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~((ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~((ctx.get_reg(dst) | ctx.get_reg(src)))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))) & 0xaaaaaaaaaaaaaaaaULL))))) & 0x000000007fffffffULL) * 0x1476d84870efdbbbULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x1476d84870efdbbbULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI_D2: { PROBE_START(); ctx.set_reg(dst, (((((0x87a662d1d7174ad7ULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0x87a662d1d7174ad8ULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0x78599d2e28e8b529ULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm)))) + 0x5895f414893f44d6ULL) - 0x5895f414893f44d6ULL)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR_D2: { PROBE_START(); ctx.set_reg(dst, (((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - ((((0x0000000000000002ULL * ((ctx.get_reg(dst) & ctx.get_reg(src)) | (ctx.get_reg(dst) & (~ctx.get_reg(src))))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) ^ ctx.get_reg(dst))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst)))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - ((((0x0000000000000002ULL * ((ctx.get_reg(dst) & ctx.get_reg(src)) | (ctx.get_reg(dst) & (~ctx.get_reg(src))))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) ^ ctx.get_reg(dst))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst)))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x08885488365ea2e1ULL) << 0x0000000000000021ULL)) ^ (((((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - ((((0x0000000000000002ULL * ((ctx.get_reg(dst) & ctx.get_reg(src)) | (ctx.get_reg(dst) & (~ctx.get_reg(src))))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) ^ ctx.get_reg(dst))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst)))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) ^ ((((((0x0000000000000002ULL * ((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - ((((0x0000000000000002ULL * ((ctx.get_reg(dst) & ctx.get_reg(src)) | (ctx.get_reg(dst) & (~ctx.get_reg(src))))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) ^ (ctx.get_reg(dst) & (~ctx.get_reg(src))))) + (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - ((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))))) ^ ctx.get_reg(dst))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst)))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & ((0x0000000000000002ULL * (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) & (~ctx.get_reg(dst)))) - (((ctx.get_reg(dst) & ctx.get_reg(src)) + (ctx.get_reg(dst) & (~ctx.get_reg(src)))) ^ ctx.get_reg(dst))))) - (ctx.get_reg(dst) | ctx.get_reg(src)))) & 0x000000007fffffffULL) * 0x08885488365ea2e1ULL) << 0x0000000000000021ULL)) & 0x000000007fffffffULL) * 0x08885488365ea2e1ULL) << 0x0000000000000021ULL))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI_D2: { PROBE_START(); ctx.set_reg(dst, (((((0xb91440da961198d4ULL * (ctx.get_reg(dst) ^ static_cast<uint64_t>(imm))) + (0xb91440da961198d4ULL * (ctx.get_reg(dst) & static_cast<uint64_t>(imm)))) + (0x46ebbf2569ee672dULL * (ctx.get_reg(dst) | static_cast<uint64_t>(imm)))) + 0xb3cdb335c5266cf0ULL) - 0xb3cdb335c5266cf0ULL)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ROL_RI_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (v << s) | (v >> ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        uint64_t _res = (val >> shift) | (val << ((64 - shift) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(imm & 63);
        ctx.set_reg(dst, v << s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI_D2: {
        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(imm & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROL_RR_D2: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RR_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, (v >> s) | (v << ((64 - s) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RR_D2: {
        uint64_t v = ctx.get_reg(dst); uint32_t s = static_cast<uint32_t>(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, v << s);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RR_D2: {
        uint64_t _res = ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63);
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RR_D2: {
        uint64_t _res = (uint64_t)((int64_t)ctx.get_reg(dst) >> (uint32_t)(ctx.get_reg(src) & 63));
        ctx.set_reg(dst, _res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR_D2: {
        uint64_t b = ctx.get_reg(src);
        if (__builtin_expect(!b, 0)) { ctx.trapped = true; goto EXIT_VM; }
        ctx.set_reg(dst, ctx.get_reg(dst) / b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR_D2: {
        int64_t b = (int64_t)ctx.get_reg(src); int64_t a = (int64_t)ctx.get_reg(dst);
        if (__builtin_expect(b == 0 || (b == -1 && a == INT64_MIN), 0)) { ctx.trapped = true; goto EXIT_VM; }
        int64_t q = (b == -1) ? (int64_t)(0ULL - (uint64_t)a) : (a / b);
        ctx.set_reg(dst, static_cast<uint64_t>(q));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_MULH_RR_D2: {
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((unsigned __int128)ctx.get_reg(dst) * (unsigned __int128)ctx.get_reg(src)) >> 64);
        #else
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t a_lo = (uint32_t)a, a_hi = a >> 32;
        uint64_t b_lo = (uint32_t)b, b_hi = b >> 32;
        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;
        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMULH_RR_D2: {
        #if defined(__SIZEOF_INT128__)
        uint64_t res = (uint64_t)(((signed __int128)(int64_t)ctx.get_reg(dst) * (signed __int128)(int64_t)ctx.get_reg(src)) >> 64);
        #else
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        uint64_t ua = (uint64_t)a, ub = (uint64_t)b;
        uint64_t a_lo = (uint32_t)ua, a_hi = ua >> 32;
        uint64_t b_lo = (uint32_t)ub, b_hi = ub >> 32;
        uint64_t cy = (((a_lo * b_lo) >> 32) + (uint32_t)(a_lo * b_hi) + (uint32_t)(a_hi * b_lo)) >> 32;
        uint64_t res = (a_hi * b_hi) + ((a_lo * b_hi) >> 32) + ((a_hi * b_lo) >> 32) + cy;
        if (a < 0) res -= ub;
        if (b < 0) res -= ua;
        #endif
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI_D2: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint32_t bits = (uint32_t)((word >> 50) & 0x7F);
        compute_sub_flags(ctx, a, b, bits);
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR_D2: {
        PROBE_START();
        uint64_t _a = ctx.get_reg(dst), _b = ctx.get_reg(src);
        compute_sub_flags(ctx, _a, _b, static_cast<uint32_t>((word >> 50) & 0x7F));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R_D2: {
        uint64_t val = ctx.get_reg(dst);
        ctx.push(val);
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        if (cur_sp >= 0x10008ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            uint64_t* sp_ptr = reinterpret_cast<uint64_t*>(cur_sp - 8ULL);
            ctx.set_reg(REG_RSP, reinterpret_cast<uint64_t>(sp_ptr));
            *sp_ptr = val;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_POP_R_D2: {
        uint64_t cur_sp = ctx.get_reg(REG_RSP);
        uint64_t val = 0;
        if (cur_sp >= 0x10000ULL && cur_sp <= 0x7FFFFFFFFFFFULL) {
            const uint64_t* sp_ptr = reinterpret_cast<const uint64_t*>(cur_sp);
            val = *sp_ptr;
            ctx.set_reg(REG_RSP, cur_sp + sizeof(uint64_t));
            ctx.pop();
        } else {
            val = ctx.pop();
        }
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RR_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t c = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a + b) + c;
        ctx.cf = (res < a) || (c && res == a);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ res) & (b ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADC_RI_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t c = ctx.cf ? 1ULL : 0ULL;
        uint64_t ab = a + b;
        uint64_t res = ab + c;
        ctx.cf = (ab < a) || (res < ab);
        ctx.of = ((((a ^ res) & (b ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RR_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t borrow = ctx.cf ? 1ULL : 0ULL;
        uint64_t res = a - (b + borrow);
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SBB_RI_D2: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t borrow = static_cast<uint64_t>(ctx.cf);
        uint64_t res = (a - b) - borrow;
        ctx.cf = (a < b) || (borrow && a == b);
        ctx.zf = (res == 0);
        ctx.sf = (res >> 63) != 0;
        ctx.of = (((a ^ b) & (a ^ res)) >> 63) != 0;
        ctx.set_reg(dst, res);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RR_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_sub_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMP_RI_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (!eval_condition(ctx, cond)) {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        } else {
            uint64_t a = ctx.get_reg(dst);
            compute_sub_flags(ctx, a, b, bits);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RR_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
            compute_add_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CCMN_RI_D2: {
        uint8_t cond = (uint8_t)((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL)));
        uint8_t nzcv = (uint8_t)((((word >> 22) + 0x0FULL) - ((word >> 22) | 0x0FULL)));
        uint64_t b = (uint64_t)((((word >> 26) + 0x1FULL) - ((word >> 26) | 0x1FULL)));
        uint32_t bits = (uint32_t)((((word >> 50) + 0x7FULL) - ((word >> 50) | 0x7FULL)));
        if (eval_condition(ctx, cond)) {
            uint64_t a = ctx.get_reg(dst);
            compute_add_flags(ctx, a, b, bits);
        } else {
            ctx.sf = (nzcv & 8) != 0;
            ctx.zf = (nzcv & 4) != 0;
            ctx.cf = (nzcv & 2) != 0;
            ctx.of = (nzcv & 1) != 0;
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_GET_FLAGS_R_D2: {
        uint64_t f = 2ULL;
        if (ctx.cf) f |= 1ULL;
        if (ctx.zf) f |= 0x40ULL;
        if (ctx.sf) f |= 0x80ULL;
        if (ctx.of) f |= 0x800ULL;
        ctx.set_reg(dst, f);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SET_FLAGS_R_D2: {
        uint64_t f = ctx.get_reg(src);
        ctx.cf = static_cast<bool>(f & 1ULL);
        ctx.zf = static_cast<bool>(f & 0x40ULL);
        ctx.sf = static_cast<bool>(f & 0x80ULL);
        ctx.of = static_cast<bool>(f & 0x800ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JMP_D2: {
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_JCC_D2: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        uint64_t base_vip = static_cast<uint64_t>(((word >> 0x0000000000000016ULL) & 0x00000000001fffffULL));
        uint64_t enc_delta = static_cast<uint64_t>(((word >> 0x000000000000002bULL) & 0x00000000001fffffULL));
        uint64_t salt = (((static_cast<uint64_t>(cond) * 0x0000000000005877ULL) ^ 0x000000001337beefULL) & 0x00000000001fffffULL);
        uint64_t delta = (enc_delta ^ salt);
        uint64_t t_true = (base_vip ^ delta);
        uint64_t t_false = base_vip;
        uint64_t c = (eval_condition(ctx, cond) ? 0x0000000000000001ULL : 0x0000000000000000ULL);
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = static_cast<uint32_t>(c);
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), t_true, t_false, static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false))));
        #else
        vIP_idx = static_cast<size_t>(((c * t_true) + ((0x0000000000000001ULL - c) * t_false)));
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CMOV_D2: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        if (eval_condition(ctx, cond)) {
                                    ctx.set_reg(dst, ctx.get_reg(src));
}
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_SETCC_D2: {
        PROBE_START();
        uint8_t cond = static_cast<uint8_t>((((word >> 0x0000000000000012ULL) + 0x000000000000000fULL) - ((word >> 0x0000000000000012ULL) | 0x000000000000000fULL)));
        ctx.set_reg(dst, static_cast<uint64_t>((eval_condition(ctx, cond) ? 1 : 0)));
        PROBE_CHECK();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CALL_D2: {
        ctx.push(static_cast<uint64_t>(vIP_idx));
        #if defined(__APPLE__)
        vIP_idx = static_cast<size_t>(imm);
        #elif defined(_WIN32)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        __debugbreak();
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #elif defined(__linux__) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = static_cast<uint32_t>(vIP_idx);
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite(static_cast<uint32_t>(vIP_idx), static_cast<uint64_t>(imm), static_cast<uint64_t>(imm), static_cast<uint64_t>((seed ^ static_cast<uint32_t>(vIP_idx))));
        raise(SIGTRAP);
        vIP_idx = ((asgard_nanomites::g_nanomite_dispatcher.resolved_target != 0) ? static_cast<size_t>(asgard_nanomites::g_nanomite_dispatcher.resolved_target) : static_cast<size_t>(imm));
        #else
        vIP_idx = static_cast<size_t>(imm);
        #endif
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_IJMP_R_D2: {
        uint64_t target = ctx.get_reg(dst);
        if (target < count) {
                         vIP_idx = static_cast<size_t>(target);
} else {
            if (target != 0x0000000000000000ULL) {
                                                      #if defined(__x86_64__) || defined(_M_X64)
                                                      uint64_t a0 = ctx.get_reg(REG_RDI);
                                                      uint64_t a1 = ctx.get_reg(REG_RSI);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RCX);
                                                      uint64_t a4 = ctx.get_reg(REG_R8);
                                                      uint64_t a5 = ctx.get_reg(REG_R9);
                                                      #else
                                                      uint64_t a0 = ctx.get_reg(REG_RAX);
                                                      uint64_t a1 = ctx.get_reg(REG_RCX);
                                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                                      uint64_t a3 = ctx.get_reg(REG_RBX);
                                                      uint64_t a4 = ctx.get_reg(REG_RSI);
                                                      uint64_t a5 = ctx.get_reg(REG_RDI);
                                                      #endif
                                                      typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                                      indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target);
                                                      uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                                      ctx.set_reg(REG_RAX, ret_val);
                                                      goto EXIT_VM;
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_ICALL_R_D2: {
        uint64_t target_ptr = ctx.get_reg(dst);
        if (__builtin_expect((target_ptr < count), 1)) {
                                                    uint64_t _ret = static_cast<uint64_t>(vIP_idx);
                                                    ctx.push(_ret);
                                                    vIP_idx = static_cast<size_t>(target_ptr);
} else {
            if (target_ptr != 0) {
                                      #if defined(__x86_64__) || defined(_M_X64)
                                      uint64_t a0 = ctx.get_reg(REG_RDI);
                                      uint64_t a1 = ctx.get_reg(REG_RSI);
                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                      uint64_t a3 = ctx.get_reg(REG_RCX);
                                      uint64_t a4 = ctx.get_reg(REG_R8);
                                      uint64_t a5 = ctx.get_reg(REG_R9);
                                      #else
                                      uint64_t a0 = ctx.get_reg(REG_RAX);
                                      uint64_t a1 = ctx.get_reg(REG_RCX);
                                      uint64_t a2 = ctx.get_reg(REG_RDX);
                                      uint64_t a3 = ctx.get_reg(REG_RBX);
                                      uint64_t a4 = ctx.get_reg(REG_RSI);
                                      uint64_t a5 = ctx.get_reg(REG_RDI);
                                      #endif
                                      typedef uint64_t (*indirect_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                                      indirect_fn_t fn = reinterpret_cast<indirect_fn_t>(target_ptr);
                                      uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5);
                                      ctx.set_reg(REG_RAX, ret_val);
            }
}
        ctx.reanchor_running_key(static_cast<uint64_t>(vIP_idx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_RET_D2: ctx.executed_instructions++; goto EXIT_VM;
    H_EXIT_D2: ctx.executed_instructions++; goto EXIT_VM;

    H_BRIDGE_TO_FLOW_D2: {
        ctx.morph_math_to_flow(static_cast<uint64_t>(imm));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH_D2: {
        ctx.morph_flow_to_math(static_cast<uint64_t>((imm & 0xffffffffffffffffULL)));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FUSED_MOV_ADD_RRI_D2: {
        ctx.set_reg(dst, (ctx.get_reg(src) + static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI_D2: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) * static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI_D2: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) ^ static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI_D2: {
        uint64_t _imm = static_cast<uint64_t>(imm);
        uint64_t _diff = (ctx.get_reg(dst) - ctx.get_reg(src));
        ctx.set_reg(dst, ((_diff | _imm) - (_diff & _imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI_D2: {
        uint64_t _a = ctx.get_reg(dst);
        uint64_t _b = ctx.get_reg(src);
        uint64_t _x = ((_a | _b) - (_a & _b));
        uint64_t _i = static_cast<uint64_t>(imm);
        ctx.set_reg(dst, ((_x | _i) + (_x & _i)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV_D2: {
        uint64_t a = ctx.get_reg(dst);
        uint64_t b = static_cast<uint64_t>(imm);
        uint8_t cond = static_cast<uint8_t>(((word >> 0x0000000000000032ULL) & 0x000000000000000fULL));
        uint32_t bits = static_cast<uint32_t>(((word >> 0x0000000000000036ULL) & 0x000000000000007fULL));
        compute_sub_flags(ctx, a, b, bits);
        uint64_t _m = (eval_condition(ctx, cond) ? (~0x0000000000000000ULL) : 0x0000000000000000ULL);
        ctx.set_reg(dst, ((ctx.get_reg(src) & _m) | (a & (~_m))));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_AND_OR_RRI_D2: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) & ctx.get_reg(src)) | static_cast<uint64_t>(imm)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SHL_ADD_RRI_D2: {
        ctx.set_reg(dst, ((ctx.get_reg(dst) << (static_cast<uint64_t>(imm) & 0x000000000000003fULL)) + ctx.get_reg(src)));
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_VADD_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        uint64_t _res0 = d0 + s0; uint64_t _res1 = d1 + s1;
        ctx.set_vreg(dst, _res0, _res1);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VSUB_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vd = vcombine_u64(vcreate_u64(d0), vcreate_u64(d1));
        uint64x2_t vs = vcombine_u64(vcreate_u64(s0), vcreate_u64(s1));
        uint64x2_t vr = vsubq_u64(vd, vs);
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vd = _mm_set_epi64x((int64_t)d1, (int64_t)d0);
        __m128i vs = _mm_set_epi64x((int64_t)s1, (int64_t)s0);
        __m128i vr = _mm_sub_epi64(vd, vs);
        ctx.set_vreg(dst, (uint64_t)_mm_extract_epi64(vr, 0), (uint64_t)_mm_extract_epi64(vr, 1));
#else
        ctx.set_vreg(dst, d0 - s0, d1 - s1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VMUL_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        ctx.set_vreg(dst, static_cast<uint64_t>(d0 * s0), static_cast<uint64_t>(d1 * s1));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VXOR_VV_D2: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
#if defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)
        uint64x2_t vr = veorq_u64(vcombine_u64(vcreate_u64(d0), vcreate_u64(d1)), vcombine_u64(vcreate_u64(s0), vcreate_u64(s1)));
        ctx.set_vreg(dst, vgetq_lane_u64(vr, 0), vgetq_lane_u64(vr, 1));
#elif defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)
        __m128i vr = _mm_xor_si128(_mm_set_epi64x((int64_t)d1, (int64_t)d0), _mm_set_epi64x((int64_t)s1, (int64_t)s0));
        ctx.set_vreg(dst, static_cast<uint64_t>(_mm_extract_epi64(vr, 0)), static_cast<uint64_t>(_mm_extract_epi64(vr, 1)));
#else
        uint64_t _r0 = d0 ^ s0, _r1 = d1 ^ s1; ctx.set_vreg(dst, _r0, _r1);
#endif
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_VEC_MOV_D2: {
        uint32_t bits = (uint32_t)(imm & 0x3ff); size_t i = 0;
        while (i < (bits + 63) / 64) { ctx.set_vreg_lane(dst, i, ctx.get_vreg_lane(src, i)); ++i; }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_BINOP_D2: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t bits = (uint32_t)((imm >> 5) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 15) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 23) & 0x1f);
        uint32_t elem = (uint32_t)((imm >> 28) & 0x3);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            uint64_t b = (ctx.get_vreg_lane(src2, chunk) >> shift) & mask;
            uint64_t value = 0;
            if (elem == 1 && vop <= 2) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                float fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint32_t>(fr);
            } else if (elem == 1 && vop == 11) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmin(fa, fb));
            } else if (elem == 1 && vop == 12) {
                float fa = std::bit_cast<float>(static_cast<uint32_t>(a));
                float fb = std::bit_cast<float>(static_cast<uint32_t>(b));
                value = std::bit_cast<uint32_t>(std::fmax(fa, fb));
            } else if (elem == 2 && vop <= 2) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                double fr = vop == 0 ? fa + fb : (vop == 1 ? fa - fb : fa * fb);
                value = std::bit_cast<uint64_t>(fr);
            } else if (elem == 2 && vop == 11) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmin(fa, fb));
            } else if (elem == 2 && vop == 12) {
                double fa = std::bit_cast<double>(a);
                double fb = std::bit_cast<double>(b);
                value = std::bit_cast<uint64_t>(std::fmax(fa, fb));
            } else {
                int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
                int64_t sb = lane_bits == 8 ? (int64_t)(int8_t)b : (lane_bits == 16 ? (int64_t)(int16_t)b : (lane_bits == 32 ? (int64_t)(int32_t)b : (int64_t)b));
                switch (vop) {
                    case 0: value = a + b; break;
                    case 1: value = a - b; break;
                    case 2: value = a * b; break;
                    case 3: value = a & b; break;
                    case 4: value = a | b; break;
                    case 5: value = a ^ b; break;
                    case 6: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                    case 7: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                    case 8: { uint32_t cnt = (uint32_t)(ctx.get_vreg_lane(src2, 0) & 0xff); value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                    case 9: value = (a == b) ? mask : 0; break;
                    case 10: value = (sa > sb) ? mask : 0; break;
                    case 11: value = (sa < sb) ? a : b; break;
                    case 12: value = (sa > sb) ? a : b; break;
                    case 13: value = (a < b) ? a : b; break;
                    case 14: value = (a > b) ? a : b; break;
                    case 15: value = (uint64_t)(sa < 0 ? -sa : sa) & mask; break;
                    case 16: value = (~a) & b; break;
                    case 17: {
                        size_t block_lane = (bit / lane_bits) % (128 / lane_bits);
                        size_t half_idx = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 18: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_idx = (num_lanes / 2) + (block_lane / 2);
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t src_bit = ((bit / 128) * 128) + (half_idx * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 21: {
                        uint8_t ctrl = (uint8_t)(b & 0xff);
                        if (ctrl & 0x80) value = 0;
                        else {
                            size_t src_bit = ((bit / 128) * 128) + ((ctrl & 0xf) * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        }
                        break;
                    }
                    case 23: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2) : ((block_lane - half_len) * 2);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 24: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t half_len = num_lanes / 2;
                        size_t src_reg = (block_lane < half_len) ? src : src2;
                        size_t sel_elem = (block_lane < half_len) ? (block_lane * 2 + 1) : ((block_lane - half_len) * 2 + 1);
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 25: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 26: {
                        size_t num_lanes = 128 / lane_bits;
                        size_t block_lane = (bit / lane_bits) % num_lanes;
                        size_t k = block_lane / 2;
                        size_t src_reg = (block_lane % 2 == 0) ? src : src2;
                        size_t sel_elem = k * 2 + 1;
                        size_t src_bit = ((bit / 128) * 128) + (sel_elem * lane_bits);
                        value = (ctx.get_vreg_lane(src_reg, src_bit / 64) >> (src_bit % 64)) & mask;
                        break;
                    }
                    case 28: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = 0;
                        }
                        break;
                    }
                    case 29: {
                        uint8_t idx = (uint8_t)(b & 0xff);
                        if (idx < 16) {
                            size_t src_bit = ((bit / 128) * 128) + (idx * 8);
                            value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xff;
                        } else {
                            value = (ctx.get_vreg_lane(dst, chunk) >> shift) & 0xff;
                        }
                        break;
                    }
                    case 30: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = ~0ULL;
                        else if (sb == -1 && sa == min_val) value = (uint64_t)sa;
                        else value = (uint64_t)(sa / sb);
                        break;
                    }
                    case 31: {
                        value = (b != 0) ? (a / b) : mask;
                        break;
                    }
                    case 32: {
                        int64_t min_val = (lane_bits == 64) ? (int64_t)0x8000000000000000ULL : (lane_bits == 32) ? (int64_t)(int32_t)0x80000000 : (lane_bits == 16) ? (int64_t)(int16_t)0x8000 : (int64_t)(int8_t)0x80;
                        if (sb == 0) value = a;
                        else if (sb == -1 && sa == min_val) value = 0;
                        else value = (uint64_t)(sa % sb);
                        break;
                    }
                    case 33: {
                        value = (b != 0) ? (a % b) : a;
                        break;
                    }
                    case 34: value = (a != b) ? mask : 0; break;
                    case 35: value = (sa <= sb) ? mask : 0; break;
                    case 36: value = (a < b) ? mask : 0; break;
                    case 37: value = (a <= b) ? mask : 0; break;
                    default: value = a ^ b; break;
                }
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_IMM_D2: {
        uint64_t imm_val = imm & 0xffULL;
        uint32_t bits = (uint32_t)((imm >> 8) & 0x3ff);
        uint32_t lane_bits = (uint32_t)((imm >> 18) & 0xff);
        if (lane_bits == 0) lane_bits = 64;
        uint32_t vop = (uint32_t)((imm >> 26) & 0x1f);
        uint64_t mask = lane_bits == 8 ? 0xffULL : (lane_bits == 16 ? 0xffffULL : (lane_bits == 32 ? 0xffffffffULL : ~0ULL));
        for (size_t bit = 0; bit < bits; bit += lane_bits) {
            size_t chunk = bit / 64; unsigned shift = (unsigned)(bit % 64);
            uint64_t a = (ctx.get_vreg_lane(src, chunk) >> shift) & mask;
            int64_t sa = lane_bits == 8 ? (int64_t)(int8_t)a : (lane_bits == 16 ? (int64_t)(int16_t)a : (lane_bits == 32 ? (int64_t)(int32_t)a : (int64_t)a));
            uint64_t value = 0;
            switch (vop) {
                case 6: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a << cnt); break; }
                case 7: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? 0 : (a >> cnt); break; }
                case 8: { uint32_t cnt = (uint32_t)imm_val; value = (cnt >= lane_bits) ? (sa < 0 ? mask : 0) : ((uint64_t)(sa >> cnt) & mask); break; }
                case 21: {
                    size_t lane_in_128 = (bit / 32) % 4;
                    size_t sel = (imm_val >> (lane_in_128 * 2)) & 3;
                    size_t src_bit = ((bit / 128) * 128) + (sel * 32);
                    value = (ctx.get_vreg_lane(src, src_bit / 64) >> (src_bit % 64)) & 0xffffffffULL;
                    break;
                }
                case 22: {
                    size_t lane_idx = bit / lane_bits;
                    size_t sel = (imm_val >> (lane_idx % 8)) & 1;
                    value = (sel == 0) ? a : ((ctx.get_vreg_lane(dst, chunk) >> shift) & mask);
                    break;
                }
                default: value = a; break;
            }
            uint64_t old_value = ctx.get_vreg_lane(dst, chunk);
            uint64_t packed_mask = mask << shift;
            ctx.set_vreg_lane(dst, chunk, (old_value & ~packed_mask) | ((value & mask) << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_CLEAR_UPPER_D2: {
        ctx.set_vreg_lane(dst, 2, 0ULL);
        ctx.set_vreg_lane(dst, 3, 0ULL);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_ZERO_UPPER_D2: {
        for (size_t i = 0; i < 16; ++i) {
            ctx.set_vreg_lane(i, 2, 0ULL);
            ctx.set_vreg_lane(i, 3, 0ULL);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PMOVMSKB_D2: {
        uint32_t bits = (uint32_t)(imm & 0x3ff);
        uint32_t num_bytes = bits / 8;
        uint64_t mask = 0;
        for (uint32_t b = 0; b < num_bytes; ++b) {
            uint64_t byte_val = (ctx.get_vreg_lane(src, b / 8) >> ((b % 8) * 8)) & 0xff;
            if (byte_val & 0x80) mask |= (1ULL << b);
        }
        ctx.set_reg(dst, mask);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_LOAD_D2: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(src) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) { uint64_t value = 0; std::memcpy(&value, reinterpret_cast<const void*>(address + i * 8), sizeof(value)); ctx.set_vreg_lane(dst, i, value); }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_STORE_D2: {
        uint32_t bits = (uint32_t)((word >> 50) & 0x3ff);
        uint64_t address = ctx.get_reg(dst) + (uint64_t)imm;
        for (size_t i = 0; i < (bits + 63) / 64; ++i) std::memcpy(reinterpret_cast<void*>(address + i * 8), &ctx.vregs[src & 31][i & 7], sizeof(uint64_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_SPLAT_D2: {
        uint32_t bits = (uint32_t)(imm & 0xffff);
        uint32_t lane_bits = (uint32_t)((imm >> 16) & 0xffff);
        uint64_t val = ctx.get_reg(src);
        uint64_t mask = (lane_bits >= 64) ? ~0ULL : ((1ULL << lane_bits) - 1ULL);
        uint64_t val_masked = val & mask;
        uint32_t num_lanes = (lane_bits > 0) ? (bits / lane_bits) : 0;
        for (uint32_t l = 0; l < num_lanes; ++l) {
            uint32_t pos = l * lane_bits;
            uint32_t chunk = pos / 64;
            uint32_t shift = pos % 64;
            uint64_t packed_mask = (lane_bits >= 64) ? ~0ULL : (mask << shift);
            uint64_t cur = ctx.get_vreg_lane(dst, chunk);
            cur = (cur & ~packed_mask) | (val_masked << shift);
            ctx.set_vreg_lane(dst, chunk, cur);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_VEC_EXT_D2: {
        uint32_t src2 = (uint32_t)(imm & 31);
        uint32_t shift_bytes = (uint32_t)((imm >> 5) & 15);
        uint32_t bits = (uint32_t)((imm >> 9) & 0x3ff);
        if (bits == 0) bits = 128;
        for (size_t byte_idx = 0; byte_idx < (bits / 8); ++byte_idx) {
            size_t total_idx = (byte_idx % 16) + shift_bytes;
            uint64_t val = 0;
            if (total_idx < 16) {
                size_t bit_pos = ((byte_idx / 16) * 128) + (total_idx * 8);
                val = (ctx.get_vreg_lane(src, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            } else {
                size_t m_idx = total_idx - 16;
                size_t bit_pos = ((byte_idx / 16) * 128) + (m_idx * 8);
                val = (ctx.get_vreg_lane(src2, bit_pos / 64) >> (bit_pos % 64)) & 0xff;
            }
            size_t chunk = (byte_idx * 8) / 64; unsigned shift = (unsigned)((byte_idx * 8) % 64);
            uint64_t old_v = ctx.get_vreg_lane(dst, chunk);
            uint64_t clr = old_v & ~(0xffULL << shift);
            ctx.set_vreg_lane(dst, chunk, clr | (val << shift));
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_CALL_EXTERN_D2: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        if (sym_ptr) {
            uint32_t sym_h = g_external_symbols[sym_idx].hash;
            uint32_t sym_ah = g_external_symbols[sym_idx].alt_hash;
            uint64_t a0 = ctx.get_reg(REG_RAX);
            uint64_t a1 = ctx.get_reg(REG_RCX);
            uint64_t a2 = ctx.get_reg(REG_RDX);
            uint64_t a3 = ctx.get_reg(REG_RBX);
            uint64_t a4 = ctx.get_reg(REG_RSI);
            uint64_t a5 = ctx.get_reg(REG_RDI);
            uint64_t a6 = ctx.get_reg(REG_R8);
            uint64_t a7 = ctx.get_reg(REG_R9);
            const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx.get_reg(REG_RSP));
            uint64_t ret_val = 0;
            if (sym_h == 0x42FCF5CFU || sym_ah == 0x42FCF5CFU || sym_h == 0x07554ACDU || sym_ah == 0x07554ACDU || sym_h == 0xE76FB4AAU || sym_ah == 0xE76FB4AAU) {
                typedef int (*printf_fn_t)(const char*, ...);
                printf_fn_t pfn = reinterpret_cast<printf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)pfn((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)pfn((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0xFCB512E2U || sym_ah == 0xFCB512E2U || sym_h == 0x4B3C5330U || sym_ah == 0x4B3C5330U || sym_h == 0x937D1EF6U || sym_ah == 0x937D1EF6U || sym_h == 0xCB76D42BU || sym_ah == 0xCB76D42BU || sym_h == 0xD54CE817U || sym_ah == 0xD54CE817U || sym_h == 0xBBED3905U || sym_ah == 0xBBED3905U || sym_h == 0x42C07C7CU || sym_ah == 0x42C07C7CU || sym_h == 0x24559DBDU || sym_ah == 0x24559DBDU) {
                typedef int (*fprintf_fn_t)(void*, const char*, ...);
                fprintf_fn_t fpfn = reinterpret_cast<fprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)fpfn((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x7FE32B00U || sym_ah == 0x7FE32B00U || sym_h == 0xBCBF60EEU || sym_ah == 0xBCBF60EEU || sym_h == 0x70E2D349U || sym_ah == 0x70E2D349U || sym_h == 0x44FA3468U || sym_ah == 0x44FA3468U) {
                typedef int (*sprintf_fn_t)(char*, const char*, ...);
                sprintf_fn_t spfn = reinterpret_cast<sprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)spfn((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
#endif
            } else if (sym_h == 0x54EE11FAU || sym_ah == 0x54EE11FAU || sym_h == 0x933075F4U || sym_ah == 0x933075F4U || sym_h == 0x3FD5EB6FU || sym_ah == 0x3FD5EB6FU || sym_h == 0x5B3553B4U || sym_ah == 0x5B3553B4U) {
                typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
                snprintf_fn_t snpfn = reinterpret_cast<snprintf_fn_t>(sym_ptr);
#if defined(__APPLE__) && defined(__aarch64__)
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
#else
                ret_val = (uint64_t)snpfn((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
#endif
            } else {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
            }
            ctx.set_reg(REG_RAX, ret_val);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint64_t _v = 0;
        std::memcpy(&_v, reinterpret_cast<const void*>(_ptr), sizeof(uint64_t));
        ctx.set_reg(dst, _v);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32_D2: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_16_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        uint16_t _v16 = 0;
        std::memcpy(&_v16, reinterpret_cast<const void*>(_ptr), sizeof(uint16_t));
        ctx.set_reg(dst, (uint64_t)_v16);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_8_D2: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint8_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S32_D2: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int32_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S16_D2: {
        const char* _base = reinterpret_cast<const char*>(ctx.get_reg(src));
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int16_t*>(_base + imm)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_S8_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(src)) + static_cast<uintptr_t>(imm);
        int8_t _s8 = 0;
        std::memcpy(&_s8, reinterpret_cast<const void*>(_ptr), sizeof(int8_t));
        ctx.set_reg(dst, (uint64_t)(int64_t)_s8);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64_D2: {
        char* _target = reinterpret_cast<char*>(ctx.get_reg(dst)) + imm;
        *reinterpret_cast<uint64_t*>(_target) = ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint32_t*>(addr) = (uint32_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16_D2: {
        uintptr_t _ptr = static_cast<uintptr_t>(ctx.get_reg(dst)) + static_cast<uintptr_t>(imm);
        uint16_t _v16 = (uint16_t)ctx.get_reg(src);
        std::memcpy(reinterpret_cast<void*>(_ptr), &_v16, sizeof(uint16_t));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM_D2: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = asgard_resolve_sym_idx((int32_t)sym_idx);
        ctx.set_reg(dst, (uint64_t)sym_ptr);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD_D2: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_a + _b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD_D2: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(std::bit_cast<double>(_s) - std::bit_cast<double>(_i)), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD_D2: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a * b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD_D2: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _b = std::bit_cast<double>(ctx.get_vreg_lane(static_cast<uint8_t>(imm), 0));
        double _q = (_b == 0.0) ? ((_a == 0.0) ? NAN : (std::signbit(_a) ^ std::signbit(_b) ? -INFINITY : INFINITY)) : (_a / _b);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_q), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSQRT_D_D2: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        double _root = (_a < 0.0) ? NAN : std::sqrt(_a);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_root), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD_D2: {
        uint64_t _s = ctx.get_vreg_lane(src, 0), _i = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(_s), b = std::bit_cast<double>(_i);
        bool _eq = (a == b), _ge = (a >= b), _lt = (a < b);
        ctx.zf = _eq; ctx.cf = _ge; ctx.sf = _lt; ctx.of = false;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS_D2: {
        double _a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        int64_t _s64 = static_cast<int64_t>(_a);
        ctx.set_reg(dst, static_cast<uint64_t>(_s64));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF_D2: {
        int64_t _s = static_cast<int64_t>(ctx.get_reg(src));
        double _d = static_cast<double>(_s);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(_d), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZU_D2: {
        double a = std::bit_cast<double>(ctx.get_vreg_lane(src, 0));
        if (a < 0.0) ctx.set_reg(dst, 0ULL); else ctx.set_reg(dst, (uint64_t)a);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_UCVTF_D2: {
        uint64_t v = ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVT_D2: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        float f32 = std::bit_cast<float>((uint32_t)a_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)f32), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD_D2: {
        uint64_t _addr = ctx.get_reg(src) + (uint64_t)imm;
        std::atomic_thread_fence(std::memory_order_seq_cst);
        uint64_t _loaded = *reinterpret_cast<volatile uint64_t*>(_addr);
        std::atomic_thread_fence(std::memory_order_seq_cst);
        ctx.set_reg(dst, _loaded);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        ptr->store(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS_D2: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t expected = ctx.get_reg(src);
        uint64_t desired = ctx.get_reg(REG_RAX);
        ptr->compare_exchange_strong(expected, desired, std::memory_order_seq_cst);
        ctx.set_reg(src, expected);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD_D2: {
        uint64_t _addr = ctx.get_reg(dst) + static_cast<uint64_t>(imm);
        uint64_t _old = __atomic_fetch_add(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
        ctx.set_reg(src, _old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP_D2: {
        uint64_t* ptr = reinterpret_cast<uint64_t*>(ctx.get_reg(dst) + (uint64_t)imm);
        uint64_t old = __atomic_load_n(ptr, __ATOMIC_RELAXED);
        uint64_t new_val = ctx.get_reg(src);
        while (!__atomic_compare_exchange_n(ptr, &old, new_val, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {}
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FENCE_D2: { std::atomic_thread_fence(std::memory_order_seq_cst); ctx.executed_instructions++; FETCH_NEXT(); }
    H_MOV_VR_D2: {
        uint64_t _val = ctx.get_reg(src);
        uint64_t _buf[1];
        std::memcpy(_buf, (&_val), sizeof(uint64_t));
        ctx.set_vreg_lane(dst, 0, _buf[0]);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_MOV_RV_D2: {
        uint64_t _val = (ctx.get_vreg_lane(src, 0) ^ 0x5a5a5a5aa5a5a5a5ULL);
        ctx.set_reg(dst, (_val ^ 0x5a5a5a5aa5a5a5a5ULL));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FCSEL_VV_D2: {
        if (eval_condition(ctx, static_cast<uint8_t>((((word >> 18) + 0x0FULL) - ((word >> 18) | 0x0FULL))))) {
            uint64_t _v = ctx.get_vreg_lane(src, 0);
            ctx.set_vreg_lane(dst, 0, _v);
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }



                                    EXIT_VM:
                                        for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&work_bc[i], 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i));
    }
                                        if (scrub_source && bytecode) {
        for (size_t i = 0; i < count; ++i) {
            SCRUB_WORD(&const_cast<uint64_t*>(bytecode)[i], 0xDEADBEEFCAFEBABEULL ^ ((uint64_t)seed + (uint64_t)i));
        }
    }
                                    if (heap_work_bc != nullptr) {
                                                                    free(heap_work_bc);
                                    }
                                    
                                    #undef DISPATCH_OPCODE
                                    
                                    
                                    #undef FETCH_NEXT
                                    
                                    return (!ctx.trapped);
                                }
                                
                                static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, bool scrub_source) {
                                
                                    return execute_threaded(ctx, bytecode, count, asgard_wbox_derive_seed(), scrub_source);
                                }
                                
                                static inline __attribute__((noinline)) uint64_t asgard_vm_call(const uint64_t* bc, size_t len, uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0, uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
                                
                                    vanguard_threaded_vm::VMContext ctx = {};
                                    ctx.init(asgard_wbox_derive_seed());
                                    alignas(16) static thread_local uint8_t host_stack[1048576];
                                    ctx.set_reg(vanguard_threaded_vm::REG_RSP, ((uint64_t)(((host_stack + sizeof(host_stack)) - 0x0000000000002000ULL))));
                                    ctx.set_reg(vanguard_threaded_vm::REG_RBP, ((uint64_t)(((host_stack + sizeof(host_stack)) - 0x0000000000002000ULL))));
                                    #if defined(__x86_64__) || defined(_M_X64)
    // System V / Windows x64 ABI argument registers
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a4);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a5);
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
#elif defined(__riscv) || defined(__riscv__)
    // RISC-V LP64 ABI argument mapping (a0->RAX, a1->RDX, a2->RCX, a3->RSI, a4->RDI, a5->R8, a6->R9, a7->R12)
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R12, a7);
#else
    // ARM64 calling convention mapping (x0->RAX, x1->RCX, x2->RDX, x3->RBX, x4->RSI, x5->RDI, x6->R8, x7->R9)
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RBX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a7);
#endif
                                    vanguard_threaded_vm::execute_threaded(ctx, bc, len, false);
                                    uint64_t ret_val = ctx.get_rax();
                                    if (__builtin_expect(ctx.trapped || ctx.canary_head != vanguard_threaded_vm::VMContext::CANARY_VAL || ctx.canary_tail != vanguard_threaded_vm::VMContext::CANARY_VAL, 0)) {
        ret_val ^= 0xDEADBEEF5A5A5A5AULL ^ ctx.reg_mask;
    }
                                    return (((ret_val ^ 0x5877cafe1337beefULL) + (0x0000000000000002ULL * (ret_val & 0x5877cafe1337beefULL))) - 0x5877cafe1337beefULL);
                                }

} // namespace vanguard_threaded_vm

