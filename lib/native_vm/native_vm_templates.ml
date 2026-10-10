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
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#elif defined(_WIN32) || defined(_WIN64)
#include <windows.h>
#endif

#ifndef ASGARD_API_HASH_RESOLVER_DEFINED
#define ASGARD_API_HASH_RESOLVER_DEFINED
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

typedef struct {
    uint32_t hash;
    uint32_t alt_hash;
    uint16_t len;
    uint8_t enc_bytes[64];
} asgard_ext_sym_t;

{%- if not has_external_symbols %}
static const asgard_ext_sym_t g_external_symbols[] = { { 0, 0, 0, { 0 } } };
{%- else %}
static const asgard_ext_sym_t g_external_symbols[] = {
{%- for sym in external_symbols %}
    { {{ sym.hash }}U, {{ sym.alt_hash }}U, {{ sym.len }}, { {{ sym.enc_bytes }} } },
{%- endfor %}
};
{%- endif %}

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

{%- if not has_constants %}
static AsgardConstantEntry g_asgard_constants[] = { { 0, 0, nullptr, nullptr, 0, 0, 1 } };
{%- else %}
{%- for c in constants %}
static const uint8_t cdata_enc_{{ c.index }}[] = { {{ c.hex_bytes }}0x00 };
static uint8_t cdata_dec_{{ c.index }}[{{ c.size }} + 1];
{%- endfor %}
static AsgardConstantEntry g_asgard_constants[] = {
{%- for c in constants %}
    { {{ c.hash }}U, {{ c.alt_hash }}U, cdata_enc_{{ c.index }}, cdata_dec_{{ c.index }}, {{ c.size }}, {{ c.xor_key }}U, 0 },
{%- endfor %}
};
{%- endif %}

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

{{ wbox_seed_source }}

{{ context_source }}

#define SCRUB_WORD(ptr, val) do { \
    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
} while(0)

static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = asgard_wbox_derive_seed() /* seed = {{ key_seed_hex }} */, bool scrub_source = false) {
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
    static thread_local asgard_memory::DualMappedBuffer g_ephemeral_jit_buf = asgard_memory::DualMappedBuffer::allocate(16384);
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
                uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)d * 256ULL + (uintptr_t)o) * 0x6A09E667F3BCC908ULL);
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
    uint64_t k_dyn = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;
    size_t next_canary_step = 47 + ((uint64_t)seed & 0x3FULL);

    #define FETCH_NEXT() do { \
        if (__builtin_expect(vIP_idx >= count, 0)) goto EXIT_VM; \
        if (__builtin_expect(ctx.executed_instructions > (count * 10000ULL + 1000000ULL), 0)) { \
            ctx.trapped = true; \
            goto EXIT_VM; \
        } \
        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \
{%- if enable_running_key %}
        k_dyn = k_pos ^ ctx.running_key; \
{%- else %}
        k_dyn = k_pos; \
{%- endif %}
        if (__builtin_expect(ctx.executed_instructions >= next_canary_step, 0)) { \
            if (__builtin_expect(!ctx.verify_canaries(), 0)) { \
                /* Deceptive Delayed Poisoning: silently corrupt register blinding */ \
                ctx.reg_mask ^= (0xCAFEBABE13375877ULL ^ (k_dyn * 0x9E3779B97F4A7C15ULL)) | 1ULL; \
            } \
            /* Dynamic Jitter: unpredictable interval [47..174] derived from state */ \
            next_canary_step = ctx.executed_instructions + 47 + ((k_dyn >> 21) & 0x7FULL); \
        } \
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
        uintptr_t k_slot = ((uintptr_t)seed * 0x517CC1B727220A95ULL) ^ (((uintptr_t)domain_idx * 256ULL + (uintptr_t)op) * 0x6A09E667F3BCC908ULL); \
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
    return execute_threaded(ctx, bytecode, count, asgard_wbox_derive_seed(), scrub_source);
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
    ctx.init(asgard_wbox_derive_seed());
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
