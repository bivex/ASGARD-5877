open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

[@@@warning "-32"]

let emit_handler_inline_ast b label (stmts : stmt list) =
  Buffer.add_string b (Printf.sprintf "    %s: { " label);
  List.iter (fun s ->
    Buffer.add_string b (string_of_stmt s);
    Buffer.add_char b ' ';
  ) stmts;
  Buffer.add_string b "}\n"

let emit_handler_ast b label (stmts : stmt list) =
  Buffer.add_string b (Printf.sprintf "    %s: {\n" label);
  List.iter (fun s ->
    Buffer.add_string b "        ";
    Buffer.add_string b (string_of_stmt s);
    Buffer.add_char b '\n';
  ) stmts;
  Buffer.add_string b "    }\n"

let let_u16 name expr = decl_var UInt16 name ~init:expr
let let_u8 name expr = decl_var UInt8 name ~init:expr
let let_i64 name expr = decl_var Int64 name ~init:expr
let let_i32 name expr = decl_var Int32 name ~init:expr
let let_i16 name expr = decl_var Int16 name ~init:expr
let let_i8 name expr = decl_var Int8 name ~init:expr
let let_size_t name expr = decl_var SizeT name ~init:expr
let let_double name expr = decl_var Double name ~init:expr
let let_float name expr = decl_var Float name ~init:expr
let let_bool name expr = decl_var Bool name ~init:expr
let get_vreg_lane r lane = call "ctx.get_vreg_lane" [r; lane]
let set_vreg_lane r lane val_e = expr_stmt (call "ctx.set_vreg_lane" [r; lane; val_e])
let set_vreg dst_e l0 l1 = expr_stmt (call "ctx.set_vreg" [dst_e; l0; l1])

(* The x86 SHA extensions (SHA-NI).  The handler works on the four 32-bit
   words of a 128-bit vector register, so it is written as portable C++ and
   not through the statement DSL: the round functions need 32-bit rotates and
   several dozen steps per instruction. *)
