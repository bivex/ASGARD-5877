(* lib/rd_jit_vm/rd_jit_synth.ml
   ASGARD-5877: Ephemeral Native Code Synthesis & JIT Bridge
   Typed C++20 / C11 EDSL Declarations *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let external_symbols_header symbols =
  let entries =
    match symbols with
    | [] -> [ str_lit "" ]
    | xs -> List.map str_lit xs
  in
  let decl =
    global_var ~is_static:true ~is_const:true
      (Array (Ptr (StructType "char"), 0))
      "g_rd_jit_external_symbols"
      ~init:(init_list entries)
  in
  render_top_decl decl ^ "\n\n"

let jit_op_kind_decl () : top_decl =
  EnumDecl {
    name = "JITOpKind";
    underlying_ty = Some UInt8;
    items = [
      ("JIT_OP_NOP", Some (i32 0));
      ("JIT_OP_MOV_RR", None);
      ("JIT_OP_MOV_RI", None);
      ("JIT_OP_ADD_RR", None);
      ("JIT_OP_ADD_RI", None);
      ("JIT_OP_SUB_RR", None);
      ("JIT_OP_SUB_RI", None);
      ("JIT_OP_MUL_RR", None);
      ("JIT_OP_MUL_RI", None);
      ("JIT_OP_CALL_EXTERN", None);
      ("JIT_OP_XOR_RR", None);
      ("JIT_OP_XOR_RI", None);
      ("JIT_OP_AND_RR", None);
      ("JIT_OP_AND_RI", None);
      ("JIT_OP_OR_RR", None);
      ("JIT_OP_OR_RI", None);
      ("JIT_OP_SHL_RI", None);
      ("JIT_OP_SHR_RI", None);
      ("JIT_OP_SAR_RI", None);
      ("JIT_OP_NOT_R", None);
      ("JIT_OP_NEG_R", None);
      ("JIT_OP_LOAD_64", None);
      ("JIT_OP_STORE_64", None);
      ("JIT_OP_RET", None);
      ("JIT_OP_EXIT", None);
      ("JIT_OP_SHL_RR", None);
      ("JIT_OP_SHR_RR", None);
      ("JIT_OP_SAR_RR", None);
      ("JIT_OP_ROR_RR", None);
      ("JIT_OP_DIV_RR", None);
      ("JIT_OP_SDIV_RR", None);
      ("JIT_OP_REM_RR", None);
      ("JIT_OP_CMP_RR", None);
      ("JIT_OP_CSEL_RR", None);
      ("JIT_OP_MULH_RR", None);
      ("JIT_OP_SMULH_RR", None);
      ("JIT_OP_LOAD_8", None);
      ("JIT_OP_LOAD_16", None);
      ("JIT_OP_LOAD_32", None);
      ("JIT_OP_STORE_8", None);
      ("JIT_OP_STORE_16", None);
      ("JIT_OP_STORE_32", None);
      ("JIT_OP_RESOLVE_SYM", None);
    ];
  }

let jit_instr_decl () : top_decl =
  StructDecl {
    align_as = None;
    name = "JITInstr";
    fields = [
      (UInt8, "op");
      (UInt8, "dst");
      (UInt8, "src");
      (UInt64, "imm");
    ];
  }

let jit_block_decl () : top_decl =
  StructDecl {
    align_as = None;
    name = "JITBlock";
    fields = [
      (UInt32, "id");
      (UInt32, "count");
      (ConstPtr (StructType "JITInstr"), "instrs");
    ];
  }

let rd_jit_types_decls () : top_decl list = [
  jit_op_kind_decl ();
  jit_instr_decl ();
  jit_block_decl ();
  raw_top "typedef void (*JITBlockFn)(RD_JIT_Context* ctx);";
]

let rd_jit_resolve_symbol_decl () : top_decl =
  raw_top {|static inline void* asgard_rd_jit_resolve_symbol(size_t sym_idx) {
    const size_t count = sizeof(g_rd_jit_external_symbols) / sizeof(g_rd_jit_external_symbols[0]);
    if (sym_idx >= count || g_rd_jit_external_symbols[sym_idx][0] == '\0') return nullptr;
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
#else
    HMODULE hMain = GetModuleHandleA(NULL);
    sym_ptr = (void*)GetProcAddress(hMain, sym_name);
    if (!sym_ptr && sym_name[0] == '_') sym_ptr = (void*)GetProcAddress(hMain, sym_name + 1);
    if (!sym_ptr) {
        char alt_name[256];
        snprintf(alt_name, sizeof(alt_name), "_%s", sym_name);
        sym_ptr = (void*)GetProcAddress(hMain, alt_name);
    }
#endif
    return sym_ptr;
}

static inline void asgard_rd_jit_resolve_sym_to_reg(RD_JIT_Context* ctx, uint8_t dst, uint64_t sym_idx) {
    if (!ctx) return;
    void* p = asgard_rd_jit_resolve_symbol((size_t)sym_idx);
    ctx->set_reg((size_t)dst, (uint64_t)(uintptr_t)p);
}|}

let rd_jit_call_extern_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] Void "asgard_rd_jit_call_extern"
    [ (Ptr (StructType "RD_JIT_Context"), "ctx"); (UInt64, "sym_idx") ]
    [
      raw {|void* sym_ptr = asgard_rd_jit_resolve_symbol((size_t)sym_idx);
    if (!sym_ptr || !ctx) return;
    const char* sym_name = g_rd_jit_external_symbols[sym_idx];
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
    ctx->set_reg(0, ret);|};
    ]

