open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let rns_moduli_decls () : top_decl list = [
  comment_top "RNS-4 Moduli Definition (Pairwise coprime, Product > 2^64)";
  global_var ~is_static:true ~is_const:true UInt64 "RNS_M1" ~init:(u64 4294967291L);
  global_var ~is_static:true ~is_const:true UInt64 "RNS_M2" ~init:(u64 4294967279L);
  global_var ~is_static:true ~is_const:true UInt64 "RNS_M3" ~init:(u64 4294967231L);
  global_var ~is_static:true ~is_const:true UInt64 "RNS_M4" ~init:(u64 4294967197L);
]

let rns_register_def () : top_decl =
  StructDef {
    align_as = None;
    name = "RNS_Register";
    members = [
      member_field UInt64 "r1";
      member_field UInt64 "r2";
      member_field UInt64 "r3";
      member_field UInt64 "r4";
      member_method ~attrs:[AlwaysInline] Void "set" [(UInt64, "val")] [
        var "r1" := var "val" %~ var "RNS_M1";
        var "r2" := var "val" %~ var "RNS_M2";
        var "r3" := var "val" %~ var "RNS_M3";
        var "r4" := var "val" %~ var "RNS_M4";
      ];
      member_method ~attrs:[AlwaysInline] Void "add" [(ConstRef (StructType "RNS_Register"), "o")] [
        var "r1" := (var "r1" +~ (var "o" $. "r1")) %~ var "RNS_M1";
        var "r2" := (var "r2" +~ (var "o" $. "r2")) %~ var "RNS_M2";
        var "r3" := (var "r3" +~ (var "o" $. "r3")) %~ var "RNS_M3";
        var "r4" := (var "r4" +~ (var "o" $. "r4")) %~ var "RNS_M4";
      ];
      member_method ~attrs:[AlwaysInline] Void "sub" [(ConstRef (StructType "RNS_Register"), "o")] [
        var "r1" := ((var "r1" +~ var "RNS_M1") -~ ((var "o" $. "r1") %~ var "RNS_M1")) %~ var "RNS_M1";
        var "r2" := ((var "r2" +~ var "RNS_M2") -~ ((var "o" $. "r2") %~ var "RNS_M2")) %~ var "RNS_M2";
        var "r3" := ((var "r3" +~ var "RNS_M3") -~ ((var "o" $. "r3") %~ var "RNS_M3")) %~ var "RNS_M3";
        var "r4" := ((var "r4" +~ var "RNS_M4") -~ ((var "o" $. "r4") %~ var "RNS_M4")) %~ var "RNS_M4";
      ];
      member_method ~attrs:[AlwaysInline] Void "mul" [(ConstRef (StructType "RNS_Register"), "o")] [
        var "r1" := c_cast UInt64 (((c_cast (StructType "__uint128_t") (var "r1")) *~ (var "o" $. "r1")) %~ var "RNS_M1");
        var "r2" := c_cast UInt64 (((c_cast (StructType "__uint128_t") (var "r2")) *~ (var "o" $. "r2")) %~ var "RNS_M2");
        var "r3" := c_cast UInt64 (((c_cast (StructType "__uint128_t") (var "r3")) *~ (var "o" $. "r3")) %~ var "RNS_M3");
        var "r4" := c_cast UInt64 (((c_cast (StructType "__uint128_t") (var "r4")) *~ (var "o" $. "r4")) %~ var "RNS_M4");
      ];
      member_method ~attrs:[AlwaysInline] ~is_const:true UInt64 "decode_crt" [] [
        ret (var "r1");
      ];
    ];
  }

let rd_jit_context_def () : top_decl =
  StructDef {
    align_as = None;
    name = "RD_JIT_Context";
    members = [
      member_field (Array (UInt64, 16)) "gprs";
      member_field (Array (StructType "RNS_Register", 16)) "vregs";
      member_field UInt64 "rip";
      member_field UInt64 "flags";
      member_field UInt64 "trace_digest";
      member_method ~attrs:[AlwaysInline] Void "init" [] [
        expr_stmt (call "memset" [var "this"; i32 0; call "sizeof" [deref (var "this")]]);
        var "trace_digest" := u64 0x13375877AABBCCDDL;
      ];
      member_method ~attrs:[AlwaysInline] Void "set_reg" [(SizeT, "idx"); (UInt64, "val")] [
        if_then (var "idx" <~ i32 16) [
          idx (var "gprs") (var "idx") := var "val";
          expr_stmt (call "vregs[idx].set" [var "val"]);
        ];
      ];
      member_method ~attrs:[AlwaysInline] ~is_const:true UInt64 "get_reg" [(SizeT, "idx")] [
        if_then (var "idx" <~ i32 16) [
          ret (idx (var "gprs") (var "idx"));
        ];
        ret (u64 0L);
      ];
      member_method ~attrs:[AlwaysInline] Void "set_rdi" [(UInt64, "val")] [
        expr_stmt (call "set_reg" [i32 0; var "val"]);
      ];
      member_method ~attrs:[AlwaysInline] ~is_const:true UInt64 "get_rax" [] [
        ret (call "get_reg" [i32 0]);
      ];
    ];
  }

let header () =
  let prefix = {|#pragma once
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
|} in
  let ast_part = render_top_decls (
    rns_moduli_decls () @
    [ rns_register_def (); rd_jit_context_def () ]
  ) in
  prefix ^ "\n" ^ ast_part ^ "\n" ^ {|
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
|}
