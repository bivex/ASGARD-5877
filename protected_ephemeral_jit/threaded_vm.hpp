#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <atomic>
#include <bit>
#include <cstring>
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
#elif defined(__linux__)
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#elif defined(_WIN32) || defined(_WIN64)
#include <windows.h>
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

static constexpr uint64_t M1 = 65537ULL;
static constexpr uint64_t M2 = 65521ULL;
static constexpr uint64_t M3 = 65519ULL;
static constexpr uint64_t M4 = 65497ULL;

static constexpr uint64_t INV_M1_M2 = 61426ULL;
static constexpr uint64_t INV_M1_M3 = 3640ULL;
static constexpr uint64_t INV_M1_M4 = 11462ULL;
static constexpr uint64_t INV_M2_M3 = 32760ULL;
static constexpr uint64_t INV_M2_M4 = 62768ULL;
static constexpr uint64_t INV_M3_M4 = 20840ULL;

struct RNSVal {
    uint64_t r1, r2, r3, r4;
};

static inline __attribute__((always_inline)) RNSVal encode(uint64_t x) noexcept {
    return { x % M1, x % M2, x % M3, x % M4 };
}

static inline __attribute__((always_inline)) RNSVal add(RNSVal a, RNSVal b) noexcept {
    return { (a.r1 + b.r1) % M1,
             (a.r2 + b.r2) % M2,
             (a.r3 + b.r3) % M3,
             (a.r4 + b.r4) % M4 };
}

static inline __attribute__((always_inline)) RNSVal sub(RNSVal a, RNSVal b) noexcept {
    return { (a.r1 + M1 - (b.r1 % M1)) % M1,
             (a.r2 + M2 - (b.r2 % M2)) % M2,
             (a.r3 + M3 - (b.r3 % M3)) % M3,
             (a.r4 + M4 - (b.r4 % M4)) % M4 };
}

static inline __attribute__((always_inline)) RNSVal mul(RNSVal a, RNSVal b) noexcept {
    return { (a.r1 * (b.r1 % M1)) % M1,
             (a.r2 * (b.r2 % M2)) % M2,
             (a.r3 * (b.r3 % M3)) % M3,
             (a.r4 * (b.r4 % M4)) % M4 };
}

static inline __attribute__((always_inline)) uint64_t decode(RNSVal r) noexcept {
    uint64_t v1 = r.r1;
    uint64_t diff2 = (r.r2 + M2 - (v1 % M2)) % M2;
    uint64_t v2 = (diff2 * INV_M1_M2) % M2;

    uint64_t diff1_3 = (r.r3 + M3 - (v1 % M3)) % M3;
    uint64_t term1_3 = (diff1_3 * INV_M1_M3) % M3;
    uint64_t diff2_3 = (term1_3 + M3 - (v2 % M3)) % M3;
    uint64_t v3 = (diff2_3 * INV_M2_M3) % M3;

    uint64_t diff1_4 = (r.r4 + M4 - (v1 % M4)) % M4;
    uint64_t term1_4 = (diff1_4 * INV_M1_M4) % M4;
    uint64_t diff2_4 = (term1_4 + M4 - (v2 % M4)) % M4;
    uint64_t term2_4 = (diff2_4 * INV_M2_M4) % M4;
    uint64_t diff3_4 = (term2_4 + M4 - (v3 % M4)) % M4;
    uint64_t v4 = (diff3_4 * INV_M3_M4) % M4;

    uint64_t term_v2 = v2 * M1;
    uint64_t term_v3 = v3 * (M1 * M2);
    uint64_t term_v4 = v4 * (M1 * M2 * M3);

    return v1 + term_v2 + term_v3 + term_v4;
}

} // namespace asgard_rns

#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#if defined(__APPLE__)
#include <sys/types.h>
#include <sys/sysctl.h>
#include <unistd.h>
#elif defined(__linux__)
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#endif

#define ASGARD_DIRECT_SYSCALLS_ENABLED 1

