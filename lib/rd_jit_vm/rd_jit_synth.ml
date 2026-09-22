let header () =
  {|
enum JITOpKind : uint8_t {
    JIT_OP_NOP = 0,
    JIT_OP_MOV_RR,
    JIT_OP_MOV_RI,
    JIT_OP_ADD_RR,
    JIT_OP_ADD_RI,
    JIT_OP_SUB_RR,
    JIT_OP_SUB_RI,
    JIT_OP_MUL_RR,
    JIT_OP_MUL_RI,
    JIT_OP_XOR_RR,
    JIT_OP_XOR_RI,
    JIT_OP_AND_RR,
    JIT_OP_AND_RI,
    JIT_OP_OR_RR,
    JIT_OP_OR_RI,
    JIT_OP_RET,
    JIT_OP_EXIT
};

struct JITInstr {
    uint8_t op;
    uint8_t dst;
    uint8_t src;
    uint64_t imm;
};

struct JITBlock {
    uint32_t id;
    uint32_t count;
    const JITInstr* instrs;
};

typedef void (*JITBlockFn)(RD_JIT_Context* ctx);

#if defined(__aarch64__)
static inline void emit_arm64_imm(uint32_t* code, size_t& idx, uint8_t reg, uint64_t imm) {
    uint32_t w0 = (uint32_t)(imm & 0xFFFFULL);
    uint32_t w1 = (uint32_t)((imm >> 16) & 0xFFFFULL);
    uint32_t w2 = (uint32_t)((imm >> 32) & 0xFFFFULL);
    uint32_t w3 = (uint32_t)((imm >> 48) & 0xFFFFULL);
    code[idx++] = 0xd2800000 | (w0 << 5) | reg; // movz reg, #w0, lsl 0
    if (w1 != 0 || (w2 == 0 && w3 == 0 && imm > 0xFFFFULL))
        code[idx++] = 0xf2a00000 | (w1 << 5) | reg; // movk reg, #w1, lsl 16
    if (w2 != 0 || (w3 == 0 && imm > 0xFFFFFFFFULL))
        code[idx++] = 0xf2c00000 | (w2 << 5) | reg; // movk reg, #w2, lsl 32
    if (w3 != 0)
        code[idx++] = 0xf2e00000 | (w3 << 5) | reg; // movk reg, #w3, lsl 48
}
#endif

static inline void synthesize_and_execute_block(DualMappedJITBuffer& jit, RD_JIT_Context& ctx, const JITBlock& block) {
    jit.begin_synthesis();
    size_t code_bytes = 0;

#if defined(__aarch64__)
    uint32_t* code = (uint32_t*)jit.get_write_ptr();
    size_t idx = 0;

    for (uint32_t i = 0; i < block.count; ++i) {
        const JITInstr& in = block.instrs[i];
        uint8_t dst_off = in.dst * 8;
        uint8_t src_off = in.src * 8;
        switch (in.op) {
            case JIT_OP_NOP:
                code[idx++] = 0xd503201f; // nop
                break;
            case JIT_OP_MOV_RR:
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 9; // ldr x9, [x0, #src_off]
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9; // str x9, [x0, #dst_off]
                break;
            case JIT_OP_MOV_RI:
                emit_arm64_imm(code, idx, 9, in.imm);
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_ADD_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;  // ldr x9, [x0, #dst_off]
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10; // ldr x10, [x0, #src_off]
                code[idx++] = 0x8b0a0129; // add x9, x9, x10
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;  // str x9, [x0, #dst_off]
                break;
            case JIT_OP_ADD_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0x8b0a0129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SUB_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0xcb0a0129; // sub x9, x9, x10
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SUB_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0xcb0a0129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_MUL_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9b0a7d29; // mul x9, x9, x10
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_MUL_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0x9b0a7d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_XOR_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0xca0a0129; // eor x9, x9, x10
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_XOR_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0xca0a0129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_RET:
            case JIT_OP_EXIT:
                break;
            default:
                break;
        }
    }
    code[idx++] = 0xd65f03c0; // ret
    code_bytes = idx * sizeof(uint32_t);
#elif defined(__x86_64__)
    uint8_t* code = (uint8_t*)jit.get_write_ptr();
    size_t idx = 0;

    auto emit_u64 = [&](uint64_t v) {
        for (int b = 0; b < 8; ++b) {
            code[idx++] = (uint8_t)((v >> (b * 8)) & 0xFF);
        }
    };

    for (uint32_t i = 0; i < block.count; ++i) {
        const JITInstr& in = block.instrs[i];
        uint8_t dst_off = in.dst * 8;
        uint8_t src_off = in.src * 8;
        switch (in.op) {
            case JIT_OP_NOP:
                code[idx++] = 0x90; // nop
                break;
            case JIT_OP_MOV_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = src_off; // mov rax, [rdi + src_off]
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off; // mov [rdi + dst_off], rax
                break;
            case JIT_OP_MOV_RI:
                code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm); // mov rax, imm
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_ADD_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xd0; // add rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_ADD_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xd0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SUB_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x29; code[idx++] = 0xd0; // sub rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SUB_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x29; code[idx++] = 0xd0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_MUL_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x0f; code[idx++] = 0xaf; code[idx++] = 0xc2; // imul rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_XOR_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x31; code[idx++] = 0xd0; // xor rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_XOR_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x31; code[idx++] = 0xd0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_RET:
            case JIT_OP_EXIT:
                break;
            default:
                break;
        }
    }
    code[idx++] = 0xc3; // ret
    code_bytes = idx;
#else
    for (uint32_t i = 0; i < block.count; ++i) {
        const JITInstr& in = block.instrs[i];
        switch (in.op) {
            case JIT_OP_MOV_RR: ctx.set_reg(in.dst, ctx.get_reg(in.src)); break;
            case JIT_OP_MOV_RI: ctx.set_reg(in.dst, in.imm); break;
            case JIT_OP_ADD_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) + ctx.get_reg(in.src)); break;
            case JIT_OP_ADD_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) + in.imm); break;
            case JIT_OP_SUB_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) - ctx.get_reg(in.src)); break;
            case JIT_OP_SUB_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) - in.imm); break;
            case JIT_OP_MUL_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) * ctx.get_reg(in.src)); break;
            case JIT_OP_MUL_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) * in.imm); break;
            case JIT_OP_XOR_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) ^ ctx.get_reg(in.src)); break;
            case JIT_OP_XOR_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) ^ in.imm); break;
            default: break;
        }
    }
    return;