let emit_arm64_imm_decl () : top_decl =
  preproc_if "defined(__aarch64__)" [
    func_decl ~attrs:[StaticFn; InlineFn] Void "emit_arm64_imm"
      [ (Ptr UInt32, "code"); (Ref SizeT, "idx"); (UInt8, "reg"); (UInt64, "imm") ]
      [
        raw {|uint32_t w0 = (uint32_t)(imm & 0xFFFFULL);
    uint32_t w1 = (uint32_t)((imm >> 16) & 0xFFFFULL);
    uint32_t w2 = (uint32_t)((imm >> 32) & 0xFFFFULL);
    uint32_t w3 = (uint32_t)((imm >> 48) & 0xFFFFULL);
    code[idx++] = 0xd2800000 | (w0 << 5) | reg;
    if (w1 != 0 || (w2 == 0 && w3 == 0 && imm > 0xFFFFULL))
        code[idx++] = 0xf2a00000 | (w1 << 5) | reg;
    if (w2 != 0 || (w3 == 0 && imm > 0xFFFFFFFFULL))
        code[idx++] = 0xf2c00000 | (w2 << 5) | reg;
    if (w3 != 0)
        code[idx++] = 0xf2e00000 | (w3 << 5) | reg;|};
      ]
  ]

let synthesize_and_execute_block_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] Void "synthesize_and_execute_block"
    [ (Ref (StructType "DualMappedJITBuffer"), "jit");
      (Ref (StructType "RD_JIT_Context"), "ctx");
      (ConstRef (StructType "JITBlock"), "block") ]
    [
      raw {|jit.begin_synthesis();
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
                code[idx++] = 0xd503201f;
                break;
            case JIT_OP_MOV_RR:
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_MOV_RI:
                emit_arm64_imm(code, idx, 9, in.imm);
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_ADD_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x8b0a0129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
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
                code[idx++] = 0xcb0a0129;
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
                code[idx++] = 0x9b0a7d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_MUL_RI:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                emit_arm64_imm(code, idx, 10, in.imm);
                code[idx++] = 0x9b0a7d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_CALL_EXTERN:
                code[idx++] = 0xa9bf7bfd;
                code[idx++] = 0xf81f0fe0;
                emit_arm64_imm(code, idx, 1, in.imm);
                emit_arm64_imm(code, idx, 16, (uintptr_t)&asgard_rd_jit_call_extern);
                code[idx++] = 0xd63f0000 | (16 << 5);
                code[idx++] = 0xf84107e0;
                code[idx++] = 0xa8c17bfd;
                break;
            case JIT_OP_RESOLVE_SYM:
                code[idx++] = 0xa9bf7bfd;
                code[idx++] = 0xf81f0fe0;
                emit_arm64_imm(code, idx, 1, (uint64_t)in.dst);
                emit_arm64_imm(code, idx, 2, in.imm);
                emit_arm64_imm(code, idx, 16, (uintptr_t)&asgard_rd_jit_resolve_sym_to_reg);
                code[idx++] = 0xd63f0000 | (16 << 5);
                code[idx++] = 0xf84107e0;
                code[idx++] = 0xa8c17bfd;
                break;
            case JIT_OP_XOR_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0xca0a0129;
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
                code[idx++] = 0x8a0a0129;
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
                code[idx++] = 0xaa0a0129;
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
                uint32_t immr = (64 - shift) & 63;
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
                code[idx++] = 0xaa2903e9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_NEG_R:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xcb0903e9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_LOAD_8:
            case JIT_OP_LOAD_16:
            case JIT_OP_LOAD_32:
            case JIT_OP_LOAD_64:
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                if (in.imm != 0) {
                    emit_arm64_imm(code, idx, 11, in.imm);
                    code[idx++] = 0x8b0b014a;
                }
                if (in.op == asgard_rd_jit::JIT_OP_LOAD_8) {
                    code[idx++] = 0x39400149;
                } else if (in.op == asgard_rd_jit::JIT_OP_LOAD_16) {
                    code[idx++] = 0x79400149;
                } else if (in.op == asgard_rd_jit::JIT_OP_LOAD_32) {
                    code[idx++] = 0xb9400149;
                } else {
                    code[idx++] = 0xf9400149;
                }
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_STORE_8:
            case JIT_OP_STORE_16:
            case JIT_OP_STORE_32:
            case JIT_OP_STORE_64:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 10;
                if (in.imm != 0) {
                    emit_arm64_imm(code, idx, 11, in.imm);
                    code[idx++] = 0x8b0b014a;
                }
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 9;
                if (in.op == asgard_rd_jit::JIT_OP_STORE_8) {
                    code[idx++] = 0x39000149;
                } else if (in.op == asgard_rd_jit::JIT_OP_STORE_16) {
                    code[idx++] = 0x79000149;
                } else if (in.op == asgard_rd_jit::JIT_OP_STORE_32) {
                    code[idx++] = 0xb9000149;
                } else {
                    code[idx++] = 0xf9000149;
                }
                break;
            case JIT_OP_SHL_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca2129;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SHR_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca2529;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SAR_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca2929;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_ROR_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca2d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_DIV_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca0929;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SDIV_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca0d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_REM_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9aca092b;
                code[idx++] = 0x9b0aa569;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_CMP_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0xeb0a013f;
                break;
            case JIT_OP_MULH_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9bca7d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_SMULH_RR:
                code[idx++] = 0xf9400000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0x9b4a7d29;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            case JIT_OP_CSEL_RR: {
                uint32_t cond = (uint32_t)(in.imm & 0xF);
                uint8_t src2 = (uint8_t)((in.imm >> 8) & 0xFF);
                uint8_t src2_off = src2 * 8;
                code[idx++] = 0xf9400000 | (src_off / 8 << 10) | (0 << 5) | 10;
                code[idx++] = 0xf9400000 | (src2_off / 8 << 10) | (0 << 5) | 11;
                code[idx++] = 0x9a800000 | (11 << 16) | (cond << 12) | (10 << 5) | 9;
                code[idx++] = 0xf9000000 | (dst_off / 8 << 10) | (0 << 5) | 9;
                break;
            }
            case JIT_OP_RET:
            case JIT_OP_EXIT:
                break;
            default:
                break;
        }
    }
    code[idx++] = 0xd65f03c0;
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
                code[idx++] = 0x90;
                break;
            case JIT_OP_MOV_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_MOV_RI:
                code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_ADD_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xd0;
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
                code[idx++] = 0x48; code[idx++] = 0x29; code[idx++] = 0xd0;
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
                code[idx++] = 0x48; code[idx++] = 0x0f; code[idx++] = 0xaf; code[idx++] = 0xc2;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_MUL_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x48; code[idx++] = 0x0f; code[idx++] = 0xaf; code[idx++] = 0xc2;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_CALL_EXTERN:
                code[idx++] = 0x57;
                code[idx++] = 0x48; code[idx++] = 0xbe; emit_u64(in.imm);
                code[idx++] = 0x49; code[idx++] = 0xbb; emit_u64((uint64_t)(uintptr_t)&asgard_rd_jit_call_extern);
                code[idx++] = 0x48; code[idx++] = 0x83; code[idx++] = 0xec; code[idx++] = 0x08;
                code[idx++] = 0x41; code[idx++] = 0xff; code[idx++] = 0xd3;
                code[idx++] = 0x48; code[idx++] = 0x83; code[idx++] = 0xc4; code[idx++] = 0x08;
                code[idx++] = 0x5f;
                break;
            case JIT_OP_RESOLVE_SYM:
                code[idx++] = 0x57;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0xdf;
                code[idx++] = 0x48; code[idx++] = 0xbe; emit_u64((uint64_t)in.dst);
                code[idx++] = 0x48; code[idx++] = 0xba; emit_u64(in.imm);
                code[idx++] = 0x49; code[idx++] = 0xbb; emit_u64((uint64_t)(uintptr_t)&asgard_rd_jit_resolve_sym_to_reg);
                code[idx++] = 0x48; code[idx++] = 0x83; code[idx++] = 0xec; code[idx++] = 0x08;
                code[idx++] = 0x41; code[idx++] = 0xff; code[idx++] = 0xd3;
                code[idx++] = 0x48; code[idx++] = 0x83; code[idx++] = 0xc4; code[idx++] = 0x08;
                code[idx++] = 0x5f;
                break;
            case JIT_OP_XOR_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x31; code[idx++] = 0xd0;
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
                code[idx++] = 0x48; code[idx++] = 0x21; code[idx++] = 0xd0;
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
                code[idx++] = 0x48; code[idx++] = 0x09; code[idx++] = 0xd0;
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
                code[idx++] = 0x48; code[idx++] = 0xc1; code[idx++] = 0xe0; code[idx++] = (uint8_t)(in.imm & 63);
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SHR_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xc1; code[idx++] = 0xe8; code[idx++] = (uint8_t)(in.imm & 63);
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SAR_RI:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xc1; code[idx++] = 0xf8; code[idx++] = (uint8_t)(in.imm & 63);
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_NOT_R:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xd0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_NEG_R:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xd8;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_LOAD_8:
            case JIT_OP_LOAD_16:
            case JIT_OP_LOAD_32:
            case JIT_OP_LOAD_64:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                if (in.imm != 0) {
                    code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm);
                    code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xc2;
                }
                if (in.op == asgard_rd_jit::JIT_OP_LOAD_8) {
                    code[idx++] = 0x48; code[idx++] = 0x0f; code[idx++] = 0xb6; code[idx++] = 0x02;
                } else if (in.op == asgard_rd_jit::JIT_OP_LOAD_16) {
                    code[idx++] = 0x48; code[idx++] = 0x0f; code[idx++] = 0xb7; code[idx++] = 0x02;
                } else if (in.op == asgard_rd_jit::JIT_OP_LOAD_32) {
                    code[idx++] = 0x8b; code[idx++] = 0x02;
                } else {
                    code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x02;
                }
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_STORE_8:
            case JIT_OP_STORE_16:
            case JIT_OP_STORE_32:
            case JIT_OP_STORE_64:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = dst_off;
                if (in.imm != 0) {
                    code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm);
                    code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xc2;
                }
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = src_off;
                if (in.op == asgard_rd_jit::JIT_OP_STORE_8) {
                    code[idx++] = 0x88; code[idx++] = 0x02;
                } else if (in.op == asgard_rd_jit::JIT_OP_STORE_16) {
                    code[idx++] = 0x66; code[idx++] = 0x89; code[idx++] = 0x02;
                } else if (in.op == asgard_rd_jit::JIT_OP_STORE_32) {
                    code[idx++] = 0x89; code[idx++] = 0x02;
                } else {
                    code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x02;
                }
                break;
            case JIT_OP_SHL_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x4f; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xd3; code[idx++] = 0xe0;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SHR_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x4f; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xd3; code[idx++] = 0xe8;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SAR_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x4f; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xd3; code[idx++] = 0xf8;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_ROR_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x4f; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xd3; code[idx++] = 0xc8;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_DIV_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x31; code[idx++] = 0xd2;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x77; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xf6;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_SDIV_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x99;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x77; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xfe;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            case JIT_OP_REM_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x31; code[idx++] = 0xd2;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x77; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xf6;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x57; code[idx++] = dst_off;
                break;
            case JIT_OP_CMP_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x39; code[idx++] = 0xd0;
                break;
            case JIT_OP_MULH_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x77; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xe6;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x57; code[idx++] = dst_off;
                break;
            case JIT_OP_SMULH_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off;
                code[idx++] = 0x48; code[idx++] = 0x99;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x77; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0xf7; code[idx++] = 0xee;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x57; code[idx++] = dst_off;
                break;
            case JIT_OP_CSEL_RR: {
                uint8_t cond_byte = 0x44;
                switch (in.imm & 0xF) {
                    case 0: cond_byte = 0x44; break;
                    case 1: cond_byte = 0x45; break;
                    case 10: cond_byte = 0x4d; break;
                    case 11: cond_byte = 0x4c; break;
                    case 12: cond_byte = 0x4f; break;
                    case 13: cond_byte = 0x4e; break;
                    default: cond_byte = 0x44; break;
                }
                uint8_t src2 = (uint8_t)((in.imm >> 8) & 0xFF);
                uint8_t src2_off = src2 * 8;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = src2_off;
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off;
                code[idx++] = 0x48; code[idx++] = 0x0f; code[idx++] = cond_byte; code[idx++] = 0xc2;
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off;
                break;
            }
            case JIT_OP_RET:
            case JIT_OP_EXIT:
                break;
            default:
                break;
        }
    }
    code[idx++] = 0xc3;
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
            case JIT_OP_RESOLVE_SYM: asgard_rd_jit_resolve_sym_to_reg(&ctx, in.dst, in.imm); break;
            case JIT_OP_NEG_R: ctx.set_reg(in.dst, (uint64_t)(-(int64_t)ctx.get_reg(in.dst))); break;
            case JIT_OP_LOAD_8: {
                uint64_t addr = ctx.get_reg(in.src) + in.imm;
                ctx.set_reg(in.dst, (uint64_t)*reinterpret_cast<const uint8_t*>(addr));
                break;
            }
            case JIT_OP_LOAD_16: {
                uint64_t addr = ctx.get_reg(in.src) + in.imm;
                ctx.set_reg(in.dst, (uint64_t)*reinterpret_cast<const uint16_t*>(addr));
                break;
            }
            case JIT_OP_LOAD_32: {
                uint64_t addr = ctx.get_reg(in.src) + in.imm;
                ctx.set_reg(in.dst, (uint64_t)*reinterpret_cast<const uint32_t*>(addr));
                break;
            }
            case JIT_OP_LOAD_64: {
                uint64_t addr = ctx.get_reg(in.src) + in.imm;
                ctx.set_reg(in.dst, *reinterpret_cast<const uint64_t*>(addr));
                break;
            }
            case JIT_OP_STORE_8: {
                uint64_t addr = ctx.get_reg(in.dst) + in.imm;
                *reinterpret_cast<uint8_t*>(addr) = (uint8_t)ctx.get_reg(in.src);
                break;
            }
            case JIT_OP_STORE_16: {
                uint64_t addr = ctx.get_reg(in.dst) + in.imm;
                *reinterpret_cast<uint16_t*>(addr) = (uint16_t)ctx.get_reg(in.src);
                break;
            }
            case JIT_OP_STORE_32: {
                uint64_t addr = ctx.get_reg(in.dst) + in.imm;
                *reinterpret_cast<uint32_t*>(addr) = (uint32_t)ctx.get_reg(in.src);
                break;
            }
            case JIT_OP_STORE_64: {
                uint64_t addr = ctx.get_reg(in.dst) + in.imm;
                *reinterpret_cast<uint64_t*>(addr) = ctx.get_reg(in.src);
                break;
            }
            case JIT_OP_SHL_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) << (ctx.get_reg(in.src) & 63)); break;
            case JIT_OP_SHR_RR: ctx.set_reg(in.dst, ctx.get_reg(in.dst) >> (ctx.get_reg(in.src) & 63)); break;
            case JIT_OP_SAR_RR: ctx.set_reg(in.dst, (uint64_t)((int64_t)ctx.get_reg(in.dst) >> (ctx.get_reg(in.src) & 63))); break;
            case JIT_OP_ROR_RR: {
                uint64_t v = ctx.get_reg(in.dst);
                uint64_t s = ctx.get_reg(in.src) & 63;
                ctx.set_reg(in.dst, s == 0 ? v : (v >> s) | (v << (64 - s)));
                break;
            }
            case JIT_OP_DIV_RR: {
                uint64_t d = ctx.get_reg(in.src);
                ctx.set_reg(in.dst, d == 0 ? 0 : ctx.get_reg(in.dst) / d);
                break;
            }
            case JIT_OP_SDIV_RR: {
                int64_t d = (int64_t)ctx.get_reg(in.src);
                ctx.set_reg(in.dst, d == 0 ? 0 : (uint64_t)((int64_t)ctx.get_reg(in.dst) / d));
                break;
            }
            case JIT_OP_REM_RR: {
                uint64_t d = ctx.get_reg(in.src);
                ctx.set_reg(in.dst, d == 0 ? 0 : ctx.get_reg(in.dst) % d);
                break;
            }
            case JIT_OP_CMP_RR: {
                uint64_t a = ctx.get_reg(in.dst);
                uint64_t b = ctx.get_reg(in.src);
                ctx.flags = (a == b ? 1 : 0) | (a < b ? 2 : 0) | ((int64_t)a < (int64_t)b ? 4 : 0);
                break;
            }
            case JIT_OP_MULH_RR: {
                uint64_t a = ctx.get_reg(in.dst);
                uint64_t b = ctx.get_reg(in.src);
                ctx.set_reg(in.dst, (uint64_t)(((__uint128_t)a * (__uint128_t)b) >> 64));
                break;
            }
            case JIT_OP_SMULH_RR: {
                int64_t a = (int64_t)ctx.get_reg(in.dst);
                int64_t b = (int64_t)ctx.get_reg(in.src);
                ctx.set_reg(in.dst, (uint64_t)(((__int128_t)a * (__int128_t)b) >> 64));
                break;
            }
            case JIT_OP_CSEL_RR: {
                uint32_t cond = (uint32_t)(in.imm & 0xF);
                uint8_t src2 = (uint8_t)((in.imm >> 8) & 0xFF);
                bool take = false;
                switch (cond) {
                    case 0: take = (ctx.flags & 1) != 0; break;
                    case 1: take = (ctx.flags & 1) == 0; break;
                    case 2: take = (ctx.flags & 2) != 0; break;
                    case 10: take = ((ctx.flags & 4) == 0); break;
                    case 11: take = ((ctx.flags & 4) != 0); break;
                    default: take = (ctx.flags & 1) != 0; break;
                }
                ctx.set_reg(in.dst, take ? ctx.get_reg(in.src) : ctx.get_reg(src2));
                break;
            }
            default: break;
        }
    }
    return;
