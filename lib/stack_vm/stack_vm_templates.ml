open Jingoo

let env = { Jg_types.std_env with autoescape = false }

let render template models =
  Jg_template.from_string ~env ~models template

let runtime_hpp_template = {|#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <stdio.h>

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

{%- if not has_symbols %}
static const char* g_external_symbols[] = { "" };
{%- else %}
static const char* g_external_symbols[] = {
{%- for sym in external_symbols %}
    "{{ sym }}",
{%- endfor %}
};
{%- endif %}

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

namespace asgard_stack_vm {

typedef struct {
    uint64_t vsp[4096];
    int vsp_idx;
    uint64_t ctx[{{ context_slots }}];
    uint64_t vkey;
    uint64_t vsp_key;
    uint64_t addr_key;
    uint8_t zf;
    uint8_t sf;
    uint8_t cf;
    uint8_t pf;
    uint8_t of;
    int halted;
} stack_vm_t;

static inline uint64_t rotl64(uint64_t v, int k) {
    return (v << (k & 63)) | (v >> ((64 - k) & 63));
}

static inline void step_key(uint64_t *key, uint8_t p) {
    *key = rotl64(*key, 3) + (p ^ 0x5A);
}

static inline uint8_t fetch_byte(stack_vm_t *vm, const uint8_t *bc, size_t *vip) {
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

static void h_read_mem(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint8_t w = fetch_byte(vm, bytecode, vip);
    uint64_t addr = 0;
    if (vm->vsp_idx > 0) {
        --vm->vsp_idx;
        addr = VSP_ENCODE(vm->vsp_idx, vm->vsp[vm->vsp_idx]);
    } else {
        vm->halted = 1; /* fail-closed: underflow */
    }
    uint64_t val = 0;
    if (addr != 0) {
        if (w == 1) val = *(const uint8_t*)addr;
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
        if (addr != 0) {
            if (w == 1) *(uint8_t*)addr = (uint8_t)val;
            else if (w == 2) *(uint16_t*)addr = (uint16_t)val;
            else if (w == 4) *(uint32_t*)addr = (uint32_t)val;
            else *(uint64_t*)addr = val;
        }
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
        *vip = g_stack_block_offsets[target_bid];
        vm->vkey = g_stack_block_keys[target_bid] ^ vm->addr_key;
    } else {
        vm->halted = 1; /* fail-closed: unknown block id */
    }
}

static void h_jcc_rel(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    uint8_t cond = fetch_byte(vm, bytecode, vip);
    int32_t target_bid = fetch_i32(vm, bytecode, vip);
    if (eval_cond(vm, cond)) {
        if (target_bid >= 0 && (size_t)target_bid < sizeof(g_stack_block_offsets)/sizeof(g_stack_block_offsets[0])) {
            *vip = g_stack_block_offsets[target_bid];
            vm->vkey = g_stack_block_keys[target_bid] ^ vm->addr_key;
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
    if (sym_idx >= 0 && (size_t)sym_idx < sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        const char* sym_name = g_external_symbols[sym_idx];
        if (sym_name && sym_name[0] != '\0') {
            void* sym_ptr = dlsym(RTLD_DEFAULT, sym_name);
            if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);
            if (!sym_ptr) {
                char alt[256];
                snprintf(alt, sizeof(alt), "_%s", sym_name);
                sym_ptr = dlsym(RTLD_DEFAULT, alt);
            }
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
    }
}

static void h_resolve_sym(stack_vm_t *vm, const uint8_t *bytecode, size_t *vip) {
    int32_t sym_idx = fetch_i32(vm, bytecode, vip);
    void* sym_ptr = nullptr;
    if (sym_idx >= 0 && (size_t)sym_idx < sizeof(g_external_symbols) / sizeof(g_external_symbols[0])) {
        const char* sym_name = g_external_symbols[sym_idx];
        if (sym_name && sym_name[0] != '\0') {
            sym_ptr = dlsym(RTLD_DEFAULT, sym_name);
            if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);
            if (!sym_ptr) {
                char alt[256];
                snprintf(alt, sizeof(alt), "_%s", sym_name);
                sym_ptr = dlsym(RTLD_DEFAULT, alt);
            }
            if (!sym_ptr) {
                sym_ptr = asgard_resolve_constant(sym_name);
            }
        }
    }
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
static uint64_t derive_addr_key(void) {
    const size_t n = sizeof(g_stack_handler_table) / sizeof(g_stack_handler_table[0]);
    uint64_t acc = UINT64_C(0x9E3779B97F4A7C15);
    for (size_t i = 0; i + 1 < n; ++i) {
        uint64_t d = (uint64_t)((uintptr_t)g_stack_handler_table[i + 1] - (uintptr_t)g_stack_handler_table[i]);
        acc ^= d + UINT64_C(0x165667B19E3779F9) + (acc << 6) + (acc >> 2);
    }
    return rotl64(acc, 31) ^ UINT64_C(0xA5A5A5A5A5A5A5A5);
}

static inline void stack_vm_run(stack_vm_t *vm, const uint8_t *bytecode, size_t size) {
    size_t vip = 0;
    while (!vm->halted && vip < size) {
        uint8_t op = fetch_byte(vm, bytecode, &vip);
        switch (op) {
{%- for d in dispatch_cases %}
            case 0x{{ d.hex }}: /* {{ d.name }} */ { {{ d.fn }}(vm, bytecode, &vip); break; }
{%- endfor %}
            default: vm->halted = 1; break;
        }
    }
}

static inline uint64_t stack_vm_call(const uint64_t* bc_words, size_t len_words,
                                      uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0,
                                      uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
    stack_vm_t vm;
    memset(&vm, 0, sizeof(vm));
{%- if is_address_bound %}
    vm.addr_key = derive_addr_key();
    vm.vkey = 0x{{ seed_key_hex }}ULL;
    vm.vkey ^= vm.addr_key;
{%- else %}
    vm.vkey = 0x{{ seed_key_hex }}ULL;
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
