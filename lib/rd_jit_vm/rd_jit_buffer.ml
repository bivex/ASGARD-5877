(* lib/rd_jit_vm/rd_jit_buffer.ml
   ASGARD-5877: Register-Driven JIT Buffer & Context
   Typed C++20 / C11 EDSL Declarations *)

open Cpp_codegen.Cpp_ast
module Magic_numbers = Random_visa_constants.Magic_numbers
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let rns_moduli_decls () : top_decl list =
  [

    global_var ~is_static:true ~is_const:true UInt64 "RNS_M1"
      ~init:(u64 Magic_numbers.rns_modulus_m1);
    global_var ~is_static:true ~is_const:true UInt64 "RNS_M2"
      ~init:(u64 Magic_numbers.rns_modulus_m2);
    global_var ~is_static:true ~is_const:true UInt64 "RNS_M3"
      ~init:(u64 Magic_numbers.rns_modulus_m3);
    global_var ~is_static:true ~is_const:true UInt64 "RNS_M4"
      ~init:(u64 Magic_numbers.rns_modulus_m4);
    ConstexprGlobal (UInt64, "PADOVAN_CODE_FRAC", u64 Magic_numbers.padovan_code_frac_64);
    ConstexprGlobal (UInt64, "PADOVAN_META_FRAC", u64 Magic_numbers.padovan_meta_frac_64);
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
      member_field Int32 "next_chunk";
      member_field Int32 "exit_requested";
      member_field UInt64 "vflags";
      member_method ~attrs:[AlwaysInline] Void "init" [] [
        expr_stmt (call "memset" [var "this"; i32 0; call "sizeof" [deref (var "this")]]);
        var "trace_digest" := u64 Magic_numbers.rd_jit_trace_digest_init;
        var "next_chunk" := i32 (-1);
        var "exit_requested" := i32 0;
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

let dual_mapped_jit_buffer_def () : top_decl =
  class_def "DualMappedJITBuffer" [
    member_private;
    member_field (Ptr Void) "rw_buf";
    member_field (ConstPtr Void) "rx_buf";
    member_field SizeT "capacity";
    member_field Bool "uses_mach_remap";
    (* OEIS A000931 - Padovan region bounds: code | metadata | spill arena
       at geometric psi spacing (cap/psi^5 : cap/psi^4 : cap/psi^3); no
       region boundary falls on a power-of-two or harmonic offset. *)
    member_field SizeT "padovan_code_end_";
    member_field SizeT "padovan_spill_begin_";

    member_public;
    member_constructor ~params:[(SizeT, "sz = 1048576")]
      ~init_list:[
        ("capacity", var "sz");
        ("rw_buf", nullptr);
        ("rx_buf", nullptr);
        ("uses_mach_remap", bool_lit false);
        ("padovan_code_end_", u64 0L);
        ("padovan_spill_begin_", u64 0L);
      ]
      "DualMappedJITBuffer"
      [
        raw "size_t page_sz = 4096;";
        raw "capacity = (sz + page_sz - 1) & ~(page_sz - 1);";
        (* OEIS A000931: code_end = floor(cap * PADOVAN_CODE_FRAC / 2^64);
           spill_begin = code_end + floor(cap * PADOVAN_META_FRAC / 2^64). *)
        var "padovan_code_end_" :=
          c_cast SizeT
            ((c_cast (StructType "__uint128_t") (var "capacity")
              *~ c_cast (StructType "__uint128_t") (var "PADOVAN_CODE_FRAC"))
             >>~ u64 64L);
        var "padovan_spill_begin_" :=
          (var "padovan_code_end_" +~
           c_cast SizeT
             ((c_cast (StructType "__uint128_t") (var "capacity")
               *~ c_cast (StructType "__uint128_t") (var "PADOVAN_META_FRAC"))
              >>~ u64 64L));
        raw {|#if defined(__APPLE__)
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
        int fd = -1;
#if defined(__NR_memfd_create)
        fd = (int)syscall(__NR_memfd_create, "asgard_rd_jit_wx", MFD_CLOEXEC);
#elif !defined(__ANDROID__)
        fd = memfd_create("asgard_rd_jit_wx", MFD_CLOEXEC);
#endif
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
#endif|};
      ];

    member_destructor "DualMappedJITBuffer" [
      raw {|#if defined(__APPLE__)
        if (uses_mach_remap) {
            if (rw_buf) vm_deallocate(mach_task_self(), (vm_address_t)rw_buf, capacity);
            if (rx_buf) vm_deallocate(mach_task_self(), (vm_address_t)rx_buf, capacity);
            return;
        }
#endif
        if (rw_buf && rw_buf != MAP_FAILED) munmap(rw_buf, capacity);
        if (rx_buf && rx_buf != rw_buf && rx_buf != MAP_FAILED) munmap((void*)rx_buf, capacity);|};
    ];

    member_method ~attrs:[InlineFn] (Ptr Void) "get_write_ptr" [] [
      ret (var "rw_buf");
    ];

    member_method ~attrs:[InlineFn] (ConstPtr Void) "get_exec_ptr" [] [
      ret (ternary (ne (var "rx_buf") nullptr) (var "rx_buf") (var "rw_buf"));
    ];
    (* OEIS A000931 - Padovan-dispersed region accessors.  The code region
       carries the W^X synthesis lifecycle above; the metadata region holds
       the runtime copies of the derangement and Stern tables; the spill
       region backs the sealed nano-arena (kept writable at all times). *)
    member_method ~attrs:[InlineFn] ~is_const:true SizeT "code_region_bytes" [] [
      ret (var "padovan_code_end_");
    ];
    member_method ~attrs:[InlineFn] ~is_const:true (Ptr Void) "metadata_region" [] [
      ret (c_cast (Ptr Void)
             ((c_cast (Ptr (StructType "char")) (var "rw_buf")) +~ var "padovan_code_end_"));
    ];
    member_method ~attrs:[InlineFn] ~is_const:true (Ptr Void) "arena_region" [] [
      ret (c_cast (Ptr Void)
             ((c_cast (Ptr (StructType "char")) (var "rw_buf"))
              +~ ((var "padovan_spill_begin_" +~ u64 63L) &~ bit_not (u64 63L))));
    ];

    member_method ~attrs:[InlineFn] Void "begin_synthesis" [] [
      raw {|if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(0);
            } else {
                mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_WRITE);
            }
#else
            mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_WRITE);
#endif
        }|};
    ];

    member_method ~attrs:[InlineFn] Void "commit_and_flush" [(SizeT, "bytes_written")] [
      raw {|if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(1);
            } else {
                mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_EXEC);
            }