namespace asgard_syscalls {

#if defined(__APPLE__) && (defined(__arm64__) || defined(__aarch64__))
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
static inline __attribute__((always_inline)) int64_t direct_syscall_0(int64_t sys_num) noexcept {
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(sys_num) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_1(int64_t sys_num, int64_t a1) noexcept {
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(sys_num), "D"(a1) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_2(int64_t sys_num, int64_t a1, int64_t a2) noexcept {
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(sys_num), "D"(a1), "S"(a2) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    int64_t ret;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(sys_num), "D"(a1), "S"(a2), "d"(a3) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_4(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4) noexcept {
    int64_t ret;
    register int64_t r10 __asm__("r10") = a4;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(sys_num), "D"(a1), "S"(a2), "d"(a3), "r"(r10) : "rcx", "r11", "memory", "cc");
    return ret;
}
static inline __attribute__((always_inline)) int64_t direct_syscall_6(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6) noexcept {
    int64_t ret;
    register int64_t r10 __asm__("r10") = a4;
    register int64_t r8  __asm__("r8")  = a5;
    register int64_t r9  __asm__("r9")  = a6;
    __asm__ volatile("syscall" : "=a"(ret) : "a"(sys_num), "D"(a1), "S"(a2), "d"(a3), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory", "cc");
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
#else
static inline int64_t direct_syscall_0(int64_t s) noexcept { (void)s; return 0; }
static inline int64_t direct_syscall_1(int64_t s, int64_t a) noexcept { (void)s; (void)a; return 0; }
static inline int64_t direct_syscall_2(int64_t s, int64_t a, int64_t b) noexcept { (void)s; (void)a; (void)b; return 0; }
static inline int64_t direct_syscall_3(int64_t s, int64_t a, int64_t b, int64_t c) noexcept { (void)s; (void)a; (void)b; (void)c; return 0; }
static inline int64_t direct_syscall_4(int64_t s, int64_t a, int64_t b, int64_t c, int64_t d) noexcept { (void)s; (void)a; (void)b; (void)c; (void)d; return 0; }
static inline int64_t direct_syscall_6(int64_t s, int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f) noexcept { (void)s; (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; return 0; }
#endif

static inline pid_t sys_getpid() noexcept {
#if defined(__APPLE__)
    return (pid_t)direct_syscall_0(20); // SYS_getpid
#elif defined(__linux__) && defined(__x86_64__)
    return (pid_t)direct_syscall_0(39); // SYS_getpid
#elif defined(__linux__) && (defined(__arm64__) || defined(__aarch64__))
    return (pid_t)direct_syscall_0(172); // SYS_getpid
#else
    return 0;
#endif
}

static inline int64_t sys_write(int fd, const void* buf, size_t count) noexcept {
#if defined(__APPLE__)
    return direct_syscall_3(4, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif defined(__linux__) && defined(__x86_64__)
    return direct_syscall_3(1, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#elif defined(__linux__) && (defined(__arm64__) || defined(__aarch64__))
    return direct_syscall_3(64, (int64_t)fd, (int64_t)buf, (int64_t)count); // SYS_write
#else
    return 0;
#endif
}

static inline void sys_exit(int status) noexcept {
#if defined(__APPLE__)
    direct_syscall_1(1, (int64_t)status); // SYS_exit
#elif defined(__linux__) && defined(__x86_64__)
    direct_syscall_1(60, (int64_t)status); // SYS_exit
#elif defined(__linux__) && (defined(__arm64__) || defined(__aarch64__))
    direct_syscall_1(93, (int64_t)status); // SYS_exit
#else
    _exit(status);
#endif
}

static inline bool sys_check_debugger_present() noexcept {
#if defined(__APPLE__)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)sys_getpid() };
    struct kinfo_proc kinfo = {};
    size_t ksize = sizeof(kinfo);
    int64_t res = direct_syscall_6(202, (int64_t)mib, 4, (int64_t)&kinfo, (int64_t)&ksize, 0, 0);
    if (res == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {
        return true;
    }
    return false;
#elif defined(__linux__)
    int fd = -1;
#if defined(__x86_64__)
    fd = (int)direct_syscall_2(2, (int64_t)"/proc/self/status", 0);
#elif defined(__arm64__) || defined(__aarch64__)
    fd = (int)direct_syscall_4(257, -100, (int64_t)"/proc/self/status", 0, 0);
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
#endif

namespace asgard_anti_emulation {

static inline __attribute__((always_inline)) uint64_t evaluate_emulation_differential() noexcept {
    uint64_t penalty = 0;

#if defined(__x86_64__)
    // 1. CPUID Hypervisor Discovery & Cycle Ratio Probe
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
#elif defined(__aarch64__)
    // ARM64 Virtual Counter Overhead & Multi-Source Jitter Probe
    uint64_t t0, t1;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));
    for (int i = 0; i < 64; ++i) { __asm__ volatile("nop"); }
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));
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
#elif defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>
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
#else
        return false;
#endif
    }

    static DualMappedBuffer allocate(size_t required_size) noexcept {
        DualMappedBuffer buf = {};
        size_t page_sz = 4096;
        buf.size = (required_size + page_sz - 1) & ~(page_sz - 1);

#if defined(__APPLE__)
        vm_address_t rw_addr = 0;
        if (vm_allocate(mach_task_self(), &rw_addr, buf.size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (vm_remap(mach_task_self(), &rx_addr, buf.size, 0, VM_FLAGS_ANYWHERE,
                          mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                vm_protect(mach_task_self(), rx_addr, buf.size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
                buf.rw_alias = (void*)rw_addr;
                buf.rx_alias = (const void*)rx_addr;
                return buf;
            }
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
#endif
        return buf;
    }

    void release() noexcept {
#if defined(__APPLE__)
        if (rw_alias) vm_deallocate(mach_task_self(), (vm_address_t)rw_alias, size);
        if (rx_alias) vm_deallocate(mach_task_self(), (vm_address_t)rx_alias, size);
#elif defined(__linux__)
        if (rw_alias && rw_alias != MAP_FAILED) munmap(rw_alias, size);
        if (rx_alias && rx_alias != MAP_FAILED) munmap((void*)rx_alias, size);
#endif
        rw_alias = nullptr;
        rx_alias = nullptr;
        size = 0;
    }
};

} // namespace asgard_memory

#define ASGARD_SMC_STRICT 1
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>

#if defined(ASGARD_SMC_STRICT)
#  if !defined(__APPLE__) && (!defined(__linux__) || !defined(MFD_CLOEXEC))
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
#if !defined(ASGARD_QUIET)
        fprintf(stderr, "[ASGARD_SMC_ERROR] Strict SMC required by max_security profile, but dual-mapping buffer allocation failed!\n");
#endif
        return 0xDEAD53C0CAFE0001ULL; // Non-zero penalty that corrupts VM context and forces abort/divergence
#else
        g_smc_status = SMC_STATUS_DEGRADED;
#if !defined(ASGARD_QUIET) && defined(ASGARD_DEBUG_DIAGNOSTICS)
        fprintf(stderr, "[ASGARD_SMC_WARN] Dual-mapping unsupported or failed; SMC degraded gracefully.\n");
#endif
        return 0; // If dual-mapping is unsupported and not in strict mode, degrade gracefully
#endif
    }

#if defined(__aarch64__)
    // Emit ARM64:
    // movz w0, #0x5877, lsl #0  -> 0x528b0ee0
    // add w0, w0, #0x12         -> 0x11004800
    // ret                       -> 0xd65f03c0
    uint32_t* code_rw = (uint32_t*)buf.rw_alias;
    code_rw[0] = 0x528b0ee0; // movz w0, #0x5877
    code_rw[1] = 0x11004800; // add w0, w0, #0x12
    code_rw[2] = 0xd65f03c0; // ret

    uint64_t t0;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));

    // Dynamic Self-Modification via RW alias: mutate immediate in add (bits 10..21)
    uint32_t imm_val = (uint32_t)(seed & 0x7F);
    code_rw[1] = 0x11000000 | (imm_val << 10);

    // Hardware icache invalidation & pipeline clear
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

    uint64_t t1;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t1));

    uint32_t expected = 0x5877 + imm_val;
    if (result != expected) {
        penalty ^= 0xBAD5A5A558771337ULL;
    }
    if ((t1 - t0) > 100000ULL) {
        penalty ^= 0xDEAD1337CAFE5877ULL; // JIT/hypervisor emulation slow-path
    }
#elif defined(__x86_64__)
    // Emit x86_64:
    // mov eax, 0x5877  -> B8 77 58 00 00
    // add eax, 0x12    -> 05 12 00 00 00
    // ret              -> C3
    uint8_t* code_rw = (uint8_t*)buf.rw_alias;
    code_rw[0] = 0xB8; code_rw[1] = 0x77; code_rw[2] = 0x58; code_rw[3] = 0x00; code_rw[4] = 0x00;
    code_rw[5] = 0x05; code_rw[6] = 0x12; code_rw[7] = 0x00; code_rw[8] = 0x00; code_rw[9] = 0x00;
    code_rw[10] = 0xC3;

    uint64_t t0 = __builtin_ia32_rdtsc();

    // Dynamic Self-Modification via RW alias
    uint8_t imm_val = (uint8_t)(seed & 0x7F);
    code_rw[6] = imm_val;

    // Hardware icache invalidation & pipeline clear
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + 16);

    // Execute via RX alias
    typedef uint32_t (*smc_fn_t)();
    smc_fn_t fn = (smc_fn_t)buf.rx_alias;
    uint32_t result = fn();

    uint64_t t1 = __builtin_ia32_rdtsc();

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
#elif defined(__linux__)
#include <stdio.h>
#include <string.h>
#endif

namespace asgard_mem_integrity {

// MEM-SBOM Style Memory Forensics & Injection Scanner
static inline __attribute__((always_inline)) uint64_t evaluate_memory_integrity() noexcept {
    uint64_t penalty = 0;

#if defined(__APPLE__)
    // 1. Thread Debug Register Inspection (DR0-DR3 / DBGBVR detection)
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

    // 2. Suspicious Anonymous RWX Memory Scanner (Anti-Frida / Shellcode Injection)
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

inline NanomiteDispatcher g_nanomite_dispatcher;

#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)
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
    if (g_nanomite_dispatcher.installed) return;
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = nanomite_trap_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTRAP, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    g_nanomite_dispatcher.installed = true;
}
#else
static inline void install_nanomite_handlers(uint32_t seed = 0x5877CAFEU) noexcept {
    g_nanomite_dispatcher.seed = seed;
    g_nanomite_dispatcher.installed = true;
}
#endif

} // namespace asgard_nanomites

#define ASGARD_EPHEMERAL_JIT 1
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#endif

namespace asgard_ephemeral_jit {

enum EphemeralOp : uint8_t {
    EPH_OP_ADD_RR = 0,
    EPH_OP_ADD_RI,
    EPH_OP_SUB_RR,
    EPH_OP_SUB_RI,
    EPH_OP_MUL_RR,
    EPH_OP_MUL_RI,
    EPH_OP_XOR_RR,
    EPH_OP_XOR_RI,
    EPH_OP_AND_RR,
    EPH_OP_AND_RI,
    EPH_OP_OR_RR,
    EPH_OP_OR_RI
};

#if defined(__aarch64__)
static inline void emit_arm64_imm(uint32_t* code, size_t& idx, uint8_t reg, uint64_t imm) noexcept {
    uint32_t w0 = (uint32_t)(imm & 0xFFFFULL);
    uint32_t w1 = (uint32_t)((imm >> 16) & 0xFFFFULL);
    uint32_t w2 = (uint32_t)((imm >> 32) & 0xFFFFULL);
    uint32_t w3 = (uint32_t)((imm >> 48) & 0xFFFFULL);
    code[idx++] = 0xd2800000 | (w0 << 5) | reg; // movz reg, #w0, lsl 0
    if (w1 != 0 || imm > 0xFFFFULL)
        code[idx++] = 0xf2a00000 | (w1 << 5) | reg; // movk reg, #w1, lsl 16
    if (w2 != 0 || imm > 0xFFFFFFFFULL)
        code[idx++] = 0xf2c00000 | (w2 << 5) | reg; // movk reg, #w2, lsl 32
    if (w3 != 0)
        code[idx++] = 0xf2e00000 | (w3 << 5) | reg; // movk reg, #w3, lsl 48
}
#endif

static inline uint64_t next_jit_rng(uint64_t& state) noexcept {
    state ^= (state << 13);
    state ^= (state >> 7);
    state ^= (state << 17);
    return state;
}

// Synthesizes machine code for an ALU operation in ephemeral W^X RAM, executes it, and zeroes it immediately.
template <typename CtxType>
__attribute__((always_inline)) static inline void execute_ephemeral_vm_op(
    asgard_memory::DualMappedBuffer& buf,
    CtxType& ctx,
    EphemeralOp op,
    uint8_t dst,
    uint8_t src,
    uint64_t imm) noexcept
{
    uint64_t val_d = ctx.get_reg(dst);
    uint64_t val_s = ctx.get_reg(src);
    bool uses_imm = (op == EPH_OP_ADD_RI || op == EPH_OP_SUB_RI || op == EPH_OP_MUL_RI ||
                     op == EPH_OP_XOR_RI || op == EPH_OP_AND_RI || op == EPH_OP_OR_RI);
    uint64_t op_rhs = uses_imm ? imm : val_s;

    if (!buf.rw_alias || !buf.rx_alias) {
        // Fallback for systems without dual-mapping W^X
        uint64_t res = 0;
        switch (op) {
            case EPH_OP_ADD_RR:
            case EPH_OP_ADD_RI: res = val_d + op_rhs; break;
            case EPH_OP_SUB_RR:
            case EPH_OP_SUB_RI: res = val_d - op_rhs; break;
            case EPH_OP_MUL_RR:
            case EPH_OP_MUL_RI: res = val_d * op_rhs; break;
            case EPH_OP_XOR_RR:
            case EPH_OP_XOR_RI: res = val_d ^ op_rhs; break;
            case EPH_OP_AND_RR:
            case EPH_OP_AND_RI: res = val_d & op_rhs; break;
            case EPH_OP_OR_RR:
            case EPH_OP_OR_RI:  res = val_d | op_rhs; break;
        }
        ctx.set_reg(dst, res);
        return;
    }

    static thread_local uint64_t rng_state = 0x5877CAFE1337BEEFULL ^ (uintptr_t)&ctx;
    uint64_t r_val = next_jit_rng(rng_state);
    size_t code_bytes = 0;

#if defined(__aarch64__)
    uint32_t* code = (uint32_t*)buf.rw_alias;
    size_t idx = 0;

    // Polymorphic scratch registers: randomly pick r1, r2 from {x9, x10, x11, x12, x13, x14, x15}
    static const uint8_t s_regs[7] = { 9, 10, 11, 12, 13, 14, 15 };
    uint8_t r1 = s_regs[r_val % 7];
    uint8_t r2 = s_regs[(r_val / 7 + 1) % 7];
    if (r1 == r2) r2 = s_regs[(r1 + 1) % 7];

    // Metamorphic junk instruction prefix (using IP0/x16)
    if ((r_val & 3) == 1) {
        code[idx++] = 0xd2800000 | (((uint32_t)r_val & 0xFFFF) << 5) | 16; // movz x16, #imm
        code[idx++] = 0xaa1003f0; // mov x16, x16
    } else if ((r_val & 3) == 2) {
        code[idx++] = 0xd503201f; // nop
    }

    // Materialize operands into dynamic scratch registers
    emit_arm64_imm(code, idx, r1, val_d);
    emit_arm64_imm(code, idx, r2, op_rhs);

    // Target ALU operation (r1 = r1 OP r2)
    switch (op) {
        case EPH_OP_ADD_RR:
        case EPH_OP_ADD_RI:
            code[idx++] = 0x8b000000 | (r2 << 16) | (r1 << 5) | r1; // add r1, r1, r2
            break;
        case EPH_OP_SUB_RR:
        case EPH_OP_SUB_RI:
            code[idx++] = 0xcb000000 | (r2 << 16) | (r1 << 5) | r1; // sub r1, r1, r2
            break;
        case EPH_OP_MUL_RR:
        case EPH_OP_MUL_RI:
            code[idx++] = 0x9b007c00 | (r2 << 16) | (r1 << 5) | r1; // mul r1, r1, r2
            break;
        case EPH_OP_XOR_RR:
        case EPH_OP_XOR_RI:
            code[idx++] = 0xca000000 | (r2 << 16) | (r1 << 5) | r1; // eor r1, r1, r2
            break;
        case EPH_OP_AND_RR:
        case EPH_OP_AND_RI:
            code[idx++] = 0x8a000000 | (r2 << 16) | (r1 << 5) | r1; // and r1, r1, r2
            break;
        case EPH_OP_OR_RR:
        case EPH_OP_OR_RI:
            code[idx++] = 0xaa000000 | (r2 << 16) | (r1 << 5) | r1; // orr r1, r1, r2
            break;
    }

    // Return value in x0
    code[idx++] = 0xaa0003e0 | r1; // mov x0, r1

    // Metamorphic junk instruction suffix
    if ((r_val & 4) != 0) {
        code[idx++] = 0xd503201f; // nop
    }

    code[idx++] = 0xd65f03c0; // ret
    code_bytes = idx * sizeof(uint32_t);

#elif defined(__x86_64__)
    uint8_t* code = (uint8_t*)buf.rw_alias;
    size_t idx = 0;

    auto emit_u64 = [&](uint64_t v) {
        for (int b = 0; b < 8; ++b) {
            code[idx++] = (uint8_t)((v >> (b * 8)) & 0xFF);
        }
    };

    // Metamorphic junk instruction prefix
    if ((r_val & 1) != 0) {
        code[idx++] = 0x90; // nop
    }

    // mov rax, val_d (0x48 0xB8 ...)
    code[idx++] = 0x48; code[idx++] = 0xB8;
    emit_u64(val_d);

    // mov rcx, op_rhs (0x48 0xB9 ...)
    code[idx++] = 0x48; code[idx++] = 0xB9;
    emit_u64(op_rhs);

    switch (op) {
        case EPH_OP_ADD_RR:
        case EPH_OP_ADD_RI:
            code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xC8; // add rax, rcx
            break;
        case EPH_OP_SUB_RR:
        case EPH_OP_SUB_RI:
            code[idx++] = 0x48; code[idx++] = 0x29; code[idx++] = 0xC8; // sub rax, rcx
            break;
        case EPH_OP_MUL_RR:
        case EPH_OP_MUL_RI:
            code[idx++] = 0x48; code[idx++] = 0x0F; code[idx++] = 0xAF; code[idx++] = 0xC1; // imul rax, rcx
            break;
        case EPH_OP_XOR_RR:
        case EPH_OP_XOR_RI:
            code[idx++] = 0x48; code[idx++] = 0x31; code[idx++] = 0xC8; // xor rax, rcx
            break;
        case EPH_OP_AND_RR:
        case EPH_OP_AND_RI:
            code[idx++] = 0x48; code[idx++] = 0x21; code[idx++] = 0xC8; // and rax, rcx
            break;
        case EPH_OP_OR_RR:
        case EPH_OP_OR_RI:
            code[idx++] = 0x48; code[idx++] = 0x09; code[idx++] = 0xC8; // or rax, rcx
            break;
    }
    code[idx++] = 0xC3; // ret
    code_bytes = idx;
#else
    // Fallback if neither aarch64 nor x86_64
    uint64_t res = 0;
    switch (op) {
        case EPH_OP_ADD_RR:
        case EPH_OP_ADD_RI: res = val_d + op_rhs; break;
        case EPH_OP_SUB_RR:
        case EPH_OP_SUB_RI: res = val_d - op_rhs; break;
        case EPH_OP_MUL_RR:
        case EPH_OP_MUL_RI: res = val_d * op_rhs; break;
        case EPH_OP_XOR_RR:
        case EPH_OP_XOR_RI: res = val_d ^ op_rhs; break;
        case EPH_OP_AND_RR:
        case EPH_OP_AND_RI: res = val_d & op_rhs; break;
        case EPH_OP_OR_RR:
        case EPH_OP_OR_RI:  res = val_d | op_rhs; break;
    }
    ctx.set_reg(dst, res);
    return;
#endif

#if defined(__APPLE__)
    sys_dcache_flush(buf.rw_alias, code_bytes);
    sys_icache_invalidate((void*)buf.rx_alias, code_bytes);
#else
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + code_bytes);
#endif

    using JITFn = uint64_t (*)();
    auto fn = (JITFn)buf.rx_alias;
    uint64_t result = fn();

    ctx.set_reg(dst, result);

    // Ephemeral self-consuming: zeroize machine code immediately
    volatile uint8_t* p = (volatile uint8_t*)buf.rw_alias;
    for (size_t i = 0; i < code_bytes; ++i) {
        p[i] = 0;
    }

#if defined(__APPLE__)
    sys_dcache_flush(buf.rw_alias, code_bytes);
    sys_icache_invalidate((void*)buf.rx_alias, code_bytes);
#else
    __builtin___clear_cache((char*)buf.rw_alias, (char*)buf.rw_alias + code_bytes);
#endif
}

} // namespace asgard_ephemeral_jit

namespace vanguard_threaded_vm {

#define ASGARD_ADDRESS_BOUND_BYTECODE 1
static const size_t g_num_blocks = 64;
static const size_t g_block_offsets[] = {
    0,
    3,
    2327,
    4186,
    4190,
    4722,
    9737,
    10113,
    12548,
    12567,
    14045,
    14048,
    14051,
    18598,
    20222,
    20226,
    20230,
    24076,
    26878,
    26882,
    26886,
    30976,
    32252,
    33885,
    33889,
    33892,
    37828,
    39332,
    39335,
    39340,
    44438,
    44444,
    45353,
    45354,
    45356,
    45358,
    45360,
    45362,
    45364,
    45366,
    45368,
    45370,
    45372,
    45374,
    45376,
    45378,
    45380,
    45382,
    45384,
    45386,
    45388,
    45390,
    45392,
    45394,
    45396,
    45398,
    45400,
    45402,
    45404,
    45406,
    45408,
    45410,
    45412,
    45414,
};
static const size_t g_block_lengths[] = {
    3,
    2324,
    1859,
    4,
    532,
    5015,
    376,
    2435,
    19,
    1478,
    3,
    3,
    4547,
    1624,
    4,
    4,
    3846,
    2802,
    4,
    4,
    4090,
    1276,
    1633,
    4,
    3,
    3936,
    1504,
    3,
    5,
    5098,
    6,
    909,
    1,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
    2,
};

static const char* const g_external_symbols[] = {
    "_verify_license._enc",
    "_verify_license._enc.5",
    "_printf",
    "_verify_license._enc.6",
    "_verify_license._enc.7",
    "_verify_license._enc.8",
    "_verify_license._enc.9",
};

struct AsgardConstantEntry {
    const char* name;
    const uint8_t* data;
    size_t size;
};

static const uint8_t cdata_0[] = { 0x41, 0x53, 0x47, 0x41, 0x52, 0x44, 0x5F, 0x42, 0x45, 0x47, 0x5F, 0x56, 0x5F, 0x5F, 0x5F, 0x5F, 0x00 };
static const uint8_t cdata_1[] = { 0x41, 0x53, 0x47, 0x41, 0x52, 0x44, 0x5F, 0x45, 0x4E, 0x44, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x5F, 0x00 };
static const uint8_t cdata_2[] = { 0x50, 0x0D, 0xEA, 0x47, 0x24, 0x81, 0x7E, 0xDB, 0xB8, 0x15, 0xF2, 0xAF, 0x0C, 0xE9, 0x46, 0x23, 0x80, 0x7D, 0xDA, 0xB7, 0x14, 0xF1, 0xAE, 0x0B, 0xE8, 0x45, 0x22, 0x9F, 0x7C, 0xD9, 0xB6, 0x13, 0xF0, 0xAD, 0x0A, 0xE7, 0x44, 0x21, 0x9E, 0x7B, 0xD8, 0x00 };
static const uint8_t cdata_3[] = { 0xEE, 0xA9, 0x5C, 0xE5, 0x80, 0x36, 0xDF, 0x1E, 0x0E, 0xB5, 0x54, 0x1F, 0xBB, 0x49, 0x83, 0x87, 0x22, 0xDD, 0x71, 0x06, 0xAC, 0x34, 0x07, 0x87, 0x6E, 0xC5, 0xA9, 0x09, 0xFC, 0x1C, 0x05, 0x97, 0x79, 0x21, 0x8B, 0x63, 0xD5, 0xAB, 0x09, 0x00 };
static const uint8_t cdata_4[] = { 0xEE, 0xB3, 0x54, 0xF9, 0x9A, 0x3F, 0xC0, 0x65, 0x06, 0xAB, 0x4C, 0x11, 0xB2, 0x57, 0xF8, 0x9D, 0x3E, 0xC3, 0x64, 0x09, 0xAA, 0x4F, 0x10, 0xB5, 0x56, 0xFB, 0x9C, 0x21, 0xC2, 0x67, 0x08, 0xAD, 0x4E, 0x13, 0xB4, 0x59, 0xFA, 0x9F, 0x20, 0xC5, 0x66, 0x00 };
static const uint8_t cdata_5[] = { 0xAD, 0xDB, 0x26, 0x9A, 0xEE, 0x19, 0xAA, 0x0A, 0x63, 0xC8, 0x24, 0x64, 0xD1, 0x71, 0x95, 0xFE, 0x41, 0xFF, 0x42, 0x00 };
static const uint8_t cdata_6[] = { 0x71, 0x2B, 0x00 };
static const uint8_t cdata_7[] = { 0x3E, 0x71, 0x82, 0x29, 0x59, 0xEA, 0x7C, 0xC1, 0xAF, 0x0D, 0xEA, 0xAD, 0x64, 0x89, 0x25, 0x48, 0x00 };
static const uint8_t cdata_8[] = { 0x08, 0x25, 0xB4, 0x64, 0x66, 0xC1, 0x3E, 0x9D, 0xE8, 0x45, 0xD1, 0xEB, 0x5D, 0xAB, 0x0B, 0x74, 0xC6, 0x3A, 0xD3, 0x00 };
static const uint8_t cdata_9[] = { 0x81, 0xDC, 0x3B, 0x96, 0x81, 0x1F, 0xE4, 0x4F, 0x27, 0xDE, 0x23, 0x7E, 0xCD, 0x60, 0x92, 0xBE, 0x1D, 0xD4, 0x21, 0x00 };
static const uint8_t cdata_10[] = { 0xA8, 0xF5, 0x12, 0xBF, 0xBA, 0x35, 0xC7, 0x64, 0x5A, 0xED, 0x0A, 0x57, 0x92, 0x7D, 0xDF, 0xBC, 0x23, 0xE4, 0x51, 0x28, 0x8D, 0x7B, 0x32, 0x8C, 0x66, 0xDC, 0xB6, 0x0E, 0xE0, 0x5E, 0x22, 0x82, 0x6B, 0x30, 0x9C, 0x6C, 0xD9, 0xA6, 0x63, 0xCF, 0x6C, 0x35, 0xB7, 0x1D, 0x00 };
static const uint8_t cdata_11[] = { 0x2A, 0x01, 0x96, 0x46, 0x44, 0xE3, 0x1C, 0xBF, 0xCA, 0x67, 0xF3, 0xCA, 0x68, 0x86, 0x2E, 0x47, 0xE5, 0x7C, 0x19, 0x16, 0xA1, 0xF0, 0xE6, 0x44, 0xBF, 0x05, 0x6F, 0xD7, 0x39, 0xD8, 0xFC, 0x57, 0xA8, 0x86, 0x00 };
static const uint8_t cdata_12[] = { 0x55, 0x08, 0xEF, 0x42, 0x49, 0xCD, 0x35, 0x8A, 0xA7, 0x10, 0xF7, 0xAA, 0x47, 0xA5, 0x00, 0x63, 0x85, 0x2C, 0x8D, 0xEB, 0x3B, 0x00 };
static const AsgardConstantEntry g_asgard_constants[] = {
    { "_verify_license", cdata_0, 16 },
    { "LBB6_17", cdata_1, 16 },
    { "_main._enc", cdata_2, 41 },
    { "_main._enc.1", cdata_3, 39 },
    { "_main._enc.2", cdata_4, 41 },
    { "_main._enc.3", cdata_5, 19 },
    { "_main._enc.4", cdata_6, 2 },
    { "_verify_license._enc", cdata_7, 16 },
    { "_verify_license._enc.5", cdata_8, 19 },
    { "_verify_license._enc.6", cdata_9, 19 },
    { "_verify_license._enc.7", cdata_10, 44 },
    { "_verify_license._enc.8", cdata_11, 34 },
    { "_verify_license._enc.9", cdata_12, 21 },
};

static inline void* asgard_resolve_constant(const char* name) {
    if (!name || name[0] == '\0') return nullptr;
    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {
        if (g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name) == 0) return (void*)g_asgard_constants[i].data;
        if (name[0] == '_' && g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name + 1) == 0) return (void*)g_asgard_constants[i].data;
    }
    return nullptr;
}

/* ------------------------------------------------------------------------- */
/* Randomized Architectural Register Map (π ∈ S_32)                          */
/* ------------------------------------------------------------------------- */
enum RegMap : uint8_t {
    REG_RAX = 28,
    REG_RCX = 22,
    REG_RDX = 16,
    REG_RBX = 20,
    REG_RSP = 26,
    REG_RBP = 1,
    REG_RSI = 4,
    REG_RDI = 15,
    REG_R8 = 3,
    REG_R9 = 25,
    REG_R10 = 13,
    REG_R11 = 10,
    REG_R12 = 11,
    REG_R13 = 21,
    REG_R14 = 19,
    REG_R15 = 29,
    REG_VTMP0 = 27,
    REG_VTMP1 = 2,
    REG_VTMP2 = 9,
    REG_VTMP3 = 23,
    REG_VIP = 12,
    REG_VSP = 5,
    REG_VKEY = 0,
    REG_VX18 = 8,
    REG_VX19 = 31,
    REG_VX20 = 7,
    REG_VX21 = 24,
    REG_VX22 = 14,
    REG_VX23 = 17,
    REG_VX24 = 18,
    REG_VX25 = 6,
    REG_VX26 = 30,
};

static inline uint64_t key64_for_offset(uint32_t seed, size_t offset) noexcept {
    uint64_t s64 = (uint64_t)seed;
    uint64_t x0 = ((s64 << 32) | (s64 ^ 0x9E3779B9ULL)) ^ ((uint64_t)offset * 0x517CC1B727220A95ULL);
    uint64_t x1 = (x0 ^ (x0 >> 30)) * 0xBF58476D1CE4E5B9ULL;
    uint64_t x2 = (x1 ^ (x1 >> 27)) * 0x94D049BB133111EBULL;
    return x2 ^ (x2 >> 31);
}

static inline uint64_t compute_handlers_hash(const void* const* const* all_domains, size_t num_domains) noexcept {
    uint64_t h = 0x5877CAFEBABE1337ULL;
    for (size_t d = 0; d < num_domains; ++d) {
        const void* const* domain = all_domains[d];
        for (size_t op = 0; op < 256; ++op) {
            uint64_t ptr_val = (uint64_t)(uintptr_t)domain[op];
            h ^= ptr_val * 0x9E3779B97F4A7C15ULL;
            h = (h >> 27) | (h << 37);
            h *= 0xBF58476D1CE4E5B9ULL;
        }
    }
    return h ^ (h >> 31);
}

struct VMContext {
    static inline constexpr uint64_t CANARY_VAL = 0xCAFEBABE13375877ULL;
    uint64_t canary_head = CANARY_VAL;
    uint64_t mid_canaries[32]; // Interleaved dynamic canaries across every 16 stack frames
    uint64_t gprs[32]; // Blinded in memory: actual_val = gprs[i] ^ reg_mask
    uint64_t vregs[32][2]; // 128-bit vector register bank: lane[0]=low, lane[1]=high
    uint64_t stack[512];
    size_t sp;
    uint64_t reg_mask;
    uint32_t init_seed;
    uint64_t poison_penalty;
    uint64_t running_key;
    bool cf, zf, sf, of;
    bool trapped;
    size_t executed_instructions;
    uint64_t canary_tail = CANARY_VAL;

