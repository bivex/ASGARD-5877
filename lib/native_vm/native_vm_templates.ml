open Jingoo

let env = { Jg_types.std_env with autoescape = false }

let render template models =
  Jg_template.from_string ~env ~models template

let threaded_header_template = {|#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
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
#elif defined(__linux__)
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#elif defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#endif

{%- if enable_vector_isa %}
#define ASGARD_VECTOR_ISA 1
#if defined(__aarch64__)
#include <arm_neon.h>
#elif defined(__x86_64__)
#include <immintrin.h>
#endif
{%- endif %}

{{ rns_header }}

{%- if enable_direct_syscalls %}
{{ direct_syscalls_header }}
{%- endif %}

{%- if enable_anti_emu %}
{{ anti_emulation_header }}
{%- endif %}

{{ dual_mapping_header }}

{%- if enable_smc %}
{%- if enable_smc_strict %}
#define ASGARD_SMC_STRICT 1
{%- endif %}
{{ smc_header }}
{%- endif %}

{%- if enable_mem_scan %}
{{ mem_scan_header }}
{%- else %}
namespace asgard_mem_integrity {
    static inline uint64_t compute_section_integrity_hash() noexcept { return 0x5877CAFE1337BEEFULL; }
    static inline uint64_t evaluate_memory_integrity() noexcept { return 0; }
}
{%- endif %}

{%- if enable_nanomites %}
{{ nanomite_header }}
{%- endif %}

{%- if enable_ephemeral_jit %}
#define ASGARD_EPHEMERAL_JIT 1
{{ ephemeral_jit_header }}
{%- endif %}

{%- if has_gpu_constants %}
{{ gpu_constants }}
{%- endif %}

namespace vanguard_threaded_vm {

{%- if enable_address_bound %}
#define ASGARD_ADDRESS_BOUND_BYTECODE 1
static const size_t g_num_blocks = {{ num_blocks }};
static const size_t g_block_offsets[] = {
{%- for b in block_spans %}
    {{ b.off }},
{%- endfor %}
};
static const size_t g_block_lengths[] = {
{%- for b in block_spans %}
    {{ b.len }},
{%- endfor %}
};
{%- endif %}

static const char* const g_external_symbols[] = {
{%- if not has_external_symbols %}
    ""
{%- else %}
{%- for s in external_symbols %}
    "{{ s }}",
{%- endfor %}
{%- endif %}
};

struct AsgardConstantEntry {
    const char* name;
    const uint8_t* data;
    size_t size;
};

{%- if not has_constants %}
static const AsgardConstantEntry g_asgard_constants[] = { { "", nullptr, 0 } };
{%- else %}
{%- for c in constants %}
static const uint8_t cdata_{{ c.index }}[] = { {{ c.hex_bytes }}0x00 };
{%- endfor %}
static const AsgardConstantEntry g_asgard_constants[] = {
{%- for c in constants %}
    { "{{ c.escaped_name }}", cdata_{{ c.index }}, {{ c.size }} },
{%- endfor %}
};
{%- endif %}

static inline void* asgard_resolve_constant(const char* name) {
    if (!name || name[0] == '\0') return nullptr;
    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {
        if (g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name) == 0) return (void*)g_asgard_constants[i].data;
        if (name[0] == '_' && g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name + 1) == 0) return (void*)g_asgard_constants[i].data;
    }
    return nullptr;
}

{{ context_source }}

#define SCRUB_WORD(ptr, val) do { \
    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
} while(0)

