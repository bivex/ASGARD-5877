let platform_compat_header = {|#pragma once
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

#if !defined(__cpp_lib_bit_cast)
namespace std {
    template <class To, class From>
    typename std::enable_if<sizeof(To) == sizeof(From) && std::is_trivially_copyable<From>::value && std::is_trivially_copyable<To>::value, To>::type
    bit_cast(const From& src) noexcept {
        To dst;
        std::memcpy(&dst, &src, sizeof(To));
        return dst;
    }
}
#endif

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
|}

let crypto_primitives_header = {|#pragma once
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
|}

let sanitization_header = {|#pragma once
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
|}