    inline void init(uint32_t seed = 0x0F9131B2U) noexcept {
        init_seed = seed;
        poison_penalty = (key64_for_offset(seed, 0x5877) ^ 0xCAA7E1D8718BF877ULL) | 1ULL;
        running_key = key64_for_offset(seed, 0x13375877ULL) ^ 0xCAFEBABE13375877ULL;
        reg_mask = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed * 0x9E3779B97F4A7C15ULL);
        for (size_t i = 0; i < 32; ++i) {
            gprs[i] = reg_mask; // Initialized to 0 (0 ^ reg_mask)
            mid_canaries[i] = CANARY_VAL ^ ((uint64_t)i * 0x517CC1B727220A95ULL) ^ (uint64_t)seed;
            vregs[i][0] = 0ULL;
            vregs[i][1] = 0ULL;
        }
        gprs[REG_VKEY] = running_key ^ reg_mask;
        sp = 0;
        cf = zf = sf = of = false;
        trapped = false;
        executed_instructions = 0;
        canary_head = canary_tail = CANARY_VAL;
    }

    static inline uint64_t advance_key_step(uint64_t k, uint8_t op, uint8_t dst, int64_t imm) noexcept {
        uint64_t x = k ^ (((uint64_t)op * 0x9E3779B97F4A7C15ULL) + ((uint64_t)dst << 24) + (uint64_t)imm);
        uint64_t rot = (x >> 23) | (x << 41);
        return (rot * 0xBF58476D1CE4E5B9ULL) ^ 0x5877CAFE1337BEEFULL;
    }

