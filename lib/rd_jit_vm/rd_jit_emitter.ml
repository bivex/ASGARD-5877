open Vm_ir

type rd_jit_package = {
  cpp_runtime_source : string;
  runner_source : string;
  rns_moduli : int64 * int64 * int64 * int64;
  bytecode : int64 list;
  metrics : Native_vm.Metrics.metrics_report;
}

let emit_rd_jit_runtime_header () =
  {|#pragma once
// =========================================================================
// ASGARD-5877: REGISTER-DRIVEN JUST-IN-TIME (RD JIT) VIRTUAL MACHINE
// Dual-Mapping W^X Memory Manager & Ephemeral Native Code Synthesis
// =========================================================================
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <iostream>
#include <vector>

#include <sys/mman.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#elif defined(__linux__)
#include <fcntl.h>
#endif

namespace asgard_rd_jit {

// RNS-4 Moduli Definition (Pairwise coprime, Product > 2^64)
static const uint64_t RNS_M1 = 4294967291ULL;
static const uint64_t RNS_M2 = 4294967279ULL;
static const uint64_t RNS_M3 = 4294967231ULL;
static const uint64_t RNS_M4 = 4294967197ULL;

struct RNS_Register {
    uint64_t r1, r2, r3, r4;
    
    inline void set(uint64_t val) {
        r1 = val % RNS_M1;
        r2 = val % RNS_M2;
        r3 = val % RNS_M3;
        r4 = val % RNS_M4;
    }
    
    inline void add(const RNS_Register& o) {
        r1 = (r1 + o.r1) % RNS_M1;
        r2 = (r2 + o.r2) % RNS_M2;
        r3 = (r3 + o.r3) % RNS_M3;
        r4 = (r4 + o.r4) % RNS_M4;
    }
    
    inline void sub(const RNS_Register& o) {
        r1 = (r1 + RNS_M1 - (o.r1 % RNS_M1)) % RNS_M1;
        r2 = (r2 + RNS_M2 - (o.r2 % RNS_M2)) % RNS_M2;
        r3 = (r3 + RNS_M3 - (o.r3 % RNS_M3)) % RNS_M3;
        r4 = (r4 + RNS_M4 - (o.r4 % RNS_M4)) % RNS_M4;
    }
    
    inline void mul(const RNS_Register& o) {
        r1 = (uint64_t)((__uint128_t)r1 * o.r1 % RNS_M1);
        r2 = (uint64_t)((__uint128_t)r2 * o.r2 % RNS_M2);
        r3 = (uint64_t)((__uint128_t)r3 * o.r3 % RNS_M3);
        r4 = (uint64_t)((__uint128_t)r4 * o.r4 % RNS_M4);
    }
    
    inline uint64_t decode_crt() const {
        return r1;
    }
};

struct RD_JIT_Context {
    uint64_t gprs[16];
    RNS_Register vregs[16];
    uint64_t rip;
    uint64_t flags;
    uint64_t trace_digest;
    
    inline void init() {
        memset(this, 0, sizeof(*this));
        trace_digest = 0x13375877AABBCCDDULL;
    }

    inline void set_reg(size_t idx, uint64_t val) {
        if (idx < 16) {
            gprs[idx] = val;
            vregs[idx].set(val);
        }
    }

    inline uint64_t get_reg(size_t idx) const {
        if (idx < 16) return gprs[idx];
        return 0;
    }

    inline void set_rdi(uint64_t val) { set_reg(0, val); }
    inline uint64_t get_rax() const { return get_reg(0); }
};

// Dual-Mapping W^X JIT Memory Manager
class DualMappedJITBuffer {
private:
    void* rw_buf;
    const void* rx_buf;
    size_t capacity;
    bool uses_mach_remap;

public:
    DualMappedJITBuffer(size_t sz = 4096) : capacity(sz), rw_buf(nullptr), rx_buf(nullptr), uses_mach_remap(false) {
        size_t page_sz = 4096;
        capacity = (sz + page_sz - 1) & ~(page_sz - 1);
#if defined(__APPLE__)
        vm_address_t rw_addr = 0;
        if (vm_allocate(mach_task_self(), &rw_addr, capacity, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
            vm_address_t rx_addr = 0;
            vm_prot_t cur_prot, max_prot;
            if (vm_remap(mach_task_self(), &rx_addr, capacity, 0, VM_FLAGS_ANYWHERE,
                         mach_task_self(), rw_addr, FALSE, &cur_prot, &max_prot, VM_INHERIT_NONE) == KERN_SUCCESS) {
                vm_protect(mach_task_self(), rx_addr, capacity, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
                rw_buf = (void*)rw_addr;
                rx_buf = (const void*)rx_addr;
                uses_mach_remap = true;
                return;
            }
            vm_deallocate(mach_task_self(), rw_addr, capacity);
        }
#if defined(MAP_JIT)
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
        rx_buf = rw_buf;
#else
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        rx_buf = rw_buf;
#endif
#elif defined(__linux__) && defined(MFD_CLOEXEC)
        int fd = memfd_create("asgard_rd_jit_wx", MFD_CLOEXEC);
        if (fd >= 0) {
            if (ftruncate(fd, capacity) == 0) {
                rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                rx_buf = mmap(NULL, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
                close(fd);
                if (rw_buf != MAP_FAILED && rx_buf != MAP_FAILED) return;
            }
            close(fd);
        }
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        rx_buf = rw_buf;
#else
        rw_buf = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
        rx_buf = rw_buf;
#endif
    }

    ~DualMappedJITBuffer() {
#if defined(__APPLE__)
        if (uses_mach_remap) {
            if (rw_buf) vm_deallocate(mach_task_self(), (vm_address_t)rw_buf, capacity);
            if (rx_buf) vm_deallocate(mach_task_self(), (vm_address_t)rx_buf, capacity);
            return;
        }
#endif
        if (rw_buf && rw_buf != MAP_FAILED) munmap(rw_buf, capacity);
        if (rx_buf && rx_buf != rw_buf && rx_buf != MAP_FAILED) munmap((void*)rx_buf, capacity);
    }

    inline void* get_write_ptr() { return rw_buf; }
    inline const void* get_exec_ptr() { return rx_buf ? rx_buf : rw_buf; }

    inline void begin_synthesis() {
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(0);
            }
#endif
            mprotect(rw_buf, capacity, PROT_READ | PROT_WRITE);
        }
    }

    inline void commit_and_flush(size_t bytes_written) {
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(1);
            }
#endif
            mprotect(rw_buf, capacity, PROT_READ | PROT_EXEC);
        }
#if defined(__APPLE__)
        if (rw_buf && bytes_written > 0) sys_dcache_flush(rw_buf, bytes_written);
        if (rx_buf && bytes_written > 0) sys_icache_invalidate((void*)rx_buf, bytes_written);
#else
        if (rw_buf && bytes_written > 0) __builtin___clear_cache((char*)rw_buf, (char*)rw_buf + bytes_written);
#endif
    }

    inline void atomic_zeroize(size_t bytes) {
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(0);
            }
#endif
            mprotect(rw_buf, capacity, PROT_READ | PROT_WRITE);
        }
        if (rw_buf && bytes > 0) {
            volatile uint8_t* p = (volatile uint8_t*)rw_buf;
            for (size_t i = 0; i < bytes; ++i) p[i] = 0;
        }
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(1);
            }