#endif

    if (code_bytes > 0) {
        jit.commit_and_flush(code_bytes);
        JITBlockFn fn = (JITBlockFn)jit.get_exec_ptr();
        fn(&ctx);
        for (size_t r = 0; r < 16; ++r) {
            ctx.vregs[r].set(ctx.gprs[r]);
        }
        jit.atomic_zeroize(code_bytes);
    }|};
    ]

let execute_jit_function_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] Void "execute_jit_function"
    [ (Ref (StructType "DualMappedJITBuffer"), "jit");
      (Ref (StructType "RD_JIT_Context"), "ctx");
      (ConstPtr (StructType "JITBlock"), "blocks");
      (SizeT, "num_blocks") ]
    [
      for_range "b" (i32 0) (var "num_blocks") [
        expr_stmt (call "synthesize_and_execute_block" [var "jit"; var "ctx"; Index (var "blocks", var "b")]);
      ];
    ]

let execute_ephemeral_block_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] Void "execute_ephemeral_block"
    [ (Ref (StructType "DualMappedJITBuffer"), "jit");
      (Ref (StructType "RD_JIT_Context"), "ctx");
      (UInt64, "op_a");
      (UInt64, "op_b") ]
    [
      expr_stmt (call "ctx.set_reg" [i32 0; var "op_a"]);
      expr_stmt (call "ctx.set_reg" [i32 1; var "op_b"]);
      raw {|static const JITInstr add_block_instrs[] = {
        { JIT_OP_ADD_RR, 0, 1, 0 },
        { JIT_OP_RET, 0, 0, 0 }
    };
    static const JITBlock add_block = { 0, 2, add_block_instrs };
    synthesize_and_execute_block(jit, ctx, add_block);|};
    ]