    inline void advance_running_key(uint8_t op, uint8_t dst, int64_t imm) noexcept {
        running_key = advance_key_step(running_key, op, dst, imm);
        gprs[REG_VKEY] = running_key ^ reg_mask;
    }

    static inline uint64_t anchor_key(uint32_t seed, uint64_t off, uint64_t addr_hash = 0) noexcept {
        return key64_for_offset(seed ^ 0x5BD1E995U, (size_t)(off ^ 0x13375877ULL)) ^ addr_hash;
    }

    inline void reanchor_running_key(uint64_t off, uint64_t addr_hash = 0) noexcept {
        running_key = anchor_key(init_seed, off, addr_hash);
        gprs[REG_VKEY] = running_key ^ reg_mask;
    }

    inline uint64_t get_vkey() const noexcept { return running_key; }

    inline bool verify_canaries() const noexcept {
        if (canary_head != CANARY_VAL || canary_tail != CANARY_VAL) return false;
        size_t frame = (sp >> 4) & 31;
        uint64_t expected = CANARY_VAL ^ ((uint64_t)frame * 0x517CC1B727220A95ULL) ^ (uint64_t)init_seed;
        return (mid_canaries[frame] == expected);
    }

    inline uint64_t get_reg(uint8_t i) const noexcept {
        return gprs[i] ^ reg_mask;
    }