static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = {{ key_seed_hex }}, bool scrub_source = false) {
    if (ctx.reg_mask == 0) ctx.init(seed);
{%- if enable_nanomites %}
    /* Nanomite Hardware Signal Dispatcher (Hardware TRAP/Branch Interceptor) */
    asgard_nanomites::install_nanomite_handlers(seed);
{%- endif %}
    /* High-Speed Continuous Keyed Poly-Hash Bytecode Integrity Guard */
    uint64_t full_hash = {{ poly_init_hex }};
    for (size_t i = 0; i < count; ++i) {
        full_hash = ((full_hash ^ bytecode[i]) * {{ poly_multiplier_hex }}) + (uint64_t)i;
    }
{%- if has_multi_hashes %}
    static const uint64_t valid_hashes[] = {
{%- for h in expected_hashes %}
        {{ h }},
{%- endfor %}
    };
    bool hash_ok = false;
    for (size_t hi = 0; hi < sizeof(valid_hashes)/sizeof(valid_hashes[0]); ++hi) {
        if (full_hash == valid_hashes[hi]) { hash_ok = true; break; }
    }
    if (!hash_ok) {
        /* Anti-Patching Tripwire: Silent Context Poisoning */
        ctx.reg_mask ^= 0xDEADBEEF5A5A5A5AULL ^ full_hash;
        ctx.trapped = true;
        return false;
    }
{%- else %}
    uint64_t hash_diff = full_hash ^ {{ expected_hash_hex }};
    if (hash_diff != 0) {
        /* Anti-Patching Tripwire: Silent Context Poisoning */
        ctx.reg_mask ^= (hash_diff * 0x5877CAFEBEEFULL) ^ 0xDEADBEEF5A5A5A5AULL;
        ctx.trapped = true;
        return false;
    }
{%- endif %}

{%- if enable_direct_syscalls %}
    /* Active Anti-Debugging Probe (Bypassing libc via Direct Kernel Syscalls) */
    if (asgard_syscalls::sys_check_debugger_present()) {
        ctx.reg_mask ^= 0xCAFEBABE13375877ULL;
        ctx.trapped = true;
        return false;
    }
{%- else %}
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
{%- endif %}

{%- if enable_anti_emu %}
    /* Anti-Emulation & Hypervisor Timing Differential Probe */
    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();
    if (emu_penalty != 0) {
        ctx.reg_mask ^= emu_penalty;
    }
{%- endif %}

{%- if enable_smc %}
    /* Introspective Self-Modifying Code (SMC) & Hardware Timing Probe (Morse & Kojsik, 2026) */
    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe((uint64_t)seed);
    if (smc_penalty != 0) {
        ctx.reg_mask ^= smc_penalty;
    }
{%- endif %}

{%- if enable_mem_scan %}
    /* In-Memory MEM-SBOM Forensics & Hardware Breakpoint Probe */
    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();
    if (mem_penalty != 0) {
        ctx.reg_mask ^= mem_penalty;
    }
{%- endif %}

    /* Ephemeral Working Buffer: Isolated stack frame execution */
    uint64_t stack_buf[256];
    uint64_t* work_bc = (count <= 256) ? stack_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));
{%- if enable_mem_sanitize %}
    for (size_t i = 0; i < count; ++i) work_bc[i] = 0x5877CAFE1337BEEFULL ^ ((uint64_t)seed + (uint64_t)i);
{%- else %}
    for (size_t i = 0; i < count; ++i) work_bc[i] = bytecode[i];
{%- endif %}

    size_t vIP_idx = 0;

{%- if enable_ephemeral_jit %}
#if defined(ASGARD_EPHEMERAL_JIT)
    static thread_local asgard_memory::DualMappedBuffer g_ephemeral_jit_buf = asgard_memory::DualMappedBuffer::allocate(4096);
