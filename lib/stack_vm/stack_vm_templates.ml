open Jingoo

let env = { Jg_types.std_env with autoescape = false }

let render template models =
  Jg_template.from_string ~env ~models template

let runtime_hpp_template = {|#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#if defined(__APPLE__) && defined(__MACH__)
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#else
#include <dlfcn.h>
#endif

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

typedef struct {
    uint32_t hash;
    uint32_t alt_hash;
    uint16_t len;
    uint8_t enc_bytes[64];
} asgard_ext_sym_t;

{%- if not has_symbols %}
static const asgard_ext_sym_t g_external_symbols[] = { { 0, 0, 0, { 0 } } };
{%- else %}
static const asgard_ext_sym_t g_external_symbols[] = {
{%- for sym in external_symbols %}
    { {{ sym.hash }}U, {{ sym.alt_hash }}U, {{ sym.len }}, { {{ sym.enc_bytes }} } },
{%- endfor %}
};
{%- endif %}

#if defined(__APPLE__) && defined(__MACH__)
static inline uint64_t asg_read_uleb128(const uint8_t** p) {
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

static void* asg_find_sym_in_trie(const uint8_t* trie_base, const uint8_t* node, uint32_t cur_h, uint32_t target_h, uintptr_t base) {
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
        const char* edge_str = (const char*)p;
        p += strlen(edge_str) + 1;
        uint64_t child_offset = asg_read_uleb128(&p);
        uint32_t child_h = cur_h;
        for (const char* c = edge_str; *c; c++) {
            child_h = (child_h ^ (uint8_t)*c) * 0x01000193U;
        }
        void* res = asg_find_sym_in_trie(trie_base, trie_base + child_offset, child_h, target_h, base);
        if (res) return res;
    }
    return nullptr;
}

static void* asgard_resolve_by_api_hash(uint32_t target_hash) {
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
                if (strcmp(seg->segname, "__LINKEDIT") == 0) {
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
#endif

static inline void asg_decrypt_sym(const asgard_ext_sym_t* sym, char* out_buf, size_t out_cap) {
    size_t n = sym->len < out_cap - 1 ? sym->len : out_cap - 1;
    for (size_t i = 0; i < n; i++) {
        uint8_t k = (uint8_t)(0x5A ^ ((i * 17 + 0x33) & 0xFF));
        out_buf[i] = (char)(sym->enc_bytes[i] ^ k);
    }
    out_buf[n] = '\0';
}

static void* asgard_resolve_sym_idx(int32_t sym_idx) {
    if (sym_idx < 0 || (size_t)sym_idx >= sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        return nullptr;
    }
    const asgard_ext_sym_t* sym = &g_external_symbols[sym_idx];
    if (sym->len == 0) return nullptr;

#if defined(__APPLE__) && defined(__MACH__)
    /* 1. Primary: Direct Mach-O export trie walking by 32-bit API Hash (0 imports) */
    void* ptr = asgard_resolve_by_api_hash(sym->hash);
    if (!ptr && sym->alt_hash != 0) {
        ptr = asgard_resolve_by_api_hash(sym->alt_hash);
    }
    if (ptr) return ptr;
#endif

    /* 2. Secondary: Decrypt symbol name on stack */
    char dec_name[64];
    asg_decrypt_sym(sym, dec_name, sizeof(dec_name));
    void* sym_ptr = asgard_resolve_constant(dec_name);

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

#define ASG_UNMASK_OFFSET(bid) ((uint32_t)(g_stack_block_offsets[(bid)] ^ (uint32_t)(0x5877A564UL + (uint32_t)(bid) * 0x19E3779BUL)))
#define ASG_UNMASK_KEY(bid) (g_stack_block_keys[(bid)] ^ (UINT64_C(0xD00F5877A5640000) + (uint64_t)(bid) * UINT64_C(0x9E3779B97F4A7C15)))

static const uint32_t g_stack_block_offsets[{{ block_offsets_count }}] = {
{%- for off in block_offsets %}
    {{ off }},
{%- endfor %}
};

static const uint64_t g_stack_block_keys[{{ block_keys_count }}] = {
{%- for k in block_keys %}
    0x{{ k }}ULL,
{%- endfor %}
};

/* Payload-tag key halves, masked with the same address-binding scheme as the
   block keys above (indices 0 and 1 of the mask64 ladder). The runtime folds
   derive_addr_key() back out, exactly once, in asg_payload_auth_ok. */
static const uint64_t g_stack_tag_keys[2] = {
    0x{{ tag_key0 }}ULL,
    0x{{ tag_key1 }}ULL,
};

#define ASG_UNMASK_TAG_K0() (g_stack_tag_keys[0] ^ (UINT64_C(0xD00F5877A5640000) + UINT64_C(0) * UINT64_C(0x9E3779B97F4A7C15)))
#define ASG_UNMASK_TAG_K1() (g_stack_tag_keys[1] ^ (UINT64_C(0xD00F5877A5640000) + UINT64_C(1) * UINT64_C(0x9E3779B97F4A7C15)))

namespace asgard_stack_vm {

typedef struct {
    uint64_t vsp[4096];
    int vsp_idx;
    uint64_t ctx[{{ context_slots }}];
    uint64_t vkey;
    uint64_t vsp_key;
    uint64_t addr_key;
    size_t bc_size;      /* authenticated image length; every fetch is bound to it */
    uint8_t zf;
    uint8_t sf;
    uint8_t cf;
    uint8_t pf;
    uint8_t of;
    int halted;
    int auth_failed;    /* set when the image did not authenticate; see stack_vm_run */
} stack_vm_t;

static inline uint64_t rotl64(uint64_t v, int k) {
    return (v << (k & 63)) | (v >> ((64 - k) & 63));
}

static inline void step_key(uint64_t *key, uint8_t p) {
    *key = rotl64(*key, 3) + (p ^ 0x5A);
}

/* Every operand fetch goes through here, so this is the single place that
   decides how far into the image the program may reach. Without the bound a
   truncated instruction read up to 8 bytes past the end and kept decoding —
   whatever .rodata followed — as instructions, feeding attacker-chosen bytes
   into the key stream as it went. Reading past the end now halts instead. */
static inline uint8_t fetch_byte(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    if (*vip >= vm->bc_size) {
        vm->halted = 1; /* fail-closed: operand fetch past the image end */
        return 0;
    }
    uint8_t c = bc[(*vip)++];
    uint8_t op = c ^ (uint8_t)(vm->vkey & 0xFF);
    step_key(&vm->vkey, op);
    return op;
}

static inline int16_t fetch_i16(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    uint16_t b0 = fetch_byte(vm, bc, vip);
    uint16_t b1 = fetch_byte(vm, bc, vip);
    return (int16_t)(b0 | (b1 << 8));
}

static inline int32_t fetch_i32(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    uint32_t b0 = fetch_byte(vm, bc, vip);
    uint32_t b1 = fetch_byte(vm, bc, vip);
    uint32_t b2 = fetch_byte(vm, bc, vip);
    uint32_t b3 = fetch_byte(vm, bc, vip);
    return (int32_t)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
}

static inline int64_t fetch_i64(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
    uint64_t res = 0;
    for (int i = 0; i < 8; ++i) {
        uint64_t b = fetch_byte(vm, bc, vip);
        res |= (b << (i * 8));
    }
    return (int64_t)res;
}

/* Phase-2 VSP Whitening: slot mask = vsp_key + slot * 0x9E3779B97F4A7C15ULL
   (vsp_key is static for the whole run — the rolling vkey must NOT be used,
    or key resets at block boundaries desync the encode/decode masks) */
#define VSP_MASK(slot) (vm->vsp_key + (uint64_t)(slot) * UINT64_C(0x9E3779B97F4A7C15))
#define VSP_ENCODE(slot, v) ((v) ^ VSP_MASK(slot))

/* x86-style PF: parity of the low byte of v (1 = even number of set bits) */
static inline uint8_t parity8(uint64_t v) {
    uint8_t x = (uint8_t)(v & 0xFF);
    x ^= x >> 4; x ^= x >> 2; x ^= x >> 1;
    return (~x) & 1;
}

static inline int eval_cond(const stack_vm_t *vm, uint8_t cond) {
    switch (cond) {
        case 0: return vm->zf;
        case 1: return !vm->zf;
        case 2: return vm->cf;
        case 3: return !vm->cf;
        case 4: return vm->cf || vm->zf;
        case 5: return !vm->cf && !vm->zf;
        case 6: return vm->sf;
        case 7: return !vm->sf;
        case 8: return vm->sf != vm->of;
        case 9: return vm->sf == vm->of;
        case 10: return vm->zf || (vm->sf != vm->of);
        case 11: return !vm->zf && (vm->sf == vm->of);
        case 12: return vm->of;
        case 13: return !vm->of;
        case 14: return vm->pf;
        case 15: return !vm->pf;
        case 16: return 1;
        default: return 1;
    }
}

static void h_push_imm(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint64_t imm = (uint64_t)fetch_i64(vm, bytecode, vip);
    if (vm->vsp_idx < 4096) {
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, imm);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: VSP overflow */
    }
}

static void h_push_reg(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    const int max_ctx = (int)(sizeof(vm->ctx) / sizeof(vm->ctx[0]));
    int16_t idx = fetch_i16(vm, bytecode, vip);
    if (vm->vsp_idx < 4096 && idx >= 0 && idx < max_ctx) {
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, vm->ctx[idx]);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: overflow or bad ctx idx */
    }
}

static void h_pop_reg(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    const int max_ctx = (int)(sizeof(vm->ctx) / sizeof(vm->ctx[0]));
    int16_t idx = fetch_i16(vm, bytecode, vip);
    if (vm->vsp_idx > 0 && idx >= 0 && idx < max_ctx) {
        --vm->vsp_idx;
        vm->ctx[idx] = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
    } else {
        vm->halted = 1; /* fail-closed: underflow or bad ctx idx */
    }
}

/* ── Guest memory access policy ────────────────────────────────────────
   READ_MEM/WRITE_MEM pop a VSP value and dereference it. That value is
   ordinary VM data, so without a policy every value that reached the stack
   was a candidate pointer: the image could turn a computed integer into a
   read or write anywhere in the process. An access is admitted only when the
   width is one of the four encodable widths, the address is non-zero,
   naturally aligned for that width, canonical (bits 63:48 are the sign
   extension of bit 47, so an integer cannot wrap through the middle of the
   address space and come out looking like a pointer), and does not run off
   the end of the space. Everything else halts the machine.

   Strictly canonical is an x86-64 notion; AArch64 top-byte-ignore would
   tolerate a non-zero byte 63. Keeping the rule uniform is the point — the
   reference interpreter in stack_eval.ml applies the same predicate.

   The compiler emits these opcodes for guest Push/Pop/Mem operands (lowered
   in ir_to_stack.ml) and ghost passes may emit safe reads against the host
   stack frame. All accesses must strictly satisfy this policy. */
static inline int asg_addr_canonical(uint64_t addr) {
    uint64_t top = addr >> 48;
    return top == ((addr & (UINT64_C(1) << 47)) ? UINT64_C(0xFFFF) : UINT64_C(0));
}

static inline int asg_mem_access_ok(uint64_t addr, uint8_t w) {
    if (w != 1 && w != 2 && w != 4 && w != 8) return 0;
    if (addr == 0) return 0;
    if ((addr & (uint64_t)(w - 1)) != 0) return 0;   /* natural alignment */
    if (!asg_addr_canonical(addr)) return 0;        /* no wrap through the middle */
    if (addr > UINT64_MAX - (uint64_t)(w - 1)) return 0;
    return 1;
}

static void h_read_mem(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint8_t w = fetch_byte(vm, bytecode, vip);
    uint64_t addr = 0;
    int have_addr = 0;
    if (vm->vsp_idx > 0) {
        --vm->vsp_idx;
        addr = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        have_addr = 1;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
    uint64_t val = 0;
    if (have_addr) {
        if (!asg_mem_access_ok(addr, w)) {
            vm->halted = 1; /* fail-closed: address rejected by policy */
        } else if (w == 1) val = *(const uint8_t*)addr;
        else if (w == 2) val = *(const uint16_t*)addr;
        else if (w == 4) val = *(const uint32_t*)addr;
        else val = *(const uint64_t*)addr;
    }
    if (vm->vsp_idx < 4096) {
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, val);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: VSP overflow */
    }
}

static void h_write_mem(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint8_t w = fetch_byte(vm, bytecode, vip);
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t val = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t addr = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        if (!asg_mem_access_ok(addr, w)) {
            vm->halted = 1; /* fail-closed: address rejected by policy */
        } else if (w == 1) *(uint8_t*)addr = (uint8_t)val;
        else if (w == 2) *(uint16_t*)addr = (uint16_t)val;
        else if (w == 4) *(uint32_t*)addr = (uint32_t)val;
        else *(uint64_t*)addr = val;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_add(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = a + b;
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = (res < a);
        vm->of = ((~(a ^ b) & (a ^ res)) >> 63) & 1;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_sub(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = a - b;
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = (a < b);
        vm->of = (((a ^ b) & (a ^ res)) >> 63) & 1;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_mul(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, a * b);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_nor(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = ~(a | b);
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = 0;
        vm->of = 0;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_nand(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = ~(a & b);
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = 0;
        vm->of = 0;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_shl(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t count = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t val = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = val << (count & 63);
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = 0;
        vm->of = 0;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_shr(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t count = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t val = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = val >> (count & 63);
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = 0;
        vm->of = 0;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_sar(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t count = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t val = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = (uint64_t)((int64_t)val >> (count & 63));
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = 0;
        vm->of = 0;
        vm->pf = parity8(res);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_div(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = (b != 0) ? (a / b) : 0;
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_idiv(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        int64_t sa = (int64_t)a, sb = (int64_t)b;
        uint64_t res = (sb == 0 || (sa == INT64_MIN && sb == -1)) ? 0 : (uint64_t)(sa / sb);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_dup(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    /* Dup: decode value from src slot, re-encode at new slot */
    if (vm->vsp_idx > 0 && vm->vsp_idx < 4096) {
        int src = vm->vsp_idx - 1;
        uint64_t decoded = VSP_ENCODE(src, vm->vsp[src]);
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, decoded);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: underflow or overflow */
    }
}

static void h_swap(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    /* Swap: decode both positions, re-encode at swapped positions */
    if (vm->vsp_idx >= 2) {
        int ia = vm->vsp_idx - 1, ib = vm->vsp_idx - 2;
        uint64_t da = VSP_ENCODE(ia, vm->vsp[ia]);
        uint64_t db = VSP_ENCODE(ib, vm->vsp[ib]);
        vm->vsp[ia] = VSP_ENCODE(ia, db);
        vm->vsp[ib] = VSP_ENCODE(ib, da);
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_push_flags(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx < 4096) {
        uint64_t fl = (vm->zf ? 0x40ULL : 0ULL) |
                      (vm->sf ? 0x80ULL : 0ULL) |
                      (vm->cf ? 0x01ULL : 0ULL) |
                      (vm->pf ? 0x04ULL : 0ULL) |
                      (vm->of ? 0x800ULL : 0ULL) | 0x02ULL;
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, fl);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: VSP overflow */
    }
}

static void h_pop_flags(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx > 0) {
        --vm->vsp_idx;
        uint64_t fl = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        vm->cf = (fl & 0x01ULL) != 0;
        vm->pf = (fl & 0x04ULL) != 0;
        vm->zf = (fl & 0x40ULL) != 0;
        vm->sf = (fl & 0x80ULL) != 0;
        vm->of = (fl & 0x800ULL) != 0;
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_jmp_rel(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    int32_t target_bid = fetch_i32(vm, bytecode, vip);
    if (target_bid >= 0 && (size_t)target_bid < sizeof(g_stack_block_offsets)/sizeof(g_stack_block_offsets[0])) {
        *vip = ASG_UNMASK_OFFSET(target_bid);
        vm->vkey = ASG_UNMASK_KEY(target_bid) ^ vm->addr_key;
    } else {
        vm->halted = 1; /* fail-closed: unknown block id */
    }
}

static void h_jcc_rel(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint8_t cond = fetch_byte(vm, bytecode, vip);
    int32_t target_bid = fetch_i32(vm, bytecode, vip);
    if (eval_cond(vm, cond)) {
        if (target_bid >= 0 && (size_t)target_bid < sizeof(g_stack_block_offsets)/sizeof(g_stack_block_offsets[0])) {
            *vip = ASG_UNMASK_OFFSET(target_bid);
            vm->vkey = ASG_UNMASK_KEY(target_bid) ^ vm->addr_key;
        } else {
            vm->halted = 1; /* fail-closed: unknown block id */
        }
    }
}

static void h_key_adjust(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    int64_t delta = fetch_i64(vm, bytecode, vip);
    vm->vkey ^= (uint64_t)delta;
}

static void h_exit(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    vm->halted = 1;
}

static void h_call_extern(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    int32_t sym_idx = fetch_i32(vm, bytecode, vip);
    void* sym_ptr = asgard_resolve_sym_idx(sym_idx);
    if (sym_ptr) {
{%- if is_aarch64 %}
        uint64_t a0 = vm->ctx[0]; /* X0 (RAX) */
        uint64_t a1 = vm->ctx[1]; /* X1 (RCX) */
        uint64_t a2 = vm->ctx[2]; /* X2 (RDX) */
        uint64_t a3 = vm->ctx[3]; /* X3 (RBX) */
        uint64_t a4 = vm->ctx[6]; /* X4 (RSI) */
        uint64_t a5 = vm->ctx[7]; /* X5 (RDI) */
        uint64_t a6 = vm->ctx[8]; /* X6 (R8)  */
        uint64_t a7 = vm->ctx[9]; /* X7 (R9)  */
{%- else %}
        uint64_t a0 = vm->ctx[7]; /* RDI */
        uint64_t a1 = vm->ctx[6]; /* RSI */
        uint64_t a2 = vm->ctx[2]; /* RDX */
        uint64_t a3 = vm->ctx[1]; /* RCX */
        uint64_t a4 = vm->ctx[8]; /* R8  */
        uint64_t a5 = vm->ctx[9]; /* R9  */
        uint64_t a6 = vm->ctx[0]; /* RAX */
        uint64_t a7 = vm->ctx[3]; /* RBX */
{%- endif %}
        typedef uint64_t (*ext_fn_8)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
        uint64_t ret = ((ext_fn_8)sym_ptr)(a0, a1, a2, a3, a4, a5, a6, a7);
        vm->ctx[0] = ret;
    } else {
        vm->halted = 1; /* fail-closed: extern symbol unresolved */
    }
}

static void h_resolve_sym(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    int32_t sym_idx = fetch_i32(vm, bytecode, vip);
    void* sym_ptr = asgard_resolve_sym_idx(sym_idx);
    if (vm->vsp_idx < 4096) {
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, (uint64_t)sym_ptr);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: VSP overflow */
    }
}

static void h_setcc(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint8_t cond = fetch_byte(vm, bytecode, vip);
    uint64_t res = eval_cond(vm, cond) ? 1ULL : 0ULL;
    if (vm->vsp_idx < 4096) {
        vm->vsp[vm->vsp_idx] = VSP_ENCODE(vm->vsp_idx, res);
        ++vm->vsp_idx;
    } else {
        vm->halted = 1; /* fail-closed: VSP overflow */
    }
}

static void h_cmov(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    const int max_ctx = (int)(sizeof(vm->ctx) / sizeof(vm->ctx[0]));
    uint8_t cond = fetch_byte(vm, bytecode, vip);
    int16_t idx = fetch_i16(vm, bytecode, vip);
    if (vm->vsp_idx > 0) {
        --vm->vsp_idx;
        uint64_t v = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        if (eval_cond(vm, cond) && idx >= 0 && idx < max_ctx) {
            vm->ctx[idx] = v;
        }
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_cmp(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = a - b;
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = (a < b);
        vm->of = (((a ^ b) & (a ^ res)) >> 63) & 1;
        vm->pf = parity8(res);
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void h_test(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    (void)bytecode; (void)vip;
    if (vm->vsp_idx >= 2) {
        --vm->vsp_idx;
        uint64_t b = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        --vm->vsp_idx;
        uint64_t a = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
        uint64_t res = a & b;
        vm->zf = (res == 0);
        vm->sf = ((int64_t)res < 0);
        vm->cf = 0;
        vm->of = 0;
        vm->pf = parity8(res);
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
}

static void (*const g_stack_handler_table[])(stack_vm_t *, const uint8_t *, size_t *) = {
    &h_push_imm, &h_push_reg, &h_pop_reg, &h_read_mem, &h_write_mem,
    &h_add, &h_sub, &h_mul, &h_nor, &h_nand,
    &h_shl, &h_shr, &h_sar, &h_div, &h_idiv,
    &h_dup, &h_swap, &h_push_flags, &h_pop_flags, &h_jmp_rel,
    &h_jcc_rel, &h_key_adjust, &h_exit, &h_call_extern, &h_resolve_sym,
    &h_setcc, &h_cmov, &h_cmp, &h_test
};
__attribute__((noinline))
static uint64_t derive_addr_key(void) {
    const size_t n = sizeof(g_stack_handler_table) / sizeof(g_stack_handler_table[0]);
    uint64_t acc = UINT64_C(0x9E3779B97F4A7C15);
#if defined(__clang__)
    #pragma clang loop unroll(disable)
#elif defined(__GNUC__)
    #pragma GCC unroll 0
#endif
    for (size_t i = 0; i + 1 < n; ++i) {
        uint64_t d = (uint64_t)((uintptr_t)g_stack_handler_table[i + 1] - (uintptr_t)g_stack_handler_table[i]);
        acc ^= d + UINT64_C(0x165667B19E3779F9) + (acc << 6) + (acc >> 2);
    }
    return rotl64(acc, 31) ^ UINT64_C(0xA5A5A5A5A5A5A5A5);
}

/* ── Payload authentication ────────────────────────────────────────────
   Mirrors Stack_encoder.payload_tag_of_keys. The rolling key stream is a
   cipher: it keeps the image unreadable but authenticates nothing, so a
   patched image decrypts exactly as well as the original. The tag below is
   what makes the image unforgeable-by-editing, and it is checked here —
   before the first fetch — so a mismatched image never executes a single
   instruction. */
#define ASG_PAYLOAD_TAG UINT64_C(0x{{ payload_tag }})

static inline uint64_t asg_siphash12(uint64_t k0, uint64_t k1, uint64_t m) {
    uint64_t v0 = k0 ^ UINT64_C(0x736F6D6570736575);
    uint64_t v1 = k1 ^ UINT64_C(0x646F72616E646F6D);
    uint64_t v2 = k0 ^ UINT64_C(0x6C7967656E657261);
    uint64_t v3 = k1 ^ UINT64_C(0x7465646279746573);
    v3 ^= m;
    v0 += v1; v1 = rotl64(v1, 13); v1 ^= v0;
    v0 = rotl64(v0, 32);
    v2 += v3; v3 = rotl64(v3, 16); v3 ^= v2;
    v0 += v3; v3 = rotl64(v3, 21); v3 ^= v0;
    v2 += v1; v1 = rotl64(v1, 17); v1 ^= v2;
    v2 = rotl64(v2, 32);
    v0 ^= m;
    v2 ^= UINT64_C(0xFF);
    for (int r = 0; r < 2; ++r) {
        v0 += v1; v1 = rotl64(v1, 13); v1 ^= v0;
        v0 = rotl64(v0, 32);
        v2 += v3; v3 = rotl64(v3, 16); v3 ^= v2;
        v0 += v3; v3 = rotl64(v3, 21); v3 ^= v0;
        v2 += v1; v1 = rotl64(v1, 17); v1 ^= v2;
        v2 = rotl64(v2, 32);
    }
    return v0 ^ v1 ^ v2 ^ v3;
}

static uint64_t asg_payload_tag(uint64_t k0, uint64_t k1, const uint8_t *bc, size_t size) {
    uint64_t acc = asg_siphash12(k0, k1, UINT64_C(0x5041594C4F414421) ^ (uint64_t)size);
    for (size_t i = 0; i < size; i += 8) {
        uint64_t w = 0;
        for (int j = 7; j >= 0; --j) w = (w << 8) | (uint64_t)bc[i + (size_t)j];
        acc = asg_siphash12(k0, k1, acc ^ w);
    }
    return acc;
}

static inline int asg_payload_auth_ok(const uint8_t *bc, size_t size, uint64_t addr_key) {
    if (size == 0 || (size & 7) != 0) return 0;
    uint64_t k0 = ASG_UNMASK_TAG_K0() ^ addr_key;
    uint64_t k1 = ASG_UNMASK_TAG_K1() ^ addr_key;
    /* Constant-time compare: a byte-at-a-time early exit would leak how much
       of a forged tag was right. */
    uint64_t diff = asg_payload_tag(k0, k1, bc, size) ^ ASG_PAYLOAD_TAG;
    return ((diff | (0 - diff)) >> 63) == 0;
}

static inline void stack_vm_run(stack_vm_t *vm, const uint8_t *bytecode, size_t size) {
    vm->bc_size = size;
    if (!asg_payload_auth_ok(bytecode, size, vm->addr_key)) {
        /* Fail-closed, and indistinguishable from an ordinary denial: the
           context is zeroed rather than left holding the caller's arguments,
           so the caller sees the same "not granted" answer, the same exit
           status and the same output as a rejected key. Leaving ctx alone
           would hand back whatever the entry sequence put there — on AArch64
           that is a0, the first argument, so the caller would compute on a
           truncated pointer and exit with a number derived from an address.
           A caller that wants to tell the two cases apart can read
           vm->auth_failed; that is deliberately not something the untrusted
           image can observe or influence. */
        vm->auth_failed = 1;
        vm->halted = 1;
        memset(vm->ctx, 0, sizeof(vm->ctx));
        vm->vsp_idx = 0;
        return;
    }
    size_t vip = ASG_UNMASK_OFFSET({{ entry_bid }});
#if defined(__GNUC__) || defined(__clang__)
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Winitializer-overrides"
    static const void* const dispatch_table[256] = {
        [0 ... 255] = &&lbl_default,
{%- for d in dispatch_cases %}
        [0x{{ d.hex }}] = &&lbl_{{ d.hex }},
{%- endfor %}
    };
    #pragma clang diagnostic pop

    #define ASG_DISPATCH_STEP() do { \
        if (vm->halted || vip >= size) goto lbl_exit; \
        uint8_t op = fetch_byte(vm, bytecode, &vip); \
        goto *dispatch_table[op]; \
    } while (0)

    ASG_DISPATCH_STEP();

{%- for d in dispatch_cases %}
lbl_{{ d.hex }}:
    {{ d.fn }}(vm, bytecode, &vip);
    ASG_DISPATCH_STEP();
{%- endfor %}

lbl_default:
    vm->halted = 1;
    goto lbl_exit;

lbl_exit:
    return;
    #undef ASG_DISPATCH_STEP
#else
    while (!vm->halted && vip < size) {
        uint8_t op = fetch_byte(vm, bytecode, &vip);
        switch (op) {
{%- for d in dispatch_cases %}
            case 0x{{ d.hex }}: /* {{ d.name }} */ { {{ d.fn }}(vm, bytecode, &vip); break; }
{%- endfor %}
            default: vm->halted = 1; break;
        }
    }
#endif
}

static inline uint64_t stack_vm_call(const uint64_t* bc_words, size_t len_words,
                                      uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0,
                                      uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
    stack_vm_t vm;
    memset(&vm, 0, sizeof(vm));
{%- if is_address_bound %}
    vm.addr_key = derive_addr_key();
    vm.vkey = ASG_UNMASK_KEY({{ entry_bid }}) ^ vm.addr_key;
{%- else %}
    vm.vkey = ASG_UNMASK_KEY({{ entry_bid }});
{%- endif %}
    vm.vsp_key = vm.vkey ^ UINT64_C(0x9E3779B97F4A7C15);
    alignas(16) static thread_local uint8_t host_stack[1048576];
    uint64_t sp_val = (uint64_t)(host_stack + sizeof(host_stack) - 8192);
    vm.ctx[4] = sp_val;
    vm.ctx[5] = sp_val;
{%- if is_aarch64 %}
    vm.ctx[0] = a0; /* X0 (RAX) */
    vm.ctx[1] = a1; /* X1 (RCX) */
    vm.ctx[2] = a2; /* X2 (RDX) */
    vm.ctx[3] = a3; /* X3 (RBX) */
    vm.ctx[6] = a4; /* X4 (RSI) */
    vm.ctx[7] = a5; /* X5 (RDI) */
    vm.ctx[8] = a6; /* X6 (R8)  */
    vm.ctx[9] = a7; /* X7 (R9)  */
{%- else %}
    vm.ctx[7] = a0; /* RDI */
    vm.ctx[6] = a1; /* RSI */
    vm.ctx[2] = a2; /* RDX */
    vm.ctx[1] = a3; /* RCX */
    vm.ctx[8] = a4; /* R8  */
    vm.ctx[9] = a5; /* R9  */
    vm.ctx[0] = a6; /* RAX */
    vm.ctx[3] = a7; /* RBX */
{%- endif %}
    const uint8_t* bc_bytes = (const uint8_t*)bc_words;
    stack_vm_run(&vm, bc_bytes, len_words * 8);
    return vm.ctx[0];
}

} // namespace asgard_stack_vm

namespace vanguard_threaded_vm {
    static inline uint64_t asgard_vm_call(const uint64_t* bc, size_t len,
                                          uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0,
                                          uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
        return asgard_stack_vm::stack_vm_call(bc, len, a0, a1, a2, a3, a4, a5, a6, a7);
    }
} // namespace vanguard_threaded_vm
|}

let runner_cpp_template = {|#include "{{ header_name }}"
#include <stdio.h>
#include <stdlib.h>

static uint64_t embedded_bytecode[] = {
{%- for w in words %}
    0x{{ w }}ULL,
{%- endfor %}
};

int main(int argc, char** argv) {
    uint64_t* bc_ptr = embedded_bytecode;
    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    if (argc >= 2) {
        FILE* f = fopen(argv[1], "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (sz > 0 && (sz % 8) == 0) {
                size_t count = (size_t)sz / 8;
                uint64_t* heap_bc = (uint64_t*)malloc((size_t)sz);
                if (heap_bc && fread(heap_bc, 8, count, f) == count) {
                    bc_ptr = heap_bc;
                    bc_len = count;
                }
            }
            fclose(f);
        }
    }
    uint64_t ret = vanguard_threaded_vm::asgard_vm_call(bc_ptr, bc_len);
    printf("[Stack-VM] Execution SUCCESS! Result: %llu\n", (unsigned long long)ret);
    return 0;
}
|}

let probe_cpp_template = {|#include "{{ header_name }}"
#include <stdio.h>

int main(void) {
    printf("ADDR_KEY: %016llX\n", (unsigned long long)asgard_stack_vm::derive_addr_key());
    return 0;
}
|}