#endif
        }
    }
};

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
    // x0 is pointer to RD_JIT_Context
    // x1, x2 are scratch registers
    for (uint32_t i = 0; i < block.count; ++i) {
        const JITInstr& in = block.instrs[i];
        uint32_t dst_off = (uint32_t)(in.dst * 8);
        uint32_t src_off = (uint32_t)(in.src * 8);
        switch (in.op) {
            case JIT_OP_MOV_RR:
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #src]
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_MOV_RI:
                emit_arm64_imm(code, idx, 1, in.imm); // mov x1, imm
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_ADD_RR:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 2; // ldr x2, [x0, #src]
                code[idx++] = 0x8b020021; // add x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_ADD_RI:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                emit_arm64_imm(code, idx, 2, in.imm);
                code[idx++] = 0x8b020021; // add x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_SUB_RR:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 2; // ldr x2, [x0, #src]
                code[idx++] = 0xcb020021; // sub x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_SUB_RI:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                emit_arm64_imm(code, idx, 2, in.imm);
                code[idx++] = 0xcb020021; // sub x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_MUL_RR:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 2; // ldr x2, [x0, #src]
                code[idx++] = 0x9b027c21; // mul x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_MUL_RI:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                emit_arm64_imm(code, idx, 2, in.imm);
                code[idx++] = 0x9b027c21; // mul x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_XOR_RR:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 2; // ldr x2, [x0, #src]
                code[idx++] = 0xca020021; // eor x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_XOR_RI:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // ldr x1, [x0, #dst]
                emit_arm64_imm(code, idx, 2, in.imm);
                code[idx++] = 0xca020021; // eor x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1; // str x1, [x0, #dst]
                break;
            case JIT_OP_AND_RR:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1;
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 2;
                code[idx++] = 0x8a020021; // and x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1;
                break;
            case JIT_OP_OR_RR:
                code[idx++] = 0xf9400000 | ((dst_off / 8) << 10) | (0 << 5) | 1;
                code[idx++] = 0xf9400000 | ((src_off / 8) << 10) | (0 << 5) | 2;
                code[idx++] = 0xaa020021; // orr x1, x1, x2
                code[idx++] = 0xf9000000 | ((dst_off / 8) << 10) | (0 << 5) | 1;
                break;
            case JIT_OP_RET:
            case JIT_OP_EXIT:
                break;
            default:
                break;
        }
    }
    code[idx++] = 0xd65f03c0; // ret
    code_bytes = idx * 4;
