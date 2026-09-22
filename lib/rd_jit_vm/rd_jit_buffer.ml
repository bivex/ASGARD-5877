let header () =
  {|#pragma once
// =========================================================================
// ASGARD-5877: REGISTER-DRIVEN JUST-IN-TIME (RD JIT) VIRTUAL MACHINE
// Dual-Mapping W^X Memory Manager & Ephemeral Native Code Synthesis
// =========================================================================
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <iostream>
#include <vector>

#include <sys/mman.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#elif defined(__linux__)
#include <fcntl.h>
#endif

namespace asgard_rd_jit {

// RNS-4 Moduli Definition (Pairwise coprime, Product > 2^64)
static const uint64_t RNS_M1 = 4294967291ULL;
static const uint64_t RNS_M2 = 4294967279ULL;
static const uint64_t RNS_M3 = 4294967231ULL;
static const uint64_t RNS_M4 = 4294967197ULL;

struct RNS_Register {
    uint64_t r1, r2, r3, r4;
    
    inline void set(uint64_t val) {
        r1 = val % RNS_M1;
        r2 = val % RNS_M2;
        r3 = val % RNS_M3;
        r4 = val % RNS_M4;
    }
    
    inline void add(const RNS_Register& o) {
        r1 = (r1 + o.r1) % RNS_M1;
        r2 = (r2 + o.r2) % RNS_M2;
        r3 = (r3 + o.r3) % RNS_M3;
        r4 = (r4 + o.r4) % RNS_M4;
    }
    
    inline void sub(const RNS_Register& o) {
        r1 = (r1 + RNS_M1 - (o.r1 % RNS_M1)) % RNS_M1;
        r2 = (r2 + RNS_M2 - (o.r2 % RNS_M2)) % RNS_M2;
        r3 = (r3 + RNS_M3 - (o.r3 % RNS_M3)) % RNS_M3;
        r4 = (r4 + RNS_M4 - (o.r4 % RNS_M4)) % RNS_M4;
    }
    
    inline void mul(const RNS_Register& o) {
        r1 = (uint64_t)((__uint128_t)r1 * o.r1 % RNS_M1);
        r2 = (uint64_t)((__uint128_t)r2 * o.r2 % RNS_M2);
        r3 = (uint64_t)((__uint128_t)r3 * o.r3 % RNS_M3);
        r4 = (uint64_t)((__uint128_t)r4 * o.r4 % RNS_M4);
    }
    
    inline uint64_t decode_crt() const {
        return r1;
    }
};

struct RD_JIT_Context {
    uint64_t gprs[16];
    RNS_Register vregs[16];
    uint64_t rip;
    uint64_t flags;
    uint64_t trace_digest;
    
    inline void init() {
        memset(this, 0, sizeof(*this));
        trace_digest = 0x13375877AABBCCDDULL;
    }

    inline void set_reg(size_t idx, uint64_t val) {
        if (idx < 16) {
            gprs[idx] = val;
            vregs[idx].set(val);
        }
    }

    inline uint64_t get_reg(size_t idx) const {
        if (idx < 16) return gprs[idx];
        return 0;
    }

    inline void set_rdi(uint64_t val) { set_reg(0, val); }
    inline uint64_t get_rax() const { return get_reg(0); }
};

// Dual-Mapping W^X JIT Memory Manager
class DualMappedJITBuffer {
private:
    void* rw_buf;
    const void* rx_buf;
    size_t capacity;
    bool uses_mach_remap;

public:
    DualMappedJITBuffer(size_t sz = 4096) : capacity(sz), rw_buf(nullptr), rx_buf(nullptr), uses_mach_remap(false) {
        size_t page_sz = 4096;
        capacity = (sz + page_sz - 1) & ~(page_sz - 1);
#if defined(__APPLE__)
        vm_address_t rw_addr = 0;
        if (vm_allocate(mach_task_self(), &rw_addr, capacity, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (vm_remap(mach_task_self(), &rx_addr, capacity, 0, VM_FLAGS_ANYWHERE,
                         mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                vm_protect(mach_task_self(), rx_addr, capacity, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
                rw_buf = (void*)rw_addr;
                rx_buf = (const void*)rx_addr;
                uses_mach_remap = true;
                return;
            }
            vm_deallocate(mach_task_self(), rw_addr, capacity);
        }
#if defined(MAP_JIT)
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
        rx_buf = rw_buf;
#else
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        rx_buf = rw_buf;
#endif
#elif defined(__linux__) && defined(MFD_CLOEXEC)
        int fd = memfd_create("asgard_rd_jit_wx", MFD_CLOEXEC);
        if (fd >= 0) {
            if (ftruncate(fd, capacity) == 0) {
                rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                rx_buf = mmap(NULL, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
                close(fd);
                if (rw_buf != MAP_FAILED && rx_buf != MAP_FAILED) return;
            }
            close(fd);
        }
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        rx_buf = rw_buf;
#else
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        rx_buf = rw_buf;
#endif
    }

    ~DualMappedJITBuffer() {
#if defined(__APPLE__)
        if (uses_mach_remap) {
            if (rw_buf) vm_deallocate(mach_task_self(), (vm_address_t)rw_buf, capacity);
            if (rx_buf) vm_deallocate(mach_task_self(), (vm_address_t)rx_buf, capacity);
            return;
        }
#endif
        if (rw_buf && rw_buf != MAP_FAILED) munmap(rw_buf, capacity);
        if (rx_buf && rx_buf != rw_buf && rx_buf != MAP_FAILED) munmap((void*)rx_buf, capacity);
    }

    inline void* get_write_ptr() { return rw_buf; }
    inline const void* get_exec_ptr() { return rx_buf ? rx_buf : rw_buf; }

    inline void begin_synthesis() {
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(0);
            }
#endif
            mprotect(rw_buf, capacity, PROT_READ | PROT_WRITE);
        }
    }

    inline void commit_and_flush(size_t bytes_written) {
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(1);
            }
#endif
            mprotect(rw_buf, capacity, PROT_READ | PROT_EXEC);
        }
#if defined(__APPLE__)
        if (rw_buf && bytes_written > 0) sys_dcache_flush(rw_buf, bytes_written);
        if (rx_buf && bytes_written > 0) sys_icache_invalidate((void*)rx_buf, bytes_written);
#else
        if (rw_buf && bytes_written > 0) __builtin___clear_cache((char*)rw_buf, (char*)rw_buf + bytes_written);
#endif
    }

    inline void atomic_zeroize(size_t bytes) {
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(0);
            }
#endif
            mprotect(rw_buf, capacity, PROT_READ | PROT_WRITE);
        }
        if (rw_buf && bytes > 0) {
            volatile uint8_t* p = (volatile uint8_t*)rw_buf;
            for (size_t i = 0; i < bytes; ++i) p[i] = 0;
        }
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(1);
            }
#endif
        }
    }
};
|}
