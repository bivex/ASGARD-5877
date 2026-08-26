#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

namespace vanguard_threaded_vm {

static inline uint32_t key_for_offset(uint32_t seed, size_t offset) noexcept {
    uint64_t x = (uint64_t)seed ^ ((uint64_t)offset * 0x9E3779B97F4A7C15ULL);
    uint32_t x32 = (uint32_t)x;
    x32 ^= x32 << 13;
    x32 ^= x32 >> 17;
    x32 ^= x32 << 5;
    return x32 == 0 ? 0x1337BEEFU : x32;
}

struct VMContext {
    uint64_t gprs[32]; // 0..15: GPRs, 16..19: VTMPs, 20: vIP, 21: vSP
    uint64_t stack[512];
    size_t sp;
    bool cf, zf, sf, of;
    bool trapped;
    size_t executed_instructions;

    inline void push(uint64_t v) noexcept { if (sp < 512) stack[sp++] = v; }
    inline uint64_t pop() noexcept { return sp > 0 ? stack[--sp] : 0ULL; }
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

__attribute__((always_inline, visibility("hidden"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x11074F6FU) {
    const uint64_t* vIP = bytecode;
    const uint64_t* vIP_end = bytecode + count;

    static const void* const dispatch_table[256] = {
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_IMUL_RI,
        &&H_RET,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_OR_RI,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_OR_RR,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_JMP,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_MOV_RR,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_EXIT,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_CMP_RR,
        &&H_PUSH_R,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_AND_RR,
        &&H_DECOY,
        &&H_DECOY,
        &&H_SUB_RR,
        &&H_XOR_RR,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_ADD_RI,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_XOR_RI,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_SUB_RI,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_CMP_RI,
        &&H_AND_RI,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_MOV_RI,
        &&H_DECOY,
        &&H_DECOY,
        &&H_CMOV,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_JCC,
        &&H_NOP,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_POP_R,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_IMUL_RR,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_ADD_RR,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
        &&H_DECOY,
    };

    uint64_t word = 0;
    uint8_t op = 0;
    uint8_t dst = 0;
    uint8_t src = 0;
    int64_t imm = 0;

    #define FETCH_NEXT() do { \
        if (vIP >= vIP_end) goto EXIT_VM; \
        size_t off = (size_t)(vIP - bytecode); \
        uint32_t k = key_for_offset(seed, off); \
        word = *vIP++ ^ (uint64_t)((int64_t)((int32_t)k)); \
        op = (uint8_t)(word & 0xFF); \
        dst = (uint8_t)((word >> 8) & 0x1F); \
        src = (uint8_t)((word >> 13) & 0x1F); \
        imm = (int64_t)((int32_t)((word >> 18) & 0xFFFFFFFFULL)); \
        goto *dispatch_table[op]; \
    } while(0)

    FETCH_NEXT();

    H_NOP: ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RR: ctx.gprs[dst] = ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_MOV_RI: ctx.gprs[dst] = (uint64_t)imm; ctx.executed_instructions++; FETCH_NEXT();
    H_ADD_RR: ctx.gprs[dst] += ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_ADD_RI: ctx.gprs[dst] += imm; ctx.executed_instructions++; FETCH_NEXT();
    H_SUB_RR: ctx.gprs[dst] -= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_SUB_RI: ctx.gprs[dst] -= imm; ctx.executed_instructions++; FETCH_NEXT();
    H_IMUL_RR: ctx.gprs[dst] *= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_IMUL_RI: ctx.gprs[dst] *= imm; ctx.executed_instructions++; FETCH_NEXT();
    H_XOR_RR: ctx.gprs[dst] ^= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_XOR_RI: ctx.gprs[dst] ^= imm; ctx.executed_instructions++; FETCH_NEXT();
    H_AND_RR: ctx.gprs[dst] &= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_AND_RI: ctx.gprs[dst] &= imm; ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RR: ctx.gprs[dst] |= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();
    H_OR_RI: ctx.gprs[dst] |= imm; ctx.executed_instructions++; FETCH_NEXT();
    H_CMP_RI: {
        uint64_t a = ctx.gprs[dst]; uint64_t b = (uint64_t)imm;
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMP_RR: {
        uint64_t a = ctx.gprs[dst]; uint64_t b = ctx.gprs[src];
        uint64_t res = a - b;
        ctx.zf = (res == 0);
        ctx.sf = ((int64_t)res < 0);
        ctx.cf = (a < b);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_PUSH_R: ctx.push(ctx.gprs[dst]); ctx.executed_instructions++; FETCH_NEXT();
    H_POP_R: ctx.gprs[dst] = ctx.pop(); ctx.executed_instructions++; FETCH_NEXT();
    H_JMP: {
        vIP = bytecode + imm;
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_JCC: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        uint16_t t_true = (uint16_t)((word >> 22) & 0x3FF);
        uint16_t t_false = (uint16_t)((word >> 32) & 0x3FF);
        vIP = bytecode + (eval_condition(ctx, cond) ? t_true : t_false);
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_CMOV: {
        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);
        if (eval_condition(ctx, cond)) ctx.gprs[dst] = ctx.gprs[src];
        ctx.executed_instructions++; FETCH_NEXT();
    }
    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;
    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;

    H_DECOY:
        ctx.trapped = true;
        goto EXIT_VM;

    EXIT_VM:
    return !ctx.trapped;
}

} // namespace vanguard_threaded_vm