#endif
{%- endif %}

    static uintptr_t all_dispatch_domains[{{ num_domains }}][256];
    static bool dispatch_domains_ready = false;
    if (__builtin_expect(!dispatch_domains_ready, 0)) {
{%- for domain in dispatch_domains %}
        static void* raw_domain{{ domain.index }}[256] = {
{%- for h in domain.handlers %}
            &&{{ h }},
{%- endfor %}
        };
{%- endfor %}
        static void** const raw_all_domains[{{ num_domains }}] = {
{%- for domain in dispatch_domains %}
            raw_domain{{ domain.index }},
{%- endfor %}
        };
        for (size_t d = 0; d < {{ num_domains }}; ++d) {
            for (size_t o = 0; o < 256; ++o) {
                uintptr_t k_slot = ((uintptr_t){{ key_seed_hex }} * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
                all_dispatch_domains[d][o] = (uintptr_t)raw_all_domains[d][o] ^ k_slot;
                *(reinterpret_cast<volatile uintptr_t*>(&raw_all_domains[d][o])) = k_slot ^ 0xDEADBEEF5A5A5A5AULL;
            }
        }
        dispatch_domains_ready = true;
    }

    uint64_t g_handlers_hash = compute_handlers_hash((const uintptr_t*)all_dispatch_domains, {{ num_domains }});

{%- if enable_address_bound %}
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
            uint8_t b_op = (uint8_t)(((plain + 0xFFULL) - (plain | 0xFFULL)));
            uint8_t b_dst = (uint8_t)((((plain >> 8) + 0x1FULL) - ((plain >> 8) | 0x1FULL)));
            int64_t b_imm = (int64_t)((int32_t)((((plain >> 18) + 0xFFFFFFFFULL) - ((plain >> 18) | 0xFFFFFFFFULL))));
            rk = VMContext::advance_key_step(rk, b_op, b_dst, b_imm);
        }
    }
{%- endif %}

    uint64_t word = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;

    #define FETCH_NEXT() do { \
        if (__builtin_expect(vIP_idx >= count, 0)) goto EXIT_VM; \
        if (__builtin_expect(ctx.executed_instructions > (count * 10000ULL + 1000000ULL), 0)) { \
            ctx.trapped = true; \
            goto EXIT_VM; \
        } \
        if (__builtin_expect((vIP_idx & 0x7F) == 0 && !ctx.verify_canaries(), 0)) { \
            ctx.trapped = true; \
            ctx.reg_mask ^= 0xCAFEBABE13375877ULL; \
            goto EXIT_VM; \
        } \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
{%- if enable_running_key %}
        uint64_t k_dyn = k_pos ^ ctx.running_key; \
{%- else %}
        uint64_t k_dyn = k_pos; \
{%- endif %}
{%- if enable_address_bound %}
        work_bc[vIP_idx] = bound_bc[vIP_idx]; \
{%- else %}
        work_bc[vIP_idx] = bytecode[vIP_idx]; \
{%- endif %}
        word = work_bc[vIP_idx] ^ k_dyn; \
{%- if enable_mem_sanitize %}
        /* Ephemeral Self-Consuming: Overwrite scratch RAM buffer with dynamic rolling noise */ \
        SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL); \
{%- endif %}
        vIP_idx++; \
        op = (uint8_t)(((word + 0xFFULL) - (word | 0xFFULL))); \
        dst = (uint8_t)((((word >> 8) + 0x1FULL) - ((word >> 8) | 0x1FULL))); \
        src = (uint8_t)((((word >> 13) + 0x1FULL) - ((word >> 13) | 0x1FULL))); \
        imm = (int64_t)((int32_t)((((word >> 18) + 0xFFFFFFFFULL) - ((word >> 18) | 0xFFFFFFFFULL)))); \
        ctx.evolve_mask((uint32_t)k_dyn); \
{%- if enable_running_key %}
        ctx.advance_running_key(op, dst, imm); \
{%- endif %}
        uint8_t domain_idx = (uint8_t)((op ^ (uint8_t)(k_dyn & 0x07)) % {{ num_domains }}); \
        uintptr_t k_slot = ((uintptr_t){{ key_seed_hex }} * 0x517CC1B727220A95ULL) ^ (((uintptr_t)domain_idx * 256ULL + (uintptr_t)op) * 0x6A09E667F3BCC908ULL); \
        void* target = (void*)(all_dispatch_domains[domain_idx][op] ^ k_slot); \
        goto *target; \
    } while(0)