#endif

    if (code_bytes > 0) {
        // Commit and flush cache
        jit.commit_and_flush(code_bytes);

        // Execute natively via RX view
        JITBlockFn fn = (JITBlockFn)jit.get_exec_ptr();
        fn(&ctx);

        // Synchronize RNS-4 residue channels post-execution
        for (size_t r = 0; r < 16; ++r) {
            ctx.vregs[r].set(ctx.gprs[r]);
        }

        // Atomic Zeroize machine code
        jit.atomic_zeroize(code_bytes);
    }
}

static inline void execute_jit_function(DualMappedJITBuffer& jit, RD_JIT_Context& ctx, const JITBlock* blocks, size_t num_blocks) {
    for (size_t b = 0; b < num_blocks; ++b) {
        synthesize_and_execute_block(jit, ctx, blocks[b]);
    }
}

static inline void execute_ephemeral_block(DualMappedJITBuffer& jit, RD_JIT_Context& ctx, uint64_t op_a, uint64_t op_b) {
    ctx.set_reg(0, op_a);
    ctx.set_reg(1, op_b);
    static const JITInstr add_block_instrs[] = {
        { JIT_OP_ADD_RR, 0, 1, 0 },
        { JIT_OP_RET, 0, 0, 0 }
    };
    static const JITBlock add_block = { 0, 2, add_block_instrs };
    synthesize_and_execute_block(jit, ctx, add_block);
}

} // namespace asgard_rd_jit

namespace vanguard_threaded_vm {
    typedef asgard_rd_jit::RD_JIT_Context VMContext;
    static inline void execute_threaded(VMContext& ctx, const uint64_t* bc, size_t len) {
        asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);
        asgard_rd_jit::execute_ephemeral_block(jit_buf, ctx, ctx.get_reg(0), ctx.get_reg(1));
    }
}
|}