#else
            mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_EXEC);
#endif
        }
#if defined(__APPLE__)
        if (rw_buf && bytes_written > 0) sys_dcache_flush(rw_buf, bytes_written);
        if (rx_buf && bytes_written > 0) sys_icache_invalidate((void*)rx_buf, bytes_written);
#else
        if (rw_buf && bytes_written > 0) __builtin___clear_cache((char*)rw_buf, (char*)rw_buf + bytes_written);
#endif|};
    ];

    member_method ~attrs:[InlineFn] Void "atomic_zeroize" [(SizeT, "bytes")] [
      raw {|if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(0);
            } else {
                mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_WRITE);
            }
#else
            mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_WRITE);
#endif
        }
        if (rw_buf && bytes > 0) {
            volatile uint32_t* p = (volatile uint32_t*)rw_buf;
            size_t words = (bytes + 3) / 4;
            uint32_t gamma = 0x5877A55AU;
            for (size_t i = 0; i < words; ++i) {
                gamma = (gamma << 1) ^ (gamma | (gamma >> 1));
                p[i] = gamma;
            }
        }
        if (!uses_mach_remap && rw_buf) {
#if defined(__APPLE__) && defined(__aarch64__)
            if (__builtin_available(macOS 11.0, *)) {
                pthread_jit_write_protect_np(1);
            } else {
                mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_EXEC);
            }
#else
            mprotect(rw_buf, padovan_code_end_, PROT_READ | PROT_EXEC);
#endif
        }|};
    ];
  ]

let header_decls () : top_decl list =
  [
    pragma "once";

    include_sys "stdint.h";
    include_sys "stdbool.h";
    include_sys "string.h";
    include_sys "unistd.h";
    include_sys "iostream";
    include_sys "vector";
    include_sys "sys/mman.h";
    preproc_if "defined(__APPLE__)"
      [
        include_sys "mach/mach.h";
        include_sys "mach/vm_map.h";
        include_sys "pthread.h";
        include_sys "libkern/OSCacheControl.h";
      ]
      ~else_decls:[
        preproc_if "defined(__linux__)"
          [ include_sys "fcntl.h" ]
      ];
    raw_top "namespace asgard_rd_jit {";
  ]
  @ rns_moduli_decls ()
  @ [ rns_register_def (); rd_jit_context_def (); dual_mapped_jit_buffer_def () ]

let header () : string =
  render_top_decls (header_decls ())