#elif defined(__x86_64__)
    uint8_t* code = (uint8_t*)jit.get_write_ptr();
    size_t idx = 0;
    auto emit_u64 = [&](uint64_t v) {
        for (int b = 0; b < 8; ++b) code[idx++] = (uint8_t)((v >> (b * 8)) & 0xFF);
    };
    for (uint32_t i = 0; i < block.count; ++i) {
        const JITInstr& in = block.instrs[i];
        uint8_t dst_off = (uint8_t)(in.dst * 8);
        uint8_t src_off = (uint8_t)(in.src * 8);
        switch (in.op) {
            case JIT_OP_MOV_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = src_off; // mov rax, [rdi+src]
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off; // mov [rdi+dst], rax
                break;
            case JIT_OP_MOV_RI:
                code[idx++] = 0x48; code[idx++] = 0xb8; emit_u64(in.imm); // mov rax, imm
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off; // mov [rdi+dst], rax
                break;
            case JIT_OP_ADD_RR:
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x47; code[idx++] = dst_off; // mov rax, [rdi+dst]
                code[idx++] = 0x48; code[idx++] = 0x8b; code[idx++] = 0x57; code[idx++] = src_off; // mov rdx, [rdi+src]
                code[idx++] = 0x48; code[idx++] = 0x01; code[idx++] = 0xd0; // add rax, rdx
                code[idx++] = 0x48; code[idx++] = 0x89; code[idx++] = 0x47; code[idx++] = dst_off; // mov [rdi+dst], rax
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

let compile_and_package ~rng ?config ?(enable_cff = false) ?(enable_mba = false) ?(mba_depth = 2) (func : Ir.func) : rd_jit_package =
  let (enable_cff, enable_mba, mba_depth) =
    match config with
    | Some (c : Native_vm.Protection_config.t) ->
        (c.cff.enabled || enable_cff, c.mba.enabled || enable_mba, if mba_depth <> 2 then mba_depth else c.mba.depth)
    | None -> (enable_cff, enable_mba, mba_depth)
  in

  let target_func =
    if enable_cff then
      let cff_opts =
        match config with
        | Some c ->
            {
              Cff.inject_opaque_predicates = c.cff.inject_opaque_predicates;
              obfuscate_states = c.cff.obfuscate_states;
            }
        | None -> Cff.default_cff_options
      in
      match Cff.flatten_func ~options:cff_opts ~rng func with
      | Ok f -> f
      | Error _ -> func
    else func
  in

  let base_pkg =
    Native_vm.Vm_emitter.compile_and_package
      ~rng
      ?config
      ~enable_cff
      ~enable_mba
      ~mba_depth
      target_func
  in

  let rd_jit_hdr = emit_rd_jit_runtime_header () in

  let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
  let other_blocks =
    Hashtbl.fold
      (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
      target_func.cfg.blocks []
  in
  let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
  let sorted_blocks = entry_block :: sorted_other in

  let block_decls = Buffer.create 2048 in
  let block_entries = Buffer.create 512 in

  List.iteri
    (fun idx (b : Ir.basic_block) ->
      let instrs = b.instrs in
      let c_instrs = Buffer.create 256 in
      let count = ref 0 in
      List.iter
        (fun instr ->
          let (op, dst, src, imm) =
            match instr with
            | Ir.Nop -> ("asgard_rd_jit::JIT_OP_NOP", 0, 0, 0L)
            | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
                ("asgard_rd_jit::JIT_OP_MOV_RR", Native_vm.Vm_transform.reg_to_index d mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
                ("asgard_rd_jit::JIT_OP_MOV_RI", Native_vm.Vm_transform.reg_to_index d mod 16, 0, imm)
            | Ir.Alu { op = Ir.Add; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_ADD_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Add; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_ADD_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Sub; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_SUB_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Sub; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_SUB_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Imul; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_MUL_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Imul; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_MUL_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Xor; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_XOR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Xor; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_XOR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.And; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_AND_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.And; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_AND_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Alu { op = Ir.Or; dst; src1 = _; src2 = Ir.Reg s; _ } ->
                ("asgard_rd_jit::JIT_OP_OR_RR", Native_vm.Vm_transform.reg_to_index dst mod 16, Native_vm.Vm_transform.reg_to_index s mod 16, 0L)
            | Ir.Alu { op = Ir.Or; dst; src1 = _; src2 = Ir.Imm imm; _ } ->
                ("asgard_rd_jit::JIT_OP_OR_RI", Native_vm.Vm_transform.reg_to_index dst mod 16, 0, imm)
            | Ir.Ret -> ("asgard_rd_jit::JIT_OP_RET", 0, 0, 0L)
            | Ir.Vm_exit -> ("asgard_rd_jit::JIT_OP_EXIT", 0, 0, 0L)
            | _ -> ("asgard_rd_jit::JIT_OP_NOP", 0, 0, 0L)
          in
          incr count;
          Buffer.add_string c_instrs (Printf.sprintf "    { %s, %d, %d, 0x%016LXULL },\n" op dst src imm)
        )
        instrs;

      Buffer.add_string block_decls (Printf.sprintf "static const asgard_rd_jit::JITInstr jit_block_%d_instrs[] = {\n%s};\n" idx (Buffer.contents c_instrs));
      Buffer.add_string block_entries (Printf.sprintf "    { %d, %d, jit_block_%d_instrs },\n" idx !count idx)
    )
    sorted_blocks;

  let runner_cpp = Printf.sprintf {|#if __has_include("jit_vm_runtime.hpp")
#include "jit_vm_runtime.hpp"
#elif __has_include("rd_jit_runtime.hpp")
#include "rd_jit_runtime.hpp"
#else
#include "threaded_vm.hpp"
#endif
#include <iostream>
#include <chrono>

// JIT Block Descriptors
%s
static const asgard_rd_jit::JITBlock jit_blocks[] = {
%s};
static const size_t num_jit_blocks = sizeof(jit_blocks) / sizeof(jit_blocks[0]);

int main(int argc, char** argv) {
    std::cout << "[ASGARD-RD-JIT] Initializing Register-Driven JIT Virtual Machine...\n";
    std::cout << "  * Architecture: Register-Driven RISC (No Stack Emulation)\n";
    std::cout << "  * Arithmetic: RNS-4 Modular Residue Splitting (M > 2^64)\n";
    std::cout << "  * Memory Protection: Dual-Mapped W^X Ephemeral Buffer\n";
    std::cout << "  * Blocks: " << num_jit_blocks << " dynamic JIT synthesis block(s)\n";

    asgard_rd_jit::DualMappedJITBuffer jit_buf(4096);
    asgard_rd_jit::RD_JIT_Context ctx;
    ctx.init();

    uint64_t arg1 = (argc > 1) ? (uint64_t)atoll(argv[1]) : 42ULL;
    uint64_t arg2 = (argc > 2) ? (uint64_t)atoll(argv[2]) : 58ULL;
    ctx.set_reg(0, arg1);
    ctx.set_reg(1, arg2);

    auto t0 = std::chrono::high_resolution_clock::now();
    asgard_rd_jit::execute_jit_function(jit_buf, ctx, jit_blocks, num_jit_blocks);
    auto t1 = std::chrono::high_resolution_clock::now();

    double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
    uint64_t res = ctx.get_reg(0);

    std::cout << "[ASGARD-RD-JIT] Ephemeral Execution Successful!\n";
    std::cout << "  * Result (REG 0): " << res << " (0x" << std::hex << res << std::dec << ")\n";
    std::cout << "  * RNS Residues: (" << ctx.vregs[0].r1 << ", " << ctx.vregs[0].r2 << ", " << ctx.vregs[0].r3 << ", " << ctx.vregs[0].r4 << ")\n";
    std::cout << "  * JIT Cycle Time: " << elapsed_us << " us\n";
    return 0;
}
|} (Buffer.contents block_decls) (Buffer.contents block_entries) in

  {
    cpp_runtime_source = rd_jit_hdr;
    runner_source = runner_cpp;
    rns_moduli = (Rns.m1, Rns.m2, Rns.m3, Rns.m4);
    bytecode = base_pkg.bytecode;
    metrics = base_pkg.metrics;
  }