let emit_sha_handler b =
  Buffer.add_string b
    {|
    H_VEC_SHA: {
        const uint32_t sha_op = static_cast<uint32_t>((word >> 50) & 0x7ULL);
        const uint32_t sha_s2 = static_cast<uint32_t>(imm & 31ULL);
        const uint32_t sha_s3 = static_cast<uint32_t>((imm >> 5) & 31ULL);
        const uint32_t sha_imm8 = static_cast<uint32_t>((imm >> 10) & 0xFFULL);
        uint32_t sha_d[4], sha_s[4], sha_w[4], sha_r[4];
        for (int i = 0; i < 4; i++) {
            sha_d[i] = static_cast<uint32_t>(ctx.get_vreg_lane(static_cast<uint8_t>(dst), i / 2) >> ((i % 2) * 32));
            sha_s[i] = static_cast<uint32_t>(ctx.get_vreg_lane(static_cast<uint8_t>(sha_s2), i / 2) >> ((i % 2) * 32));
        }
        auto sha_rol32 = [](uint32_t x, int n) -> uint32_t {
            n &= 31;
            return n ? ((x << n) | (x >> (32 - n))) : x;
        };
        auto sha_ror32 = [](uint32_t x, int n) -> uint32_t {
            n &= 31;
            return n ? ((x >> n) | (x << (32 - n))) : x;
        };
        auto sha_f = [](int round, uint32_t b, uint32_t c, uint32_t d) -> uint32_t {
            switch (round) {
                case 0: return (b & c) | (~b & d);
                case 2: return (b & c) | (b & d) | (c & d);
                default: return b ^ c ^ d;
            }
        };
        auto sha_k = [](int round) -> uint32_t {
            switch (round) {
                case 0: return 0x5A827999u;
                case 1: return 0x6ED9EBA1u;
                case 2: return 0x8F1BBCDCu;
                default: return 0xCA62C1D6u;
            }
        };
        auto sha_ch = [](uint32_t x, uint32_t y, uint32_t z) -> uint32_t {
            return (x & y) ^ (~x & z);
        };
        auto sha_maj = [](uint32_t x, uint32_t y, uint32_t z) -> uint32_t {
            return (x & y) ^ (x & z) ^ (y & z);
        };
        auto sha_sigma0 = [&](uint32_t x) -> uint32_t {
            return sha_ror32(x, 2) ^ sha_ror32(x, 13) ^ sha_ror32(x, 22);
        };
        auto sha_sigma1 = [&](uint32_t x) -> uint32_t {
            return sha_ror32(x, 6) ^ sha_ror32(x, 11) ^ sha_ror32(x, 25);
        };
        switch (sha_op) {
            case 0: { /* SHA1RNDS4 */
                const int round = static_cast<int>(sha_imm8 & 3u);
                uint32_t a = sha_d[0], b = sha_d[1], c = sha_d[2], d = sha_d[3], e = 0u;
                for (int i = 0; i < 4; i++) {
                    const uint32_t a_new = sha_f(round, b, c, d) + sha_rol32(a, 5) + sha_s[i] + e + sha_k(round);
                    const uint32_t b_new = a;
                    const uint32_t c_new = sha_rol32(b, 30);
                    const uint32_t d_new = c;
                    const uint32_t e_new = d;
                    a = a_new; b = b_new; c = c_new; d = d_new; e = e_new;
                }
                sha_r[0] = a; sha_r[1] = b; sha_r[2] = c; sha_r[3] = d;
                break;
            }
            case 1: { /* SHA1NEXTE */
                sha_r[0] = sha_s[0] + sha_rol32(sha_d[0], 30);
                sha_r[1] = sha_s[1];
                sha_r[2] = sha_s[2];
                sha_r[3] = sha_s[3];
                break;
            }
            case 2: { /* SHA1MSG1 */
                sha_r[0] = sha_d[2] ^ sha_d[0];
                sha_r[1] = sha_d[3] ^ sha_d[1];
                sha_r[2] = sha_s[0] ^ sha_d[2];
                sha_r[3] = sha_s[1] ^ sha_d[3];
                break;
            }
            case 3: { /* SHA1MSG2 */
                const uint32_t w16 = sha_rol32(sha_d[0] ^ sha_s[1], 1);
                const uint32_t w17 = sha_rol32(sha_d[1] ^ sha_s[2], 1);
                const uint32_t w18 = sha_rol32(sha_d[2] ^ sha_s[3], 1);
                const uint32_t w19 = sha_rol32(sha_d[3] ^ w16, 1);
                sha_r[0] = w16; sha_r[1] = w17; sha_r[2] = w18; sha_r[3] = w19;
                break;
            }
            case 4: { /* SHA256RNDS2 */
                uint32_t wk[2];
                for (int i = 0; i < 2; i++) {
                    wk[i] = static_cast<uint32_t>(ctx.get_vreg_lane(static_cast<uint8_t>(sha_s3), i / 2) >> ((i % 2) * 32));
                }
                uint32_t a = sha_s[0], b = sha_s[1], c = sha_d[0], d = sha_d[1];
                uint32_t e = sha_s[2], f = sha_s[3], g = sha_d[2], h = sha_d[3];
                for (int i = 0; i < 2; i++) {
                    const uint32_t ch = sha_ch(e, f, g);
                    const uint32_t t1 = ch + sha_sigma1(e) + wk[i] + h;
                    const uint32_t a_new = t1 + sha_maj(a, b, c) + sha_sigma0(a);
                    const uint32_t e_new = t1 + d;
                    const uint32_t b_new = a, c_new = b, d_new = c;
                    const uint32_t f_new = e, g_new = f, h_new = g;
                    a = a_new; b = b_new; c = c_new; d = d_new;
                    e = e_new; f = f_new; g = g_new; h = h_new;
                }
                sha_r[0] = a; sha_r[1] = b; sha_r[2] = e; sha_r[3] = f;
                break;
            }
            case 5: { /* SHA256MSG1 */
                sha_r[0] = sha_d[3] + sha_sigma0(sha_d[2]);
                sha_r[1] = sha_d[2] + sha_sigma0(sha_d[1]);
                sha_r[2] = sha_d[1] + sha_sigma0(sha_d[0]);
                sha_r[3] = sha_d[0] + sha_sigma0(sha_s[0]);
                break;
            }
            default: { /* SHA256MSG2 */
                const uint32_t w16 = sha_d[3] + sha_sigma1(sha_s[1]);
                const uint32_t w17 = sha_d[2] + sha_sigma1(sha_s[0]);
                const uint32_t w18 = sha_d[1] + sha_sigma1(w16);
                const uint32_t w19 = sha_d[0] + sha_sigma1(w17);
                sha_r[0] = w16; sha_r[1] = w17; sha_r[2] = w18; sha_r[3] = w19;
                break;
            }
        }
        for (int i = 0; i < 4; i++) {
            const uint8_t lane = static_cast<uint8_t>(i / 2);
            const uint64_t mask = (i % 2 == 0) ? 0xFFFFFFFFULL : 0xFFFFFFFF00000000ULL;
            const uint64_t old_value = ctx.get_vreg_lane(static_cast<uint8_t>(dst), lane);
            ctx.set_vreg_lane(static_cast<uint8_t>(dst), lane,
                              (old_value & ~mask) | (static_cast<uint64_t>(sha_r[i]) << ((i % 2) * 32)));
        }
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
|}

(* PCLMULQDQ and the CET shadow stack instructions (RDSSP, INCSSP). *)
let emit_pclmul_ssp_handlers b =
  Buffer.add_string b
    {|
    H_VEC_PCLMUL: {
        const uint64_t pclmul_src1_l0 = ctx.get_vreg_lane(static_cast<uint8_t>(src), 0);
        const uint64_t pclmul_src1_l1 = ctx.get_vreg_lane(static_cast<uint8_t>(src), 1);
        const uint32_t pclmul_src2 = static_cast<uint32_t>(imm & 31ULL);
        const uint64_t pclmul_src2_l0 = ctx.get_vreg_lane(static_cast<uint8_t>(pclmul_src2), 0);
        const uint64_t pclmul_src2_l1 = ctx.get_vreg_lane(static_cast<uint8_t>(pclmul_src2), 1);
        const uint32_t pclmul_op = static_cast<uint32_t>((imm >> 5) & 0xFFULL);
        const uint64_t pclmul_t1 = (pclmul_op & 1u) ? pclmul_src1_l1 : pclmul_src1_l0;
        const uint64_t pclmul_t2 = (pclmul_op & 16u) ? pclmul_src2_l1 : pclmul_src2_l0;
        uint64_t pclmul_lo = 0, pclmul_hi = 0;
        for (int i = 0; i < 64; i++) {
            if ((pclmul_t1 >> i) & 1ULL) {
                if (i == 0) {
                    pclmul_lo ^= pclmul_t2;
                } else {
                    pclmul_lo ^= (pclmul_t2 << i);
                    pclmul_hi ^= (pclmul_t2 >> (64 - i));
                }
            }
        }
        const uint64_t pclmul_dst_hi = (pclmul_op & 16u) ? pclmul_src1_l1 : pclmul_hi;
        ctx.set_vreg_lane(static_cast<uint8_t>(dst), 0, pclmul_lo);
        ctx.set_vreg_lane(static_cast<uint8_t>(dst), 1, pclmul_dst_hi);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_READ_SSP: {
        const uint64_t ssp_value = ctx.get_ssp();
        ctx.set_reg(dst, (imm == 32ULL) ? (ssp_value & 0xFFFFFFFFULL) : ssp_value);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_INC_SSP: {
        const uint64_t ssp_step = (imm == 32ULL) ? 16ULL : 64ULL;
        ctx.set_ssp(ctx.get_ssp() + ssp_step);
        ctx.set_reg(REG_RSP, ctx.get_reg(REG_RSP) - ssp_step);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_CPUID: {
        const uint32_t in_eax = static_cast<uint32_t>(ctx.get_reg(REG_RAX) & 0xFFFFFFFFULL);
        const uint32_t in_ecx = static_cast<uint32_t>(ctx.get_reg(REG_RCX) & 0xFFFFFFFFULL);
        uint32_t out_eax = 0, out_ebx = 0, out_ecx = 0, out_edx = 0;
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
        __asm__ __volatile__(
            "cpuid"
            : "=a"(out_eax), "=b"(out_ebx), "=c"(out_ecx), "=d"(out_edx)
            : "a"(in_eax), "c"(in_ecx)
        );
#else
        switch (in_eax) {
            case 0x00u:
                out_eax = 0x16u;
                out_ebx = 0x756e6547u;
                out_ecx = 0x6c65746eu;
                out_edx = 0x49656e69u;
                break;
            case 0x01u:
                out_eax = 0x000906E9u;
                out_ebx = 0x00080800u;
                out_ecx = 0x7FFAFBEFu;
                out_edx = 0xBFEBFBFFu;
                break;
            case 0x02u:
                out_eax = 0x76036301u;
                out_ebx = 0x00F0B5FFu;
                out_ecx = 0x00000000u;
                out_edx = 0x00C10000u;
                break;
            case 0x04u:
                if (in_ecx == 0u) {
                    out_eax = 0x1C004121u; out_ebx = 0x01C0003Fu; out_ecx = 0x3Fu; out_edx = 0u;
                } else if (in_ecx == 1u) {
                    out_eax = 0x1C004122u; out_ebx = 0x01C0003Fu; out_ecx = 0x3Fu; out_edx = 0u;
                } else if (in_ecx == 2u) {
                    out_eax = 0x1C004143u; out_ebx = 0x00C0003Fu; out_ecx = 0x1FFu; out_edx = 0u;
                } else if (in_ecx == 3u) {
                    out_eax = 0x1C03C163u; out_ebx = 0x03C0003Fu; out_ecx = 0x1FFFu; out_edx = 2u;
                } else {
                    out_eax = 0u; out_ebx = 0u; out_ecx = 0u; out_edx = 0u;
                }
                break;
            case 0x07u:
                if (in_ecx == 0u) {
                    out_eax = 0u;
                    out_ebx = 0x209C01A9u;
                    out_ecx = 0u;
                    out_edx = 0u;
                }
                break;
            case 0x15u:
                out_eax = 2u; out_ebx = 170u; out_ecx = 24000000u; out_edx = 0u;
                break;
            case 0x16u:
                out_eax = 2800u; out_ebx = 4000u; out_ecx = 100u; out_edx = 0u;
                break;
            case 0x80000000u:
                out_eax = 0x80000008u; out_ebx = 0u; out_ecx = 0u; out_edx = 0u;
                break;
            case 0x80000001u:
                out_eax = 0x000906E9u;
                out_ebx = 0u;
                out_ecx = 0x00000121u;
                out_edx = 0x2C100800u;
                break;
            case 0x80000002u:
                out_eax = 0x65746E49u; out_ebx = 0x2952286Cu; out_ecx = 0x726F4320u; out_edx = 0x4D542865u;
                break;
            case 0x80000003u:
                out_eax = 0x37692029u; out_ebx = 0x50432020u; out_ecx = 0x20202020u; out_edx = 0x20202055u;
                break;
            case 0x80000004u:
                out_eax = 0x2E322040u; out_ebx = 0x4730382Eu; out_ecx = 0x007A487Au; out_edx = 0x00000000u;
                break;
            case 0x80000006u:
                out_eax = 0u; out_ebx = 0u; out_ecx = 0x01006040u; out_edx = 0u;
                break;
            case 0x80000008u:
                out_eax = 0x00003027u;
                out_ebx = 0u; out_ecx = 0u; out_edx = 0u;
                break;
            default:
                if (in_eax > 0x16u && in_eax < 0x80000000u) {
                    out_eax = 2800u; out_ebx = 4000u; out_ecx = 100u; out_edx = 0u;
                } else if (in_eax > 0x80000008u) {
                    out_eax = 0x00003027u; out_ebx = 0u; out_ecx = 0u; out_edx = 0u;
                } else {
                    out_eax = 0u; out_ebx = 0u; out_ecx = 0u; out_edx = 0u;
                }
                break;
        }
#endif
        ctx.set_reg(REG_RAX, static_cast<uint64_t>(out_eax));
        ctx.set_reg(REG_RBX, static_cast<uint64_t>(out_ebx));
        ctx.set_reg(REG_RCX, static_cast<uint64_t>(out_ecx));
        ctx.set_reg(REG_RDX, static_cast<uint64_t>(out_edx));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
|}

(* Legacy x87 FPU Handlers: circular stack, arithmetic, comparisons, transcendentals *)
let emit_fpu_handlers b =
  Buffer.add_string b
    {|
    H_FPU_PUSH_ST: {
        const double val = ctx.get_st(static_cast<uint8_t>(imm & 7ULL));
        ctx.fpu_push(val);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_PUSH_MEM: {
        const uint64_t addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        const uint64_t mode = (word >> 50) & 0x3FFFULL;
        double val = 0.0;
        if (mode & 1ULL) {
            float f = 0.0f;
            std::memcpy(&f, reinterpret_cast<const void*>(addr), 4);
            val = static_cast<double>(f);
        } else if (mode & 2ULL) {
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__)
            long double ld = 0.0L;
            std::memcpy(&ld, reinterpret_cast<const void*>(addr), 10);
            val = static_cast<double>(ld);
#else
            uint64_t mantissa = 0; uint16_t exp_bits = 0;
            std::memcpy(&mantissa, reinterpret_cast<const void*>(addr), 8);
            std::memcpy(&exp_bits, reinterpret_cast<const void*>(addr + 8), 2);
            const int sign = (exp_bits & 0x8000) ? -1 : 1;
            const int exp = (exp_bits & 0x7FFF);
            if (exp == 0 && mantissa == 0) val = 0.0 * sign;
            else if (exp == 0x7FFF) val = (mantissa & 0x7FFFFFFFFFFFFFFFULL) ? NAN : (sign * INFINITY);
            else val = sign * std::ldexp(static_cast<double>(mantissa) / 9223372036854775808.0, exp - 16382);
#endif
        } else {
            std::memcpy(&val, reinterpret_cast<const void*>(addr), 8);
        }
        ctx.fpu_push(val);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_PUSH_INT: {
        const uint64_t addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        const uint64_t wcode = (word >> 50) & 0x3FFFULL;
        double val = 0.0;
        if (wcode == 1ULL) {
            int16_t v = 0;
            std::memcpy(&v, reinterpret_cast<const void*>(addr), 2);
            val = static_cast<double>(v);
        } else if (wcode == 2ULL) {
            int32_t v = 0;
            std::memcpy(&v, reinterpret_cast<const void*>(addr), 4);
            val = static_cast<double>(v);
        } else {
            int64_t v = 0;
            std::memcpy(&v, reinterpret_cast<const void*>(addr), 8);
            val = static_cast<double>(v);
        }
        ctx.fpu_push(val);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_STORE_ST: {
        const double val = ctx.get_st(0);
        ctx.set_st(static_cast<uint8_t>(imm & 7ULL), val);
        const uint64_t pop_flag = (word >> 50) & 0x3FFFULL;
        if (pop_flag & 1ULL) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_STORE_MEM: {
        const double val = ctx.get_st(0);
        const uint64_t addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        const uint64_t flags = (word >> 50) & 0x3FFFULL;
        if (flags & 1ULL) {
            float f = static_cast<float>(val);
            std::memcpy(reinterpret_cast<void*>(addr), &f, 4);
        } else if (flags & 2ULL) {
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__)
            long double ld = static_cast<long double>(val);
            std::memcpy(reinterpret_cast<void*>(addr), &ld, 10);
#else
            double d = val;
            std::memcpy(reinterpret_cast<void*>(addr), &d, 8);
            uint16_t pad = 0;
            std::memcpy(reinterpret_cast<void*>(addr + 8), &pad, 2);
#endif
        } else {
            std::memcpy(reinterpret_cast<void*>(addr), &val, 8);
        }
        if (flags & 4ULL) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_STORE_INT: {
        const double val = ctx.get_st(0);
        const uint64_t addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        const uint64_t flags = (word >> 50) & 0x3FFFULL;
        const int64_t ival = static_cast<int64_t>(std::nearbyint(val));
        const uint64_t wcode = flags & 3ULL;
        if (wcode == 1ULL) {
            int16_t v = static_cast<int16_t>(ival);
            std::memcpy(reinterpret_cast<void*>(addr), &v, 2);
        } else if (wcode == 2ULL) {
            int32_t v = static_cast<int32_t>(ival);
            std::memcpy(reinterpret_cast<void*>(addr), &v, 4);
        } else {
            std::memcpy(reinterpret_cast<void*>(addr), &ival, 8);
        }
        if (flags & 4ULL) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_BINOP: {
        const double a = ctx.get_st(static_cast<uint8_t>(dst));
        const double b = ctx.get_st(static_cast<uint8_t>(src));
        const uint64_t flags = (word >> 50) & 0x3FFFULL;
        const uint64_t fop = (flags >> 1) & 7ULL;
        double res = 0.0;
        switch (fop) {
            case 0: res = a + b; break;
            case 1: res = a - b; break;
            case 2: res = b - a; break;
            case 3: res = a * b; break;
            case 4: res = (b == 0.0) ? 0.0 : (a / b); break;
            case 5: res = (a == 0.0) ? 0.0 : (b / a); break;
            default: res = a + b; break;
        }
        ctx.set_st(static_cast<uint8_t>(dst), res);
        if (flags & 1ULL) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_BINOP_MEM: {
        const uint64_t addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        const uint64_t flags = (word >> 50) & 0x3FFFULL;
        const uint64_t fop = (flags >> 1) & 7ULL;
        double b = 0.0;
        if (flags & 1ULL) {
            float f = 0.0f;
            std::memcpy(&f, reinterpret_cast<const void*>(addr), 4);
            b = static_cast<double>(f);
        } else {
            std::memcpy(&b, reinterpret_cast<const void*>(addr), 8);
        }
        const double a = ctx.get_st(0);
        double res = 0.0;
        switch (fop) {
            case 0: res = a + b; break;
            case 1: res = a - b; break;
            case 2: res = b - a; break;
            case 3: res = a * b; break;
            case 4: res = (b == 0.0) ? 0.0 : (a / b); break;
            case 5: res = (a == 0.0) ? 0.0 : (b / a); break;
            default: res = a + b; break;
        }
        ctx.set_st(0, res);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_COMPARE: {
        const double a = ctx.get_st(0);
        const double b = ctx.get_st(static_cast<uint8_t>(imm & 7ULL));
        uint16_t sw = ctx.get_fsw() & ~0x4500;
        if (std::isnan(a) || std::isnan(b)) {
            sw |= 0x4500;
        } else if (a < b) {
            sw |= 0x0100;
        } else if (a == b) {
            sw |= 0x4000;
        }
        ctx.set_fsw(sw);
        const uint64_t pop_count = (word >> 50) & 0x3FFFULL;
        for (uint64_t p = 0; p < pop_count; ++p) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_COMPARE_I: {
        const double a = ctx.get_st(0);
        const double b = ctx.get_st(static_cast<uint8_t>(imm & 7ULL));
        ctx.of = false; ctx.sf = false;
        if (std::isnan(a) || std::isnan(b)) {
            ctx.zf = true; ctx.pf = true; ctx.cf = true;
        } else if (a < b) {
            ctx.zf = false; ctx.pf = false; ctx.cf = true;
        } else if (a == b) {
            ctx.zf = true; ctx.pf = false; ctx.cf = false;
        } else {
            ctx.zf = false; ctx.pf = false; ctx.cf = false;
        }
        const uint64_t pop_flag = (word >> 50) & 0x3FFFULL;
        if (pop_flag & 1ULL) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_COMPARE_MEM: {
        const uint64_t addr = ctx.get_reg(src) + static_cast<uint64_t>(imm);
        const uint64_t flags = (word >> 50) & 0x3FFFULL;
        double b = 0.0;
        if (flags & 1ULL) {
            float f = 0.0f;
            std::memcpy(&f, reinterpret_cast<const void*>(addr), 4);
            b = static_cast<double>(f);
        } else {
            std::memcpy(&b, reinterpret_cast<const void*>(addr), 8);
        }
        const double a = ctx.get_st(0);
        uint16_t sw = ctx.get_fsw() & ~0x4500;
        if (std::isnan(a) || std::isnan(b)) {
            sw |= 0x4500;
        } else if (a < b) {
            sw |= 0x0100;
        } else if (a == b) {
            sw |= 0x4000;
        }
        ctx.set_fsw(sw);
        if (flags & 4ULL) ctx.fpu_pop();
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_UNARY: {
        const double a = ctx.get_st(0);
        double res = a;
        switch (imm & 3ULL) {
            case 0: res = -a; break;
            case 1: res = std::fabs(a); break;
            case 2: res = std::sqrt(a); break;
            default: break;
        }
        ctx.set_st(0, res);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_CONST: {
        double c = 0.0;
        switch (imm & 7ULL) {
            case 0: c = 0.0; break;
            case 1: c = 1.0; break;
            case 2: c = 3.14159265358979323846; break;
            case 3: c = 1.44269504088896340736; break;
            case 4: c = 3.32192809488736234787; break;
            case 5: c = 0.30102999566398119521; break;
            case 6: c = 0.693147180559945309417; break;
            default: c = 0.0; break;
        }
        ctx.fpu_push(c);
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_TRANS: {
        switch (imm & 7ULL) {
            case 0:
                ctx.set_st(0, std::sin(ctx.get_st(0)));
                break;
            case 1:
                ctx.set_st(0, std::cos(ctx.get_st(0)));
                break;
            case 2: {
                const double v = ctx.get_st(0);
                ctx.set_st(0, std::sin(v));
                ctx.fpu_push(std::cos(v));
                break;
            }
            case 3:
                ctx.set_st(0, std::tan(ctx.get_st(0)));
                ctx.fpu_push(1.0);
                break;
            case 4: {
                const double y = ctx.get_st(1);
                const double x = ctx.get_st(0);
                ctx.fpu_pop();
                ctx.set_st(0, std::atan2(y, x));
                break;
            }
            case 5: {
                const double y = ctx.get_st(1);
                const double x = ctx.get_st(0);
                ctx.fpu_pop();
                ctx.set_st(0, y * std::log2(x));
                break;
            }
            case 6: {
                const double y = ctx.get_st(1);
                const double x = ctx.get_st(0);
                ctx.fpu_pop();
                ctx.set_st(0, y * std::log2(x + 1.0));
                break;
            }
            case 7:
                ctx.set_st(0, std::pow(2.0, ctx.get_st(0)) - 1.0);
                break;
            default: break;
        }
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
    H_FPU_STATUS_TO_AX: {
        const uint16_t fsw = ctx.get_fsw();
        const uint64_t cur_rax = ctx.get_reg(REG_RAX);
        ctx.set_reg(REG_RAX, (cur_rax & ~0xFFFFULL) | static_cast<uint64_t>(fsw));
        ctx.executed_instructions++;
        FETCH_NEXT();
    }
|}

let emit_simd_handlers ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  let vadd_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vd" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]]);
           decl_var (StructType "uint64x2_t") "vs" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]]);
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vaddq_u64" [var "vd"; var "vs"]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vd" ~init:(call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")]);
             decl_var (StructType "__m128i") "vs" ~init:(call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")]);
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_add_epi64" [var "vd"; var "vs"]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             set_vreg (var "dst") (var "d0" +~ var "s0") (var "d1" +~ var "s1");
           ]
         ]
       ]
     | 1 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vaddq_u64" [
             call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]];
             call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]];
           ]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_add_epi64" [
               call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")];
               call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")];
             ]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             let_u64 "_r0" (var "d0" +~ var "s0");
             let_u64 "_r1" (var "d1" +~ var "s1");
             set_vreg (var "dst") (var "_r0") (var "_r1");
           ]
         ]
       ]
     | _ -> [
         let_u64 "_res0" (var "d0" +~ var "s0");
         let_u64 "_res1" (var "d1" +~ var "s1");
         set_vreg (var "dst") (var "_res0") (var "_res1");
       ])
  in
  emit_handler_ast b "H_VADD_VV" (vadd_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vsub_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vd" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]]);
           decl_var (StructType "uint64x2_t") "vs" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]]);
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vsubq_u64" [var "vd"; var "vs"]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vd" ~init:(call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")]);
             decl_var (StructType "__m128i") "vs" ~init:(call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")]);
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_sub_epi64" [var "vd"; var "vs"]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             set_vreg (var "dst") (var "d0" -~ var "s0") (var "d1" -~ var "s1");
           ]
         ]
       ]
     | 1 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "vsubq_u64" [
             call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]];
             call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]];
           ]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_sub_epi64" [
               call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")];
               call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")];
             ]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             let_u64 "_r0" (var "d0" -~ var "s0");
             let_u64 "_r1" (var "d1" -~ var "s1");
             set_vreg (var "dst") (var "_r0") (var "_r1");
           ]
         ]
       ]
     | _ -> [
         let_u64 "_res0" (var "d0" -~ var "s0");
         let_u64 "_res1" (var "d1" -~ var "s1");
         set_vreg (var "dst") (var "_res0") (var "_res1");
       ])
  in
  emit_handler_ast b "H_VSUB_VV" (vsub_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vmul_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [ set_vreg (var "dst") (var "d0" *~ var "s0") (var "d1" *~ var "s1") ]
     | 1 -> [
         let_u64 "_m0" (var "d0" *~ var "s0");
         let_u64 "_m1" (var "d1" *~ var "s1");
         set_vreg (var "dst") (var "_m0") (var "_m1");
       ]
     | _ -> [
         set_vreg (var "dst") (cast UInt64 (var "d0" *~ var "s0")) (cast UInt64 (var "d1" *~ var "s1"));
       ])
  in
  emit_handler_ast b "H_VMUL_VV" (vmul_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vxor_vv_stmts =
    let_u64 "d0" (get_vreg_lane (var "dst") (i32 0)) ::
    let_u64 "d1" (get_vreg_lane (var "dst") (i32 1)) ::
    let_u64 "s0" (get_vreg_lane (var "src") (i32 0)) ::
    let_u64 "s1" (get_vreg_lane (var "src") (i32 1)) ::
    (match pick_variant 3 with
     | 0 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vd" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]]);
           decl_var (StructType "uint64x2_t") "vs" ~init:(call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]]);
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "veorq_u64" [var "vd"; var "vs"]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vd" ~init:(call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")]);
             decl_var (StructType "__m128i") "vs" ~init:(call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")]);
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_xor_si128" [var "vd"; var "vs"]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             set_vreg (var "dst") (var "d0" ^~ var "s0") (var "d1" ^~ var "s1");
           ]
         ]
       ]
     | 1 -> [
         preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__aarch64__)" [
           decl_var (StructType "uint64x2_t") "vr" ~init:(call "veorq_u64" [
             call "vcombine_u64" [call "vcreate_u64" [var "d0"]; call "vcreate_u64" [var "d1"]];
             call "vcombine_u64" [call "vcreate_u64" [var "s0"]; call "vcreate_u64" [var "s1"]];
           ]);
           set_vreg (var "dst") (call "vgetq_lane_u64" [var "vr"; i32 0]) (call "vgetq_lane_u64" [var "vr"; i32 1]);
         ] ~else_stmts:[
           preproc_if_stmt "defined(ASGARD_VECTOR_ISA) && defined(__x86_64__)" [
             decl_var (StructType "__m128i") "vr" ~init:(call "_mm_xor_si128" [
               call "_mm_set_epi64x" [cast Int64 (var "d1"); cast Int64 (var "d0")];
               call "_mm_set_epi64x" [cast Int64 (var "s1"); cast Int64 (var "s0")];
             ]);
             set_vreg (var "dst") (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 0])) (cast UInt64 (call "_mm_extract_epi64" [var "vr"; i32 1]));
           ] ~else_stmts:[
             let_u64 "_r0" (var "d0" ^~ var "s0");
             let_u64 "_r1" (var "d1" ^~ var "s1");
             set_vreg (var "dst") (var "_r0") (var "_r1");
           ]
         ]
       ]
     | _ -> [
         let_u64 "_res0" (var "d0" ^~ var "s0");
         let_u64 "_res1" (var "d1" ^~ var "s1");
         set_vreg (var "dst") (var "_res0") (var "_res1");
       ])
  in
  emit_handler_ast b "H_VXOR_VV" (vxor_vv_stmts @ [ inc_instrs; fetch_next ]);

  let vec_mov_stmts = match pick_variant 3 with
    | 0 -> [
        let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
        if_then_else (var "bits" ==~ i32 32) [
          let_u64 "_dst0" (get_vreg_lane (var "dst") (i32 0));
          let_u64 "_src0" (get_vreg_lane (var "src") (i32 0));
          set_vreg_lane (var "dst") (i32 0)
            ((var "_dst0" &~ u64 0xFFFFFFFF00000000L) |~ (var "_src0" &~ u64 0xFFFFFFFFL));
        ] [
          for_range "i" (i32 0) ((var "bits" +~ i32 63) /~ i32 64) [
            set_vreg_lane (var "dst") (var "i") (get_vreg_lane (var "src") (var "i"));
          ];
        ];
      ]
    | 1 -> [
        let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
        if_then_else (var "bits" ==~ i32 32) [
          let_u64 "_dst0" (get_vreg_lane (var "dst") (i32 0));
          let_u64 "_src0" (get_vreg_lane (var "src") (i32 0));
          set_vreg_lane (var "dst") (i32 0)
            ((var "_dst0" &~ u64 0xFFFFFFFF00000000L) |~ (var "_src0" &~ u64 0xFFFFFFFFL));
        ] [
          let_size_t "_words" (cast SizeT ((var "bits" +~ i32 63) /~ i32 64));
          for_range "i" (i32 0) (var "_words") [
            let_u64 "_v" (get_vreg_lane (var "src") (var "i"));
            set_vreg_lane (var "dst") (var "i") (var "_v");
          ];
        ];
      ]
    | _ -> [
        let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
        if_then_else (var "bits" ==~ i32 32) [
          let_u64 "_dst0" (get_vreg_lane (var "dst") (i32 0));
          let_u64 "_src0" (get_vreg_lane (var "src") (i32 0));
          set_vreg_lane (var "dst") (i32 0)
            ((var "_dst0" &~ u64 0xFFFFFFFF00000000L) |~ (var "_src0" &~ u64 0xFFFFFFFFL));
        ] [
          decl_var SizeT "i" ~init:(i32 0);
          while_loop (var "i" <~ ((var "bits" +~ i32 63) /~ i32 64)) [
            set_vreg_lane (var "dst") (var "i") (get_vreg_lane (var "src") (var "i"));
            (var "i" += i32 1);
          ];
        ];
      ]
  in
  emit_handler_ast b "H_VEC_MOV" (vec_mov_stmts @ [ inc_instrs; fetch_next ]);
  let vec_binop_stmts = [
    let_u32 "src2" (cast UInt32 (var "imm" &~ u64 31L));
    let_u32 "bits" (cast UInt32 ((var "imm" >>~ i32 5) &~ u64 0x3FFL));
    decl_var UInt32 "lane_bits" ~init:(cast UInt32 ((var "imm" >>~ i32 15) &~ u64 0xFFL));
    if_then (var "lane_bits" ==~ i32 0) [ var "lane_bits" := i32 64 ];
    let_u32 "vop" (cast UInt32 ((var "imm" >>~ i32 23) &~ u64 0x1FL));
    let_u32 "elem" (cast UInt32 ((var "imm" >>~ i32 28) &~ u64 0x3L));
    let_u64 "mask" (ternary (var "lane_bits" ==~ i32 8) (u64 0xFFL)
      (ternary (var "lane_bits" ==~ i32 16) (u64 0xFFFFL)
        (ternary (var "lane_bits" ==~ i32 32) (u64 0xFFFFFFFFL) (u64 (-1L)))));
    decl_var SizeT "bit" ~init:(i32 0);
    while_loop (var "bit" <~ var "bits") [
      let_size_t "chunk" (var "bit" /~ i32 64);
      decl_var UInt32 "shift" ~init:(cast UInt32 (var "bit" %~ i32 64));
      let_u64 "a" ((get_vreg_lane (var "src") (var "chunk") >>~ var "shift") &~ var "mask");
      let_u64 "b" ((get_vreg_lane (var "src2") (var "chunk") >>~ var "shift") &~ var "mask");
      decl_var UInt64 "value" ~init:(u64 0L);
      if_then_else ((var "elem" ==~ i32 1) &&~ (var "vop" <=~ i32 2)) [
        decl_var Float "fa" ~init:(bit_cast Float (cast UInt32 (var "a")));
        decl_var Float "fb" ~init:(bit_cast Float (cast UInt32 (var "b")));
        decl_var Float "fr" ~init:(ternary (var "vop" ==~ i32 0) (var "fa" +~ var "fb")
          (ternary (var "vop" ==~ i32 1) (var "fa" -~ var "fb") (var "fa" *~ var "fb")));
        var "value" := bit_cast UInt32 (var "fr");
      ] [
        if_then_else ((var "elem" ==~ i32 1) &&~ (var "vop" ==~ i32 11)) [
          decl_var Float "fa" ~init:(bit_cast Float (cast UInt32 (var "a")));
          decl_var Float "fb" ~init:(bit_cast Float (cast UInt32 (var "b")));
          var "value" := bit_cast UInt32 (call "std::fmin" [var "fa"; var "fb"]);
        ] [
          if_then_else ((var "elem" ==~ i32 1) &&~ (var "vop" ==~ i32 12)) [
            decl_var Float "fa" ~init:(bit_cast Float (cast UInt32 (var "a")));
            decl_var Float "fb" ~init:(bit_cast Float (cast UInt32 (var "b")));
            var "value" := bit_cast UInt32 (call "std::fmax" [var "fa"; var "fb"]);
          ] [
            if_then_else ((var "elem" ==~ i32 2) &&~ (var "vop" <=~ i32 2)) [
              decl_var Double "fa" ~init:(bit_cast Double (var "a"));
              decl_var Double "fb" ~init:(bit_cast Double (var "b"));
              decl_var Double "fr" ~init:(ternary (var "vop" ==~ i32 0) (var "fa" +~ var "fb")
                (ternary (var "vop" ==~ i32 1) (var "fa" -~ var "fb") (var "fa" *~ var "fb")));
              var "value" := bit_cast UInt64 (var "fr");
            ] [
              if_then_else ((var "elem" ==~ i32 2) &&~ (var "vop" ==~ i32 11)) [
                decl_var Double "fa" ~init:(bit_cast Double (var "a"));
                decl_var Double "fb" ~init:(bit_cast Double (var "b"));
                var "value" := bit_cast UInt64 (call "std::fmin" [var "fa"; var "fb"]);
              ] [
                if_then_else ((var "elem" ==~ i32 2) &&~ (var "vop" ==~ i32 12)) [
                  decl_var Double "fa" ~init:(bit_cast Double (var "a"));
                  decl_var Double "fb" ~init:(bit_cast Double (var "b"));
                  var "value" := bit_cast UInt64 (call "std::fmax" [var "fa"; var "fb"]);
                ] [
                  let_i64 "sa" (ternary (var "lane_bits" ==~ i32 8) (cast Int64 (c_cast Int8 (var "a")))
                    (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (var "a")))
                      (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (var "a"))) (cast Int64 (var "a")))));
                  let_i64 "sb" (ternary (var "lane_bits" ==~ i32 8) (cast Int64 (c_cast Int8 (var "b")))
                    (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (var "b")))
                      (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (var "b"))) (cast Int64 (var "b")))));
                  switch_annotated (var "vop") [
                    case (i32 0) [ var "value" := var "a" +~ var "b"; break_stmt ];
                    case (i32 1) [ var "value" := var "a" -~ var "b"; break_stmt ];
                    case (i32 2) [ var "value" := var "a" *~ var "b"; break_stmt ];
                    case (i32 3) [ var "value" := var "a" &~ var "b"; break_stmt ];
                    case (i32 4) [ var "value" := var "a" |~ var "b"; break_stmt ];
                    case (i32 5) [ var "value" := var "a" ^~ var "b"; break_stmt ];
                    case (i32 6) [
                      block [
                        let_u32 "cnt" (cast UInt32 (get_vreg_lane (var "src2") (i32 0) &~ u64 0xFFL));
                        var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" <<~ var "cnt");
                        break_stmt;
                      ]
                    ];
                    case (i32 7) [
                      block [
                        let_u32 "cnt" (cast UInt32 (get_vreg_lane (var "src2") (i32 0) &~ u64 0xFFL));
                        var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" >>~ var "cnt");
                        break_stmt;
                      ]
                    ];
                    case (i32 8) [
                      block [
                        let_u32 "cnt" (cast UInt32 (get_vreg_lane (var "src2") (i32 0) &~ u64 0xFFL));
                        var "value" := ternary (var "cnt" >=~ var "lane_bits")
                          (ternary (var "sa" <~ i32 0) (var "mask") (u64 0L))
                          ((cast UInt64 (var "sa" >>~ var "cnt")) &~ var "mask");
                        break_stmt;
                      ]
                    ];
                    case (i32 9) [ var "value" := ternary (var "a" ==~ var "b") (var "mask") (u64 0L); break_stmt ];
                    case (i32 10) [ var "value" := ternary (var "sa" >~ var "sb") (var "mask") (u64 0L); break_stmt ];
                    case (i32 11) [ var "value" := ternary (var "sa" <~ var "sb") (var "a") (var "b"); break_stmt ];
                    case (i32 12) [ var "value" := ternary (var "sa" >~ var "sb") (var "a") (var "b"); break_stmt ];
                    case (i32 13) [ var "value" := ternary (var "a" <~ var "b") (var "a") (var "b"); break_stmt ];
                    case (i32 14) [ var "value" := ternary (var "a" >~ var "b") (var "a") (var "b"); break_stmt ];
                    case (i32 15) [
                      var "value" := (cast UInt64 (ternary (var "sa" <~ i32 0) (neg (var "sa")) (var "sa"))) &~ var "mask";
                      break_stmt;
                    ];
                    case (i32 16) [ var "value" := (bit_not (var "a")) &~ var "b"; break_stmt ];
                    case (i32 17) [
                      block [
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ (i32 128 /~ var "lane_bits"));
                        let_size_t "half_idx" (var "block_lane" /~ i32 2);
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "half_idx" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 18) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "half_idx" ((var "num_lanes" /~ i32 2) +~ (var "block_lane" /~ i32 2));
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "half_idx" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 21) [
                      block [
                        let_u8 "ctrl" (cast UInt8 (var "b" &~ u64 0xFFL));
                        if_then_else ((var "ctrl" &~ i32 0x80) <>~ i32 0) [
                          var "value" := u64 0L;
                        ] [
                          let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ ((var "ctrl" &~ i32 0xF) *~ i32 8));
                          var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFL;
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 23) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "half_len" (var "num_lanes" /~ i32 2);
                        let_size_t "src_reg" (ternary (var "block_lane" <~ var "half_len") (var "src") (var "src2"));
                        let_size_t "sel_elem" (ternary (var "block_lane" <~ var "half_len") (var "block_lane" *~ i32 2) ((var "block_lane" -~ var "half_len") *~ i32 2));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 24) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "half_len" (var "num_lanes" /~ i32 2);
                        let_size_t "src_reg" (ternary (var "block_lane" <~ var "half_len") (var "src") (var "src2"));
                        let_size_t "sel_elem" (ternary (var "block_lane" <~ var "half_len") ((var "block_lane" *~ i32 2) +~ i32 1) (((var "block_lane" -~ var "half_len") *~ i32 2) +~ i32 1));
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 25) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "k" (var "block_lane" /~ i32 2);
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "sel_elem" (var "k" *~ i32 2);
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 26) [
                      block [
                        let_size_t "num_lanes" (i32 128 /~ var "lane_bits");
                        let_size_t "block_lane" ((var "bit" /~ var "lane_bits") %~ var "num_lanes");
                        let_size_t "k" (var "block_lane" /~ i32 2);
                        let_size_t "src_reg" (ternary ((var "block_lane" %~ i32 2) ==~ i32 0) (var "src") (var "src2"));
                        let_size_t "sel_elem" ((var "k" *~ i32 2) +~ i32 1);
                        let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel_elem" *~ var "lane_bits"));
                        var "value" := (get_vreg_lane (var "src_reg") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ var "mask";
                        break_stmt;
                      ]
                    ];
                    case (i32 28) [
                      block [
                        let_u8 "idx" (cast UInt8 (var "b" &~ u64 0xFFL));
                        if_then_else (var "idx" <~ i32 16) [
                          let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "idx" *~ i32 8));
                          var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFL;
                        ] [
                          var "value" := u64 0L;
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 29) [
                      block [
                        let_u8 "idx" (cast UInt8 (var "b" &~ u64 0xFFL));
                        if_then_else (var "idx" <~ i32 16) [
                          let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "idx" *~ i32 8));
                          var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFL;
                        ] [
                          var "value" := (get_vreg_lane (var "dst") (var "chunk") >>~ var "shift") &~ u64 0xFFL;
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 30) [
                      block [
                        let_i64 "min_val" (ternary (var "lane_bits" ==~ i32 64) (cast Int64 (u64 0x8000000000000000L))
                          (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (u64 0x80000000L)))
                            (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (i32 0x8000)))
                              (cast Int64 (c_cast Int8 (i32 0x80))))));
                        if_then_else (var "sb" ==~ i32 0) [
                          var "value" := u64 (-1L);
                        ] [
                          if_then_else ((var "sb" ==~ i32 (-1)) &&~ (var "sa" ==~ var "min_val")) [
                            var "value" := cast UInt64 (var "sa");
                          ] [
                            var "value" := cast UInt64 (var "sa" /~ var "sb");
                          ];
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 31) [
                      var "value" := ternary (var "b" <>~ i32 0) (var "a" /~ var "b") (var "mask");
                      break_stmt;
                    ];
                    case (i32 32) [
                      block [
                        let_i64 "min_val" (ternary (var "lane_bits" ==~ i32 64) (cast Int64 (u64 0x8000000000000000L))
                          (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (u64 0x80000000L)))
                            (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (i32 0x8000)))
                              (cast Int64 (c_cast Int8 (i32 0x80))))));
                        if_then_else (var "sb" ==~ i32 0) [
                          var "value" := var "a";
                        ] [
                          if_then_else ((var "sb" ==~ i32 (-1)) &&~ (var "sa" ==~ var "min_val")) [
                            var "value" := u64 0L;
                          ] [
                            var "value" := cast UInt64 (var "sa" %~ var "sb");
                          ];
                        ];
                        break_stmt;
                      ]
                    ];
                    case (i32 33) [
                      var "value" := ternary (var "b" <>~ i32 0) (var "a" %~ var "b") (var "a");
                      break_stmt;
                    ];
                    case (i32 34) [ var "value" := ternary (var "a" <>~ var "b") (var "mask") (u64 0L); break_stmt ];
                    case (i32 35) [ var "value" := ternary (var "sa" <=~ var "sb") (var "mask") (u64 0L); break_stmt ];
                    case (i32 36) [ var "value" := ternary (var "a" <~ var "b") (var "mask") (u64 0L); break_stmt ];
                    case (i32 37) [ var "value" := ternary (var "a" <=~ var "b") (var "mask") (u64 0L); break_stmt ];
                  ] (Some [ var "value" := var "a" ^~ var "b"; break_stmt ])
                ]
              ]
            ]
          ]
        ]
      ];
      let_u64 "old_value" (get_vreg_lane (var "dst") (var "chunk"));
      let_u64 "packed_mask" (var "mask" <<~ var "shift");
      set_vreg_lane (var "dst") (var "chunk")
        ((var "old_value" &~ bit_not (var "packed_mask")) |~ ((var "value" &~ var "mask") <<~ var "shift"));
      (var "bit" += var "lane_bits");
    ];
  ] in
  emit_handler_ast b "H_VEC_BINOP" (vec_binop_stmts @ [ inc_instrs; fetch_next ]);
  emit_sha_handler b;
  emit_pclmul_ssp_handlers b;
  emit_fpu_handlers b;

  let vec_imm_stmts = [
    let_u64 "imm_val" (var "imm" &~ u64 0xFFL);
    let_u32 "bits" (cast UInt32 ((var "imm" >>~ i32 8) &~ u64 0x3FFL));
    decl_var UInt32 "lane_bits" ~init:(cast UInt32 ((var "imm" >>~ i32 18) &~ u64 0xFFL));
    if_then (var "lane_bits" ==~ i32 0) [ var "lane_bits" := i32 64 ];
    let_u32 "vop" (cast UInt32 ((var "imm" >>~ i32 26) &~ u64 0x1FL));
    let_u64 "mask" (ternary (var "lane_bits" ==~ i32 8) (u64 0xFFL)
      (ternary (var "lane_bits" ==~ i32 16) (u64 0xFFFFL)
        (ternary (var "lane_bits" ==~ i32 32) (u64 0xFFFFFFFFL) (u64 (-1L)))));
    decl_var SizeT "bit" ~init:(i32 0);
    while_loop (var "bit" <~ var "bits") [
      let_size_t "chunk" (var "bit" /~ i32 64);
      decl_var UInt32 "shift" ~init:(cast UInt32 (var "bit" %~ i32 64));
      let_u64 "a" ((get_vreg_lane (var "src") (var "chunk") >>~ var "shift") &~ var "mask");
      let_i64 "sa" (ternary (var "lane_bits" ==~ i32 8) (cast Int64 (c_cast Int8 (var "a")))
        (ternary (var "lane_bits" ==~ i32 16) (cast Int64 (c_cast Int16 (var "a")))
          (ternary (var "lane_bits" ==~ i32 32) (cast Int64 (c_cast Int32 (var "a"))) (cast Int64 (var "a")))));
      decl_var UInt64 "value" ~init:(u64 0L);
      switch_annotated (var "vop") [
        case (i32 6) [
          block [
            let_u32 "cnt" (cast UInt32 (var "imm_val"));
            var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" <<~ var "cnt");
            break_stmt;
          ]
        ];
        case (i32 7) [
          block [
            let_u32 "cnt" (cast UInt32 (var "imm_val"));
            var "value" := ternary (var "cnt" >=~ var "lane_bits") (u64 0L) (var "a" >>~ var "cnt");
            break_stmt;
          ]
        ];
        case (i32 8) [
          block [
            let_u32 "cnt" (cast UInt32 (var "imm_val"));
            var "value" := ternary (var "cnt" >=~ var "lane_bits")
              (ternary (var "sa" <~ i32 0) (var "mask") (u64 0L))
              ((cast UInt64 (var "sa" >>~ var "cnt")) &~ var "mask");
            break_stmt;
          ]
        ];
        case (i32 21) [
          block [
            let_size_t "lane_in_128" ((var "bit" /~ i32 32) %~ i32 4);
            let_size_t "sel" ((var "imm_val" >>~ (var "lane_in_128" *~ i32 2)) &~ u64 3L);
            let_size_t "src_bit" (((var "bit" /~ i32 128) *~ i32 128) +~ (var "sel" *~ i32 32));
            var "value" := (get_vreg_lane (var "src") (var "src_bit" /~ i32 64) >>~ (var "src_bit" %~ i32 64)) &~ u64 0xFFFFFFFFL;
            break_stmt;
          ]
        ];
        case (i32 22) [
          block [
            let_size_t "lane_idx" (var "bit" /~ var "lane_bits");
            let_size_t "sel" ((var "imm_val" >>~ (var "lane_idx" %~ i32 8)) &~ u64 1L);
            var "value" := ternary (var "sel" ==~ i32 0) (var "a")
              ((get_vreg_lane (var "dst") (var "chunk") >>~ var "shift") &~ var "mask");
            break_stmt;
          ]
        ];
      ] (Some [ var "value" := var "a"; break_stmt ]);
      let_u64 "old_value" (get_vreg_lane (var "dst") (var "chunk"));
      let_u64 "packed_mask" (var "mask" <<~ var "shift");
      set_vreg_lane (var "dst") (var "chunk")
        ((var "old_value" &~ bit_not (var "packed_mask")) |~ ((var "value" &~ var "mask") <<~ var "shift"));
      (var "bit" += var "lane_bits");
    ];
  ] in
  emit_handler_ast b "H_VEC_IMM" (vec_imm_stmts @ [ inc_instrs; fetch_next ]);

  emit_handler_ast b "H_VEC_CLEAR_UPPER" [
    set_vreg_lane (var "dst") (i32 2) (u64 0L);
    set_vreg_lane (var "dst") (i32 3) (u64 0L);
    inc_instrs; fetch_next;
  ];

  emit_handler_ast b "H_VEC_ZERO_UPPER" [
    for_range "i" (i32 0) (i32 16) [
      set_vreg_lane (var "i") (i32 2) (u64 0L);
      set_vreg_lane (var "i") (i32 3) (u64 0L);
    ];
    inc_instrs; fetch_next;
  ];

  let pmovmskb_stmts = [
    let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0x3FFL));
    let_u32 "num_bytes" (var "bits" /~ i32 8);
    decl_var UInt64 "mask" ~init:(u64 0L);
    for_range "b_idx" (i32 0) (var "num_bytes") [
      let_u64 "byte_val" ((get_vreg_lane (var "src") (var "b_idx" /~ i32 8) >>~ ((var "b_idx" %~ i32 8) *~ i32 8)) &~ u64 0xFFL);
      if_then ((var "byte_val" &~ u64 0x80L) <>~ u64 0L) [
        (var "mask" |= (u64 1L <<~ var "b_idx"));
      ];
    ];
    set_reg (var "dst") (var "mask");
  ] in
  emit_handler_ast b "H_PMOVMSKB" (pmovmskb_stmts @ [ inc_instrs; fetch_next ]);

  let vec_load_stmts = [
    let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x3FFL));
    let_u64 "address" (reg_src +~ cast UInt64 (var "imm"));
    for_range "i" (i32 0) (i32 8) [
      set_vreg_lane (var "dst") (var "i") (u64 0L);
    ];
    if_then_else (var "bits" ==~ i32 32) [
      decl_var UInt32 "_val32" ~init:(u32 0l);
      expr_stmt (call "std::memcpy" [
        addr_of (var "_val32");
        reinterpret_cast (ConstPtr Void) (var "address");
        sizeof_expr (var "_val32")
      ]);
      set_vreg_lane (var "dst") (i32 0) (cast UInt64 (var "_val32"));
    ] [
      for_range "i" (i32 0) ((var "bits" +~ i32 63) /~ i32 64) [
        decl_var UInt64 "value" ~init:(u64 0L);
        expr_stmt (call "std::memcpy" [
          addr_of (var "value");
          reinterpret_cast (ConstPtr Void) (var "address" +~ (var "i" *~ i32 8));
          sizeof_expr (var "value")
        ]);
        set_vreg_lane (var "dst") (var "i") (var "value");
      ];
    ];
  ] in
  emit_handler_ast b "H_VEC_LOAD" (vec_load_stmts @ [ inc_instrs; fetch_next ]);

  let vec_store_stmts = [
    let_u32 "bits" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 0x3FFL));
    let_u64 "address" (reg_dst +~ cast UInt64 (var "imm"));
    if_then_else (var "bits" ==~ i32 32) [
      let_u64 "_val0" (get_vreg_lane (var "src") (i32 0));
      decl_var UInt32 "_val32" ~init:(cast UInt32 (var "_val0" &~ u64 0xFFFFFFFFL));
      expr_stmt (call "std::memcpy" [
        reinterpret_cast (Ptr Void) (var "address");
        addr_of (var "_val32");
        sizeof_expr (var "_val32")
      ]);
    ] [
      for_range "i" (i32 0) ((var "bits" +~ i32 63) /~ i32 64) [
        expr_stmt (call "std::memcpy" [
          reinterpret_cast (Ptr Void) (var "address" +~ (var "i" *~ i32 8));
          addr_of (idx (idx (var "ctx.vregs") (var "src" &~ i32 31)) (var "i" &~ i32 7));
          sizeof_ty UInt64
        ]);
      ];
    ];
  ] in
  emit_handler_ast b "H_VEC_STORE" (vec_store_stmts @ [ inc_instrs; fetch_next ]);

  let vec_splat_stmts = [
    let_u32 "bits" (cast UInt32 (var "imm" &~ u64 0xFFFFL));
    let_u32 "lane_bits" (cast UInt32 ((var "imm" >>~ i32 16) &~ u64 0xFFFFL));
    let_u64 "val" reg_src;
    let_u64 "mask" (ternary (var "lane_bits" >=~ i32 64) (u64 (-1L)) ((u64 1L <<~ var "lane_bits") -~ u64 1L));
    let_u64 "val_masked" (var "val" &~ var "mask");
    let_u32 "num_lanes" (ternary (var "lane_bits" >~ i32 0) (var "bits" /~ var "lane_bits") (i32 0));
    for_range "l" (i32 0) (var "num_lanes") [
      let_u32 "pos" (var "l" *~ var "lane_bits");
      let_u32 "chunk" (var "pos" /~ i32 64);
      let_u32 "shift" (var "pos" %~ i32 64);
      let_u64 "packed_mask" (ternary (var "lane_bits" >=~ i32 64) (u64 (-1L)) (var "mask" <<~ var "shift"));
      decl_var UInt64 "cur" ~init:(get_vreg_lane (var "dst") (var "chunk"));
      var "cur" := (var "cur" &~ bit_not (var "packed_mask")) |~ (var "val_masked" <<~ var "shift");
      set_vreg_lane (var "dst") (var "chunk") (var "cur");
    ];
  ] in
  emit_handler_ast b "H_VEC_SPLAT" (vec_splat_stmts @ [ inc_instrs; fetch_next ]);

  let vec_ext_stmts = [
    let_u32 "src2" (cast UInt32 (var "imm" &~ u64 31L));
    let_u32 "shift_bytes" (cast UInt32 ((var "imm" >>~ i32 5) &~ u64 15L));
    decl_var UInt32 "bits" ~init:(cast UInt32 ((var "imm" >>~ i32 9) &~ u64 0x3FFL));
    if_then (var "bits" ==~ i32 0) [ var "bits" := i32 128 ];
    for_range "byte_idx" (i32 0) (var "bits" /~ i32 8) [
      let_size_t "total_idx" ((var "byte_idx" %~ i32 16) +~ var "shift_bytes");
      decl_var UInt64 "val" ~init:(u64 0L);
      if_then_else (var "total_idx" <~ i32 16) [
        let_size_t "bit_pos" (((var "byte_idx" /~ i32 16) *~ i32 128) +~ (var "total_idx" *~ i32 8));
        var "val" := (get_vreg_lane (var "src") (var "bit_pos" /~ i32 64) >>~ (var "bit_pos" %~ i32 64)) &~ u64 0xFFL;
      ] [
        let_size_t "m_idx" (var "total_idx" -~ i32 16);
        let_size_t "bit_pos" (((var "byte_idx" /~ i32 16) *~ i32 128) +~ (var "m_idx" *~ i32 8));
        var "val" := (get_vreg_lane (var "src2") (var "bit_pos" /~ i32 64) >>~ (var "bit_pos" %~ i32 64)) &~ u64 0xFFL;
      ];
      let_size_t "chunk" ((var "byte_idx" *~ i32 8) /~ i32 64);
      decl_var UInt32 "shift" ~init:(cast UInt32 ((var "byte_idx" *~ i32 8) %~ i32 64));
      let_u64 "old_v" (get_vreg_lane (var "dst") (var "chunk"));
      let_u64 "clr" (var "old_v" &~ bit_not (u64 0xFFL <<~ var "shift"));
      set_vreg_lane (var "dst") (var "chunk") (var "clr" |~ (var "val" <<~ var "shift"));
    ];
  ] in
  emit_handler_ast b "H_VEC_EXT" (vec_ext_stmts @ [ inc_instrs; fetch_next ])