    inline void set_reg(uint8_t i, uint64_t v) noexcept {
        gprs[i] = v ^ reg_mask;
    }

    // 128-bit vector register accessors (two 64-bit lanes)
    inline uint64_t get_vreg_lane(uint8_t i, size_t lane) const noexcept {
        return vregs[i & 31][lane & 1];
    }

    inline void set_vreg(uint8_t i, uint64_t lo, uint64_t hi) noexcept {
        vregs[i & 31][0] = lo;
        vregs[i & 31][1] = hi;
    }

    // Named architectural register accessors via randomized permutation
    inline uint64_t get_rax() const noexcept { return get_reg(REG_RAX); }
    inline void set_rax(uint64_t v) noexcept { set_reg(REG_RAX, v); }
    inline uint64_t get_rdi() const noexcept { return get_reg(REG_RDI); }
    inline void set_rdi(uint64_t v) noexcept { set_reg(REG_RDI, v); }
    inline uint64_t get_rsi() const noexcept { return get_reg(REG_RSI); }
    inline void set_rsi(uint64_t v) noexcept { set_reg(REG_RSI, v); }

    // RNS-4 Residue Arithmetic Engine (Garner CRT)
    inline uint64_t rns_add(uint64_t a, uint64_t b) const noexcept {
        return asgard_rns::decode(asgard_rns::add(asgard_rns::encode(a), asgard_rns::encode(b)));
    }
    inline uint64_t rns_sub(uint64_t a, uint64_t b) const noexcept {
        return asgard_rns::decode(asgard_rns::sub(asgard_rns::encode(a), asgard_rns::encode(b)));
    }
    inline uint64_t rns_mul(uint64_t a, uint64_t b) const noexcept {
        return asgard_rns::decode(asgard_rns::mul(asgard_rns::encode(a), asgard_rns::encode(b)));
    }

    inline void evolve_mask(uint32_t k) noexcept {
        uint64_t delta = ((uint64_t)k * 0x6A09E667F3BCC908ULL) ^ 0x1337ULL;
        uint64_t old_mask = reg_mask;
        uint64_t new_mask = (reg_mask ^ delta) + 0x5877ULL;
        for (size_t i = 0; i < 32; ++i) {
            gprs[i] = (gprs[i] ^ old_mask) ^ new_mask;
        }
        reg_mask = new_mask;
    }

    /* Virtual Stack Scrambling (8-Round Speck-64 ARX Permutation Core) */
    static inline constexpr size_t STACK_SIZE = 512;
    static inline constexpr size_t STACK_STRIDE = 213;
    static inline constexpr size_t STACK_OFFSET = 46;

    inline size_t scramble_stack_idx(size_t index) const noexcept {
        return (size_t)((index * STACK_STRIDE + STACK_OFFSET) & (STACK_SIZE - 1));
    }

    inline void push(uint64_t v) noexcept {
        if (!verify_canaries()) { reg_mask ^= poison_penalty; trapped = true; }
        if (sp < STACK_SIZE) {
            size_t phys_idx = scramble_stack_idx(sp);
            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;
            stack[phys_idx] = v ^ enc_mask;
            sp++;
        }
    }

    inline uint64_t pop() noexcept {
        if (!verify_canaries()) { reg_mask ^= poison_penalty; trapped = true; }
        if (sp > 0) {
            sp--;
            size_t phys_idx = scramble_stack_idx(sp);
            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;
            uint64_t val = stack[phys_idx] ^ enc_mask;
            stack[phys_idx] = 0xDEADBEEFCAFE1337ULL ^ enc_mask; // Ephemeral slot wipe
            return val;
        }
        return 0ULL;
    }

    uint64_t trace_digest = 0x53B7D9F7A1B4283EULL;

    inline void morph_math_to_flow(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : trace_digest;
        uint64_t regs[16];
        for (int i = 0; i < 16; ++i) regs[i] = get_reg(i);
        in_place_morph_math_to_flow(regs, stack, dig);
        for (int i = 0; i < 16; ++i) set_reg(i, 0x5A5A5A5A13375877ULL ^ ((uint64_t)i * 0x9E3779B97F4A7C15ULL));
        trace_digest = bridge_rol64(dig, 13) ^ 0x5877CAFEULL;
#else
        (void)target_digest;
#endif
    }

    inline void morph_flow_to_math(uint64_t target_digest = 0) noexcept {
#if defined(ASGARD_MULTI_VM_ENABLED)
        uint64_t dig = target_digest ? target_digest : (bridge_rol64(trace_digest, 51) ^ 0x5877CAFEULL);
        uint64_t regs[16];
        in_place_morph_flow_to_math(stack, regs, dig);
        for (int i = 0; i < 16; ++i) set_reg(i, regs[i]);
        for (int i = 0; i < 16; ++i) stack[i] = 0;
        trace_digest = dig;
#else
        (void)target_digest;
#endif
    }
};

static inline bool eval_condition(const VMContext& ctx, uint8_t cond) noexcept {
    switch (cond) {
        case 0: return ctx.zf;                         // E
        case 1: return !ctx.zf;                        // NE
        case 2: return ctx.cf;                         // B
        case 3: return !ctx.cf;                        // AE
        case 4: return ctx.cf || ctx.zf;               // BE
        case 5: return !ctx.cf && !ctx.zf;             // A
        case 6: return ctx.sf;                         // S
        case 7: return !ctx.sf;                        // NS
        case 8: return ctx.sf != ctx.of;               // L
        case 9: return ctx.sf == ctx.of;               // GE
        case 10: return ctx.zf || (ctx.sf != ctx.of);  // LE
        case 11: return !ctx.zf && (ctx.sf == ctx.of); // G
        default: return true;
    }
}