let execute_threaded_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] Void "execute_threaded"
    [ (Ref (StructType "VMContext"), "ctx");
      (ConstPtr UInt64, "bc");
      (SizeT, "len") ]
    [
      raw "asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);";
      raw "asgard_rd_jit::execute_ephemeral_block(jit_buf, ctx, ctx.get_reg(0), ctx.get_reg(1));";
    ]

let asgard_vm_call_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] UInt64 "asgard_vm_call"
    [ (ConstPtr UInt64, "bc");
      (SizeT, "len");
      (UInt64, "a0 = 0");
      (UInt64, "a1 = 0");
      (UInt64, "a2 = 0");
      (UInt64, "a3 = 0");
      (UInt64, "a4 = 0");
      (UInt64, "a5 = 0");
      (UInt64, "a6 = 0");
      (UInt64, "a7 = 0");
      (UInt8, "macro_salt = 0") ]
    [
      raw {|if (bc != nullptr && len >= 3 && bc[0] == 0x58774A4954303031ULL) {
        uint64_t master = bc[1];
        size_t num_chunks = (size_t)bc[2];
        asgard::nano_jit::NanoTicket tickets_buf[64];
        const uint64_t* blobs_buf[64];
        asgard::nano_jit::NanoTicket* tickets = tickets_buf;
        const uint64_t** blobs = blobs_buf;
        if (num_chunks > 64) {
            tickets = (asgard::nano_jit::NanoTicket*)malloc(num_chunks * sizeof(asgard::nano_jit::NanoTicket));
            blobs = (const uint64_t**)malloc(num_chunks * sizeof(const uint64_t*));
        }
        size_t pos = 3;
        for (size_t k = 0; k < num_chunks && pos + 4 <= len; ++k) {
            tickets[k].nonce = bc[pos++];
            tickets[k].word_count = (uint32_t)bc[pos++];
            tickets[k].instr_count = (uint32_t)bc[pos++];
            tickets[k].perm_idx = (uint32_t)bc[pos++];
            blobs[k] = &bc[pos];
            pos += tickets[k].word_count;
        }
        asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);
        asgard_rd_jit::RD_JIT_Context ctx;
        ctx.init();
        ctx.set_reg(0, a0);
        ctx.set_reg(1, a1);
        ctx.set_reg(2, a2);
        ctx.set_reg(3, a3);
        ctx.set_reg(4, a4);
        ctx.set_reg(5, a5);
        ctx.set_reg(6, a6);
        ctx.set_reg(7, a7);
        asgard::nano_jit::execute_sealed_function(jit_buf, ctx, tickets, blobs, num_chunks, master);
        uint64_t res = ctx.get_rax();
        if (num_chunks > 64) {
            free(tickets);
            free(blobs);
        }
        return res;
    }
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
    return ctx.get_rax();|};
    ]
