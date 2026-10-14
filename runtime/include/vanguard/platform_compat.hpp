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