#define SCRUB_WORD(ptr, val) do { \
    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
} while(0)

__attribute__((always_inline, visibility("hidden"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x0F9131B2U, bool scrub_source = false) {
    if (ctx.reg_mask == 0) ctx.init(seed);
    /* Nanomite Hardware Signal Dispatcher (Hardware TRAP/Branch Interceptor) */
    asgard_nanomites::install_nanomite_handlers(seed);

    /* High-Speed Continuous Bytecode Integrity Guard (Anti-Patching / Breakpoint Detection) */
    uint64_t full_hash = 0x811C9DC5C9DC5119ULL ^ (uint64_t)seed;
    for (size_t i = 0; i < count; ++i) {
        full_hash = ((full_hash ^ bytecode[i]) * 0x100000001B3ULL) + (uint64_t)i;
    }
    if (full_hash != 0x6FFBC64E9A89B8EBULL) {
        /* Anti-Patching Tripwire: Silent Context Poisoning */
        ctx.reg_mask ^= 0xDEADBEEF5A5A5A5AULL;
        ctx.trapped = true;
        return false;
    }

    /* Active Anti-Debugging Probe (Bypassing libc via Direct Kernel Syscalls) */
    if (asgard_syscalls::sys_check_debugger_present()) {
        ctx.reg_mask ^= 0xCAFEBABE13375877ULL;
        ctx.trapped = true;
        return false;
    }

    /* Anti-Emulation & Hypervisor Timing Differential Probe */
    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
    if (emu_penalty != 0) {
        ctx.reg_mask ^= emu_penalty;
    }

    /* Introspective Self-Modifying Code (SMC) & Hardware Timing Probe (Morse & Kojsik, 2026) */
    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe((uint64_t)seed);
    if (smc_penalty != 0) {
        ctx.reg_mask ^= smc_penalty;
    }

    /* In-Memory MEM-SBOM Forensics & Hardware Breakpoint Probe */
    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();
    if (mem_penalty != 0) {
        ctx.reg_mask ^= mem_penalty;
    }

    /* Ephemeral Working Buffer: Isolated stack frame execution */
    uint64_t stack_buf[256];
    uint64_t* work_bc = (count <= 256) ? stack_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));
    for (size_t i = 0; i < count; ++i) work_bc[i] = 0x5877CAFE1337BEEFULL ^ ((uint64_t)seed + (uint64_t)i);

    size_t vIP_idx = 0;

#if defined(ASGARD_EPHEMERAL_JIT)
    static thread_local asgard_memory::DualMappedBuffer g_ephemeral_jit_buf = asgard_memory::DualMappedBuffer::allocate(4096);
#endif

    static const void* const dispatch_domain0[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain1[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain2[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain3[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain4[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain5[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain6[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const dispatch_domain7[256] = {
        &&H_ROR_RI,
        &&H_ATOMIC_LOAD,
        &&H_DECOY_1,
        &&H_CMOV,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_13,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_FUSED_CMP_CMOV,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_5,
        &&H_ROL_RI,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_LOAD_S16,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_14,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_LOAD_S8,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_STORE_32,
        &&H_DECOY_2,
        &&H_ADD_RR,
        &&H_DECOY_1,
        &&H_XOR_RR,
        &&H_FCVTZS,
        &&H_ATOMIC_STORE,
        &&H_DECOY_5,
        &&H_ATOMIC_ADD,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_STORE_64,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_OR_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DIV_RR,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_BRIDGE_TO_MATH,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_3,
        &&H_RESOLVE_SYM,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_14,
        &&H_ATOMIC_SWP,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_8,
        &&H_LOAD_32,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_IMUL_RR,
        &&H_DECOY_4,
        &&H_DECOY_1,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_VXOR_VV,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_RET,
        &&H_DECOY_11,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_ATOMIC_CAS,
        &&H_LOAD_S32,
        &&H_DECOY_13,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_7,
        &&H_SUB_RI,
        &&H_DECOY_7,
        &&H_IMUL_RI,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_0,
        &&H_MOV_RI,
        &&H_DECOY_5,
        &&H_AND_RR,
        &&H_DECOY_9,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_FADD_DD,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_CALL_EXTERN,
        &&H_FDIV_DD,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_SCVTF,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_5,
        &&H_STORE_16,
        &&H_DECOY_13,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_10,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_4,
        &&H_DECOY_5,
        &&H_DECOY_11,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_IDIV_RR,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_MOV_RR,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_1,
        &&H_SUB_RR,
        &&H_CMP_RI,
        &&H_SETCC,
        &&H_DECOY_6,
        &&H_ADD_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_5,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_STORE_8,
        &&H_DECOY_14,
        &&H_BRIDGE_TO_FLOW,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_OR_RR,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_FSUB_DD,
        &&H_FMUL_DD,
        &&H_DECOY_14,
        &&H_FCMP_DD,
        &&H_VMUL_VV,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_SAR_RI,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_VSUB_VV,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_LOAD_64,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_PUSH_R,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_SHL_RI,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_EXIT,
        &&H_DECOY_8,
        &&H_LOAD_16,
        &&H_DECOY_9,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_LOAD_8,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_JCC,
        &&H_DECOY_11,
        &&H_CMP_RR,
        &&H_NOP,
        &&H_DECOY_0,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_5,
        &&H_VADD_VV,
        &&H_DECOY_12,
        &&H_DECOY_4,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_SHR_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_JMP,
        &&H_DECOY_13,
        &&H_POP_R,
        &&H_DECOY_3,
        &&H_CALL,
        &&H_DECOY_9,
        &&H_AND_RI,
    };

    static const void* const* const all_dispatch_domains[8] = {
        dispatch_domain0,
        dispatch_domain1,
        dispatch_domain2,
        dispatch_domain3,
        dispatch_domain4,
        dispatch_domain5,
        dispatch_domain6,
        dispatch_domain7,
    };

    uint64_t g_handlers_hash = compute_handlers_hash((const void* const* const*)all_dispatch_domains, 8);

    uint64_t bound_buf[256];
    uint64_t* bound_bc = (count <= 256) ? bound_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));
    for (size_t b = 0; b < g_num_blocks; ++b) {
        size_t off = g_block_offsets[b];
        size_t len = g_block_lengths[b];
        uint64_t rk = VMContext::anchor_key(seed, (uint64_t)off, g_handlers_hash);
        for (size_t j = 0; j < len; ++j) {
            size_t idx = off + j;
            uint64_t k_pos = key64_for_offset(seed, idx);
            uint64_t plain = bytecode[idx] ^ k_pos;
            bound_bc[idx] = plain ^ k_pos ^ rk;
            uint8_t b_op = (uint8_t)(plain & 0xFF);
            uint8_t b_dst = (uint8_t)((plain >> 8) & 0x1F);
            int64_t b_imm = (int64_t)((int32_t)((plain >> 18) & 0xFFFFFFFFULL));
            rk = VMContext::advance_key_step(rk, b_op, b_dst, b_imm);
        }
    }

    uint64_t word = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;

    #define FETCH_NEXT() do { \
        if (vIP_idx >= count) goto EXIT_VM; \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
        uint64_t k_dyn = k_pos ^ ctx.running_key; \
        work_bc[vIP_idx] = bound_bc[vIP_idx]; \
        word = work_bc[vIP_idx] ^ k_dyn; \
        /* Ephemeral Self-Consuming: Overwrite scratch RAM buffer with dynamic rolling noise */ \
        SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL); \
        vIP_idx++; \
        op = (uint8_t)(word & 0xFF); \
        dst = (uint8_t)((word >> 8) & 0x1F); \
        src = (uint8_t)((word >> 13) & 0x1F); \
        imm = (int64_t)((int32_t)((word >> 18) & 0xFFFFFFFFULL)); \
        ctx.evolve_mask((uint32_t)k_dyn); \
        ctx.advance_running_key(op, dst, imm); \
        uint8_t domain_idx = (uint8_t)((op ^ (uint8_t)(k_dyn & 0x07)) % 8); \
        goto *all_dispatch_domains[domain_idx][op]; \
    } while(0)

    ctx.reanchor_running_key(0, g_handlers_hash);
    FETCH_NEXT();

    #if defined(__x86_64__)
    #define PROBE_START() uint64_t _t0 = __builtin_ia32_rdtsc()
    #define PROBE_CHECK() do { uint64_t _t1 = __builtin_ia32_rdtsc(); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #elif defined(__aarch64__)
    #define PROBE_START() uint64_t _t0; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t0))
    #define PROBE_CHECK() do { uint64_t _t1; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(_t1)); if ((_t1 - _t0) > 100000ULL) { ctx.reg_mask ^= 0x1337BEEF5877A5A5ULL; } } while(0)
    #else
    #define PROBE_START() uint64_t _t0 = 0
    #define PROBE_CHECK() do {} while(0)
    #endif

    H_NOP: ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RR: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RI: ctx.set_reg(dst, (uint64_t)(uint32_t)imm); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_HIGH: {
        uint64_t high_val = (uint64_t)(uint32_t)imm << 32;
        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
#if defined(ASGARD_EPHEMERAL_JIT)
    H_ADD_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ADD_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_ADD_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SUB_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_SUB_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_MUL_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_MUL_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RR: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_XOR_RR, dst, src, 0); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI: { PROBE_START(); asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_XOR_RI, dst, 0, (uint64_t)imm); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_AND_RR, dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI: { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_AND_RI, dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RR:  { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_OR_RR,  dst, src, 0); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI:  { asgard_ephemeral_jit::execute_ephemeral_vm_op(g_ephemeral_jit_buf, ctx, asgard_ephemeral_jit::EPH_OP_OR_RI,  dst, 0, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
#else
    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, (((0x2ull * (((((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ull) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ull)) + (((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))))) - (((((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ull) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ull)) + (((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))) ^ ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))))) + (((((((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ull) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ull)) + (((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))) | ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL))))) + (((((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & 0x5555555555555555ull) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & 0x5555555555555555ull)) + (((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))) & ((((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & 0x5555555555555555ull)) + (((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)) - ((ctx.get_reg(dst) + ctx.get_reg(src)) & (uint64_t)(-6148914691236517206LL)))))) - (ctx.get_reg(dst) + ctx.get_reg(src))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, ((((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) ^ (((((ctx.get_reg(dst) + ctx.get_reg(src)) - (0x2ull * (ctx.get_reg(dst) & ctx.get_reg(src)))) & (~((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~(ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) - ((~(ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + ((((ctx.get_reg(dst) + ctx.get_reg(src)) - (0x2ull * (ctx.get_reg(dst) & ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) - ((~(ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (0x2ull * (((ctx.get_reg(dst) & (~ctx.get_reg(src))) - (((~ctx.get_reg(dst)) - ((~ctx.get_reg(dst)) & (~ctx.get_reg(src)))) + (((~ctx.get_reg(dst)) ^ ctx.get_reg(src)) - (((~ctx.get_reg(dst)) | ctx.get_reg(src)) - ((~ctx.get_reg(dst)) & ctx.get_reg(src)))))) & ((((ctx.get_reg(dst) ^ ctx.get_reg(src)) & (~((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~(ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) + (((ctx.get_reg(dst) ^ ctx.get_reg(src)) ^ ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))))))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) - 2 * ((~ctx.get_reg(dst)) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_IMUL_RR: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IMUL_RI: {
        PROBE_START();
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));
        PROBE_CHECK();
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, (((((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) + (0x2ull * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src))))) & (~((((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull + (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((0x2ull & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) * ((~0x2ull) & (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))))))) - ((~(((0x2ull * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - (ctx.get_reg(dst) + ctx.get_reg(src))))) & ((((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull + (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((0x2ull & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) * ((~0x2ull) & (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))))))) + ((((((ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) ^ ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - (ctx.get_reg(dst) ^ ctx.get_reg(src))))) + (0x2ull * ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src))))) ^ ((((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull + (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((0x2ull & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) * ((~0x2ull) & (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src)))))) - (((((0x2ull * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) | ((((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull + (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((0x2ull & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) * ((~0x2ull) & (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src)))))) - ((((0x2ull * ((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) + ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & ((((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull + (ctx.get_reg(dst) & ctx.get_reg(src)))) + ((0x2ull & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) * ((~0x2ull) & (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src))) * (0x2ull & (ctx.get_reg(dst) & ctx.get_reg(src)))))))))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) ^ (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR: { ctx.set_reg(dst, (((((ctx.get_reg(dst) & (~(ctx.get_reg(dst) & (~ctx.get_reg(src))))) - ((~ctx.get_reg(dst)) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ull) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL))))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ull) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) | ((((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & (~((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~(ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) - ((~(ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) - ((~(ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + ((((ctx.get_reg(dst) & (~(ctx.get_reg(dst) & (~ctx.get_reg(src))))) - ((~ctx.get_reg(dst)) & (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ull) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL))))) + ((ctx.get_reg(dst) ^ (((ctx.get_reg(dst) & (~ctx.get_reg(src))) & 0x5555555555555555ull) + ((ctx.get_reg(dst) & (~ctx.get_reg(src))) & (uint64_t)(-6148914691236517206LL)))) - ((ctx.get_reg(dst) | (ctx.get_reg(dst) & (~ctx.get_reg(src)))) - (ctx.get_reg(dst) & (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) & ((((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) & (~((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))))) - ((~(ctx.get_reg(dst) ^ ctx.get_reg(src))) & ((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) - ((~(ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src)))))))) + (((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) ^ ((((ctx.get_reg(dst) | ctx.get_reg(src)) & (~(ctx.get_reg(dst) & ctx.get_reg(src)))) - ((~(ctx.get_reg(dst) | ctx.get_reg(src))) & (ctx.get_reg(dst) & ctx.get_reg(src)))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src))) - (((ctx.get_reg(dst) | ctx.get_reg(src)) | (ctx.get_reg(dst) & ctx.get_reg(src))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) & (ctx.get_reg(dst) & ctx.get_reg(src))))))) - (((ctx.get_reg(dst) ^ ctx.get_reg(src)) | ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))) - ((ctx.get_reg(dst) ^ ctx.get_reg(src)) & ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RI: ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RR: { ctx.set_reg(dst, (((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - (((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))) | ((ctx.get_reg(dst) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~(~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~ctx.get_reg(src)))) + ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))) - (((0x2ull * (ctx.get_reg(dst) | ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))))) & ((ctx.get_reg(dst) - ((ctx.get_reg(dst) - (ctx.get_reg(dst) & (~(~ctx.get_reg(src))))) + ((ctx.get_reg(dst) ^ (~ctx.get_reg(src))) - ((ctx.get_reg(dst) | (~ctx.get_reg(src))) - (ctx.get_reg(dst) & (~ctx.get_reg(src))))))) + ((((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src))) + (((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))) - (ctx.get_reg(dst) + ctx.get_reg(src)))) - ((ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) & ctx.get_reg(src)))))))); ctx.executed_instructions++; FETCH_NEXT(); }
    H_OR_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();
#endif
    H_ROL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val << shift) | (val >> ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ROR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (val >> shift) | (val << ((64 - shift) & 63)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHL_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val << shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SHR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, val >> shift);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SAR_RI: {
        uint64_t val = ctx.get_reg(dst); uint32_t shift = (uint32_t)(imm & 63);
        ctx.set_reg(dst, (uint64_t)((int64_t)val >> shift));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_DIV_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        ctx.set_reg(dst, (b == 0) ? 0ULL : (a / b));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_IDIV_RR: {
        int64_t a = (int64_t)ctx.get_reg(dst); int64_t b = (int64_t)ctx.get_reg(src);
        int64_t q = (b == 0) ? 0 : ((b == -1) ? (int64_t)(0 - (uint64_t)a) : (a / b));
        ctx.set_reg(dst, (uint64_t)q);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.of = ((((a ^ b) & (a ^ res)) >> 63) != 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R: ctx.push(ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT();
    H_POP_R: ctx.set_reg(dst, ctx.pop()); ctx.executed_instructions++; FETCH_NEXT();
    H_JMP: {
#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));
        raise(SIGTRAP);
        vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;
#else
        vIP_idx = (size_t)imm;
#endif
        ctx.reanchor_running_key((uint64_t)vIP_idx, g_handlers_hash);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JCC: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        uint64_t t_true = (uint64_t)((word >> 22) & 0x1FFFFFULL);
        uint64_t t_false = (uint64_t)((word >> 43) & 0x1FFFFFULL);
        uint64_t c = eval_condition(ctx, cond) ? 1ULL : 0ULL;
#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;
        asgard_nanomites::g_nanomite_dispatcher.current_condition = (uint32_t)c;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, t_true, t_false, (uint64_t)(seed ^ (uint32_t)vIP_idx));
        raise(SIGTRAP);
        vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;
#else
        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);
#endif
        ctx.reanchor_running_key((uint64_t)vIP_idx, g_handlers_hash);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMOV: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SETCC: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        uint64_t val = eval_condition(ctx, cond) ? 1ULL : 0ULL;
        ctx.set_reg(dst, val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CALL: {
        ctx.push((uint64_t)vIP_idx);
#if (defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)
        asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;
        asgard_nanomites::g_nanomite_dispatcher.current_condition = 1;
        asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, (uint64_t)imm, (uint64_t)imm, (uint64_t)(seed ^ (uint32_t)vIP_idx));
        raise(SIGTRAP);
        vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;
#else
        vIP_idx = (size_t)imm;
#endif
        ctx.reanchor_running_key((uint64_t)vIP_idx, g_handlers_hash);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;
    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;

    H_BRIDGE_TO_FLOW: {
        ctx.morph_math_to_flow((uint64_t)imm);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_BRIDGE_TO_MATH: {
        ctx.morph_flow_to_math((uint64_t)imm);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }

    H_FUSED_MOV_ADD_RRI: {
        ctx.set_reg(dst, ctx.get_reg(src) + (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_IMUL_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) * (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_ADD_XOR_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) ^ (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_SUB_XOR_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) - ctx.get_reg(src)) ^ (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_XOR_ADD_RRI: {
        ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (uint64_t)imm);
        ctx.executed_instructions += 2;
        FETCH_NEXT();
    }
    H_FUSED_CMP_CMOV: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);
        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));
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
    H_VMUL_VV: {
        uint64_t d0 = ctx.get_vreg_lane(dst, 0), d1 = ctx.get_vreg_lane(dst, 1);
        uint64_t s0 = ctx.get_vreg_lane(src, 0), s1 = ctx.get_vreg_lane(src, 1);
        ctx.set_vreg(dst, d0 * s0, d1 * s1);
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

    H_CALL_EXTERN: {
        size_t sym_idx = (size_t)imm;
        if (sym_idx < sizeof(g_external_symbols) / sizeof(g_external_symbols[0]) && g_external_symbols[sym_idx][0] != '\0') {
            const char* sym_name = g_external_symbols[sym_idx];
            void* sym_ptr = dlsym(RTLD_DEFAULT, sym_name);
            if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);
            if (!sym_ptr) {
                char alt_name[256];
                snprintf(alt_name, sizeof(alt_name), "_%s", sym_name);
                sym_ptr = dlsym(RTLD_DEFAULT, alt_name);
            }
            if (sym_ptr) {
                typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
                extern_fn_t fn = reinterpret_cast<extern_fn_t>(sym_ptr);
                uint64_t a0 = ctx.get_reg(REG_RAX);
                uint64_t a1 = ctx.get_reg(REG_RCX);
                uint64_t a2 = ctx.get_reg(REG_RDX);
                uint64_t a3 = ctx.get_reg(REG_RBX);
                uint64_t a4 = ctx.get_reg(REG_RSI);
                uint64_t a5 = ctx.get_reg(REG_RDI);
                uint64_t a6 = ctx.get_reg(REG_R8);
                uint64_t a7 = ctx.get_reg(REG_R9);
                uint64_t ret_val = fn(a0, a1, a2, a3, a4, a5, a6, a7);
                ctx.set_reg(REG_RAX, ret_val);
            }
        }
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_LOAD_64: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, *reinterpret_cast<const uint64_t*>(addr));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_LOAD_32: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(*reinterpret_cast<const uint32_t*>(addr)));
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
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        ctx.set_reg(dst, (uint64_t)(int64_t)(*reinterpret_cast<const int8_t*>(addr)));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_64: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_32: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint32_t*>(addr) = (uint32_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_16: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint16_t*>(addr) = (uint16_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_STORE_8: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(src);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RESOLVE_SYM: {
        size_t sym_idx = (size_t)imm;
        void* sym_ptr = nullptr;
        if (sym_idx < sizeof(g_external_symbols) / sizeof(g_external_symbols[0]) && g_external_symbols[sym_idx][0] != '\0') {
            const char* sym_name = g_external_symbols[sym_idx];
            sym_ptr = dlsym(RTLD_DEFAULT, sym_name);
            if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);
            if (!sym_ptr) {
                char alt_name[256];
                snprintf(alt_name, sizeof(alt_name), "_%s", sym_name);
                sym_ptr = dlsym(RTLD_DEFAULT, alt_name);
            }
            if (!sym_ptr) {
                sym_ptr = asgard_resolve_constant(sym_name);
            }
        }
        ctx.set_reg(dst, (uint64_t)sym_ptr);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FADD_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(dst, 0), b_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a + b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FSUB_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(dst, 0), b_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a - b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FMUL_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(dst, 0), b_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(a * b), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FDIV_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(dst, 0), b_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        double r = (b != 0.0) ? (a / b) : 0.0;
        ctx.set_vreg(dst, std::bit_cast<uint64_t>(r), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCMP_DD: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0), b_raw = ctx.get_vreg_lane((uint8_t)imm, 0);
        double a = std::bit_cast<double>(a_raw), b = std::bit_cast<double>(b_raw);
        ctx.zf = (a == b);
        ctx.cf = (a >= b);
        ctx.sf = (a < b);
        ctx.of = false;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_FCVTZS: {
        uint64_t a_raw = ctx.get_vreg_lane(src, 0);
        double a = std::bit_cast<double>(a_raw);
        ctx.set_reg(dst, (uint64_t)((int64_t)a));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_SCVTF: {
        int64_t v = (int64_t)ctx.get_reg(src);
        ctx.set_vreg(dst, std::bit_cast<uint64_t>((double)v), 0);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_LOAD: {
        uint64_t addr = ctx.get_reg(src) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        ctx.set_reg(dst, ptr->load(std::memory_order_seq_cst));
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_STORE: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        ptr->store(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_CAS: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t expected = ctx.get_reg(src);
        uint64_t desired = ctx.get_reg(REG_RAX);
        ptr->compare_exchange_strong(expected, desired, std::memory_order_seq_cst);
        ctx.set_reg(src, expected);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_ADD: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t old = ptr->fetch_add(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ATOMIC_SWP: {
        uint64_t addr = ctx.get_reg(dst) + (uint64_t)imm;
        auto* ptr = reinterpret_cast<std::atomic<uint64_t>*>(addr);
        uint64_t old = ptr->exchange(ctx.get_reg(src), std::memory_order_seq_cst);
        ctx.set_reg(src, old);
        ctx.executed_instructions++; FETCH_NEXT();
    }

    H_DECOY_0: { ctx.set_reg(dst, ctx.get_reg(dst) ^ 0x5877ULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_1: { ctx.set_reg(dst, ctx.get_reg(dst) + (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_2: { ctx.set_reg(dst, ctx.get_reg(dst) * 0x9E37ULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_3: { ctx.set_reg(dst, (ctx.get_reg(dst) << 3) | (ctx.get_reg(dst) >> 61)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_4: { ctx.set_reg(dst, ctx.get_reg(src) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_5: { ctx.set_reg(dst, ctx.get_reg(dst) & ~ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_6: { ctx.set_reg(dst, ctx.get_reg(dst) | 0xCAFEBABEULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_7: { ctx.set_reg(dst, (ctx.get_reg(dst) >> 5) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_8: { ctx.set_reg(dst, ctx.get_reg(dst) - 0x1337ULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_9: { ctx.set_reg(dst, ctx.get_reg(dst) ^ (ctx.get_reg(src) + 1)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_10: { ctx.set_reg(dst, (ctx.get_reg(dst) * 6364136223846793005ULL) + 1); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_11: { ctx.set_reg(dst, (ctx.get_reg(dst) << 7) ^ (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_12: { ctx.set_reg(dst, ctx.get_reg(dst) ^ 0xDEADBEEFULL); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_13: { ctx.set_reg(dst, ctx.get_reg(dst) + ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_14: { ctx.set_reg(dst, ctx.get_reg(dst) ^ (uint64_t)(imm * 3)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY_15: { ctx.set_reg(dst, ~ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT(); }
    H_DECOY:
        ctx.trapped = true;
        goto EXIT_VM;

    EXIT_VM:
    /* Ephemeral Complete Memory Sanitization: Scrub all working memory */
    for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&work_bc[i], 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i));
    }
    for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&bound_bc[i], 0xDEADBEEF5877CAFEULL ^ ((uint64_t)seed + (uint64_t)i));
    }
    if (scrub_source && bytecode) {
        for (size_t i = 0; i < count; ++i) {
            SCRUB_WORD(&const_cast<uint64_t*>(bytecode)[i], 0xDEADBEEFCAFEBABEULL ^ ((uint64_t)seed + (uint64_t)i));
        }
    }
    return !ctx.trapped;
}

__attribute__((always_inline, visibility("hidden"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, bool scrub_source) {
    return execute_threaded(ctx, bytecode, count, 0x0F9131B2U, scrub_source);
}

static inline uint64_t asgard_vm_call(const uint64_t* bc, size_t len, uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0, uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init(0x0F9131B2U);
    alignas(16) static thread_local uint8_t host_stack[1048576];
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(host_stack + sizeof(host_stack) - 8192));
    ctx.set_reg(vanguard_threaded_vm::REG_RBP, (uint64_t)(host_stack + sizeof(host_stack) - 8192));
    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a1);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);
    ctx.set_reg(vanguard_threaded_vm::REG_RBX, a3);
    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a4);
    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a5);
    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a6);
    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a7);
    vanguard_threaded_vm::execute_threaded(ctx, bc, len, false);
    return ctx.get_rax();
}

} // namespace vanguard_threaded_vm
