#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
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

namespace vanguard_threaded_vm {

/* ------------------------------------------------------------------------- */
/* Randomized Architectural Register Map (π ∈ S_32)                          */
/* ------------------------------------------------------------------------- */
enum RegMap : uint8_t {
    REG_RAX = 18,
    REG_RCX = 20,
    REG_RDX = 3,
    REG_RBX = 16,
    REG_RSP = 7,
    REG_RBP = 11,
    REG_RSI = 1,
    REG_RDI = 26,
    REG_R8 = 13,
    REG_R9 = 12,
    REG_R10 = 17,
    REG_R11 = 25,
    REG_R12 = 9,
    REG_R13 = 5,
    REG_R14 = 28,
    REG_R15 = 8,
    REG_VTMP0 = 2,
    REG_VTMP1 = 0,
    REG_VTMP2 = 15,
    REG_VTMP3 = 14,
    REG_VIP = 29,
    REG_VSP = 4,
    REG_VKEY = 22,
};

static inline uint64_t key64_for_offset(uint32_t seed, size_t offset) noexcept {
    uint64_t s64 = (uint64_t)seed;
    uint64_t x0 = ((s64 << 32) | (s64 ^ 0x9E3779B9ULL)) ^ ((uint64_t)offset * 0x517CC1B727220A95ULL);
    uint64_t x1 = (x0 ^ (x0 >> 30)) * 0xBF58476D1CE4E5B9ULL;
    uint64_t x2 = (x1 ^ (x1 >> 27)) * 0x94D049BB133111EBULL;
    return x2 ^ (x2 >> 31);
}

struct VMContext {
    static inline constexpr uint64_t CANARY_VAL = 0xCAFEBABE13375877ULL;
    uint64_t canary_head = CANARY_VAL;
    uint64_t mid_canaries[32]; // Interleaved dynamic canaries across every 16 stack frames
    uint64_t gprs[32]; // Blinded in memory: actual_val = gprs[i] ^ reg_mask
    uint64_t stack[512];
    size_t sp;
    uint64_t reg_mask;
    uint32_t init_seed;
    uint64_t poison_penalty;
    bool cf, zf, sf, of;
    bool trapped;
    size_t executed_instructions;
    uint64_t canary_tail = CANARY_VAL;

    inline void init(uint32_t seed = 0x3E36AAA4U) noexcept {
        init_seed = seed;
        poison_penalty = (key64_for_offset(seed, 0x5877) ^ 0xCAA7E1D8718BF877ULL) | 1ULL;
        reg_mask = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed * 0x9E3779B97F4A7C15ULL);
        for (size_t i = 0; i < 32; ++i) {
            gprs[i] = reg_mask; // Initialized to 0 (0 ^ reg_mask)
            mid_canaries[i] = CANARY_VAL ^ ((uint64_t)i * 0x517CC1B727220A95ULL) ^ (uint64_t)seed;
        }
        sp = 0;
        cf = zf = sf = of = false;
        trapped = false;
        executed_instructions = 0;
        canary_head = canary_tail = CANARY_VAL;
    }

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

    // Named architectural register accessors via randomized permutation
    inline uint64_t get_rax() const noexcept { return get_reg(REG_RAX); }
    inline void set_rax(uint64_t v) noexcept { set_reg(REG_RAX, v); }
    inline uint64_t get_rdi() const noexcept { return get_reg(REG_RDI); }
    inline void set_rdi(uint64_t v) noexcept { set_reg(REG_RDI, v); }
    inline uint64_t get_rsi() const noexcept { return get_reg(REG_RSI); }
    inline void set_rsi(uint64_t v) noexcept { set_reg(REG_RSI, v); }

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
    static inline constexpr size_t STACK_STRIDE = 27;
    static inline constexpr size_t STACK_OFFSET = 73;

