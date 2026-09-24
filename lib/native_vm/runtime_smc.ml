let emit_introspective_smc_header () =
  {|#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#if defined(__APPLE__)
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#endif

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
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(t0));

    // Dynamic Self-Modification via RW alias: mutate immediate in add (bits 10..21)
    uint32_t imm_val = (uint32_t)(seed & 0x7F);
    code_rw[1] = 0x11000000 | (imm_val << 10);

    // Hardware icache invalidation & pipeline clear
#if defined(__APPLE__)
    sys_dcache_flush(buf.rw_alias, 16);
    sys_icache_invalidate((void*)buf.rx_alias, 16);
    pthread_jit_write_protect_np(1);
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
