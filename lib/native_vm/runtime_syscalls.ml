type target_os = [ `Darwin | `Linux | `Windows | `Auto ]

let emit_direct_syscalls_header ?(target_os = `Auto) () =
  let os_macro =
    match target_os with
    | `Darwin -> "#define ASGARD_TARGET_DARWIN 1\n"
    | `Linux -> "#define ASGARD_TARGET_LINUX 1\n"
    | `Windows -> "#define ASGARD_TARGET_WINDOWS 1\n"
    | `Auto -> ""
  in
  os_macro ^ {|#pragma once
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
|}