let asgard_vm_call_with_salt_decl () : top_decl =
  func_decl ~attrs:[StaticFn; InlineFn] UInt64 "asgard_vm_call_with_salt"
    [ (UInt8, "macro_salt");
      (ConstPtr UInt64, "bc");
      (SizeT, "len");
      (UInt64, "a0 = 0");
      (UInt64, "a1 = 0");
      (UInt64, "a2 = 0");
      (UInt64, "a3 = 0");
      (UInt64, "a4 = 0");
      (UInt64, "a5 = 0");
      (UInt64, "a6 = 0");
      (UInt64, "a7 = 0") ]
    [
      ret (call "asgard_vm_call" [
        var "bc"; var "len";
        var "a0"; var "a1"; var "a2"; var "a3";
        var "a4"; var "a5"; var "a6"; var "a7";
        var "macro_salt";
      ]);
    ]

let synth_decls ?(external_symbols = []) () : top_decl list =
  ignore external_symbols;
  rd_jit_types_decls ()
  @ [
    include_sys "stdio.h";
    include_sys "stdlib.h";
    include_sys "string.h";
    preproc_if "!defined(_WIN32) && !defined(_WIN64)"
      [ include_sys "dlfcn.h" ]
      ~else_decls:[ include_sys "windows.h" ];
    rd_jit_resolve_symbol_decl ();
    rd_jit_call_extern_decl ();
    emit_arm64_imm_decl ();
    synthesize_and_execute_block_decl ();
    execute_jit_function_decl ();
    execute_ephemeral_block_decl ();
    raw_top "} // namespace asgard_rd_jit";
  ]

let vm_bridge_decls () : top_decl list = [
  namespace_def "vanguard_threaded_vm" [
    raw_top "typedef asgard_rd_jit::RD_JIT_Context VMContext;";
    execute_threaded_decl ();
    asgard_vm_call_decl ();
    asgard_vm_call_with_salt_decl ();
  ];
]

let header_decls ?(external_symbols = []) () : top_decl list =
  synth_decls ~external_symbols () @ vm_bridge_decls ()

let header ?(external_symbols = []) () : string =
  render_top_decls (header_decls ~external_symbols ())
