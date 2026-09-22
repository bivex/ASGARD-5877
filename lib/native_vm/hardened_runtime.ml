type target_os = [ `Darwin | `Linux | `Windows | `Auto ]

let emit_direct_syscalls_header ?(target_os = `Auto) () =
  let _ = target_os in

  {|#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

namespace asgard_syscalls {

#if defined(__APPLE__) && defined(__aarch64__)
// Direct Darwin ARM64 Syscall Stub (SVC #0x80 with BSD class 0x2000000)
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    register int64_t x16 __asm__("x16") = sys_num;
    register int64_t x0  __asm__("x0")  = a1;
    register int64_t x1  __asm__("x1")  = a2;
    register int64_t x2  __asm__("x2")  = a3;
    __asm__ volatile(
        "svc #0x80"
        : "+r"(x0)
        : "r"(x16), "r"(x1), "r"(x2)
        : "memory", "cc"
    );
    return x0;
}
#elif defined(__APPLE__) && defined(__x86_64__)
// Direct Darwin x86_64 Syscall Stub (syscall with 0x2000000 class offset)
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    int64_t ret;
    register int64_t r10 __asm__("r10") = a3;
    __asm__ volatile(
        "syscall"
        : "=a"(ret)
        : "a"(0x2000000 | sys_num), "D"(a1), "S"(a2), "r"(r10)
        : "rcx", "r11", "memory"
    );
    return ret;
}
#elif defined(__linux__) && defined(__x86_64__)
// Direct Linux x86_64 Syscall Stub
static inline __attribute__((always_inline)) int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    int64_t ret;
    register int64_t r10 __asm__("r10") = a3;
    __asm__ volatile(
        "syscall"
        : "=a"(ret)
        : "a"(sys_num), "D"(a1), "S"(a2), "r"(r10)
        : "rcx", "r11", "memory"
    );
    return ret;
}
#else
static inline int64_t direct_syscall_3(int64_t sys_num, int64_t a1, int64_t a2, int64_t a3) noexcept {
    (void)sys_num; (void)a1; (void)a2; (void)a3;
    return 0;
}
#endif

} // namespace asgard_syscalls
|}

let emit_dual_mapping_header () =
  {|#pragma once
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
|}

let emit_anti_emulation_probes () =
  {|#pragma once
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
|}

let emit_introspective_smc_header () =
  {|#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

namespace asgard_smc {

// Introspective Self-Modifying Code (SMC) + Hardware Timing Probe (Morse & Kojsik, 2026)
static inline __attribute__((always_inline)) uint64_t execute_introspective_smc_probe(uint64_t seed) noexcept {
    uint64_t penalty = 0;
    asgard_memory::DualMappedBuffer buf = asgard_memory::DualMappedBuffer::allocate(4096);
    if (!buf.rw_alias || !buf.rx_alias) {
        return 0; // If dual-mapping is unsupported in environment, degrade gracefully
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
#endif

    buf.release();
    return penalty;
}

} // namespace asgard_smc
|}

let emit_memory_integrity_scanner_header () =
  {|#pragma once
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
|}

let emit_nanomite_engine_header () =
  {|#pragma once
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
|}

