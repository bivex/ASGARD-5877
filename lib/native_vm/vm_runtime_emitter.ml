let emit_cpp_threaded_header ~rng ~key_seed ~reg_perm ~expected_hash ?(runtime_profile : Random_visa_domain.Vm_runtime_profile.t option) ?(config : Protection_config.t option) ?(external_symbols = []) ?(constants = []) opcode_to_handler =
  let profile = match runtime_profile with
    | Some p -> p
    | None -> Random_visa_domain.Vm_runtime_profile.generate ~seed:(Int64.of_int32 key_seed) ~total_opcodes:256 ()
  in
  let stride = profile.dispatch.context_layout.affine_a in
  let offset = profile.dispatch.context_layout.affine_b in
  let num_domains =
    match config with
    | Some c -> max 1 c.vm_runtime.num_dispatch_domains
    | None -> profile.dispatch.num_domains
  in
  let enable_smc = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.smc | None -> true in
  let enable_anti_emu = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.anti_emulation | None -> true in
  let enable_mem_scan = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.memory_integrity_scanner | None -> true in
  let enable_timing_probes = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.hardware_timing_probes | None -> true in
  let enable_nanomites = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.nanomites | None -> true in
  let enable_direct_syscalls = match config with Some c -> c.anti_tamper.enabled && c.anti_tamper.direct_syscalls | None -> true in
  let enable_running_key = Protection_config.rolling_key_enabled config in
  let enable_stack_scramble = match config with Some c -> c.vm_runtime.stack_scrambling | None -> true in
  let enable_mem_sanitize = match config with Some c -> c.vm_runtime.memory_sanitization | None -> true in
  let enable_vector_isa = match config with Some c -> c.vm_runtime.vector_isa | None -> true in
  let enable_egraph_expansion = match config with Some c -> c.vm_runtime.egraph_expansion | None -> true in
  let b = Buffer.create 4096 in
  Buffer.add_string b "#pragma once\n";
  Buffer.add_string b "#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n#include <stdio.h>\n#include <atomic>\n#include <bit>\n#include <cstring>\n";
  Buffer.add_string b "#if !defined(_WIN32) && !defined(_WIN64)\n#include <dlfcn.h>\n#endif\n#if !defined(RTLD_DEFAULT)\n#define RTLD_DEFAULT ((void*)0)\n#endif\n";
  Buffer.add_string b "#if defined(__APPLE__)\n#include <sys/types.h>\n#include <sys/sysctl.h>\n#include <unistd.h>\n#include <mach/mach.h>\n#include <mach/thread_act.h>\n#elif defined(__linux__)\n#include <fcntl.h>\n#include <unistd.h>\n#include <string.h>\n#elif defined(_WIN32) || defined(_WIN64)\n#include <windows.h>\n#endif\n\n";
  if enable_vector_isa then begin
    Buffer.add_string b "#if defined(__aarch64__)\n#include <arm_neon.h>\n#elif defined(__x86_64__)\n#include <immintrin.h>\n#endif\n\n";
  end;
  Buffer.add_string b (Vm_ir.Rns.emit_cpp_rns_header ());
  Buffer.add_string b "\n";
  if enable_direct_syscalls then begin
    Buffer.add_string b (Hardened_runtime.emit_direct_syscalls_header ());
    Buffer.add_string b "\n";
  end;
  if enable_anti_emu then begin
    Buffer.add_string b (Hardened_runtime.emit_anti_emulation_probes ());
    Buffer.add_string b "\n";
  end;
  Buffer.add_string b (Hardened_runtime.emit_dual_mapping_header ());
  Buffer.add_string b "\n";
  if enable_smc then begin
    Buffer.add_string b (Hardened_runtime.emit_introspective_smc_header ());
    Buffer.add_string b "\n";
  end;
  if enable_mem_scan then begin
    Buffer.add_string b (Hardened_runtime.emit_memory_integrity_scanner_header ());
    Buffer.add_string b "\n";
  end;
  if enable_nanomites then begin
    Buffer.add_string b (Hardened_runtime.emit_nanomite_engine_header ());
    Buffer.add_string b "\n";
  end;
  Buffer.add_string b "namespace vanguard_threaded_vm {\n\n";

  Buffer.add_string b "static const char* const g_external_symbols[] = {\n";
  if external_symbols = [] then
    Buffer.add_string b "    \"\"\n"
  else
    List.iter
      (fun s -> Buffer.add_string b (Printf.sprintf "    \"%s\",\n" (String.escaped s)))
      external_symbols;
  Buffer.add_string b "};\n\n";

  Buffer.add_string b "struct AsgardConstantEntry {\n    const char* name;\n    const uint8_t* data;\n    size_t size;\n};\n\n";
  if constants = [] then begin
    Buffer.add_string b "static const AsgardConstantEntry g_asgard_constants[] = { { \"\", nullptr, 0 } };\n\n";
  end else begin
    List.iteri
      (fun idx (_name, bytes) ->
        Buffer.add_string b (Printf.sprintf "static const uint8_t cdata_%d[] = { " idx);
        for i = 0 to String.length bytes - 1 do
          Buffer.add_string b (Printf.sprintf "0x%02X, " (Char.code bytes.[i]))
        done;
        Buffer.add_string b "0x00 };\n")
      constants;
    Buffer.add_string b "static const AsgardConstantEntry g_asgard_constants[] = {\n";
    List.iteri
      (fun idx (name, bytes) ->
        Buffer.add_string b (Printf.sprintf "    { \"%s\", cdata_%d, %d },\n" (String.escaped name) idx (String.length bytes)))
      constants;
    Buffer.add_string b "};\n\n";
  end;

  Buffer.add_string b "static inline void* asgard_resolve_constant(const char* name) {\n";
  Buffer.add_string b "    if (!name || name[0] == '\\0') return nullptr;\n";
  Buffer.add_string b "    for (size_t i = 0; i < sizeof(g_asgard_constants) / sizeof(g_asgard_constants[0]); ++i) {\n";
  Buffer.add_string b "        if (g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name) == 0) return (void*)g_asgard_constants[i].data;\n";
  Buffer.add_string b "        if (name[0] == '_' && g_asgard_constants[i].size > 0 && strcmp(g_asgard_constants[i].name, name + 1) == 0) return (void*)g_asgard_constants[i].data;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    return nullptr;\n";
  Buffer.add_string b "}\n\n";

  Vm_context_emitter.emit_context_hpp b ~key_seed ~reg_perm ~stride ~offset ~enable_running_key ~enable_stack_scramble ~enable_mem_sanitize;

  (* execute_threaded function with Multi-Domain Dispatch and Bytecode Integrity Checksumming *)
  Buffer.add_string b "#define SCRUB_WORD(ptr, val) do { \\\n";
  Buffer.add_string b "    *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \\\n";
  Buffer.add_string b "} while(0)\n\n";

  Buffer.add_string b (Printf.sprintf "__attribute__((always_inline, visibility(\"hidden\"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x%08lXU, bool scrub_source = false) {\n" key_seed);
  Buffer.add_string b "    if (ctx.reg_mask == 0) ctx.init(seed);\n";
  if enable_nanomites then begin
    Buffer.add_string b "    /* Nanomite Hardware Signal Dispatcher (Hardware TRAP/Branch Interceptor) */\n";
    Buffer.add_string b "    asgard_nanomites::install_nanomite_handlers(seed);\n\n";
  end;
  Buffer.add_string b "    /* High-Speed Continuous Bytecode Integrity Guard (Anti-Patching / Breakpoint Detection) */\n";
  Buffer.add_string b "    uint64_t full_hash = 0x811C9DC5C9DC5119ULL ^ (uint64_t)seed;\n";
  Buffer.add_string b "    for (size_t i = 0; i < count; ++i) {\n";
  Buffer.add_string b "        full_hash = ((full_hash ^ bytecode[i]) * 0x100000001B3ULL) + (uint64_t)i;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b (Printf.sprintf "    if (full_hash != 0x%016LXULL) {\n" expected_hash);
  Buffer.add_string b "        /* Anti-Patching Tripwire: Silent Context Poisoning */\n";
  Buffer.add_string b "        ctx.reg_mask ^= 0xDEADBEEF5A5A5A5AULL;\n";
  Buffer.add_string b "        ctx.trapped = true;\n";
  Buffer.add_string b "        return false;\n";
  Buffer.add_string b "    }\n\n";
  if enable_direct_syscalls then begin
    Buffer.add_string b "    /* Active Anti-Debugging Probe (Bypassing libc via Direct Kernel Syscalls) */\n";
    Buffer.add_string b "    if (asgard_syscalls::sys_check_debugger_present()) {\n";
    Buffer.add_string b "        ctx.reg_mask ^= 0xCAFEBABE13375877ULL;\n";
    Buffer.add_string b "        ctx.trapped = true;\n";
    Buffer.add_string b "        return false;\n";
    Buffer.add_string b "    }\n\n";
  end else begin
    Buffer.add_string b "    /* Active Anti-Debugging & Hardware Breakpoint Probe */\n";
    Buffer.add_string b "#if defined(__APPLE__)\n";
    Buffer.add_string b "    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };\n";
    Buffer.add_string b "    struct kinfo_proc kinfo = {};\n";
    Buffer.add_string b "    size_t ksize = sizeof(kinfo);\n";
    Buffer.add_string b "    if (sysctl(mib, 4, &kinfo, &ksize, (void*)0, 0) == 0 && (kinfo.kp_proc.p_flag & P_TRACED)) {\n";
    Buffer.add_string b "        ctx.reg_mask ^= 0xCAFEBABE13375877ULL;\n";
    Buffer.add_string b "        ctx.trapped = true;\n";
    Buffer.add_string b "        return false;\n";
    Buffer.add_string b "    }\n";
    Buffer.add_string b "#endif\n\n";
  end;
  if enable_anti_emu then begin
    Buffer.add_string b "    /* Anti-Emulation & Hypervisor Timing Differential Probe */\n";
    Buffer.add_string b "    uint64_t emu_penalty = asgard_anti_emulation::evaluate_emulation_differential();\n";
    Buffer.add_string b "    if (emu_penalty != 0) {\n";
    Buffer.add_string b "        ctx.reg_mask ^= emu_penalty;\n";
    Buffer.add_string b "    }\n\n";
  end;
  if enable_smc then begin
    Buffer.add_string b "    /* Introspective Self-Modifying Code (SMC) & Hardware Timing Probe (Morse & Kojsik, 2026) */\n";
    Buffer.add_string b "    uint64_t smc_penalty = asgard_smc::execute_introspective_smc_probe((uint64_t)seed);\n";
    Buffer.add_string b "    if (smc_penalty != 0) {\n";
    Buffer.add_string b "        ctx.reg_mask ^= smc_penalty;\n";
    Buffer.add_string b "    }\n\n";
  end;
  if enable_mem_scan then begin
    Buffer.add_string b "    /* In-Memory MEM-SBOM Forensics & Hardware Breakpoint Probe */\n";
    Buffer.add_string b "    uint64_t mem_penalty = asgard_mem_integrity::evaluate_memory_integrity();\n";
    Buffer.add_string b "    if (mem_penalty != 0) {\n";
    Buffer.add_string b "        ctx.reg_mask ^= mem_penalty;\n";
    Buffer.add_string b "    }\n\n";
  end;

  Buffer.add_string b "    /* Ephemeral Working Buffer: Isolated stack frame execution */\n";
  Buffer.add_string b "    uint64_t stack_buf[256];\n";
  Buffer.add_string b "    uint64_t* work_bc = (count <= 256) ? stack_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));\n";
  if enable_mem_sanitize then
    Buffer.add_string b "    for (size_t i = 0; i < count; ++i) work_bc[i] = 0x5877CAFE1337BEEFULL ^ ((uint64_t)seed + (uint64_t)i);\n\n"
  else
    Buffer.add_string b "    for (size_t i = 0; i < count; ++i) work_bc[i] = bytecode[i];\n\n";
  Buffer.add_string b "    size_t vIP_idx = 0;\n\n";

  (* Multi-Domain Dispatch Tables *)
  for d = 0 to num_domains - 1 do
    Buffer.add_string b (Printf.sprintf "    static const void* const dispatch_domain%d[256] = {\n" d);
    for i = 0 to 255 do
      let h_name = opcode_to_handler.(i) in
      Buffer.add_string b (Printf.sprintf "        &&%s,\n" h_name)
    done;
    Buffer.add_string b "    };\n\n"
  done;

  Buffer.add_string b (Printf.sprintf "    static const void* const* const all_dispatch_domains[%d] = {\n" num_domains);
  for d = 0 to num_domains - 1 do
    Buffer.add_string b (Printf.sprintf "        dispatch_domain%d,\n" d)
  done;
  Buffer.add_string b "    };\n\n";

  Buffer.add_string b "    uint64_t word = 0;\n";
  Buffer.add_string b "    uint8_t op = 0;\n";
  Buffer.add_string b "    uint8_t dst = 0;\n";
  Buffer.add_string b "    uint8_t src = 0;\n";
  Buffer.add_string b "    int64_t imm = 0;\n\n";

  Buffer.add_string b "    #define FETCH_NEXT() do { \\\n";
  Buffer.add_string b "        if (vIP_idx >= count) goto EXIT_VM; \\\n";
  Buffer.add_string b "        uint64_t k_pos = key64_for_offset(seed, vIP_idx); \\\n";
  if enable_running_key then
    Buffer.add_string b "        uint64_t k_dyn = k_pos ^ ctx.running_key; \\\n"
  else
    Buffer.add_string b "        uint64_t k_dyn = k_pos; \\\n";
  Buffer.add_string b "        work_bc[vIP_idx] = bytecode[vIP_idx]; \\\n";
  Buffer.add_string b "        word = work_bc[vIP_idx] ^ k_dyn; \\\n";
  if enable_mem_sanitize then
    Buffer.add_string b "        /* Ephemeral Self-Consuming: Overwrite scratch RAM buffer with dynamic rolling noise */ \\\n        SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL); \\\n";
  Buffer.add_string b "        vIP_idx++; \\\n";
  Buffer.add_string b "        op = (uint8_t)(word & 0xFF); \\\n";
  Buffer.add_string b "        dst = (uint8_t)((word >> 8) & 0x1F); \\\n";
  Buffer.add_string b "        src = (uint8_t)((word >> 13) & 0x1F); \\\n";
  Buffer.add_string b "        imm = (int64_t)((int32_t)((word >> 18) & 0xFFFFFFFFULL)); \\\n";
  Buffer.add_string b "        ctx.evolve_mask((uint32_t)k_dyn); \\\n";
  if enable_running_key then
    Buffer.add_string b "        ctx.advance_running_key(op, dst, imm); \\\n";
  Buffer.add_string b (Printf.sprintf "        uint8_t domain_idx = (uint8_t)((op ^ (uint8_t)(k_dyn & 0x07)) %% %d); \\\n" num_domains);
  Buffer.add_string b "        goto *all_dispatch_domains[domain_idx][op]; \\\n";
  Buffer.add_string b "    } while(0)\n\n";

  (* Anti-Pushan: entry block always starts at offset 0 — anchor the chain there. *)
  if enable_running_key then
    Buffer.add_string b "    ctx.reanchor_running_key(0);\n";
  Buffer.add_string b "    FETCH_NEXT();\n\n";

  Vm_handlers_emitter.emit_handlers_hpp b ~rng ~enable_running_key ~enable_timing_probes ~enable_nanomites ~enable_egraph_expansion;

  Buffer.add_string b "    EXIT_VM:\n";
  if enable_mem_sanitize then begin
    Buffer.add_string b "    /* Ephemeral Complete Memory Sanitization: Scrub all working memory */\n";
    Buffer.add_string b "    for (size_t i = 0; i < count; ++i) {\n";
    Buffer.add_string b "        SCRUB_WORD(&work_bc[i], 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i));\n";
    Buffer.add_string b "    }\n";
    Buffer.add_string b "    if (scrub_source && bytecode) {\n";
    Buffer.add_string b "        for (size_t i = 0; i < count; ++i) {\n";
    Buffer.add_string b "            SCRUB_WORD(&const_cast<uint64_t*>(bytecode)[i], 0xDEADBEEFCAFEBABEULL ^ ((uint64_t)seed + (uint64_t)i));\n";
    Buffer.add_string b "        }\n";
    Buffer.add_string b "    }\n";
  end;
  Buffer.add_string b "    return !ctx.trapped;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b (Printf.sprintf "__attribute__((always_inline, visibility(\"hidden\"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, bool scrub_source) {\n    return execute_threaded(ctx, bytecode, count, 0x%08lXU, scrub_source);\n}\n\n" key_seed);
  Buffer.add_string b "static inline uint64_t asgard_vm_call(const uint64_t* bc, size_t len, uint64_t a0 = 0, uint64_t a1 = 0, uint64_t a2 = 0, uint64_t a3 = 0, uint64_t a4 = 0, uint64_t a5 = 0, uint64_t a6 = 0, uint64_t a7 = 0) {\n";
  Buffer.add_string b "    vanguard_threaded_vm::VMContext ctx = {};\n";
  Buffer.add_string b (Printf.sprintf "    ctx.init(0x%08lXU);\n" key_seed);
  Buffer.add_string b "    alignas(16) static thread_local uint8_t host_stack[1048576];\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RSP, (uint64_t)(host_stack + sizeof(host_stack) - 8192));\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RBP, (uint64_t)(host_stack + sizeof(host_stack) - 8192));\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RAX, a0);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RCX, a1);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RDX, a2);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RBX, a3);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RSI, a4);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_RDI, a5);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_R8,  a6);\n";
  Buffer.add_string b "    ctx.set_reg(vanguard_threaded_vm::REG_R9,  a7);\n";
  Buffer.add_string b "    vanguard_threaded_vm::execute_threaded(ctx, bc, len, false);\n";
  Buffer.add_string b "    return ctx.get_rax();\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "} // namespace vanguard_threaded_vm\n";
  Buffer.contents b

let emit_runner_cpp ?(key_seed = 0x5877CAFEL) ~reg_perm bytecode =
  let _ = key_seed in
  let _ = reg_perm in
  let b = Buffer.create 2048 in
  Buffer.add_string b "#include \"threaded_vm.hpp\"\n";
  Buffer.add_string b "#include <stdio.h>\n#include <stdlib.h>\n\n";
  Buffer.add_string b "/* Self-contained embedded encrypted bytecode (Mutable for Ephemeral Memory Scrubbing) */\n";
  Buffer.add_string b "static uint64_t embedded_bytecode[] = {\n";
  List.iter
    (fun w ->
      Buffer.add_string b (Printf.sprintf "    0x%016LXULL,\n" w))
    bytecode;
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "int main(int argc, char** argv) {\n";
  Buffer.add_string b "    uint64_t* bc_ptr = embedded_bytecode;\n";
  Buffer.add_string b "    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);\n";
  Buffer.add_string b "    uint64_t* heap_bc = NULL;\n\n";
  Buffer.add_string b "    if (argc >= 2) {\n";
  Buffer.add_string b "        FILE* f = fopen(argv[1], \"rb\");\n";
  Buffer.add_string b "        if (f) {\n";
  Buffer.add_string b "            fseek(f, 0, SEEK_END);\n";
  Buffer.add_string b "            long sz = ftell(f);\n";
  Buffer.add_string b "            fseek(f, 0, SEEK_SET);\n";
  Buffer.add_string b "            if (sz > 0 && (sz % 8) == 0) {\n";
  Buffer.add_string b "                size_t count = (size_t)sz / 8;\n";
  Buffer.add_string b "                heap_bc = (uint64_t*)malloc((size_t)sz);\n";
  Buffer.add_string b "                if (heap_bc && fread(heap_bc, 8, count, f) == count) {\n";
  Buffer.add_string b "                    bc_ptr = heap_bc;\n";
  Buffer.add_string b "                    bc_len = count;\n";
  Buffer.add_string b "                }\n";
  Buffer.add_string b "            }\n";
  Buffer.add_string b "            fclose(f);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    vanguard_threaded_vm::VMContext ctx = {};\n";
  Buffer.add_string b "    bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr, bc_len, true);\n";
  Buffer.add_string b "    if (heap_bc) {\n";
  Buffer.add_string b "        /* Ephemeral Heap Sanitization: Scrub all dynamically allocated bytecode before free */\n";
  Buffer.add_string b "        for (size_t i = 0; i < bc_len; ++i) {\n";
  Buffer.add_string b "            SCRUB_WORD(&heap_bc[i], 0xDEADBEEFCAFEBABEULL ^ (uint64_t)i);\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        free(heap_bc);\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    if (!ok) return 2;\n";
  Buffer.add_string b "    printf(\"[VM] Execution SUCCESS! Verified %zu instructions. RAX: %llu\\n\",\n";
  Buffer.add_string b "           ctx.executed_instructions, (unsigned long long)ctx.get_rax());\n";
  Buffer.add_string b "    return 0;\n";
  Buffer.add_string b "}\n";
  Buffer.contents b
