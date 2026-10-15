(* lib/c_macro_obf/c_macro_guards.ml
   Typed C++20 / C11 EDSL Declarations for Obfuscation Guards & Probes *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_guards_macro_decls ?(emit_timing = true) ?(emit_anti_debug = true) ?(emit_signal = true) ?(emit_nanomites = true) ~p () : top_decl list =
  let timing_decls =
    if emit_timing then [
      comment_top "/* ------------------------------------------------------------------------- */";
      comment_top "/* 8. HIGH-PRECISION ANTI-TRACE & HARDWARE TIMING WATCHDOG (RDTSC Guard)     */";
      comment_top "/* ------------------------------------------------------------------------- */";
      preproc_if "defined(__x86_64__) || defined(_M_X64)"
        [
          func_decl ~attrs:[StaticFn; InlineFn] UInt64 (p ^ "read_cpu_ticks") []
            [
              DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                        is_constexpr = false; is_volatile = false; ty = UInt32; name = "lo"; init = None };
              DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                        is_constexpr = false; is_volatile = false; ty = UInt32; name = "hi"; init = None };
              raw "    __asm__ __volatile__(\"rdtsc\" : \"=a\"(lo), \"=d\"(hi));";
              ret (Binary (BitOr, Binary (Shl, c_cast UInt64 (var "hi"), LitInt 32), c_cast UInt64 (var "lo")));
            ]
        ]
        ~else_decls:[
          preproc_if "defined(__aarch64__) || defined(__arm64__)"
            [
              func_decl ~attrs:[StaticFn; InlineFn] UInt64 (p ^ "read_cpu_ticks") []
                [
                  DeclVar { align_as = None; is_static = false; is_thread_local = false; is_const = false;
                            is_constexpr = false; is_volatile = false; ty = UInt64; name = "val"; init = None };
                  raw "    __asm__ __volatile__(\"mrs %0, cntvct_el0\" : \"=r\"(val));";
                  ret (var "val");
                ]
            ]
            ~else_decls:[
              func_decl ~attrs:[StaticFn; InlineFn] UInt64 (p ^ "read_cpu_ticks") []
                [ ret (LitU64 0L) ]
            ]
        ];
      raw_top ("#define " ^ p ^ "TIMING_GUARD_START(var_name) uint64_t var_name##_start = " ^ p ^ "read_cpu_ticks()");
      raw_top ("#define " ^ p ^ "TIMING_GUARD_CHECK(var_name, max_ticks, on_tamper) do { \\\n    uint64_t var_name##_end = " ^ p ^ "read_cpu_ticks(); \\\n    if ((var_name##_end - var_name##_start) > (uint64_t)(max_ticks)) { \\\n        on_tamper; \\\n    } \\\n} while(0)");
    ] else []
  in

  let anti_debug_decls =
    if emit_anti_debug then [
      comment_top "/* ------------------------------------------------------------------------- */";
      comment_top "/* 9. ACTIVE ANTI-DEBUGGING & HARDWARE BREAKPOINT PROBES (DR0..DR7 / sysctl) */";
      comment_top "/* ------------------------------------------------------------------------- */";
      preproc_if "defined(__APPLE__)"
        [
          include_sys "sys/types.h";
          include_sys "sys/sysctl.h";
          include_sys "unistd.h";
          include_sys "mach/mach.h";
          include_sys "mach/thread_act.h";
          raw_top ("static inline bool " ^ p ^ "check_ptrace_sysctl(void) {\n    int mib[4];\n    struct kinfo_proc info;\n    size_t size = sizeof(info);\n    info.kp_proc.p_flag = 0;\n    mib[0] = CTL_KERN;\n    mib[1] = KERN_PROC;\n    mib[2] = KERN_PROC_PID;\n    mib[3] = getpid();\n    if (sysctl(mib, 4, &info, &size, (void*)0, 0) == 0) {\n        return (info.kp_proc.p_flag & P_TRACED) != 0;\n    }\n    return false;\n}");
          raw_top ("static inline bool " ^ p ^ "check_hw_breakpoints(void) {\n#if defined(__x86_64__)\n    x86_debug_state64_t dbg;\n    mach_msg_type_number_t count = x86_DEBUG_STATE64_COUNT;\n    if (thread_get_state(mach_thread_self(), x86_DEBUG_STATE64, (thread_state_t)&dbg, &count) == KERN_SUCCESS) {\n        if (dbg.__dr0 || dbg.__dr1 || dbg.__dr2 || dbg.__dr3 || (dbg.__dr7 & 0xFF)) return true;\n    }\n#elif defined(__arm64__) || defined(__aarch64__)\n    arm_debug_state64_t dbg;\n    mach_msg_type_number_t count = ARM_DEBUG_STATE64_COUNT;\n    if (thread_get_state(mach_thread_self(), ARM_DEBUG_STATE64, (thread_state_t)&dbg, &count) == KERN_SUCCESS) {\n        for (int i = 0; i < 16; ++i) {\n            if (dbg.__bvr[i] || (dbg.__bcr[i] & 1)) return true;\n            if (dbg.__wvr[i] || (dbg.__wcr[i] & 1)) return true;\n        }\n    }\n#endif\n    return false;\n}");
        ]
        ~else_decls:[
          preproc_if "defined(__linux__)"
            [
              include_sys "fcntl.h";
              include_sys "unistd.h";
              include_sys "string.h";
              raw_top ("static inline bool " ^ p ^ "check_ptrace_sysctl(void) {\n    int fd = open(\"/proc/self/status\", O_RDONLY);\n    if (fd < 0) return false;\n    char buf[512];\n    ssize_t n = read(fd, buf, sizeof(buf) - 1);\n    close(fd);\n    if (n <= 0) return false;\n    buf[n] = '\\0';\n    const char* p_tracer = strstr(buf, \"TracerPid:\\t\");\n    if (p_tracer) {\n        p_tracer += 11;\n        while (*p_tracer == ' ' || *p_tracer == '\\t') p_tracer++;\n        if (*p_tracer > '0' && *p_tracer <= '9') return true;\n    }\n    return false;\n}");
              func_decl ~attrs:[StaticFn; InlineFn] Bool (p ^ "check_hw_breakpoints") [] [ ret (LitBool false) ];
            ]
            ~else_decls:[
              preproc_if "defined(_WIN32) || defined(_WIN64)"
                [
                  include_sys "windows.h";
                  raw_top ("static inline bool " ^ p ^ "check_ptrace_sysctl(void) { return IsDebuggerPresent(); }");
                  raw_top ("static inline bool " ^ p ^ "check_hw_breakpoints(void) {\n    CONTEXT ctx; memset(&ctx, 0, sizeof(ctx)); ctx.ContextFlags = CONTEXT_DEBUG_REGISTERS;\n    if (GetThreadContext(GetCurrentThread(), &ctx)) {\n#if defined(_M_ARM64) || defined(__aarch64__)\n        for (size_t i = 0; i < sizeof(ctx.Bcr)/sizeof(ctx.Bcr[0]); ++i) {\n            if (ctx.Bcr[i] & 1) return true;\n        }\n#elif defined(_M_X64) || defined(_M_IX86) || defined(__x86_64__) || defined(__i386__)\n        if (ctx.Dr0 || ctx.Dr1 || ctx.Dr2 || ctx.Dr3 || (ctx.Dr7 & 0xFF)) return true;\n#endif\n    }\n    return false;\n}");
                ]
                ~else_decls:[
                  func_decl ~attrs:[StaticFn; InlineFn] Bool (p ^ "check_ptrace_sysctl") [] [ ret (LitBool false) ];
                  func_decl ~attrs:[StaticFn; InlineFn] Bool (p ^ "check_hw_breakpoints") [] [ ret (LitBool false) ];
                ]
            ]
        ];
      func_decl ~attrs:[StaticFn; InlineFn] Bool (p ^ "is_debugger_present") []
        [ ret (Binary (LogOr, call (p ^ "check_ptrace_sysctl") [], call (p ^ "check_hw_breakpoints") [])) ];
      raw_top ("#define " ^ p ^ "ANTI_DEBUG_GUARD(on_debugger) do { \\\n    if (" ^ p ^ "is_debugger_present()) { \\\n        on_debugger; \\\n    } \\\n} while(0)");
    ] else []
  in

  let signal_decls =
    if emit_signal then [
      comment_top "/* ------------------------------------------------------------------------- */";
      comment_top "/* 10. OPAQUE SIGNAL & EXCEPTION-BASED DISPATCHING (ucontext_t / SEH)        */";
      comment_top "/* ------------------------------------------------------------------------- */";
      preproc_if "(defined(__APPLE__) || defined(__linux__)) && !defined(_MSC_VER)"
        [
          include_sys "signal.h";
          preproc_if "defined(__APPLE__)" [ include_sys "sys/ucontext.h" ] ~else_decls:[ include_sys "ucontext.h" ];
          include_sys "string.h";
          global_var ~is_static:true ~is_volatile:true UIntPtr (p ^ "sig_target") ~init:(LitInt 0);
          raw_top ("static void " ^ p ^ "signal_dispatcher_handler(int sig, siginfo_t* info, void* ucontext_ptr) {\n    (void)sig;\n    (void)info;\n    if (" ^ p ^ "sig_target != 0) {\n        ucontext_t* uc = (ucontext_t*)ucontext_ptr;\n#if defined(__APPLE__)\n#if defined(__x86_64__)\n        uc->uc_mcontext->__ss.__rip = " ^ p ^ "sig_target;\n#elif defined(__arm64__) || defined(__aarch64__)\n        uc->uc_mcontext->__ss.__pc = " ^ p ^ "sig_target;\n#endif\n#elif defined(__linux__)\n#if defined(__x86_64__)\n        uc->uc_mcontext.gregs[REG_RIP] = (greg_t)" ^ p ^ "sig_target;\n#elif defined(__arm64__) || defined(__aarch64__)\n        uc->uc_mcontext.pc = " ^ p ^ "sig_target;\n#endif\n#endif\n        " ^ p ^ "sig_target = 0;\n    }\n}");
          raw_top ("static inline void " ^ p ^ "install_signal_dispatcher(void) {\n    struct sigaction sa;\n    memset(&sa, 0, sizeof(sa));\n    sa.sa_sigaction = " ^ p ^ "signal_dispatcher_handler;\n    sa.sa_flags = SA_SIGINFO;\n    sigemptyset(&sa.sa_mask);\n    sigaction(SIGFPE, &sa, NULL);\n    sigaction(SIGILL, &sa, NULL);\n}");
          raw_top ("#define " ^ p ^ "SIG_DISPATCH_SETUP() " ^ p ^ "install_signal_dispatcher()");
          raw_top ("#define " ^ p ^ "SIG_JUMP(target_ptr) do { \\\n    " ^ p ^ "sig_target = (uintptr_t)(target_ptr); \\\n    raise(SIGILL); \\\n} while(0)");
        ]
        ~else_decls:[
          preproc_if "defined(_WIN32) || defined(_WIN64)"
            [
              include_sys "windows.h";
              global_var ~is_static:true ~is_volatile:true UIntPtr (p ^ "sig_target") ~init:(LitInt 0);
              raw_top ("static LONG WINAPI " ^ p ^ "veh_handler(PEXCEPTION_POINTERS pExceptionInfo) {\n    if (" ^ p ^ "sig_target != 0) {\n#if defined(_M_X64) || defined(__x86_64__)\n        pExceptionInfo->ContextRecord->Rip = (DWORD64)" ^ p ^ "sig_target;\n#else\n        pExceptionInfo->ContextRecord->Eip = (DWORD)" ^ p ^ "sig_target;\n#endif\n        " ^ p ^ "sig_target = 0;\n        return EXCEPTION_CONTINUE_EXECUTION;\n    }\n    return EXCEPTION_CONTINUE_SEARCH;\n}");
              raw_top ("static inline void " ^ p ^ "install_signal_dispatcher(void) {\n    AddVectoredExceptionHandler(1, " ^ p ^ "veh_handler);\n}");
              raw_top ("#define " ^ p ^ "SIG_DISPATCH_SETUP() " ^ p ^ "install_signal_dispatcher()");
              raw_top ("#define " ^ p ^ "SIG_JUMP(target_ptr) do { \\\n    " ^ p ^ "sig_target = (uintptr_t)(target_ptr); \\\n    RaiseException(0xE0000001, 0, 0, NULL); \\\n} while(0)");
            ]
            ~else_decls:[
              raw_top ("#define " ^ p ^ "SIG_DISPATCH_SETUP() ((void)0)");
              raw_top ("#define " ^ p ^ "SIG_JUMP(target_ptr) ((void)0)");
            ]
        ]
    ] else []
  in

  let nanomites_decls =
    if emit_nanomites then [
      comment_top "/* ------------------------------------------------------------------------- */";
      comment_top "/* 11. MULTITHREADED NANOMITES & TRAP-AND-TRACE DISPATCHING                  */";
      comment_top "/* ------------------------------------------------------------------------- */";
      raw_top ("typedef struct {\n    uint32_t trap_id;\n    uintptr_t target_true;\n    uintptr_t target_false;\n    uint32_t key;\n} " ^ p ^ "nanomite_entry_t;");
      global_var ~is_static:true (Array (StructType (p ^ "nanomite_entry_t"), 64)) (p ^ "nanomite_table");
      global_var ~is_static:true SizeT (p ^ "nanomite_count") ~init:(LitInt 0);
      global_var ~is_static:true ~is_volatile:true UInt32 (p ^ "current_trap_id") ~init:(LitInt 0);
      global_var ~is_static:true ~is_volatile:true UInt32 (p ^ "current_condition") ~init:(LitInt 0);
      raw_top ("static inline void " ^ p ^ "register_nanomite(uint32_t trap_id, uintptr_t t_true, uintptr_t t_false, uint32_t key) {\n    if (" ^ p ^ "nanomite_count < 64) {\n        " ^ p ^ "nanomite_table[" ^ p ^ "nanomite_count].trap_id = trap_id;\n        " ^ p ^ "nanomite_table[" ^ p ^ "nanomite_count].target_true = t_true ^ (uintptr_t)key;\n        " ^ p ^ "nanomite_table[" ^ p ^ "nanomite_count].target_false = t_false ^ (uintptr_t)key;\n        " ^ p ^ "nanomite_table[" ^ p ^ "nanomite_count].key = key;\n        " ^ p ^ "nanomite_count++;\n    }\n}");
      raw_top ("static inline void " ^ p ^ "nanomite_dispatch(uint32_t id, uint32_t cond) {\n    for (size_t i = 0; i < " ^ p ^ "nanomite_count; ++i) {\n        if (" ^ p ^ "nanomite_table[i].trap_id == id) {\n            uintptr_t enc_target = cond ? " ^ p ^ "nanomite_table[i].target_true : " ^ p ^ "nanomite_table[i].target_false;\n            uintptr_t real_target = enc_target ^ (uintptr_t)" ^ p ^ "nanomite_table[i].key;\n            ((void (*)(void))real_target)();\n            return;\n        }\n    }\n}");
      preproc_if "defined(__APPLE__)"
        [
          func_decl ~attrs:[StaticFn; InlineFn] Void (p ^ "install_nanomites") [] [ raw "    (void)0;" ];
          raw_top ("#define " ^ p ^ "NANOMITE_INIT() " ^ p ^ "install_nanomites()");
          raw_top ("#define " ^ p ^ "NANOMITE_REGISTER(id, t_true, t_false, key) " ^ p ^ "register_nanomite((id), (uintptr_t)(t_true), (uintptr_t)(t_false), (uint32_t)(key))");
          raw_top ("#define " ^ p ^ "NANOMITE_DISPATCH(id, cond) " ^ p ^ "nanomite_dispatch((id), (cond) ? 1 : 0)");
        ]
        ~else_decls:[
          preproc_if "defined(__linux__) && !defined(_MSC_VER)"
            [
              include_sys "signal.h";
              include_sys "ucontext.h";
              raw_top ("static void " ^ p ^ "nanomite_trap_handler(int sig, siginfo_t* info, void* ucontext_ptr) {\n    (void)sig; (void)info;\n    ucontext_t* uc = (ucontext_t*)ucontext_ptr;\n    for (size_t i = 0; i < " ^ p ^ "nanomite_count; ++i) {\n        if (" ^ p ^ "nanomite_table[i].trap_id == " ^ p ^ "current_trap_id) {\n            uintptr_t enc_target = " ^ p ^ "current_condition ?\n                " ^ p ^ "nanomite_table[i].target_true :\n                " ^ p ^ "nanomite_table[i].target_false;\n            uintptr_t real_target = enc_target ^ (uintptr_t)" ^ p ^ "nanomite_table[i].key;\n#if defined(__x86_64__)\n            uc->uc_mcontext.gregs[REG_RIP] = (greg_t)real_target;\n#elif defined(__arm64__) || defined(__aarch64__)\n            uc->uc_mcontext.pc = real_target;\n#endif\n            " ^ p ^ "current_trap_id = 0;\n            return;\n        }\n    }\n}");
              raw_top ("static inline void " ^ p ^ "install_nanomites(void) {\n    struct sigaction sa;\n    memset(&sa, 0, sizeof(sa));\n    sa.sa_sigaction = " ^ p ^ "nanomite_trap_handler;\n    sa.sa_flags = SA_SIGINFO;\n    sigemptyset(&sa.sa_mask);\n    sigaction(SIGTRAP, &sa, NULL);\n}");
              raw_top ("#define " ^ p ^ "NANOMITE_INIT() " ^ p ^ "install_nanomites()");
              raw_top ("#define " ^ p ^ "NANOMITE_REGISTER(id, t_true, t_false, key) " ^ p ^ "register_nanomite((id), (uintptr_t)(t_true), (uintptr_t)(t_false), (uint32_t)(key))");
              raw_top ("#define " ^ p ^ "NANOMITE_DISPATCH(id, cond) do { \\\n    " ^ p ^ "current_trap_id = (id); \\\n    " ^ p ^ "current_condition = (cond) ? 1 : 0; \\\n    raise(SIGTRAP); \\\n} while(0)");
            ]
            ~else_decls:[
              preproc_if "defined(_WIN32) || defined(_WIN64)"
                [
                  raw_top ("static LONG WINAPI " ^ p ^ "nanomite_veh_handler(PEXCEPTION_POINTERS pExceptionInfo) {\n    if (pExceptionInfo->ExceptionRecord->ExceptionCode == EXCEPTION_BREAKPOINT || pExceptionInfo->ExceptionRecord->ExceptionCode == 0xE0000002) {\n        for (size_t i = 0; i < " ^ p ^ "nanomite_count; ++i) {\n            if (" ^ p ^ "nanomite_table[i].trap_id == " ^ p ^ "current_trap_id) {\n                uintptr_t enc_target = " ^ p ^ "current_condition ?\n                    " ^ p ^ "nanomite_table[i].target_true :\n                    " ^ p ^ "nanomite_table[i].target_false;\n                uintptr_t real_target = enc_target ^ (uintptr_t)" ^ p ^ "nanomite_table[i].key;\n#if defined(_M_X64) || defined(__x86_64__)\n                pExceptionInfo->ContextRecord->Rip = (DWORD64)real_target;\n#else\n                pExceptionInfo->ContextRecord->Eip = (DWORD)real_target;\n#endif\n                " ^ p ^ "current_trap_id = 0;\n                return EXCEPTION_CONTINUE_EXECUTION;\n            }\n        }\n    }\n    return EXCEPTION_CONTINUE_SEARCH;\n}");
                  raw_top ("static inline void " ^ p ^ "install_nanomites(void) {\n    AddVectoredExceptionHandler(1, " ^ p ^ "nanomite_veh_handler);\n}");
                  raw_top ("#define " ^ p ^ "NANOMITE_INIT() " ^ p ^ "install_nanomites()");
                  raw_top ("#define " ^ p ^ "NANOMITE_REGISTER(id, t_true, t_false, key) " ^ p ^ "register_nanomite((id), (uintptr_t)(t_true), (uintptr_t)(t_false), (uint32_t)(key))");
                  raw_top ("#define " ^ p ^ "NANOMITE_DISPATCH(id, cond) do { \\\n    " ^ p ^ "current_trap_id = (id); \\\n    " ^ p ^ "current_condition = (cond) ? 1 : 0; \\\n    RaiseException(0xE0000002, 0, 0, NULL); \\\n} while(0)");
                ]
                ~else_decls:[
                  raw_top ("#define " ^ p ^ "NANOMITE_INIT() ((void)0)");
                  raw_top ("#define " ^ p ^ "NANOMITE_REGISTER(id, t_true, t_false, key) ((void)0)");
                  raw_top ("#define " ^ p ^ "NANOMITE_DISPATCH(id, cond) ((void)0)");
                ]
            ]
        ]
    ] else []
  in

  timing_decls
  @ anti_debug_decls
  @ signal_decls
  @ nanomites_decls

let emit_guards_macros ?(emit_timing = true) ?(emit_anti_debug = true) ?(emit_signal = true) ?(emit_nanomites = true) b ~p =
  let decls = emit_guards_macro_decls ~emit_timing ~emit_anti_debug ~emit_signal ~emit_nanomites ~p () in
  Buffer.add_string b (render_top_decls decls ^ "\n")
