let emit_ephemeral_jit_header () =
  {|#pragma once
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
|}