    inline size_t scramble_stack_idx(size_t index) const noexcept {
        uint32_t x = (uint32_t)((index * STACK_STRIDE + STACK_OFFSET) & 0xFFFF);
        uint32_t y = (uint32_t)(index ^ 0x1337U);
        for (size_t r = 0; r < 8; ++r) {
            uint32_t rot_rx = ((x >> 8) | (x << 24));
            x = (rot_rx + y) ^ 0x9E3779B9U;
            uint32_t rot_ly = ((y << 3) | (y >> 29));
            y = rot_ly ^ x;
        }
        return (size_t)((x ^ y) & (STACK_SIZE - 1));
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

__attribute__((always_inline, visibility("hidden"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x3E36AAA4U) {
    if (ctx.reg_mask == 0) ctx.init(seed);
    /* High-Speed Continuous Bytecode Integrity Guard (Anti-Patching / Breakpoint Detection) */
    uint64_t full_hash = 0x811C9DC5C9DC5119ULL ^ (uint64_t)seed;
    for (size_t i = 0; i < count; ++i) {
        full_hash = ((full_hash ^ bytecode[i]) * 0x100000001B3ULL) + (uint64_t)i;
    }
    if (full_hash != 0x79D9E0012A10F90CULL) {
        /* Anti-Patching Tripwire: Silent Context Poisoning */
        ctx.reg_mask ^= 0xDEADBEEF5A5A5A5AULL;
        ctx.trapped = true;
        return false;
    }

    /* Active Anti-Debugging & Hardware Breakpoint Probe */
#if defined(__APPLE__)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc kinfo = {};
    size_t ksize = sizeof(kinfo);
    if (sysctl(mib, 4, &kinfo, &ksize, (void*)0, 0) == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {
        ctx.reg_mask ^= 0xCAFEBABE13375877ULL;
        ctx.trapped = true;
        return false;
    }
#endif

/* Anti-Emulation & Hypervisor Timing Differential Probe */
uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
if (emu_penalty != 0) {
ctx.reg_mask ^= emu_penalty;
}


    /* Ephemeral Working Buffer: Isolated stack frame execution */
    uint64_t stack_buf[256];
    uint64_t* work_bc = (count <= 256) ? stack_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));
    for (size_t i = 0; i < count; ++i) work_bc[i] = bytecode[i];

    size_t vIP_idx = 0;

    static const void* const dispatch_domain0[256] = {
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_8,
        &&H_SHR_RI,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_DECOY_4,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_10,
        &&H_ROR_RI,
        &&H_DECOY_4,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_ADD_RR,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_14,
        &&H_DECOY_0,
        &&H_DECOY_5,
        &&H_DECOY_12,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_JCC,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_OR_RI,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_DECOY_1,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_14,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_IMUL_RI,
        &&H_DECOY_6,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_CMP_RR,
        &&H_AND_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_ADD_RI,
        &&H_DECOY_12,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_DECOY_0,
        &&H_DECOY_12,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_9,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_6,
        &&H_DECOY_3,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_MOV_RR,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_JMP,
        &&H_DECOY_5,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_ROL_RI,
        &&H_DECOY_15,
        &&H_DECOY_13,
        &&H_SHL_RI,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_7,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_IMUL_RR,
        &&H_PUSH_R,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_FUSED_CMP_CMOV,
        &&H_SUB_RR,
        &&H_DECOY_10,
        &&H_EXIT,
        &&H_DECOY_2,
        &&H_MOV_RI,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_RET,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_9,
        &&H_AND_RR,
        &&H_SUB_RI,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_POP_R,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_XOR_RR,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_CMOV,
        &&H_DECOY_13,
        &&H_CMP_RI,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_NOP,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_CALL,
        &&H_OR_RR,
        &&H_DECOY_13,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_11,
        &&H_SETCC,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_3,
    };

    static const void* const dispatch_domain1[256] = {
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_8,
        &&H_SHR_RI,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_DECOY_4,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_10,
        &&H_ROR_RI,
        &&H_DECOY_4,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_ADD_RR,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_14,
        &&H_DECOY_0,
        &&H_DECOY_5,
        &&H_DECOY_12,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_JCC,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_OR_RI,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_DECOY_1,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_14,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_IMUL_RI,
        &&H_DECOY_6,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_CMP_RR,
        &&H_AND_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_ADD_RI,
        &&H_DECOY_12,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_DECOY_0,
        &&H_DECOY_12,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_9,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_6,
        &&H_DECOY_3,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_MOV_RR,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_JMP,
        &&H_DECOY_5,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_ROL_RI,
        &&H_DECOY_15,
        &&H_DECOY_13,
        &&H_SHL_RI,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_7,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_IMUL_RR,
        &&H_PUSH_R,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_FUSED_CMP_CMOV,
        &&H_SUB_RR,
        &&H_DECOY_10,
        &&H_EXIT,
        &&H_DECOY_2,
        &&H_MOV_RI,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_RET,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_9,
        &&H_AND_RR,
        &&H_SUB_RI,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_POP_R,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_XOR_RR,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_CMOV,
        &&H_DECOY_13,
        &&H_CMP_RI,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_NOP,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_CALL,
        &&H_OR_RR,
        &&H_DECOY_13,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_11,
        &&H_SETCC,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_3,
    };

    static const void* const dispatch_domain2[256] = {
        &&H_DECOY_0,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_8,
        &&H_SHR_RI,
        &&H_DECOY_7,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_DECOY_6,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_0,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_DECOY_4,
        &&H_DECOY_15,
        &&H_DECOY_14,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_15,
        &&H_DECOY_3,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_10,
        &&H_ROR_RI,
        &&H_DECOY_4,
        &&H_FUSED_XOR_ADD_RRI,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_ADD_RR,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_14,
        &&H_DECOY_0,
        &&H_DECOY_5,
        &&H_DECOY_12,
        &&H_FUSED_ADD_XOR_RRI,
        &&H_DECOY_1,
        &&H_DECOY_11,
        &&H_DECOY_4,
        &&H_DECOY_0,
        &&H_JCC,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_OR_RI,
        &&H_DECOY_14,
        &&H_DECOY_6,
        &&H_FUSED_ADD_IMUL_RRI,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_7,
        &&H_DECOY_9,
        &&H_DECOY_5,
        &&H_DECOY_2,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_DECOY_3,
        &&H_DECOY_1,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_14,
        &&H_FUSED_SUB_XOR_RRI,
        &&H_IMUL_RI,
        &&H_DECOY_6,
        &&H_DECOY_7,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_4,
        &&H_CMP_RR,
        &&H_AND_RI,
        &&H_DECOY_8,
        &&H_DECOY_9,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_FUSED_MOV_ADD_RRI,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_ADD_RI,
        &&H_DECOY_12,
        &&H_DECOY_10,
        &&H_DECOY_11,
        &&H_DECOY_0,
        &&H_DECOY_12,
        &&H_DECOY_9,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_9,
        &&H_DECOY_4,
        &&H_DECOY_10,
        &&H_DECOY_6,
        &&H_DECOY_3,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_9,
        &&H_DECOY_10,
        &&H_DECOY_9,
        &&H_DECOY_1,
        &&H_DECOY_3,
        &&H_MOV_HIGH,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_DECOY_1,
        &&H_DECOY_7,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_9,
        &&H_DECOY_15,
        &&H_DECOY_4,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_14,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_MOV_RR,
        &&H_DECOY_2,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_DECOY_0,
        &&H_DECOY_8,
        &&H_DECOY_2,
        &&H_DECOY_12,
        &&H_DECOY_11,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_12,
        &&H_DECOY_6,
        &&H_DECOY_14,
        &&H_DECOY_1,
        &&H_DECOY_1,
        &&H_JMP,
        &&H_DECOY_5,
        &&H_DECOY_2,
        &&H_DECOY_10,
        &&H_DECOY_10,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_10,
        &&H_DECOY_5,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_0,
        &&H_DECOY_15,
        &&H_ROL_RI,
        &&H_DECOY_15,
        &&H_DECOY_13,
        &&H_SHL_RI,
        &&H_DECOY_12,
        &&H_DECOY_7,
        &&H_DECOY_7,
        &&H_DECOY_8,
        &&H_DECOY_14,
        &&H_DECOY_8,
        &&H_DECOY_4,
        &&H_DECOY_2,
        &&H_IMUL_RR,
        &&H_PUSH_R,
        &&H_DECOY_9,
        &&H_DECOY_7,
        &&H_DECOY_12,
        &&H_FUSED_CMP_CMOV,
        &&H_SUB_RR,
        &&H_DECOY_10,
        &&H_EXIT,
        &&H_DECOY_2,
        &&H_MOV_RI,
        &&H_DECOY_13,
        &&H_DECOY_5,
        &&H_DECOY_5,
        &&H_DECOY_0,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_RET,
        &&H_DECOY_12,
        &&H_DECOY_13,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_9,
        &&H_AND_RR,
        &&H_SUB_RI,
        &&H_DECOY_11,
        &&H_DECOY_1,
        &&H_DECOY_5,
        &&H_DECOY_4,
        &&H_DECOY_7,
        &&H_DECOY_4,
        &&H_DECOY_11,
        &&H_DECOY_13,
        &&H_DECOY_14,
        &&H_POP_R,
        &&H_DECOY_5,
        &&H_DECOY_10,
        &&H_DECOY_13,
        &&H_DECOY_12,
        &&H_DECOY_8,
        &&H_DECOY_6,
        &&H_DECOY_5,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_XOR_RR,
        &&H_DECOY_0,
        &&H_DECOY_10,
        &&H_XOR_RI,
        &&H_DECOY_3,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_15,
        &&H_DECOY_6,
        &&H_DECOY_11,
        &&H_DECOY_15,
        &&H_DECOY_2,
        &&H_DECOY_14,
        &&H_DECOY_2,
        &&H_CMOV,
        &&H_DECOY_13,
        &&H_CMP_RI,
        &&H_DECOY_0,
        &&H_DECOY_3,
        &&H_DECOY_6,
        &&H_NOP,
        &&H_DECOY_13,
        &&H_DECOY_9,
        &&H_CALL,
        &&H_OR_RR,
        &&H_DECOY_13,
        &&H_DECOY_2,
        &&H_DECOY_7,
        &&H_DECOY_3,
        &&H_DECOY_11,
        &&H_SETCC,
        &&H_DECOY_4,
        &&H_DECOY_8,
        &&H_DECOY_5,
        &&H_DECOY_8,
        &&H_DECOY_15,
        &&H_DECOY_3,
    };

    static const void* const* const all_dispatch_domains[3] = {
        dispatch_domain0,
        dispatch_domain1,
        dispatch_domain2,
    };

    uint64_t word = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;

    #define FETCH_NEXT() do { \
        if (vIP_idx >= count) goto EXIT_VM; \
        uint64_t k = key64_for_offset(seed, vIP_idx); \
        word = bytecode[vIP_idx] ^ k; \
        /* Ephemeral Self-Consuming: Overwrite scratch RAM buffer with rolling noise */ \
        work_bc[vIP_idx] = (k * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL; \
        vIP_idx++; \
        op = (uint8_t)(word & 0xFF); \
        dst = (uint8_t)((word >> 8) & 0x1F); \
        src = (uint8_t)((word >> 13) & 0x1F); \
        imm = (int64_t)((int32_t)((word >> 18) & 0xFFFFFFFFULL)); \
        ctx.evolve_mask((uint32_t)k); \
        uint8_t domain_idx = (uint8_t)((op ^ (uint8_t)(k & 0x07)) % 3); \
        goto *all_dispatch_domains[domain_idx][op]; \
    } while(0)

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
    H_MOV_RI: ctx.set_reg(dst, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_HIGH: {
        uint64_t high_val = (uint64_t)imm << 32;
        ctx.set_reg(dst, (ctx.get_reg(dst) & 0xFFFFFFFFULL) | high_val);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_ADD_RR: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_ADD_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_SUB_RR: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) ^ ctx.get_reg(src)) - 2 * ((~ctx.get_reg(dst)) & ctx.get_reg(src)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
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
    H_XOR_RR: { PROBE_START(); ctx.set_reg(dst, ((ctx.get_reg(dst) + ctx.get_reg(src)) - 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_XOR_RI: { PROBE_START(); ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) ^ (ctx.get_reg(dst) & (uint64_t)imm)); PROBE_CHECK(); ctx.executed_instructions++; FETCH_NEXT(); }
    H_AND_RR: ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) | ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();
    H_AND_RI: ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RR: ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();
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
    H_CMP_RI: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR: {
        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R: ctx.push(ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT();
    H_POP_R: ctx.set_reg(dst, ctx.pop()); ctx.executed_instructions++; FETCH_NEXT();
    H_JMP: {
        vIP_idx = (size_t)imm;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JCC: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        uint64_t t_true = (uint64_t)((word >> 22) & 0x3FF);
        uint64_t t_false = (uint64_t)((word >> 32) & 0x3FF);
        uint64_t c = eval_condition(ctx, cond) ? 1ULL : 0ULL;
        vIP_idx = (size_t)(c * t_true + (1ULL - c) * t_false);
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
        vIP_idx = (size_t)imm;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;
    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;

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
        work_bc[i] = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i);
    }
    return !ctx.trapped;
}

} // namespace vanguard_threaded_vm