{%- if enable_running_key %}
{%- if enable_address_bound %}
    ctx.reanchor_running_key(0, g_handlers_hash);
{%- else %}
    ctx.reanchor_running_key(0);
{%- endif %}
{%- endif %}
    FETCH_NEXT();

{{ handlers_source }}

    EXIT_VM:
{%- if enable_mem_sanitize %}
    /* Ephemeral Complete Memory Sanitization: Scrub all working memory */
    for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&work_bc[i], 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i));
    }
{%- if enable_address_bound %}
    for (size_t i = 0; i < count; ++i) {
        SCRUB_WORD(&bound_bc[i], 0xDEADBEEF5877CAFEULL ^ ((uint64_t)seed + (uint64_t)i));
    }
{%- endif %}
    if (scrub_source && bytecode) {
        for (size_t i = 0; i < count; ++i) {
            SCRUB_WORD(&const_cast<uint64_t*>(bytecode)[i], 0xDEADBEEFCAFEBABEULL ^ ((uint64_t)seed + (uint64_t)i));
        }
    }
{%- endif %}
    return !ctx.trapped;
}

static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, bool scrub_source) {
    return execute_threaded(ctx, bytecode, count, {{ key_seed_hex }}, scrub_source);
}

#if defined(__GNUC__) || defined(__clang__)
#define ASG_CALL_NOINLINE __attribute__((noinline))
#elif defined(_MSC_VER)
#define ASG_CALL_NOINLINE __declspec(noinline)
#else
#define ASG_CALL_NOINLINE
#endif

static ASG_CALL_NOINLINE uint64_t asgard_vm_call(const uint64_t* bc, size_t len, uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0, uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init({{ key_seed_hex }});
    alignas(16) static thread_local uint8_t host_stack[1048576];
    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(host_stack + sizeof(host_stack) - 8192));
    ctx.set_reg(vanguard_threaded_vm::REG_RBP, (uint64_t)(host_stack + sizeof(host_stack) - 8192));
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
    return ((ret_val ^ 0x5877CAFE1337BEEFULL) + 2ULL * (ret_val & 0x5877CAFE1337BEEFULL)) - 0x5877CAFE1337BEEFULL;
}

} // namespace vanguard_threaded_vm
|}

let runner_template = {|#include "threaded_vm.hpp"
#include <stdio.h>
#include <stdlib.h>

/* Self-contained embedded encrypted bytecode (Mutable for Ephemeral Memory Scrubbing) */
static uint64_t embedded_bytecode[] = {
{%- for w in bytecode_words %}
    {{ w }},
{%- endfor %}
};

int main(int argc, char** argv) {
    uint64_t* bc_ptr = embedded_bytecode;
    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    uint64_t* heap_bc = NULL;

    if (argc >= 2) {
        FILE* f = fopen(argv[1], "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (sz > 0 && (sz % 8) == 0) {
                size_t count = (size_t)sz / 8;
                heap_bc = (uint64_t*)malloc((size_t)sz);
                if (heap_bc && fread(heap_bc, 8, count, f) == count) {
                    bc_ptr = heap_bc;
                    bc_len = count;
                }
            }
            fclose(f);
        }
    }

    vanguard_threaded_vm::VMContext ctx = {};
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr, bc_len, true);
    if (heap_bc) {
        /* Ephemeral Heap Sanitization: Scrub all dynamically allocated bytecode before free */
        for (size_t i = 0; i < bc_len; ++i) {
            SCRUB_WORD(&heap_bc[i], 0xDEADBEEFCAFEBABEULL ^ (uint64_t)i);
        }
        free(heap_bc);
    }

    if (!ok) return 2;
    printf("[VM] Execution SUCCESS! Verified %zu instructions. RAX: %llu\n",
           ctx.executed_instructions, (unsigned long long)ctx.get_rax());
    return 0;
}
|}