let emit_mem_and_ffi_handlers ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in

  let check_sym hashes =
    let conds = List.concat_map (fun h -> [
      var "sym_h" ==~ LitU32 (Int64.to_int32 h);
      var "sym_ah" ==~ LitU32 (Int64.to_int32 h);
    ]) hashes in
    List.fold_left (fun acc c -> acc ||~ c) (List.hd conds) (List.tl conds)
  in
  let arm64_args = [
    let_u64 "a0" (call "ctx.get_reg" [var "REG_RAX"]);
    let_u64 "a1" (call "ctx.get_reg" [var "REG_RCX"]);
    let_u64 "a2" (call "ctx.get_reg" [var "REG_RDX"]);
    let_u64 "a3" (call "ctx.get_reg" [var "REG_RBX"]);
    let_u64 "a4" (call "ctx.get_reg" [var "REG_RSI"]);
    let_u64 "a5" (call "ctx.get_reg" [var "REG_RDI"]);
    let_u64 "a6" (call "ctx.get_reg" [var "REG_R8"]);
    let_u64 "a7" (call "ctx.get_reg" [var "REG_R9"]);
  ] in
  let riscv64_args = [
    let_u64 "a0" (call "ctx.get_reg" [var "REG_RAX"]);
    let_u64 "a1" (call "ctx.get_reg" [var "REG_RDX"]);
    let_u64 "a2" (call "ctx.get_reg" [var "REG_RCX"]);
    let_u64 "a3" (call "ctx.get_reg" [var "REG_RSI"]);
    let_u64 "a4" (call "ctx.get_reg" [var "REG_RDI"]);
    let_u64 "a5" (call "ctx.get_reg" [var "REG_R8"]);
    let_u64 "a6" (call "ctx.get_reg" [var "REG_R9"]);
    let_u64 "a7" (call "ctx.get_reg" [var "REG_R12"]);
  ] in
  let x86_args = [
    let_u64 "a0" (ternary (call "ctx.get_reg" [var "REG_RDI"]) (call "ctx.get_reg" [var "REG_RDI"]) (call "ctx.get_reg" [var "REG_RAX"]));
    let_u64 "a1" (call "ctx.get_reg" [var "REG_RSI"]);
    let_u64 "a2" (call "ctx.get_reg" [var "REG_RDX"]);
    let_u64 "a3" (call "ctx.get_reg" [var "REG_RCX"]);
    let_u64 "a4" (call "ctx.get_reg" [var "REG_R8"]);
    let_u64 "a5" (call "ctx.get_reg" [var "REG_R9"]);
    let_u64 "a6" (call "ctx.get_reg" [var "REG_RAX"]);
    let_u64 "a7" (call "ctx.get_reg" [var "REG_RBX"]);
  ] in
  let reg_args_stmt =
    preproc_if_stmt "defined(ASGARD_GUEST_ARM64) || (!defined(ASGARD_GUEST_X86_64) && !defined(ASGARD_GUEST_RISCV64) && (defined(__aarch64__) || defined(_M_ARM64)))" arm64_args
      ~else_stmts:[
        preproc_if_stmt "defined(ASGARD_GUEST_RISCV64)" riscv64_args
          ~else_stmts:x86_args
      ]
  in
  let printf_branch = [
    raw "typedef int (*printf_fn_t)(const char*, ...);";
    decl_var (StructType "printf_fn_t") "pfn" ~init:(reinterpret_cast (StructType "printf_fn_t") (var "sym_ptr"));
    preproc_if_stmt "defined(__APPLE__) && defined(__aarch64__)" [
      var "ret_val" := c_cast UInt64 (call "pfn" [
        c_cast (ConstPtr (StructType "char")) (var "a0");
        (var "stk").%[i32 0]; (var "stk").%[i32 1]; (var "stk").%[i32 2]; (var "stk").%[i32 3];
        (var "stk").%[i32 4]; (var "stk").%[i32 5]; (var "stk").%[i32 6]; (var "stk").%[i32 7];
      ]);
    ] ~else_stmts:[
      var "ret_val" := c_cast UInt64 (call "pfn" [
        c_cast (ConstPtr (StructType "char")) (var "a0");
        var "a1"; var "a2"; var "a3"; var "a4"; var "a5"; var "a6"; var "a7";
      ]);
    ];
  ] in
  let fprintf_branch = [
    raw "typedef int (*fprintf_fn_t)(void*, const char*, ...);";
    decl_var (StructType "fprintf_fn_t") "fpfn" ~init:(reinterpret_cast (StructType "fprintf_fn_t") (var "sym_ptr"));
    preproc_if_stmt "defined(__APPLE__) && defined(__aarch64__)" [
      var "ret_val" := c_cast UInt64 (call "fpfn" [
        c_cast (Ptr Void) (var "a0");
        c_cast (ConstPtr (StructType "char")) (var "a1");
        (var "stk").%[i32 0]; (var "stk").%[i32 1]; (var "stk").%[i32 2]; (var "stk").%[i32 3];
        (var "stk").%[i32 4]; (var "stk").%[i32 5]; (var "stk").%[i32 6]; (var "stk").%[i32 7];
      ]);
    ] ~else_stmts:[
      var "ret_val" := c_cast UInt64 (call "fpfn" [
        c_cast (Ptr Void) (var "a0");
        c_cast (ConstPtr (StructType "char")) (var "a1");
        var "a2"; var "a3"; var "a4"; var "a5"; var "a6"; var "a7";
      ]);
    ];
  ] in
  let sprintf_branch = [
    raw "typedef int (*sprintf_fn_t)(char*, const char*, ...);";
    decl_var (StructType "sprintf_fn_t") "spfn" ~init:(reinterpret_cast (StructType "sprintf_fn_t") (var "sym_ptr"));
    preproc_if_stmt "defined(__APPLE__) && defined(__aarch64__)" [
      var "ret_val" := c_cast UInt64 (call "spfn" [
        c_cast (Ptr (StructType "char")) (var "a0");
        c_cast (ConstPtr (StructType "char")) (var "a1");
        (var "stk").%[i32 0]; (var "stk").%[i32 1]; (var "stk").%[i32 2]; (var "stk").%[i32 3];
        (var "stk").%[i32 4]; (var "stk").%[i32 5]; (var "stk").%[i32 6]; (var "stk").%[i32 7];
      ]);
    ] ~else_stmts:[
      var "ret_val" := c_cast UInt64 (call "spfn" [
        c_cast (Ptr (StructType "char")) (var "a0");
        c_cast (ConstPtr (StructType "char")) (var "a1");
        var "a2"; var "a3"; var "a4"; var "a5"; var "a6"; var "a7";
      ]);
    ];
  ] in
  let snprintf_branch = [
    raw "typedef int (*snprintf_fn_t)(char*, size_t, const char*, ...);";
    decl_var (StructType "snprintf_fn_t") "snpfn" ~init:(reinterpret_cast (StructType "snprintf_fn_t") (var "sym_ptr"));
    preproc_if_stmt "defined(__APPLE__) && defined(__aarch64__)" [
      var "ret_val" := c_cast UInt64 (call "snpfn" [
        c_cast (Ptr (StructType "char")) (var "a0");
        c_cast SizeT (var "a1");
        c_cast (ConstPtr (StructType "char")) (var "a2");
        (var "stk").%[i32 0]; (var "stk").%[i32 1]; (var "stk").%[i32 2]; (var "stk").%[i32 3];
        (var "stk").%[i32 4]; (var "stk").%[i32 5]; (var "stk").%[i32 6]; (var "stk").%[i32 7];
      ]);
    ] ~else_stmts:[
      var "ret_val" := c_cast UInt64 (call "snpfn" [
        c_cast (Ptr (StructType "char")) (var "a0");
        c_cast SizeT (var "a1");
        c_cast (ConstPtr (StructType "char")) (var "a2");
        var "a3"; var "a4"; var "a5"; var "a6"; var "a7";
      ]);
    ];
  ] in
  let fallback_branch = [
    raw "typedef uint64_t (*extern_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);";
    decl_var (StructType "extern_fn_t") "fn" ~init:(reinterpret_cast (StructType "extern_fn_t") (var "sym_ptr"));
    var "ret_val" := call "fn" [var "a0"; var "a1"; var "a2"; var "a3"; var "a4"; var "a5"; var "a6"; var "a7"];
  ] in
  let if_chain =
    if_then_else (check_sym [0x42FCF5CFL; 0x07554ACDL; 0xE76FB4AAL]) printf_branch
      [
        if_then_else (check_sym [0xFCB512E2L; 0x4B3C5330L; 0x937D1EF6L; 0xCB76D42BL; 0xD54CE817L; 0xBBED3905L; 0x42C07C7CL; 0x24559DBDL]) fprintf_branch
          [
            if_then_else (check_sym [0x7FE32B00L; 0xBCBF60EEL; 0x70E2D349L; 0x44FA3468L]) sprintf_branch
              [
                if_then_else (check_sym [0x54EE11FAL; 0x933075F4L; 0x3FD5EB6FL; 0x5B3553B4L]) snprintf_branch
                  fallback_branch
              ]
          ]
      ]
  in
  let call_extern_stmts = [
    let_size_t "sym_idx" (c_cast SizeT (var "imm"));
    decl_var (Ptr Void) "sym_ptr" ~init:(call "asgard_resolve_sym_idx" [c_cast Int32 (var "sym_idx")]);
    if_then (var "sym_ptr") [
      let_u32 "sym_h" ((var "g_external_symbols").%[var "sym_idx"] $. "hash");
      let_u32 "sym_ah" ((var "g_external_symbols").%[var "sym_idx"] $. "alt_hash");
      reg_args_stmt;
      decl_var (ConstPtr UInt64) "stk" ~init:(reinterpret_cast (ConstPtr UInt64) (call "ctx.get_reg" [var "REG_RSP"]));
      let_u64 "ret_val" (u64 0L);
      if_chain;
      set_reg (var "REG_RAX") (var "ret_val");
    ];
    inc_instrs;
    fetch_next;
  ] in
  emit_handler_ast b "H_CALL_EXTERN" call_extern_stmts;

  let load_64_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (call "asgard::oblivious_mem::oblivious_load_u64" [cast UIntPtr (var "addr")]);
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u64 "_val" (call "asgard::oblivious_mem::oblivious_load_u64" [var "_addr"]);
          set_reg (var "dst") (var "_val");
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (deref (reinterpret_cast (ConstPtr UInt64) (var "addr")));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (deref (reinterpret_cast (ConstPtr UInt64) (var "_base" +~ var "imm")));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u64 "_v" (u64 0L);
          expr_stmt (call "std::memcpy" [addr_of (var "_v"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty UInt64]);
          set_reg (var "dst") (var "_v");
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_64" (load_64_stmts @ [ inc_instrs; fetch_next ]);

  let load_32_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (call "asgard::oblivious_mem::oblivious_load_u32" [cast UIntPtr (var "addr")]));
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u32 "_v32" (call "asgard::oblivious_mem::oblivious_load_u32" [var "_addr"]);
          set_reg (var "dst") (c_cast UInt64 (var "_v32"));
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (deref (reinterpret_cast (ConstPtr UInt32) (var "addr"))));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (c_cast UInt64 (deref (reinterpret_cast (ConstPtr UInt32) (var "_base" +~ var "imm"))));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u32 "_v32" (u32 0l);
          expr_stmt (call "std::memcpy" [addr_of (var "_v32"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty UInt32]);
          set_reg (var "dst") (c_cast UInt64 (var "_v32"));
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_32" (load_32_stmts @ [ inc_instrs; fetch_next ]);

  let load_16_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (call "asgard::oblivious_mem::oblivious_load_u16" [cast UIntPtr (var "addr")]));
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u16 "_v16" (call "asgard::oblivious_mem::oblivious_load_u16" [var "_addr"]);
          set_reg (var "dst") (c_cast UInt64 (var "_v16"));
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (deref (reinterpret_cast (ConstPtr UInt16) (var "addr"))));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (c_cast UInt64 (deref (reinterpret_cast (ConstPtr UInt16) (var "_base" +~ var "imm"))));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u16 "_v16" (c_cast UInt16 (u32 0l));
          expr_stmt (call "std::memcpy" [addr_of (var "_v16"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty UInt16]);
          set_reg (var "dst") (c_cast UInt64 (var "_v16"));
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_16" (load_16_stmts @ [ inc_instrs; fetch_next ]);

  let load_8_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (call "asgard::oblivious_mem::oblivious_load_u8" [cast UIntPtr (var "addr")]));
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u8 "_v8" (call "asgard::oblivious_mem::oblivious_load_u8" [var "_addr"]);
          set_reg (var "dst") (c_cast UInt64 (var "_v8"));
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (deref (reinterpret_cast (ConstPtr UInt8) (var "addr"))));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (c_cast UInt64 (deref (reinterpret_cast (ConstPtr UInt8) (var "_base" +~ var "imm"))));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_u8 "_v8" (u8 0);
          expr_stmt (call "std::memcpy" [addr_of (var "_v8"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty UInt8]);
          set_reg (var "dst") (c_cast UInt64 (var "_v8"));
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_8" (load_8_stmts @ [ inc_instrs; fetch_next ]);

  let load_s32_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (c_cast Int32 (call "asgard::oblivious_mem::oblivious_load_u32" [cast UIntPtr (var "addr")]))));
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_i32 "_s32" (c_cast Int32 (call "asgard::oblivious_mem::oblivious_load_u32" [var "_addr"]));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "_s32")));
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (deref (reinterpret_cast (ConstPtr Int32) (var "addr")))));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (deref (reinterpret_cast (ConstPtr Int32) (var "_base" +~ var "imm")))));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_i32 "_s32" (i32 0);
          expr_stmt (call "std::memcpy" [addr_of (var "_s32"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty Int32]);
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "_s32")));
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_S32" (load_s32_stmts @ [ inc_instrs; fetch_next ]);

  let load_s16_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (c_cast Int16 (call "asgard::oblivious_mem::oblivious_load_u16" [cast UIntPtr (var "addr")]))));
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_i16 "_s16" (c_cast Int16 (call "asgard::oblivious_mem::oblivious_load_u16" [var "_addr"]));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "_s16")));
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (deref (reinterpret_cast (ConstPtr Int16) (var "addr")))));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (deref (reinterpret_cast (ConstPtr Int16) (var "_base" +~ var "imm")))));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_i16 "_s16" (c_cast Int16 (i32 0));
          expr_stmt (call "std::memcpy" [addr_of (var "_s16"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty Int16]);
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "_s16")));
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_S16" (load_s16_stmts @ [ inc_instrs; fetch_next ]);

  let load_s8_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (c_cast Int8 (call "asgard::oblivious_mem::oblivious_load_u8" [cast UIntPtr (var "addr")]))));
        ]
      | _ -> [
          decl_var UIntPtr "_addr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_i8 "_s8" (c_cast Int8 (call "asgard::oblivious_mem::oblivious_load_u8" [var "_addr"]));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "_s8")));
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (deref (reinterpret_cast (ConstPtr Int8) (var "addr")))));
        ]
      | 1 -> [
          decl_var (ConstPtr (StructType "char")) "_base" ~init:(reinterpret_cast (ConstPtr (StructType "char")) reg_src);
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (deref (reinterpret_cast (ConstPtr Int8) (var "_base" +~ var "imm")))));
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_src +~ cast UIntPtr (var "imm"));
          let_i8 "_s8" (c_cast Int8 (i32 0));
          expr_stmt (call "std::memcpy" [addr_of (var "_s8"); reinterpret_cast (ConstPtr Void) (var "_ptr"); sizeof_ty Int8]);
          set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "_s8")));
        ]
    )
  ] in
  emit_handler_ast b "H_LOAD_S8" (load_s8_stmts @ [ inc_instrs; fetch_next ]);

  let store_64_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u64" [cast UIntPtr (var "addr"); reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u64" [var "_ptr"; reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          deref (reinterpret_cast (Ptr UInt64) (var "addr")) := reg_src;
        ]
      | 1 -> [
          decl_var (Ptr (StructType "char")) "_target" ~init:(reinterpret_cast (Ptr (StructType "char")) reg_dst +~ var "imm");
          deref (reinterpret_cast (Ptr UInt64) (var "_target")) := reg_src;
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          let_u64 "_src_v" reg_src;
          expr_stmt (call "std::memcpy" [reinterpret_cast (Ptr Void) (var "_ptr"); addr_of (var "_src_v"); sizeof_ty UInt64]);
        ]
    )
  ] in
  emit_handler_ast b "H_STORE_64" (store_64_stmts @ [ inc_instrs; fetch_next ]);

  let store_32_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u32" [cast UIntPtr (var "addr"); c_cast UInt32 reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u32" [var "_ptr"; c_cast UInt32 reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          deref (reinterpret_cast (Ptr UInt32) (var "addr")) := c_cast UInt32 reg_src;
        ]
      | 1 -> [
          decl_var (Ptr (StructType "char")) "_target" ~init:(reinterpret_cast (Ptr (StructType "char")) reg_dst +~ var "imm");
          deref (reinterpret_cast (Ptr UInt32) (var "_target")) := c_cast UInt32 reg_src;
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          let_u32 "_v32" (c_cast UInt32 reg_src);
          expr_stmt (call "std::memcpy" [reinterpret_cast (Ptr Void) (var "_ptr"); addr_of (var "_v32"); sizeof_ty UInt32]);
        ]
    )
  ] in
  emit_handler_ast b "H_STORE_32" (store_32_stmts @ [ inc_instrs; fetch_next ]);

  let store_16_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u16" [cast UIntPtr (var "addr"); c_cast UInt16 reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u16" [var "_ptr"; c_cast UInt16 reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          deref (reinterpret_cast (Ptr UInt16) (var "addr")) := c_cast UInt16 reg_src;
        ]
      | 1 -> [
          decl_var (Ptr (StructType "char")) "_target" ~init:(reinterpret_cast (Ptr (StructType "char")) reg_dst +~ var "imm");
          deref (reinterpret_cast (Ptr UInt16) (var "_target")) := c_cast UInt16 reg_src;
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          let_u16 "_v16" (c_cast UInt16 reg_src);
          expr_stmt (call "std::memcpy" [reinterpret_cast (Ptr Void) (var "_ptr"); addr_of (var "_v16"); sizeof_ty UInt16]);
        ]
    )
  ] in
  emit_handler_ast b "H_STORE_16" (store_16_stmts @ [ inc_instrs; fetch_next ]);

  let store_8_stmts = [
    preproc_if_stmt "defined(ASGARD_OBLIVIOUS_MEM)" (
      match pick_variant 2 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u8" [cast UIntPtr (var "addr"); c_cast UInt8 reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          expr_stmt (call "asgard::oblivious_mem::oblivious_store_u8" [var "_ptr"; c_cast UInt8 reg_src; addr_of (var "ctx.decoy_sink")]);
        ]
    ) ~else_stmts:(
      match pick_variant 3 with
      | 0 -> [
          let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
          deref (reinterpret_cast (Ptr UInt8) (var "addr")) := c_cast UInt8 reg_src;
        ]
      | 1 -> [
          decl_var (Ptr (StructType "char")) "_target" ~init:(reinterpret_cast (Ptr (StructType "char")) reg_dst +~ var "imm");
          deref (reinterpret_cast (Ptr UInt8) (var "_target")) := c_cast UInt8 reg_src;
        ]
      | _ -> [
          decl_var UIntPtr "_ptr" ~init:(cast UIntPtr reg_dst +~ cast UIntPtr (var "imm"));
          let_u8 "_v8" (c_cast UInt8 reg_src);
          expr_stmt (call "std::memcpy" [reinterpret_cast (Ptr Void) (var "_ptr"); addr_of (var "_v8"); sizeof_ty UInt8]);
        ]
    )
  ] in
  emit_handler_ast b "H_STORE_8" (store_8_stmts @ [ inc_instrs; fetch_next ]);

  let resolve_sym_stmts =
    match pick_variant 3 with
    | 1 -> [
        decl_var SizeT "_idx" ~init:(cast SizeT (var "imm"));
        decl_var (Ptr Void) "_p" ~init:(call "asgard_resolve_sym_idx" [c_cast Int32 (var "_idx")]);
        set_reg (var "dst") (cast UInt64 (reinterpret_cast UIntPtr (var "_p")));
      ]
    | _ -> [
        let_size_t "sym_idx" (c_cast SizeT (var "imm"));
        decl_var (Ptr Void) "sym_ptr" ~init:(call "asgard_resolve_sym_idx" [c_cast Int32 (var "sym_idx")]);
        set_reg (var "dst") (c_cast UInt64 (var "sym_ptr"));
      ]
  in
  emit_handler_ast b "H_RESOLVE_SYM" (resolve_sym_stmts @ [ inc_instrs; fetch_next ]);
  let fadd_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        let_u64 "b_raw" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "a_raw"));
        let_double "b" (bit_cast Double (var "b_raw"));
        set_vreg (var "dst") (bit_cast UInt64 (var "a" +~ var "b")) (u64 0L);
      ]
    | 1 -> [
        let_double "_a" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
        let_double "_b" (bit_cast Double (get_vreg_lane (cast UInt8 (var "imm")) (i32 0)));
        set_vreg (var "dst") (bit_cast UInt64 (var "_a" +~ var "_b")) (u64 0L);
      ]
    | _ -> [
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        let_u64 "_i" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        set_vreg (var "dst") (bit_cast UInt64 (bit_cast Double (var "_s") +~ bit_cast Double (var "_i"))) (u64 0L);
      ]
  in
  emit_handler_ast b "H_FADD_DD" (fadd_stmts @ [ inc_instrs; fetch_next ]);

  let fsub_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        let_u64 "b_raw" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "a_raw"));
        let_double "b" (bit_cast Double (var "b_raw"));
        set_vreg (var "dst") (bit_cast UInt64 (var "a" -~ var "b")) (u64 0L);
      ]
    | 1 -> [
        let_double "_a" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
        let_double "_b" (bit_cast Double (get_vreg_lane (cast UInt8 (var "imm")) (i32 0)));
        set_vreg (var "dst") (bit_cast UInt64 (var "_a" -~ var "_b")) (u64 0L);
      ]
    | _ -> [
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        let_u64 "_i" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        set_vreg (var "dst") (bit_cast UInt64 (bit_cast Double (var "_s") -~ bit_cast Double (var "_i"))) (u64 0L);
      ]
  in
  emit_handler_ast b "H_FSUB_DD" (fsub_stmts @ [ inc_instrs; fetch_next ]);

  let fmul_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        let_u64 "b_raw" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "a_raw"));
        let_double "b" (bit_cast Double (var "b_raw"));
        set_vreg (var "dst") (bit_cast UInt64 (var "a" *~ var "b")) (u64 0L);
      ]
    | 1 -> [
        let_double "_a" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
        let_double "_b" (bit_cast Double (get_vreg_lane (cast UInt8 (var "imm")) (i32 0)));
        set_vreg (var "dst") (bit_cast UInt64 (var "_a" *~ var "_b")) (u64 0L);
      ]
    | _ -> [
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        let_u64 "_i" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        set_vreg (var "dst") (bit_cast UInt64 (bit_cast Double (var "_s") *~ bit_cast Double (var "_i"))) (u64 0L);
      ]
  in
  emit_handler_ast b "H_FMUL_DD" (fmul_stmts @ [ inc_instrs; fetch_next ]);

  let fdiv_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        let_u64 "b_raw" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "a_raw"));
        let_double "b" (bit_cast Double (var "b_raw"));
        let_double "r" (var "a" /~ var "b");
        set_vreg (var "dst") (bit_cast UInt64 (var "r")) (u64 0L);
      ]
    | 1 -> [
        let_double "_a" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
        let_double "_b" (bit_cast Double (get_vreg_lane (cast UInt8 (var "imm")) (i32 0)));
        let_double "_q" (ternary (var "_b" ==~ var "0.0")
          (ternary (var "_a" ==~ var "0.0")
            (var "NAN")
            (ternary (call "std::signbit" [var "_a"] ^~ call "std::signbit" [var "_b"]) (neg (var "INFINITY")) (var "INFINITY")))
          (var "_a" /~ var "_b"));
        set_vreg (var "dst") (bit_cast UInt64 (var "_q")) (u64 0L);
      ]
    | _ -> [
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        let_u64 "_i" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "_s"));
        let_double "b" (bit_cast Double (var "_i"));
        set_vreg (var "dst") (bit_cast UInt64 (ternary (var "b" <>~ var "0.0") (var "a" /~ var "b") (var "0.0"))) (u64 0L);
      ]
  in
  emit_handler_ast b "H_FDIV_DD" (fdiv_stmts @ [ inc_instrs; fetch_next ]);

  let fsqrt_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        let_double "a" (bit_cast Double (var "a_raw"));
        let_double "r" (call "std::sqrt" [var "a"]);
        set_vreg (var "dst") (bit_cast UInt64 (var "r")) (u64 0L);
      ]
    | 1 -> [
        let_double "_a" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
        let_double "_root" (ternary (var "_a" <~ var "0.0") (var "NAN") (call "std::sqrt" [var "_a"]));
        set_vreg (var "dst") (bit_cast UInt64 (var "_root")) (u64 0L);
      ]
    | _ -> [
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        let_double "a" (bit_cast Double (var "_s"));
        set_vreg (var "dst") (bit_cast UInt64 (ternary (var "a" >=~ var "0.0") (call "std::sqrt" [var "a"]) (var "0.0"))) (u64 0L);
      ]
  in
  emit_handler_ast b "H_FSQRT_D" (fsqrt_stmts @ [ inc_instrs; fetch_next ]);

  let fcmp_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        let_u64 "b_raw" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "a_raw"));
        let_double "b" (bit_cast Double (var "b_raw"));
        let_bool "is_nan" (call "std::isnan" [var "a"] ||~ call "std::isnan" [var "b"]);
        var "ctx.zf" := (var "is_nan" ||~ (var "a" ==~ var "b"));
        var "ctx.cf" := (var "is_nan" ||~ (var "a" <~ var "b"));
        var "ctx.pf" := var "is_nan";
        var "ctx.sf" := bool_lit false;
        var "ctx.of" := bool_lit false;
      ]
    | 1 -> [
        let_double "_a" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
        let_double "_b" (bit_cast Double (get_vreg_lane (cast UInt8 (var "imm")) (i32 0)));
        let_bool "_nan" (call "std::isnan" [var "_a"] ||~ call "std::isnan" [var "_b"]);
        var "ctx.of" := bool_lit false;
        var "ctx.sf" := bool_lit false;
        var "ctx.cf" := (var "_nan" ||~ (var "_a" <~ var "_b"));
        var "ctx.zf" := (var "_nan" ||~ (var "_a" ==~ var "_b"));
        var "ctx.pf" := var "_nan";
      ]
    | _ -> [
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        let_u64 "_i" (get_vreg_lane (c_cast UInt8 (var "imm")) (i32 0));
        let_double "a" (bit_cast Double (var "_s"));
        let_double "b" (bit_cast Double (var "_i"));
        let_bool "_nan" (call "std::isnan" [var "a"] ||~ call "std::isnan" [var "b"]);
        let_bool "_eq" (var "a" ==~ var "b");
        let_bool "_lt" (var "a" <~ var "b");
        var "ctx.zf" := (var "_nan" ||~ var "_eq");
        var "ctx.cf" := (var "_nan" ||~ var "_lt");
        var "ctx.pf" := var "_nan";
        var "ctx.sf" := bool_lit false;
        var "ctx.of" := bool_lit false;
      ]
  in
  emit_handler_ast b "H_FCMP_DD" (fcmp_stmts @ [ inc_instrs; fetch_next ]);

  let fcvtzs_stmts = [
    decl_var Double "a";
    if_then_else ((var "imm" &~ u64 1L) <>~ u64 0L)
      [
        let_u32 "f_raw" (c_cast UInt32 (get_vreg_lane (var "src") (i32 0)));
        let_float "f" (bit_cast Float (var "f_raw"));
        (var "a" := cast Double (var "f"));
      ]
      [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        (var "a" := bit_cast Double (var "a_raw"));
      ];
    set_reg (var "dst") (c_cast UInt64 (c_cast Int64 (var "a")));
  ] in
  emit_handler_ast b "H_FCVTZS" (fcvtzs_stmts @ [ inc_instrs; fetch_next ]);

  let scvtf_stmts = [
    decl_var Double "d";
    if_then_else ((var "imm" &~ u64 1L) <>~ u64 0L)
      [ (var "d" := cast Double (cast Int32 reg_src)) ]
      [ (var "d" := cast Double (cast Int64 reg_src)) ];
    if_then_else ((var "imm" &~ u64 2L) <>~ u64 0L)
      [
        decl_var Float "f" ~init:(cast Float (var "d"));
        set_vreg (var "dst") (cast UInt64 (bit_cast UInt32 (var "f"))) (u64 0L);
      ]
      [
        set_vreg (var "dst") (bit_cast UInt64 (var "d")) (u64 0L);
      ];
  ] in
  emit_handler_ast b "H_SCVTF" (scvtf_stmts @ [ inc_instrs; fetch_next ]);

  let fcvtzu_stmts = [
    decl_var Double "a";
    if_then_else ((var "imm" &~ u64 1L) <>~ u64 0L)
      [
        let_u32 "f_raw" (c_cast UInt32 (get_vreg_lane (var "src") (i32 0)));
        let_float "f" (bit_cast Float (var "f_raw"));
        (var "a" := cast Double (var "f"));
      ]
      [
        let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
        (var "a" := bit_cast Double (var "a_raw"));
      ];
    set_reg (var "dst") (ternary (var "a" <~ var "0.0") (u64 0L) (c_cast UInt64 (var "a")));
  ] in
  emit_handler_ast b "H_FCVTZU" (fcvtzu_stmts @ [ inc_instrs; fetch_next ]);

  let ucvtf_stmts = [
    decl_var Double "d";
    if_then_else ((var "imm" &~ u64 1L) <>~ u64 0L)
      [ (var "d" := cast Double (cast UInt32 reg_src)) ]
      [ (var "d" := cast Double reg_src) ];
    if_then_else ((var "imm" &~ u64 2L) <>~ u64 0L)
      [
        decl_var Float "f" ~init:(cast Float (var "d"));
        set_vreg (var "dst") (cast UInt64 (bit_cast UInt32 (var "f"))) (u64 0L);
      ]
      [
        set_vreg (var "dst") (bit_cast UInt64 (var "d")) (u64 0L);
      ];
  ] in
  emit_handler_ast b "H_UCVTF" (ucvtf_stmts @ [ inc_instrs; fetch_next ]);

  let fcvt_stmts =
    match pick_variant 3 with
    | 0 -> [
        if_then_else (c_cast UInt32 (var "imm") ==~ i32 1)
          [
            let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
            let_double "d64" (bit_cast Double (var "a_raw"));
            let_float "f32" (cast Float (var "d64"));
            decl_var UInt32 "u32" ~init:(bit_cast UInt32 (var "f32"));
            let_u64 "old_val" (get_vreg_lane (var "dst") (i32 0));
            set_vreg (var "dst") ((var "old_val" &~ u64 0xFFFFFFFF00000000L) |~ c_cast UInt64 (var "u32")) (u64 0L);
          ]
          [
            let_u64 "a_raw" (get_vreg_lane (var "src") (i32 0));
            let_float "f32" (bit_cast Float (c_cast UInt32 (var "a_raw")));
            set_vreg (var "dst") (bit_cast UInt64 (c_cast Double (var "f32"))) (u64 0L);
          ];
      ]
    | 1 -> [
        if_then_else (cast UInt32 (var "imm") ==~ i32 1)
          [
            let_double "_d" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
            let_float "_f" (cast Float (var "_d"));
            decl_var UInt32 "_u" ~init:(bit_cast UInt32 (var "_f"));
            let_u64 "_prev" (get_vreg_lane (var "dst") (i32 0));
            set_vreg (var "dst") ((var "_prev" &~ u64 0xFFFFFFFF00000000L) |~ cast UInt64 (var "_u")) (u64 0L);
          ]
          [
            decl_var UInt32 "_raw32" ~init:(cast UInt32 (get_vreg_lane (var "src") (i32 0)));
            let_float "_f" (bit_cast Float (var "_raw32"));
            let_double "_d" (cast Double (var "_f"));
            set_vreg (var "dst") (bit_cast UInt64 (var "_d")) (u64 0L);
          ];
      ]
    | _ -> [
        if_then_else (c_cast UInt32 (var "imm") ==~ i32 1)
          [
            let_double "d64" (bit_cast Double (get_vreg_lane (var "src") (i32 0)));
            let_float "f32" (c_cast Float (var "d64"));
            decl_var UInt32 "u32" ~init:(bit_cast UInt32 (var "f32"));
            set_vreg (var "dst") ((get_vreg_lane (var "dst") (i32 0) &~ u64 0xFFFFFFFF00000000L) |~ c_cast UInt64 (var "u32")) (u64 0L);
          ]
          [
            let_float "f32" (bit_cast Float (c_cast UInt32 (get_vreg_lane (var "src") (i32 0))));
            set_vreg (var "dst") (bit_cast UInt64 (c_cast Double (var "f32"))) (u64 0L);
          ];
      ]
  in
  emit_handler_ast b "H_FCVT" (fcvt_stmts @ [ inc_instrs; fetch_next ]);

  let atomic_load_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "addr" (reg_src +~ c_cast UInt64 (var "imm"));
        decl_var (Ptr (StructType "std::atomic<uint64_t>")) "ptr" ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint64_t>")) (var "addr"));
        set_reg (var "dst") (call "ptr->load" [var "std::memory_order_seq_cst"]);
      ]
    | 1 -> [
        let_u64 "_addr" (reg_src +~ cast UInt64 (var "imm"));
        let_u64 "_val" (call "__atomic_load_n" [reinterpret_cast (Ptr UInt64) (var "_addr"); var "__ATOMIC_SEQ_CST"]);
        set_reg (var "dst") (var "_val");
      ]
    | _ -> [
        let_u64 "_addr" (reg_src +~ c_cast UInt64 (var "imm"));
        expr_stmt (call "std::atomic_thread_fence" [var "std::memory_order_seq_cst"]);
        let_u64 "_loaded" (deref (reinterpret_cast (VolatilePtr UInt64) (var "_addr")));
        expr_stmt (call "std::atomic_thread_fence" [var "std::memory_order_seq_cst"]);
        set_reg (var "dst") (var "_loaded");
      ]
  in
  emit_handler_ast b "H_ATOMIC_LOAD" (atomic_load_stmts @ [ inc_instrs; fetch_next ]);

  let atomic_store_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
        decl_var (Ptr (StructType "std::atomic<uint64_t>")) "ptr" ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint64_t>")) (var "addr"));
        expr_stmt (call "ptr->store" [reg_src; var "std::memory_order_seq_cst"]);
      ]
    | 1 -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        expr_stmt (call "__atomic_store_n" [reinterpret_cast (Ptr UInt64) (var "_addr"); reg_src; var "__ATOMIC_SEQ_CST"]);
      ]
    | _ -> [
        let_u64 "_addr" (reg_dst +~ c_cast UInt64 (var "imm"));
        expr_stmt (c_cast Void (call "__atomic_exchange_n" [reinterpret_cast (Ptr UInt64) (var "_addr"); reg_src; var "__ATOMIC_SEQ_CST"]));
      ]
  in
  emit_handler_ast b "H_ATOMIC_STORE" (atomic_store_stmts @ [ inc_instrs; fetch_next ]);

  let atomic_cas_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "addr" (reg_dst +~ c_cast UInt64 (var "imm"));
        decl_var (Ptr (StructType "std::atomic<uint64_t>")) "ptr" ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint64_t>")) (var "addr"));
        let_u64 "expected" reg_src;
        let_u64 "desired" (call "ctx.get_reg" [var "REG_RAX"]);
        expr_stmt (call "ptr->compare_exchange_strong" [var "expected"; var "desired"; var "std::memory_order_seq_cst"]);
        set_reg (var "src") (var "expected");
      ]
    | 1 -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u64 "_exp" reg_src;
        let_u64 "_des" (call "ctx.get_reg" [var "REG_RAX"]);
        expr_stmt (call "__atomic_compare_exchange_n" [
          reinterpret_cast (Ptr UInt64) (var "_addr");
          addr_of (var "_exp");
          var "_des";
          bool_lit false;
          var "__ATOMIC_SEQ_CST";
          var "__ATOMIC_SEQ_CST";
        ]);
        set_reg (var "src") (var "_exp");
      ]
    | _ -> [
        decl_var (Ptr (StructType "std::atomic<uint64_t>")) "ptr" ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint64_t>")) (reg_dst +~ c_cast UInt64 (var "imm")));
        let_u64 "expected" reg_src;
        while_loop (log_not (call "ptr->compare_exchange_weak" [var "expected"; call "ctx.get_reg" [var "REG_RAX"]; var "std::memory_order_seq_cst"; var "std::memory_order_seq_cst"])) [
          if_then (var "expected" <>~ reg_src) [ break_stmt ];
        ];
        set_reg (var "src") (var "expected");
      ]
  in
  emit_handler_ast b "H_ATOMIC_CAS" (atomic_cas_stmts @ [ inc_instrs; fetch_next ]);

  (* The atomic add has three metamorphic variants: the __atomic builtin, the
     C++ atomic member and a load/compare-exchange loop.  All of them honour
     the width code in the word's extra bits (1 = 32-bit, 2 = 16-bit,
     3 = 8-bit, anything else = 64-bit). *)
  let atomic_add_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u32 "wcode" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 3L));
        if_then_else (var "wcode" ==~ i32 1)
          [
            let_u32 "_old32" (call "__atomic_fetch_add" [reinterpret_cast (Ptr UInt32) (var "_addr"); cast UInt32 reg_src; var "__ATOMIC_SEQ_CST"]);
            set_reg (var "src") (cast UInt64 (var "_old32"));
          ]
          [
            if_then_else (var "wcode" ==~ i32 2)
              [
                let_u16 "_old16" (call "__atomic_fetch_add" [reinterpret_cast (Ptr UInt16) (var "_addr"); cast UInt16 reg_src; var "__ATOMIC_SEQ_CST"]);
                set_reg (var "src") (cast UInt64 (var "_old16"));
              ]
              [
                if_then_else (var "wcode" ==~ i32 3)
                  [
                    let_u8 "_old8" (call "__atomic_fetch_add" [reinterpret_cast (Ptr UInt8) (var "_addr"); cast UInt8 reg_src; var "__ATOMIC_SEQ_CST"]);
                    set_reg (var "src") (cast UInt64 (var "_old8"));
                  ]
                  [
                    let_u64 "_old64" (call "__atomic_fetch_add" [reinterpret_cast (Ptr UInt64) (var "_addr"); reg_src; var "__ATOMIC_SEQ_CST"]);
                    set_reg (var "src") (var "_old64");
                  ];
              ];
          ];
      ]
    | 1 -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u32 "wcode" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 3L));
        if_then_else (var "wcode" ==~ i32 1)
          [
            decl_var (Ptr (StructType "std::atomic<uint32_t>")) "_p32"
              ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint32_t>")) (var "_addr"));
            let_u32 "_old32" (call "_p32->fetch_add" [cast UInt32 reg_src; var "std::memory_order_seq_cst"]);
            set_reg (var "src") (cast UInt64 (var "_old32"));
          ]
          [
            if_then_else (var "wcode" ==~ i32 2)
              [
                decl_var (Ptr (StructType "std::atomic<uint16_t>")) "_p16"
                  ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint16_t>")) (var "_addr"));
                let_u16 "_old16" (call "_p16->fetch_add" [cast UInt16 reg_src; var "std::memory_order_seq_cst"]);
                set_reg (var "src") (cast UInt64 (var "_old16"));
              ]
              [
                if_then_else (var "wcode" ==~ i32 3)
                  [
                    decl_var (Ptr (StructType "std::atomic<uint8_t>")) "_p8"
                      ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint8_t>")) (var "_addr"));
                    let_u8 "_old8" (call "_p8->fetch_add" [cast UInt8 reg_src; var "std::memory_order_seq_cst"]);
                    set_reg (var "src") (cast UInt64 (var "_old8"));
                  ]
                  [
                    decl_var (Ptr (StructType "std::atomic<uint64_t>")) "_p64"
                      ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint64_t>")) (var "_addr"));
                    let_u64 "_old64" (call "_p64->fetch_add" [reg_src; var "std::memory_order_seq_cst"]);
                    set_reg (var "src") (var "_old64");
                  ];
              ];
          ];
      ]
    | _ -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u32 "wcode" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 3L));
        let_u64 "_add" reg_src;
        if_then_else (var "wcode" ==~ i32 1)
          [
            decl_var (Ptr UInt32) "_p32" ~init:(reinterpret_cast (Ptr UInt32) (var "_addr"));
            let_u32 "_old32" (call "__atomic_load_n" [var "_p32"; var "__ATOMIC_RELAXED"]);
            while_loop
              (log_not (call "__atomic_compare_exchange_n" [ var "_p32"; addr_of (var "_old32");
                                                           var "_old32" +~ cast UInt32 (var "_add");
                                                           bool_lit false; var "__ATOMIC_SEQ_CST";
                                                           var "__ATOMIC_SEQ_CST" ]))
              [];
            set_reg (var "src") (cast UInt64 (var "_old32"));
          ]
          [
            if_then_else (var "wcode" ==~ i32 2)
              [
                decl_var (Ptr UInt16) "_p16" ~init:(reinterpret_cast (Ptr UInt16) (var "_addr"));
                let_u16 "_old16" (call "__atomic_load_n" [var "_p16"; var "__ATOMIC_RELAXED"]);
                while_loop
                  (log_not (call "__atomic_compare_exchange_n" [ var "_p16"; addr_of (var "_old16");
                                                               var "_old16" +~ cast UInt16 (var "_add");
                                                               bool_lit false; var "__ATOMIC_SEQ_CST";
                                                               var "__ATOMIC_SEQ_CST" ]))
                  [];
                set_reg (var "src") (cast UInt64 (var "_old16"));
              ]
              [
                if_then_else (var "wcode" ==~ i32 3)
                  [
                    decl_var (Ptr UInt8) "_p8" ~init:(reinterpret_cast (Ptr UInt8) (var "_addr"));
                    let_u8 "_old8" (call "__atomic_load_n" [var "_p8"; var "__ATOMIC_RELAXED"]);
                    while_loop
                      (log_not (call "__atomic_compare_exchange_n" [ var "_p8"; addr_of (var "_old8");
                                                                   var "_old8" +~ cast UInt8 (var "_add");
                                                                   bool_lit false; var "__ATOMIC_SEQ_CST";
                                                                   var "__ATOMIC_SEQ_CST" ]))
                      [];
                    set_reg (var "src") (cast UInt64 (var "_old8"));
                  ]
                  [
                    decl_var (Ptr UInt64) "_p64" ~init:(reinterpret_cast (Ptr UInt64) (var "_addr"));
                    let_u64 "_old64" (call "__atomic_load_n" [var "_p64"; var "__ATOMIC_RELAXED"]);
                    while_loop
                      (log_not (call "__atomic_compare_exchange_n" [ var "_p64"; addr_of (var "_old64");
                                                                   var "_old64" +~ var "_add";
                                                                   bool_lit false; var "__ATOMIC_SEQ_CST";
                                                                   var "__ATOMIC_SEQ_CST" ]))
                      [];
                    set_reg (var "src") (var "_old64");
                  ];
              ];
          ];
      ]
  in
  emit_handler_ast b "H_ATOMIC_ADD" (atomic_add_stmts @ [ inc_instrs; fetch_next ]);

  (* The atomic swap has the same three metamorphic variants as the atomic
     add: the __atomic builtin, the C++ atomic member and a
     load/compare-exchange loop. *)
  let atomic_swp_stmts =
    match pick_variant 3 with
    | 0 -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u32 "wcode" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 3L));
        if_then_else (var "wcode" ==~ i32 1)
          [
            let_u32 "_old32" (call "__atomic_exchange_n" [reinterpret_cast (Ptr UInt32) (var "_addr"); cast UInt32 reg_src; var "__ATOMIC_SEQ_CST"]);
            set_reg (var "src") (cast UInt64 (var "_old32"));
          ]
          [
            if_then_else (var "wcode" ==~ i32 2)
              [
                let_u16 "_old16" (call "__atomic_exchange_n" [reinterpret_cast (Ptr UInt16) (var "_addr"); cast UInt16 reg_src; var "__ATOMIC_SEQ_CST"]);
                set_reg (var "src") (cast UInt64 (var "_old16"));
              ]
              [
                if_then_else (var "wcode" ==~ i32 3)
                  [
                    let_u8 "_old8" (call "__atomic_exchange_n" [reinterpret_cast (Ptr UInt8) (var "_addr"); cast UInt8 reg_src; var "__ATOMIC_SEQ_CST"]);
                    set_reg (var "src") (cast UInt64 (var "_old8"));
                  ]
                  [
                    let_u64 "_old64" (call "__atomic_exchange_n" [reinterpret_cast (Ptr UInt64) (var "_addr"); reg_src; var "__ATOMIC_SEQ_CST"]);
                    set_reg (var "src") (var "_old64");
                  ];
              ];
          ];
      ]
    | 1 -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u32 "wcode" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 3L));
        if_then_else (var "wcode" ==~ i32 1)
          [
            decl_var (Ptr (StructType "std::atomic<uint32_t>")) "_p32"
              ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint32_t>")) (var "_addr"));
            let_u32 "_old32" (call "_p32->exchange" [cast UInt32 reg_src; var "std::memory_order_seq_cst"]);
            set_reg (var "src") (cast UInt64 (var "_old32"));
          ]
          [
            if_then_else (var "wcode" ==~ i32 2)
              [
                decl_var (Ptr (StructType "std::atomic<uint16_t>")) "_p16"
                  ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint16_t>")) (var "_addr"));
                let_u16 "_old16" (call "_p16->exchange" [cast UInt16 reg_src; var "std::memory_order_seq_cst"]);
                set_reg (var "src") (cast UInt64 (var "_old16"));
              ]
              [
                if_then_else (var "wcode" ==~ i32 3)
                  [
                    decl_var (Ptr (StructType "std::atomic<uint8_t>")) "_p8"
                      ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint8_t>")) (var "_addr"));
                    let_u8 "_old8" (call "_p8->exchange" [cast UInt8 reg_src; var "std::memory_order_seq_cst"]);
                    set_reg (var "src") (cast UInt64 (var "_old8"));
                  ]
                  [
                    decl_var (Ptr (StructType "std::atomic<uint64_t>")) "_p64"
                      ~init:(reinterpret_cast (Ptr (StructType "std::atomic<uint64_t>")) (var "_addr"));
                    let_u64 "_old64" (call "_p64->exchange" [reg_src; var "std::memory_order_seq_cst"]);
                    set_reg (var "src") (var "_old64");
                  ];
              ];
          ];
      ]
    | _ -> [
        let_u64 "_addr" (reg_dst +~ cast UInt64 (var "imm"));
        let_u32 "wcode" (cast UInt32 ((var "word" >>~ i32 50) &~ u64 3L));
        if_then_else (var "wcode" ==~ i32 1)
          [
            decl_var (Ptr UInt32) "_p32" ~init:(reinterpret_cast (Ptr UInt32) (var "_addr"));
            let_u32 "_old32" (call "__atomic_load_n" [var "_p32"; var "__ATOMIC_RELAXED"]);
            while_loop
              (log_not (call "__atomic_compare_exchange_n" [ var "_p32"; addr_of (var "_old32");
                                                           cast UInt32 reg_src; bool_lit false;
                                                           var "__ATOMIC_SEQ_CST"; var "__ATOMIC_SEQ_CST" ]))
              [];
            set_reg (var "src") (cast UInt64 (var "_old32"));
          ]
          [
            if_then_else (var "wcode" ==~ i32 2)
              [
                decl_var (Ptr UInt16) "_p16" ~init:(reinterpret_cast (Ptr UInt16) (var "_addr"));
                let_u16 "_old16" (call "__atomic_load_n" [var "_p16"; var "__ATOMIC_RELAXED"]);
                while_loop
                  (log_not (call "__atomic_compare_exchange_n" [ var "_p16"; addr_of (var "_old16");
                                                               cast UInt16 reg_src; bool_lit false;
                                                               var "__ATOMIC_SEQ_CST"; var "__ATOMIC_SEQ_CST" ]))
                  [];
                set_reg (var "src") (cast UInt64 (var "_old16"));
              ]
              [
                if_then_else (var "wcode" ==~ i32 3)
                  [
                    decl_var (Ptr UInt8) "_p8" ~init:(reinterpret_cast (Ptr UInt8) (var "_addr"));
                    let_u8 "_old8" (call "__atomic_load_n" [var "_p8"; var "__ATOMIC_RELAXED"]);
                    while_loop
                      (log_not (call "__atomic_compare_exchange_n" [ var "_p8"; addr_of (var "_old8");
                                                                   cast UInt8 reg_src; bool_lit false;
                                                                   var "__ATOMIC_SEQ_CST"; var "__ATOMIC_SEQ_CST" ]))
                      [];
                    set_reg (var "src") (cast UInt64 (var "_old8"));
                  ]
                  [
                    decl_var (Ptr UInt64) "_p64" ~init:(reinterpret_cast (Ptr UInt64) (var "_addr"));
                    let_u64 "_old64" (call "__atomic_load_n" [var "_p64"; var "__ATOMIC_RELAXED"]);
                    while_loop
                      (log_not (call "__atomic_compare_exchange_n" [ var "_p64"; addr_of (var "_old64");
                                                                   reg_src; bool_lit false;
                                                                   var "__ATOMIC_SEQ_CST"; var "__ATOMIC_SEQ_CST" ]))
                      [];
                    set_reg (var "src") (var "_old64");
                  ];
              ];
          ];
      ]
  in
  emit_handler_ast b "H_ATOMIC_SWP" (atomic_swp_stmts @ [ inc_instrs; fetch_next ]);
  emit_handler_inline_ast b "H_FENCE" [
    expr_stmt (call "std::atomic_thread_fence" [var "std::memory_order_seq_cst"]);
    inc_instrs; fetch_next;
  ];
  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_MOV_VR" [
       expr_stmt (call "ctx.set_vreg_lane" [var "dst"; i32 0; reg_src]);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_ast b "H_MOV_VR" [
       let_u64 "_val" reg_src;
       decl_var (Array (UInt64, 1)) "_buf";
       expr_stmt (call "std::memcpy" [var "_buf"; addr_of (var "_val"); call "sizeof" [var "uint64_t"]]);
       expr_stmt (call "ctx.set_vreg_lane" [var "dst"; i32 0; idx (var "_buf") (i32 0)]);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_ast b "H_MOV_VR" [
       let_u64 "_val" (reg_src ^~ u64 0xA5A5A5A55A5A5A5AL);
       expr_stmt (call "ctx.set_vreg_lane" [var "dst"; i32 0; var "_val" ^~ u64 0xA5A5A5A55A5A5A5AL]);
       inc_instrs; fetch_next;
     ]);
  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_MOV_RV" [
       set_reg (var "dst") (call "ctx.get_vreg_lane" [var "src"; i32 0]);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_ast b "H_MOV_RV" [
       let_u64 "_val" (call "ctx.get_vreg_lane" [var "src"; i32 0]);
       decl_var (Array (UInt64, 1)) "_buf";
       expr_stmt (call "std::memcpy" [var "_buf"; addr_of (var "_val"); call "sizeof" [var "uint64_t"]]);
       set_reg (var "dst") (idx (var "_buf") (i32 0));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_ast b "H_MOV_RV" [
       let_u64 "_val" (call "ctx.get_vreg_lane" [var "src"; i32 0] ^~ u64 0x5A5A5A5AA5A5A5A5L);
       set_reg (var "dst") (var "_val" ^~ u64 0x5A5A5A5AA5A5A5A5L);
       inc_instrs; fetch_next;
     ]);
  let fcsel_stmts =
    let mba_cond = (((var "word" >>~ i32 18) +~ u64 0x0FL) -~ ((var "word" >>~ i32 18) |~ u64 0x0FL)) in
    match pick_variant 3 with
    | 0 -> [
        let_u8 "cond" (c_cast UInt8 mba_cond);
        if_then (call "eval_condition" [var "ctx"; var "cond"]) [
          set_vreg_lane (var "dst") (i32 0) (get_vreg_lane (var "src") (i32 0));
        ];
      ]
    | 1 -> [
        if_then (call "eval_condition" [var "ctx"; cast UInt8 mba_cond]) [
          let_u64 "_v" (get_vreg_lane (var "src") (i32 0));
          set_vreg_lane (var "dst") (i32 0) (var "_v");
        ];
      ]
    | _ -> [
        let_u8 "_c" (c_cast UInt8 mba_cond);
        let_u64 "_s" (get_vreg_lane (var "src") (i32 0));
        if_then (call "eval_condition" [var "ctx"; var "_c"]) [
          set_vreg_lane (var "dst") (i32 0) (var "_s");
        ];
      ]
  in
  emit_handler_ast b "H_FCSEL_VV" (fcsel_stmts @ [ inc_instrs; fetch_next ])

