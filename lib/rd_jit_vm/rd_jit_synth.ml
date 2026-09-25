let external_symbols_header symbols =
  let entries =
    match symbols with
    | [] -> [ "    \"\"" ]
    | xs -> List.map (fun s -> Printf.sprintf "    \"%s\"" (String.escaped s)) xs
  in
  "static const char* const g_rd_jit_external_symbols[] = {\n"
  ^ String.concat ",\n" entries
  ^ "\n};\n\n"

let header ?(external_symbols = []) () =
  ignore external_symbols;
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
    JIT_OP_CALL_EXTERN,
    JIT_OP_XOR_RR,
    JIT_OP_XOR_RI,
    JIT_OP_AND_RR,
    JIT_OP_AND_RI,
    JIT_OP_OR_RR,
    JIT_OP_OR_RI,
    JIT_OP_SHL_RI,
    JIT_OP_SHR_RI,
    JIT_OP_SAR_RI,
    JIT_OP_NOT_R,
    JIT_OP_NEG_R,
    JIT_OP_LOAD_64,
    JIT_OP_STORE_64,
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

#include <stdio.h>
#include <string.h>
#if !defined(_WIN32) && !defined(_WIN64)
#include <dlfcn.h>
#endif

static inline void asgard_rd_jit_call_extern(RD_JIT_Context* ctx, uint64_t sym_idx) {
    const size_t count = sizeof(g_rd_jit_external_symbols) / sizeof(g_rd_jit_external_symbols[0]);
    if (!ctx || sym_idx >= count || g_rd_jit_external_symbols[sym_idx][0] == '\0') return;
    const char* sym_name = g_rd_jit_external_symbols[sym_idx];
    void* sym_ptr = nullptr;
#if !defined(_WIN32) && !defined(_WIN64)
    sym_ptr = dlsym(RTLD_DEFAULT, sym_name);
    if (!sym_ptr && sym_name[0] == '_') sym_ptr = dlsym(RTLD_DEFAULT, sym_name + 1);
    if (!sym_ptr) {
        char alt_name[256];
        snprintf(alt_name, sizeof(alt_name), "_%s", sym_name);
        sym_ptr = dlsym(RTLD_DEFAULT, alt_name);
    }
#endif
    if (!sym_ptr) return;
    const char* clean_name = (sym_name[0] == '_') ? sym_name + 1 : sym_name;
    const uint64_t a0 = ctx->gprs[0];
    const uint64_t a1 = ctx->gprs[1];
    const uint64_t a2 = ctx->gprs[2];
    const uint64_t a3 = ctx->gprs[3];
    const uint64_t a4 = ctx->gprs[4];
    const uint64_t a5 = ctx->gprs[5];
    const uint64_t a6 = ctx->gprs[6];
    const uint64_t a7 = ctx->gprs[7];
    const uint64_t* stk = reinterpret_cast<const uint64_t*>(ctx->gprs[4]);
    uint64_t ret = 0;
#if defined(__APPLE__) && defined(__aarch64__)
    if (strcmp(clean_name, "printf") == 0) {
        typedef int (*printf_fn_t)(const char*, ...);
        ret = (uint64_t)reinterpret_cast<printf_fn_t>(sym_ptr)((const char*)a0, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
    } else if (strcmp(clean_name, "fprintf") == 0 || strcmp(clean_name, "dprintf") == 0) {
        typedef int (*fprintf_fn_t)(void*, const char*, ...);
        ret = (uint64_t)reinterpret_cast<fprintf_fn_t>(sym_ptr)((void*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
    } else if (strcmp(clean_name, "sprintf") == 0) {
        typedef int (*sprintf_fn_t)(char*, const char*, ...);
        ret = (uint64_t)reinterpret_cast<sprintf_fn_t>(sym_ptr)((char*)a0, (const char*)a1, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
    } else if (strcmp(clean_name, "snprintf") == 0) {
        typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
        ret = (uint64_t)reinterpret_cast<snprintf_fn_t>(sym_ptr)((char*)a0, (size_t)a1, (const char*)a2, stk[0], stk[1], stk[2], stk[3], stk[4], stk[5], stk[6], stk[7]);
    } else {
        typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
        ret = reinterpret_cast<extern_fn_t>(sym_ptr)(a0, a1, a2, a3, a4, a5, a6, a7);
    }
#else
    if (strcmp(clean_name, "printf") == 0) {
        typedef int (*printf_fn_t)(const char*, ...);
        ret = (uint64_t)reinterpret_cast<printf_fn_t>(sym_ptr)((const char*)a0, a1, a2, a3, a4, a5, a6, a7);
    } else if (strcmp(clean_name, "fprintf") == 0 || strcmp(clean_name, "dprintf") == 0) {
        typedef int (*fprintf_fn_t)(void*, const char*, ...);
        ret = (uint64_t)reinterpret_cast<fprintf_fn_t>(sym_ptr)((void*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
    } else if (strcmp(clean_name, "sprintf") == 0) {
        typedef int (*sprintf_fn_t)(char*, const char*, ...);
        ret = (uint64_t)reinterpret_cast<sprintf_fn_t>(sym_ptr)((char*)a0, (const char*)a1, a2, a3, a4, a5, a6, a7);
    } else if (strcmp(clean_name, "snprintf") == 0) {
        typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);
        ret = (uint64_t)reinterpret_cast<snprintf_fn_t>(sym_ptr)((char*)a0, (size_t)a1, (const char*)a2, a3, a4, a5, a6, a7);
    } else {
        typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
        ret = reinterpret_cast<extern_fn_t>(sym_ptr)(a0, a1, a2, a3, a4, a5, a6, a7);
    }
#endif
    ctx->gprs[0] = ret;
}

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
              case JIT_OP_CALL_EXTERN:
                  emit_arm64_imm(code, idx, 1, in.imm);
                  code[idx++] = 0xf81f0ffe;
                  emit_arm64_imm(code, idx, 16, (uintptr_t)&asgard_rd_jit_call_extern);
                  code[idx++] = 0xd63f0000 | (16 << 5);
                  code[idx++] = 0xf84107fe;
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
            case JIT_OP_AND_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x8a0a0129; // and x9, x9, x10
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_AND_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0x8a0a0129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_OR_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0xaa0a0129; // orr x9, x9, x10
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_OR_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0xaa0a0129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SHL_RI: {
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                uint32_t shift = (uint32_t)(in.imm & 63);
                uint32_t immr = (-shift) & 63;
                uint32_t imms = 63 - shift;
                code[idx++] = 0xd3400000 | (1 << 22) | (immr << 16) | (imms << 10) | (9 << 5) | 9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            }
            case JIT_OP_SHR_RI: {
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                uint32_t shift = (uint32_t)(in.imm & 63);
                code[idx++] = 0xd3400000 | (1 << 22) | (shift << 16) | (63 << 10) | (9 << 5) | 9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            }
            case JIT_OP_SAR_RI: {
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                uint32_t shift = (uint32_t)(in.imm & 63);
                code[idx++] = 0x93400000 | (1 << 22) | (shift << 16) | (63 << 10) | (9 << 5) | 9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            }
            case JIT_OP_NOT_R:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xaa2903e9; // mvn x9, x9
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_NEG_R:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xcb0903e9; // neg x9, x9
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_LOAD_64:
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10; // ldr x10, [x0, #src_off]
                if (in.imm != 0) {
                    emit_arm64_imm(code, idx, 11, in.imm);
                    code[idx++] = 0x8b0b014a; // add x10, x10, x11
                }
                code[idx++] = 0xf9400149; // ldr x9, [x10]
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9; // str x9, [x0, #dst_off]
                break;
            case JIT_OP_STORE_64:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 10; // ldr x10, [x0, #dst_off]
                if (in.imm != 0) {
                    emit_arm64_imm(code, idx, 11, in.imm);
                    code[idx++] = 0x8b0b014a; // add x10, x10, x11
                }
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 9; // ldr x9, [x0, #src_off]
                code[idx++] = 0xf9000149; // str x9, [x10]
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
             case JIT_OP_CALL_EXTERN:
                 code[idx++] = 0x48; code[idx++] = 0xbe; emit_u64(in.imm);
                 code[idx++] = 0x49; code[idx++] = 0xbb; emit_u64((uint64_t)(uintptr_t)&asgard_rd_jit_call_extern);
                 code[idx++] = 0x48; code[idx++] = 0x83; code[idx++] = 0xec; code[idx++] = 0x08;
                 code[idx++] = 0x41; code[idx++] = 0xff; code[idx++] = 0xd3;
                 code[idx++] = 0x48; code[idx++] = 0x83; code[idx++] = 0xc4; code[idx++] = 0x08;
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
            case JIT_OP_AND_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x21; code[idx++] = 0xd0; // and rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_AND_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x21; code[idx++] = 0xd0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_OR_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x09; code[idx++] = 0xd0; // or rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_OR_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x09; code[idx++] = 0xd0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SHL_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xc1; code[idx++] = 0xe0; code[idx++] = (uint8_t)(in.imm & 63); // shl rax, imm8
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SHR_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xc1; code[idx++] = 0xe8; code[idx++] = (uint8_t)(in.imm & 63); // shr rax, imm8
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SAR_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xc1; code[idx++] = 0xf8; code[idx++] = (uint8_t)(in.imm & 63); // sar rax, imm8
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_NOT_R:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xd0; // not rax
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_NEG_R:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xd8; // neg rax
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_LOAD_64:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off; // mov rdx, [rdi + src_off]
                if (in.imm != 0) {
                    code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm); // mov rax, imm
                    code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xc2; // add rdx, rax
                }
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x02; // mov rax, [rdx]
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off; // mov [rdi + dst_off], rax
                break;
            case JIT_OP_STORE_64:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = dst_off; // mov rdx, [rdi + dst_off]
                if (in.imm != 0) {
                    code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm); // mov rax, imm
                    code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xc2; // add rdx, rax
                }
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = src_off; // mov rax, [rdi + src_off]
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x02; // mov [rdx], rax
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
            case JIT_OP_CALL_EXTERN: asgard_rd_jit_call_extern(&ctx, in.imm); break;
            case JIT_OP_XOR_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) ^ ctx.get_reg(in.src)); break;
            case JIT_OP_XOR_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) ^ in.imm); break;
            case JIT_OP_AND_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) & ctx.get_reg(in.src)); break;
            case JIT_OP_AND_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) & in.imm); break;
            case JIT_OP_OR_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) | ctx.get_reg(in.src)); break;
            case JIT_OP_OR_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) | in.imm); break;
            case JIT_OP_SHL_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) << (in.imm & 63)); break;
            case JIT_OP_SHR_RI: ctx.set_reg(in.dst, ctx.get_reg(in.dst) >> (in.imm & 63)); break;
            case JIT_OP_SAR_RI: ctx.set_reg(in.dst, (uint64_t)((int64_t)ctx.get_reg(in.dst) >> (in.imm & 63))); break;
            case JIT_OP_NOT_R: ctx.set_reg(in.dst, ~ctx.get_reg(in.dst)); break;
            case JIT_OP_NEG_R: ctx.set_reg(in.dst, (uint64_t)(-(int64_t)ctx.get_reg(in.dst))); break;
            case JIT_OP_LOAD_64: {
                uint64_t addr = ctx.get_reg(in.src) + in.imm;
                ctx.set_reg(in.dst, *reinterpret_cast<const uint64_t*>(addr));
                break;
            }
            case JIT_OP_STORE_64: {
                uint64_t addr = ctx.get_reg(in.dst) + in.imm;
                *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(in.src);
                break;
            }
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
    static inline uint64_t asgard_vm_call(const uint64_t* bc, size_t len, uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0, uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {
        VMContext ctx;
        ctx.init();
        ctx.set_reg(0, a0);
        ctx.set_reg(1, a1);
        ctx.set_reg(2, a2);
        ctx.set_reg(3, a3);
        ctx.set_reg(4, a4);
        ctx.set_reg(5, a5);
        ctx.set_reg(6, a6);
        ctx.set_reg(7, a7);
        execute_threaded(ctx, bc, len);
        return ctx.get_rax();
    }
}
|}