let emit_decoy_handlers ?rng b =
  let pick_variant n =
    match rng with
    | Some r -> Random.State.int r n
    | None -> 0
  in
  let k_dyn = var "k_dyn" in
  let op = var "op" in
  let imm_u64 = cast UInt64 (var "imm") in
  let reg_mask = var "ctx.reg_mask" in

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_0" [
       (reg_mask ^= (((k_dyn *~ u64 0x6A09E667F3BCC908L) +~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ (u64 0x5877L +~ imm_u64));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_0" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= ((k_dyn ^~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") ((var "_d" ^~ u64 0x5877L) +~ reg_mask);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_0" [
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x9E3779B97F4A7C15L) |~ u64 1L));
       set_reg (var "dst") (bit_not reg_dst ^~ bit_not (u64 0x5877L));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_1" [
       (reg_mask ^= ((k_dyn +~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_1" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (var "_d" +~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_1" [
       (reg_mask ^= ((k_dyn ^~ imm_u64) |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ imm_u64) +~ (u64 2L *~ (reg_dst &~ imm_u64)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_2" [
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xBF58476D1CE4E5B9L) |~ u64 1L));
       set_reg (var "dst") (reg_dst *~ u64 0x9E37L);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_2" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= ((k_dyn *~ u64 0x9E37L) |~ u64 1L));
       set_reg (var "dst") ((var "_d" *~ u64 0x9E37L) ^~ reg_mask);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_2" [
       (reg_mask ^= ((k_dyn ^~ u64 0x9E37L) |~ u64 1L));
       set_reg (var "dst") (reg_dst *~ u64 0x9E37L);
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_3" [
       (reg_mask ^= ((k_dyn >>~ i32 13) |~ u64 1L));
       set_reg (var "dst") ((reg_dst <<~ i32 3) |~ (reg_dst >>~ i32 61));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_3" [
       let_u64 "_v" reg_dst;
       (reg_mask ^= (((cast UInt64 op) <<~ i32 7) |~ u64 1L));
       set_reg (var "dst") ((var "_v" <<~ i32 3) ^~ (var "_v" >>~ i32 61));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_3" [
       let_u64 "_l" (reg_dst <<~ i32 3);
       let_u64 "_r" (reg_dst >>~ i32 61);
       (reg_mask ^= ((k_dyn *~ u64 0x517CC1B727220A95L) |~ u64 1L));
       set_reg (var "dst") (var "_l" |~ var "_r");
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_4" [
       (reg_mask ^= (((k_dyn ^~ imm_u64) *~ u64 0x9E3779B97F4A7C15L) |~ u64 1L));
       set_reg (var "dst") (reg_src ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_4" [
       let_u64 "_s" reg_src;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xCAFEL) |~ u64 1L));
       set_reg (var "dst") (var "_s" ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_4" [
       (reg_mask ^= ((k_dyn +~ cast UInt64 (var "src")) |~ u64 1L));
       set_reg (var "dst") ((reg_src |~ imm_u64) -~ (reg_src &~ imm_u64));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_5" [
       (reg_mask ^= ((k_dyn *~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (reg_dst &~ bit_not reg_src);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_5" [
       let_u64 "_d" reg_dst; let_u64 "_s" reg_src;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (var "_d" &~ bit_not (var "_s"));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_5" [
       (reg_mask ^= ((k_dyn ^~ cast UInt64 (var "dst")) |~ u64 1L));
       set_reg (var "dst") (bit_not (bit_not reg_dst |~ reg_src));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_6" [
       (reg_mask ^= ((k_dyn ^~ u64 0xCAFEBABEL) |~ u64 1L));
       set_reg (var "dst") (reg_dst |~ u64 0xCAFEBABEL);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_6" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xCAFEBABEL) |~ u64 1L));
       set_reg (var "dst") (var "_d" |~ u64 0xCAFEBABEL);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_6" [
       (reg_mask ^= ((k_dyn +~ u64 0xCAFEBABEL) |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ u64 0xCAFEBABEL) +~ (reg_dst &~ u64 0xCAFEBABEL));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_7" [
       (reg_mask ^= ((k_dyn >>~ i32 5) |~ u64 1L));
       set_reg (var "dst") ((reg_dst >>~ i32 5) ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_7" [
       let_u64 "_sh" (reg_dst >>~ i32 5);
       (reg_mask ^= (((cast UInt64 op) ^~ imm_u64) |~ u64 1L));
       set_reg (var "dst") (var "_sh" ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_7" [
       (reg_mask ^= ((k_dyn *~ u64 0x94D049BB133111EBL) |~ u64 1L));
       set_reg (var "dst") (((reg_dst >>~ i32 5) |~ imm_u64) -~ ((reg_dst >>~ i32 5) &~ imm_u64));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_8" [
       (reg_mask ^= ((k_dyn ^~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (reg_dst -~ u64 0x1337L);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_8" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) -~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (var "_d" -~ u64 0x1337L);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_8" [
       (reg_mask ^= ((k_dyn *~ u64 0x1337L) |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ (bit_not (u64 0x1337L) +~ u64 1L));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_9" [
       (reg_mask ^= (((k_dyn +~ u64 1L) *~ u64 0x5877L) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ (reg_src +~ u64 1L));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_9" [
       let_u64 "_rhs" (reg_src +~ u64 1L);
       (reg_mask ^= (((cast UInt64 op) ^~ var "_rhs") |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ var "_rhs");
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_9" [
       (reg_mask ^= ((k_dyn ^~ cast UInt64 (var "src")) |~ u64 1L));
       set_reg (var "dst") ((reg_dst |~ (reg_src +~ u64 1L)) -~ (reg_dst &~ (reg_src +~ u64 1L)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_10" [
       (reg_mask ^= ((k_dyn *~ u64 6364136223846793005L) |~ u64 1L));
       set_reg (var "dst") ((reg_dst *~ u64 6364136223846793005L) +~ u64 1L);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_10" [
       let_u64 "_m" (reg_dst *~ u64 6364136223846793005L);
       (reg_mask ^= (((cast UInt64 op) *~ u64 0x6A09L) |~ u64 1L));
       set_reg (var "dst") (var "_m" +~ u64 1L);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_10" [
       (reg_mask ^= ((k_dyn +~ u64 0x6364L) |~ u64 1L));
       set_reg (var "dst") ((reg_dst *~ u64 6364136223846793005L) +~ u64 1L);
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_11" [
       (reg_mask ^= ((k_dyn <<~ i32 7) |~ u64 1L));
       set_reg (var "dst") ((reg_dst <<~ i32 7) ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_11" [
       let_u64 "_sh" (reg_dst <<~ i32 7);
       (reg_mask ^= (((cast UInt64 op) <<~ i32 7) |~ u64 1L));
       set_reg (var "dst") (var "_sh" ^~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_11" [
       (reg_mask ^= ((k_dyn *~ u64 0x517CC1B727220A95L) |~ u64 1L));
       set_reg (var "dst") (((reg_dst <<~ i32 7) |~ imm_u64) -~ ((reg_dst <<~ i32 7) &~ imm_u64));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_12" [
       (reg_mask ^= ((k_dyn ^~ u64 0xDEADBEEFL) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ u64 0xDEADBEEFL);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_12" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (((cast UInt64 op) *~ u64 0xDEADBEEFL) |~ u64 1L));
       set_reg (var "dst") (var "_d" ^~ u64 0xDEADBEEFL);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_12" [
       (reg_mask ^= ((k_dyn +~ u64 0xDEADBEEFL) |~ u64 1L));
       set_reg (var "dst") (bit_not reg_dst ^~ bit_not (u64 0xDEADBEEFL));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_13" [
       (reg_mask ^= ((k_dyn +~ cast UInt64 (var "src")) |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ reg_src);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_13" [
       let_u64 "_a" reg_dst; let_u64 "_b" reg_src;
       (reg_mask ^= (((cast UInt64 op) +~ var "_a") |~ u64 1L));
       set_reg (var "dst") (var "_a" +~ var "_b");
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_13" [
       (reg_mask ^= ((k_dyn ^~ cast UInt64 (var "dst")) |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ reg_src) +~ (u64 2L *~ (reg_dst &~ reg_src)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_14" [
       (reg_mask ^= ((k_dyn ^~ (imm_u64 *~ u64 3L)) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ (imm_u64 *~ u64 3L));
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_14" [
       let_u64 "_adj" (imm_u64 *~ u64 3L);
       (reg_mask ^= (((cast UInt64 op) *~ var "_adj") |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ var "_adj");
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_14" [
       (reg_mask ^= ((k_dyn *~ u64 3L) |~ u64 1L));
       set_reg (var "dst") ((reg_dst |~ (imm_u64 *~ u64 3L)) -~ (reg_dst &~ (imm_u64 *~ u64 3L)));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY_15" [
       (reg_mask ^= (bit_not k_dyn |~ u64 1L));
       set_reg (var "dst") (bit_not reg_dst);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY_15" [
       let_u64 "_d" reg_dst;
       (reg_mask ^= (bit_not (cast UInt64 op) |~ u64 1L));
       set_reg (var "dst") (bit_not (var "_d"));
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY_15" [
       (reg_mask ^= ((k_dyn *~ u64 0xBF58476D1CE4E5B9L) |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ bit_not (u64 0L));
       inc_instrs; fetch_next;
     ]);

  (match pick_variant 3 with
   | 0 -> emit_handler_inline_ast b "H_DECOY" [
       let_u64 "_p" (((k_dyn *~ u64 0x5877CAFEBEEFL) ^~ ((cast UInt64 op) *~ u64 0x9E3779B97F4A7C15L)) ^~ u64 0xDEADBEEF5A5A5A5AL);
       (reg_mask ^= (var "_p" |~ u64 1L));
       set_reg (var "dst") (reg_dst +~ reg_mask);
       inc_instrs; fetch_next;
     ]
   | 1 -> emit_handler_inline_ast b "H_DECOY" [
       let_u64 "_p" ((((cast UInt64 op) *~ u64 0xBF58476D1CE4E5B9L) ^~ (k_dyn *~ u64 0x6A09E667F3BCC908L)) ^~ u64 0xCAFEBABE13375877L);
       (reg_mask ^= (var "_p" |~ u64 1L));
       set_reg (var "dst") ((reg_dst ^~ reg_mask) +~ imm_u64);
       inc_instrs; fetch_next;
     ]
   | _ -> emit_handler_inline_ast b "H_DECOY" [
       let_u64 "_p" ((k_dyn ^~ ((cast UInt64 op) *~ u64 0x517CC1B727220A95L)) *~ u64 0x94D049BB133111EBL);
       (reg_mask ^= (var "_p" |~ u64 1L));
       set_reg (var "dst") (reg_dst ^~ reg_mask);
       inc_instrs; fetch_next;
     ])
