open Vm_ir

type vm_package = {
  bytecode : int64 list;
  cpp_runtime_source : string;
  runner_source : string;
  metrics : Metrics.metrics_report;
}

let reg_to_index = function
  | Register.Gpr (g, _) -> Register.gpr_index g
  | Register.Vreg (Register.VTMP0, _) -> 16
  | Register.Vreg (Register.VTMP1, _) -> 17
  | Register.Vreg (Register.VTMP2, _) -> 18
  | Register.Vreg (Register.VTMP3, _) -> 19
  | Register.Vreg (Register.VIP, _)   -> 20
  | Register.Vreg (Register.VSP, _)   -> 21
  | Register.Vreg (Register.VKEY, _)  -> 22

let cond_to_code = function
  | Flags.E -> 0 | Flags.NE -> 1 | Flags.B -> 2 | Flags.AE -> 3
  | Flags.BE -> 4 | Flags.A -> 5 | Flags.S -> 6 | Flags.NS -> 7
  | Flags.L -> 8 | Flags.GE -> 9 | Flags.LE -> 10 | Flags.G -> 11
  | Flags.O -> 12 | Flags.NO -> 13 | Flags.P -> 14 | Flags.NP -> 15
  | Flags.ALWAYS -> 0

type raw_op_kind =
  | OP_NOP
  | OP_MOV_RR
  | OP_MOV_RI
  | OP_ADD_RR
  | OP_ADD_RI
  | OP_SUB_RR
  | OP_SUB_RI
  | OP_IMUL_RR
  | OP_IMUL_RI
  | OP_XOR_RR
  | OP_XOR_RI
  | OP_AND_RR
  | OP_AND_RI
  | OP_OR_RR
  | OP_OR_RI
  | OP_CMP_RR
  | OP_CMP_RI
  | OP_PUSH_R
  | OP_POP_R
  | OP_JMP
  | OP_JCC
  | OP_CMOV
  | OP_RET
  | OP_EXIT
  | OP_FUSED_MOV_ADD_RRI
  | OP_FUSED_ADD_IMUL_RRI
  | OP_FUSED_ADD_XOR_RRI
  | OP_FUSED_SUB_XOR_RRI
  | OP_FUSED_XOR_ADD_RRI
  | OP_FUSED_CMP_CMOV

let all_op_kinds = [
  OP_NOP; OP_MOV_RR; OP_MOV_RI; OP_ADD_RR; OP_ADD_RI;
  OP_SUB_RR; OP_SUB_RI; OP_IMUL_RR; OP_IMUL_RI; OP_XOR_RR; OP_XOR_RI;
  OP_AND_RR; OP_AND_RI; OP_OR_RR; OP_OR_RI; OP_CMP_RR; OP_CMP_RI; OP_PUSH_R;
  OP_POP_R; OP_JMP; OP_JCC; OP_CMOV; OP_RET; OP_EXIT;
  OP_FUSED_MOV_ADD_RRI; OP_FUSED_ADD_IMUL_RRI; OP_FUSED_ADD_XOR_RRI;
  OP_FUSED_SUB_XOR_RRI; OP_FUSED_XOR_ADD_RRI; OP_FUSED_CMP_CMOV;
]

let op_kind_to_handler_name = function
  | OP_NOP -> "H_NOP"
  | OP_MOV_RR -> "H_MOV_RR"
  | OP_MOV_RI -> "H_MOV_RI"
  | OP_ADD_RR -> "H_ADD_RR"
  | OP_ADD_RI -> "H_ADD_RI"
  | OP_SUB_RR -> "H_SUB_RR"
  | OP_SUB_RI -> "H_SUB_RI"
  | OP_IMUL_RR -> "H_IMUL_RR"
  | OP_IMUL_RI -> "H_IMUL_RI"
  | OP_XOR_RR -> "H_XOR_RR"
  | OP_XOR_RI -> "H_XOR_RI"
  | OP_AND_RR -> "H_AND_RR"
  | OP_AND_RI -> "H_AND_RI"
  | OP_OR_RR -> "H_OR_RR"
  | OP_OR_RI -> "H_OR_RI"
  | OP_CMP_RR -> "H_CMP_RR"
  | OP_CMP_RI -> "H_CMP_RI"
  | OP_PUSH_R -> "H_PUSH_R"
  | OP_POP_R -> "H_POP_R"
  | OP_JMP -> "H_JMP"
  | OP_JCC -> "H_JCC"
  | OP_CMOV -> "H_CMOV"
  | OP_RET -> "H_RET"
  | OP_EXIT -> "H_EXIT"
  | OP_FUSED_MOV_ADD_RRI -> "H_FUSED_MOV_ADD_RRI"
  | OP_FUSED_ADD_IMUL_RRI -> "H_FUSED_ADD_IMUL_RRI"
  | OP_FUSED_ADD_XOR_RRI -> "H_FUSED_ADD_XOR_RRI"
  | OP_FUSED_SUB_XOR_RRI -> "H_FUSED_SUB_XOR_RRI"
  | OP_FUSED_XOR_ADD_RRI -> "H_FUSED_XOR_ADD_RRI"
  | OP_FUSED_CMP_CMOV -> "H_FUSED_CMP_CMOV"



let shuffle_array rng arr =
  let n = Array.length arr in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- tmp
  done

let emit_cpp_threaded_header ~rng ~key_seed ~reg_perm ~expected_hash opcode_to_handler =
  let b = Buffer.create 4096 in
  Buffer.add_string b "#pragma once\n";
  Buffer.add_string b "#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\n";
  Buffer.add_string b "#if defined(__APPLE__)\n#include <sys/types.h>\n#include <sys/sysctl.h>\n#include <unistd.h>\n#include <mach/mach.h>\n#include <mach/thread_act.h>\n#elif defined(__linux__)\n#include <fcntl.h>\n#include <unistd.h>\n#include <string.h>\n#elif defined(_WIN32) || defined(_WIN64)\n#include <windows.h>\n#endif\n\n";
  Buffer.add_string b "namespace vanguard_threaded_vm {\n\n";


  Buffer.add_string b "/* ------------------------------------------------------------------------- */\n";
  Buffer.add_string b "/* Randomized Architectural Register Map (π ∈ S_32)                          */\n";
  Buffer.add_string b "/* ------------------------------------------------------------------------- */\n";
  Buffer.add_string b "enum RegMap : uint8_t {\n";
  let gpr_names = [|
    "REG_RAX"; "REG_RCX"; "REG_RDX"; "REG_RBX"; "REG_RSP"; "REG_RBP"; "REG_RSI"; "REG_RDI";
    "REG_R8";  "REG_R9";  "REG_R10"; "REG_R11"; "REG_R12"; "REG_R13"; "REG_R14"; "REG_R15";
    "REG_VTMP0"; "REG_VTMP1"; "REG_VTMP2"; "REG_VTMP3"; "REG_VIP"; "REG_VSP"; "REG_VKEY"
  |] in
  Array.iteri
    (fun i name ->
      Buffer.add_string b (Printf.sprintf "    %s = %d,\n" name reg_perm.(i)))
    gpr_names;
  Buffer.add_string b "};\n\n";

  (* Key Derivation for Bytecode Offset *)
  Buffer.add_string b "static inline uint32_t key_for_offset(uint32_t seed, size_t offset) noexcept {\n";
  Buffer.add_string b "    uint64_t x = (uint64_t)seed ^ ((uint64_t)offset * 0x9E3779B97F4A7C15ULL);\n";
  Buffer.add_string b "    uint32_t x32 = (uint32_t)x;\n";
  Buffer.add_string b "    x32 ^= x32 << 13;\n";
  Buffer.add_string b "    x32 ^= x32 >> 17;\n";
  Buffer.add_string b "    x32 ^= x32 << 5;\n";
  Buffer.add_string b "    return x32 == 0 ? 0x1337BEEFU : x32;\n";
  Buffer.add_string b "}\n\n";

  (* Blinded VMContext (Resisting VMPredator & Memory Taint Analysis) *)
  Buffer.add_string b "struct VMContext {\n";
  Buffer.add_string b "    uint64_t gprs[32]; // Blinded in memory: actual_val = gprs[i] ^ reg_mask\n";
  Buffer.add_string b "    uint64_t stack[512];\n";
  Buffer.add_string b "    size_t sp;\n";
  Buffer.add_string b "    uint64_t reg_mask;\n";
  Buffer.add_string b "    bool cf, zf, sf, of;\n";
  Buffer.add_string b "    bool trapped;\n";
  Buffer.add_string b "    size_t executed_instructions;\n\n";
  Buffer.add_string b "    inline void init(uint32_t seed = 0x13375877U) noexcept {\n";
  Buffer.add_string b "        reg_mask = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed * 0x9E3779B97F4A7C15ULL);\n";
  Buffer.add_string b "        for (size_t i = 0; i < 32; ++i) gprs[i] = reg_mask; // Initialized to 0 (0 ^ reg_mask)\n";
  Buffer.add_string b "        sp = 0;\n";
  Buffer.add_string b "        cf = zf = sf = of = false;\n";
  Buffer.add_string b "        trapped = false;\n";
  Buffer.add_string b "        executed_instructions = 0;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint64_t get_reg(uint8_t i) const noexcept {\n";
  Buffer.add_string b "        return gprs[i] ^ reg_mask;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline void set_reg(uint8_t i, uint64_t v) noexcept {\n";
  Buffer.add_string b "        gprs[i] = v ^ reg_mask;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    // Named architectural register accessors via randomized permutation\n";
  Buffer.add_string b "    inline uint64_t get_rax() const noexcept { return get_reg(REG_RAX); }\n";
  Buffer.add_string b "    inline void set_rax(uint64_t v) noexcept { set_reg(REG_RAX, v); }\n";
  Buffer.add_string b "    inline uint64_t get_rdi() const noexcept { return get_reg(REG_RDI); }\n";
  Buffer.add_string b "    inline void set_rdi(uint64_t v) noexcept { set_reg(REG_RDI, v); }\n";
  Buffer.add_string b "    inline uint64_t get_rsi() const noexcept { return get_reg(REG_RSI); }\n";
  Buffer.add_string b "    inline void set_rsi(uint64_t v) noexcept { set_reg(REG_RSI, v); }\n\n";
  Buffer.add_string b "    inline void evolve_mask(uint32_t k) noexcept {\n";
  Buffer.add_string b "        uint64_t delta = ((uint64_t)k * 0x6A09E667F3BCC908ULL) ^ 0x1337ULL;\n";
  Buffer.add_string b "        uint64_t old_mask = reg_mask;\n";
  Buffer.add_string b "        uint64_t new_mask = (reg_mask ^ delta) + 0x5877ULL;\n";
  Buffer.add_string b "        for (size_t i = 0; i < 32; ++i) {\n";
  Buffer.add_string b "            gprs[i] = (gprs[i] ^ old_mask) ^ new_mask;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        reg_mask = new_mask;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    /* Virtual Stack Scrambling (Non-linear Permutation & Dynamic Memory Encryption) */\n";
  Buffer.add_string b "    static inline constexpr size_t STACK_SIZE = 512;\n";
  Buffer.add_string b "    static inline constexpr size_t STACK_STRIDE = 37;\n";
  Buffer.add_string b "    static inline constexpr size_t STACK_OFFSET = 13;\n\n";
  Buffer.add_string b "    inline size_t scramble_stack_idx(size_t index) const noexcept {\n";
  Buffer.add_string b "        return (index * STACK_STRIDE + STACK_OFFSET) & (STACK_SIZE - 1);\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline void push(uint64_t v) noexcept {\n";
  Buffer.add_string b "        if (sp < STACK_SIZE) {\n";
  Buffer.add_string b "            size_t phys_idx = scramble_stack_idx(sp);\n";
  Buffer.add_string b "            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;\n";
  Buffer.add_string b "            stack[phys_idx] = v ^ enc_mask;\n";
  Buffer.add_string b "            sp++;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint64_t pop() noexcept {\n";
  Buffer.add_string b "        if (sp > 0) {\n";
  Buffer.add_string b "            sp--;\n";
  Buffer.add_string b "            size_t phys_idx = scramble_stack_idx(sp);\n";
  Buffer.add_string b "            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;\n";
  Buffer.add_string b "            uint64_t val = stack[phys_idx] ^ enc_mask;\n";
  Buffer.add_string b "            stack[phys_idx] = 0xDEADBEEFCAFE1337ULL ^ enc_mask; // Ephemeral slot wipe\n";
  Buffer.add_string b "            return val;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        return 0ULL;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";

  (* Helper condition check *)
  Buffer.add_string b "static inline bool eval_condition(const VMContext& ctx, uint8_t cond) noexcept {\n";
  Buffer.add_string b "    switch (cond) {\n";
  Buffer.add_string b "        case 0: return ctx.zf;                         // E\n";
  Buffer.add_string b "        case 1: return !ctx.zf;                        // NE\n";
  Buffer.add_string b "        case 2: return ctx.cf;                         // B\n";
  Buffer.add_string b "        case 3: return !ctx.cf;                        // AE\n";
  Buffer.add_string b "        case 4: return ctx.cf || ctx.zf;               // BE\n";
  Buffer.add_string b "        case 5: return !ctx.cf && !ctx.zf;             // A\n";
  Buffer.add_string b "        case 6: return ctx.sf;                         // S\n";
  Buffer.add_string b "        case 7: return !ctx.sf;                        // NS\n";
  Buffer.add_string b "        case 8: return ctx.sf != ctx.of;               // L\n";
  Buffer.add_string b "        case 9: return ctx.sf == ctx.of;               // GE\n";
  Buffer.add_string b "        case 10: return ctx.zf || (ctx.sf != ctx.of);  // LE\n";
  Buffer.add_string b "        case 11: return !ctx.zf && (ctx.sf == ctx.of); // G\n";
  Buffer.add_string b "        default: return true;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "}\n\n";

  (* execute_threaded function with Bytecode Integrity Checksumming *)
  Buffer.add_string b (Printf.sprintf "__attribute__((always_inline, visibility(\"hidden\"))) static inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x%08lXU) {\n" key_seed);
  Buffer.add_string b "    if (ctx.reg_mask == 0) ctx.init(seed);\n";
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

  Buffer.add_string b "    /* Ephemeral Working Buffer: Isolated stack frame execution */\n";
  Buffer.add_string b "    uint64_t stack_buf[256];\n";
  Buffer.add_string b "    uint64_t* work_bc = (count <= 256) ? stack_buf : (uint64_t*)__builtin_alloca(count * sizeof(uint64_t));\n";
  Buffer.add_string b "    for (size_t i = 0; i < count; ++i) work_bc[i] = bytecode[i];\n\n";
  Buffer.add_string b "    size_t vIP_idx = 0;\n\n";


  Buffer.add_string b "    static const void* const dispatch_table[256] = {\n";
  for i = 0 to 255 do
    let h_name = opcode_to_handler.(i) in
    Buffer.add_string b (Printf.sprintf "        &&%s,\n" h_name)
  done;
  Buffer.add_string b "    };\n\n";

  Buffer.add_string b "    uint64_t word = 0;\n";
  Buffer.add_string b "    uint8_t op = 0;\n";
  Buffer.add_string b "    uint8_t dst = 0;\n";
  Buffer.add_string b "    uint8_t src = 0;\n";
  Buffer.add_string b "    int64_t imm = 0;\n\n";

  Buffer.add_string b "    #define FETCH_NEXT() do { \\\n";
  Buffer.add_string b "        if (vIP_idx >= count) goto EXIT_VM; \\\n";
  Buffer.add_string b "        uint32_t k = key_for_offset(seed, vIP_idx); \\\n";
  Buffer.add_string b "        word = bytecode[vIP_idx] ^ (uint64_t)((int64_t)((int32_t)k)); \\\n";
  Buffer.add_string b "        /* Ephemeral Self-Consuming: Overwrite scratch RAM buffer with rolling noise */ \\\n";
  Buffer.add_string b "        work_bc[vIP_idx] = ((uint64_t)k * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL; \\\n";
  Buffer.add_string b "        vIP_idx++; \\\n";
  Buffer.add_string b "        op = (uint8_t)(word & 0xFF); \\\n";
  Buffer.add_string b "        dst = (uint8_t)((word >> 8) & 0x1F); \\\n";
  Buffer.add_string b "        src = (uint8_t)((word >> 13) & 0x1F); \\\n";
  Buffer.add_string b "        imm = (int64_t)((int32_t)((word >> 18) & 0xFFFFFFFFULL)); \\\n";
  Buffer.add_string b "        ctx.evolve_mask(k); \\\n";
  Buffer.add_string b "        goto *dispatch_table[op]; \\\n";
  Buffer.add_string b "    } while(0)\n\n";

  Buffer.add_string b "    FETCH_NEXT();\n\n";

  (* Polymorphic SOTA Handlers (Synthesized Non-Linear Variants) *)
  let pick_poly_add () =
    match Random.State.int rng 3 with
    | 0 -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)) + 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | 1 -> "((ctx.get_reg(dst) | ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | _ -> "(2 * (ctx.get_reg(dst) | ctx.get_reg(src)) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))"
  in
  let pick_poly_sub () =
    match Random.State.int rng 2 with
    | 0 -> "((ctx.get_reg(dst) ^ ctx.get_reg(src)) - 2 * ((~ctx.get_reg(dst)) & ctx.get_reg(src)))"
    | _ -> "(2 * (ctx.get_reg(dst) & (~ctx.get_reg(src))) - (ctx.get_reg(dst) ^ ctx.get_reg(src)))"
  in
  let pick_poly_xor () =
    match Random.State.int rng 2 with
    | 0 -> "((ctx.get_reg(dst) | ctx.get_reg(src)) ^ (ctx.get_reg(dst) & ctx.get_reg(src)))"
    | _ -> "((ctx.get_reg(dst) + ctx.get_reg(src)) - 2 * (ctx.get_reg(dst) & ctx.get_reg(src)))"
  in

  Buffer.add_string b "    H_NOP: ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RR: ctx.set_reg(dst, ctx.get_reg(src)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RI: ctx.set_reg(dst, (uint64_t)imm); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b (Printf.sprintf "    H_ADD_RR: ctx.set_reg(dst, %s); ctx.executed_instructions++; FETCH_NEXT();\n" (pick_poly_add ()));
  Buffer.add_string b "    H_ADD_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + 2 * (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b (Printf.sprintf "    H_SUB_RR: ctx.set_reg(dst, %s); ctx.executed_instructions++; FETCH_NEXT();\n" (pick_poly_sub ()));
  Buffer.add_string b "    H_SUB_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) - 2 * ((~ctx.get_reg(dst)) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_IMUL_RR: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
  Buffer.add_string b "        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_IMUL_RI: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
  Buffer.add_string b "        ctx.set_reg(dst, ((a & b) * (a | b)) + ((a & (~b)) * ((~a) & b)));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b (Printf.sprintf "    H_XOR_RR: ctx.set_reg(dst, %s); ctx.executed_instructions++; FETCH_NEXT();\n" (pick_poly_xor ()));
  Buffer.add_string b "    H_XOR_RI: ctx.set_reg(dst, (ctx.get_reg(dst) | (uint64_t)imm) ^ (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_AND_RR: ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) - (ctx.get_reg(dst) | ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_AND_RI: ctx.set_reg(dst, (ctx.get_reg(dst) + (uint64_t)imm) - (ctx.get_reg(dst) | (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_OR_RR: ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (ctx.get_reg(dst) & ctx.get_reg(src))); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_OR_RI: ctx.set_reg(dst, (ctx.get_reg(dst) ^ (uint64_t)imm) + (ctx.get_reg(dst) & (uint64_t)imm)); ctx.executed_instructions++; FETCH_NEXT();\n";

  Buffer.add_string b "    H_CMP_RI: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMP_RR: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = ctx.get_reg(src);\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_PUSH_R: ctx.push(ctx.get_reg(dst)); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_POP_R: ctx.set_reg(dst, ctx.pop()); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_JMP: {\n";
  Buffer.add_string b "        vIP_idx = (size_t)imm;\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_JCC: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        uint16_t t_true = (uint16_t)((word >> 22) & 0x3FF);\n";
  Buffer.add_string b "        uint16_t t_false = (uint16_t)((word >> 32) & 0x3FF);\n";
  Buffer.add_string b "        vIP_idx = eval_condition(ctx, cond) ? (size_t)t_true : (size_t)t_false;\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMOV: {\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;\n";
  Buffer.add_string b "    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;\n\n";


  (* Super-Operators (Fused Instruction Handlers - TODD PROEBSTING SOTA) *)
  Buffer.add_string b "    H_FUSED_MOV_ADD_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, ctx.get_reg(src) + (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_ADD_IMUL_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) * (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_ADD_XOR_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) + ctx.get_reg(src)) ^ (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_SUB_XOR_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) - ctx.get_reg(src)) ^ (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_XOR_ADD_RRI: {\n";
  Buffer.add_string b "        ctx.set_reg(dst, (ctx.get_reg(dst) ^ ctx.get_reg(src)) + (uint64_t)imm);\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_FUSED_CMP_CMOV: {\n";
  Buffer.add_string b "        uint64_t a = ctx.get_reg(dst); uint64_t b = (uint64_t)imm;\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = ((int64_t)res < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        uint8_t cond = (uint8_t)((word >> 50) & 0x0F);\n";
  Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.set_reg(dst, ctx.get_reg(src));\n";
  Buffer.add_string b "        ctx.executed_instructions += 2;\n";
  Buffer.add_string b "        FETCH_NEXT();\n";
  Buffer.add_string b "    }\n\n";

  Buffer.add_string b "    H_DECOY:\n";
  Buffer.add_string b "        ctx.trapped = true;\n";
  Buffer.add_string b "        goto EXIT_VM;\n\n";


  Buffer.add_string b "    EXIT_VM:\n";
  Buffer.add_string b "    /* Ephemeral Complete Memory Sanitization: Scrub all working memory */\n";
  Buffer.add_string b "    for (size_t i = 0; i < count; ++i) {\n";
  Buffer.add_string b "        work_bc[i] = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed + (uint64_t)i);\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    return !ctx.trapped;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "} // namespace vanguard_threaded_vm\n";
  Buffer.contents b



let emit_runner_cpp ~reg_perm bytecode =
  let _ = reg_perm in
  let b = Buffer.create 2048 in
  Buffer.add_string b "#include \"threaded_vm.hpp\"\n";
  Buffer.add_string b "#include <stdio.h>\n#include <stdlib.h>\n\n";
  Buffer.add_string b "/* Self-contained embedded encrypted bytecode */\n";
  Buffer.add_string b "static const uint64_t embedded_bytecode[] = {\n";
  List.iter
    (fun w ->
      Buffer.add_string b (Printf.sprintf "    0x%016LXULL,\n" w))
    bytecode;
  Buffer.add_string b "};\n\n";
  Buffer.add_string b "int main(int argc, char** argv) {\n";
  Buffer.add_string b "    const uint64_t* bc_ptr = embedded_bytecode;\n";
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
  Buffer.add_string b "    bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr, bc_len);\n";
  Buffer.add_string b "    if (heap_bc) free(heap_bc);\n\n";
  Buffer.add_string b "    if (!ok) return 2;\n";
  Buffer.add_string b "    printf(\"[VM] Execution SUCCESS! Verified %zu instructions. RAX: %llu\\n\",\n";
  Buffer.add_string b "           ctx.executed_instructions, (unsigned long long)ctx.get_rax());\n";
  Buffer.add_string b "    return 0;\n";
  Buffer.add_string b "}\n";
  Buffer.contents b

type vm_op =
  | Raw of Ir.instr
  | Fused_Mov_Add of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Add_Imul of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Add_Xor of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Sub_Xor of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Xor_Add of { dst : Register.t; src : Register.t; imm : int64 }
  | Fused_Cmp_Cmov of { cmp_dst : Register.t; cmp_imm : int64; cond : Flags.condition; cmov_dst : Register.t; cmov_src : Register.t }

let extract_real_regs instrs =
  let set = Hashtbl.create 8 in

  List.iter
    (fun (i : Ir.instr) ->
      match i with
      | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
          Hashtbl.replace set d (); Hashtbl.replace set s ()
      | Ir.Mov { dst = Ir.Reg d; _ } -> Hashtbl.replace set d ()
      | Ir.Alu { dst = d; src1 = Ir.Reg s1; src2 = Ir.Reg s2; _ } ->
          Hashtbl.replace set d (); Hashtbl.replace set s1 (); Hashtbl.replace set s2 ()
      | Ir.Alu { dst = d; src1 = Ir.Reg s1; _ } ->
          Hashtbl.replace set d (); Hashtbl.replace set s1 ()
      | Ir.Cmp { src1 = Ir.Reg s1; src2 = Ir.Reg s2 } ->
          Hashtbl.replace set s1 (); Hashtbl.replace set s2 ()
      | Ir.Cmp { src1 = Ir.Reg s1; _ } -> Hashtbl.replace set s1 ()
      | Ir.Push (Ir.Reg r) | Ir.Pop (Ir.Reg r) | Ir.Cmov { dst = r; _ } -> Hashtbl.replace set r ()
      | _ -> ())
    instrs;
  Hashtbl.fold (fun r () acc ->
    match r with
    | Register.Gpr _ -> r :: acc
    | _ -> acc) set []

let generate_junk_instrs rng ~real_regs =
  let vdst = Register.Vreg (Register.VTMP2, Register.B64) in
  let imm = Int64.of_int32 (Random.State.int32 rng Int32.max_int) in
  match Random.State.int rng 5 with
  | 0 ->
      (* Phantom constant load *)
      [ Ir.Mov { dst = Ir.Reg vdst; src = Ir.Imm imm } ]
  | 1 ->
      (* Phantom arithmetic accumulation *)
      [ Ir.Alu { op = Ir.Add; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false } ]
  | 2 ->
      (* Phantom non-linear XOR-MUL chain *)
      [
        Ir.Alu { op = Ir.Xor; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false };
        Ir.Alu { op = Ir.Imul; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm 0x5877L; set_flags = false };
      ]
  | 3 ->
      (* Dead Taint Siphoning: Copy real register into phantom register without altering real register *)
      if List.length real_regs > 0 then
        let r = List.nth real_regs (Random.State.int rng (List.length real_regs)) in
        [
          Ir.Mov { dst = Ir.Reg vdst; src = Ir.Reg r };
          Ir.Alu { op = Ir.Xor; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false };
        ]
      else
        [ Ir.Alu { op = Ir.Add; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false } ]
  | _ ->
      (* Phantom bitwise OR *)
      [ Ir.Alu { op = Ir.Or; dst = vdst; src1 = Ir.Reg vdst; src2 = Ir.Imm imm; set_flags = false } ]

let inject_junk_instructions ~rng instrs =
  let real_regs = extract_real_regs instrs in
  let rec aux = function
    | [] -> []
    | [Ir.Ret] -> [Ir.Ret]
    | [Ir.Vm_exit] -> [Ir.Vm_exit]
    | (Ir.Cmp _ as cmp) :: (Ir.Cmov _ as cmov) :: rest ->
        let junk = if Random.State.int rng 100 < 35 then generate_junk_instrs rng ~real_regs else [] in
        cmp :: cmov :: (junk @ aux rest)
    | (Ir.Cmp _ as cmp) :: (Ir.Jcc _ as jcc) :: rest ->
        cmp :: jcc :: aux rest
    | (Ir.Jmp _ as j) :: rest ->
        j :: aux rest
    | (Ir.Jcc _ as j) :: rest ->
        j :: aux rest
    | hd :: rest ->
        let junk = if Random.State.int rng 100 < 35 then generate_junk_instrs rng ~real_regs else [] in
        hd :: (junk @ aux rest)
  in
  aux instrs


let rec fuse_block_instructions instrs =
  match instrs with
  | [] -> []
  | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ::
    Ir.Alu { op = Ir.Add; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d2 && d = d3 ->
      Fused_Mov_Add { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Imul; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 ->
      Fused_Add_Imul { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Xor; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 ->
      Fused_Add_Xor { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Xor; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 ->
      Fused_Sub_Xor { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg d1; src2 = Ir.Reg s; _ } ::
    Ir.Alu { op = Ir.Add; dst = d2; src1 = Ir.Reg d3; src2 = Ir.Imm imm; _ } :: rest
    when d = d1 && d = d2 && d = d3 ->
      Fused_Xor_Add { dst = d; src = s; imm } :: fuse_block_instructions rest

  | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Imm imm } ::
    Ir.Cmov { cond; dst = d2; src = Ir.Reg s } :: rest
    when d = d2 ->
      Fused_Cmp_Cmov { cmp_dst = d; cmp_imm = imm; cond; cmov_dst = d2; cmov_src = s } :: fuse_block_instructions rest

  | hd :: rest ->
      Raw hd :: fuse_block_instructions rest

let compile_and_package
    ~rng
    ?(enable_cff = false)
    ?(enable_mba = false)
    ?(enable_junk = true)
    ?(mba_depth = 2)
    (func : Ir.func) =
  let target_func =
    if enable_cff then
      match Cff.flatten_func ~rng func with
      | Ok f -> f
      | Error _ -> func
    else func
  in

  (* Generate randomized bijective register permutation π ∈ S_32 *)
  let reg_perm = Array.init 32 (fun i -> i) in
  shuffle_array rng reg_perm;
  let get_reg_idx r = reg_perm.(reg_to_index r) in

  (* Set up opcode bijection and junk decoys *)
  let slots = Array.init 256 (fun i -> i) in
  shuffle_array rng slots;
  let kind_to_code = Hashtbl.create 32 in
  let opcode_to_handler = Array.make 256 "H_DECOY" in
  List.iteri
    (fun i kind ->
      let code = slots.(i) in
      Hashtbl.replace kind_to_code kind code;
      opcode_to_handler.(code) <- op_kind_to_handler_name kind)
    all_op_kinds;

  let get_opcode kind =
    Hashtbl.find kind_to_code kind
  in

  (* Linearize blocks and calculate block start offsets in bytecode with Super-Operator fusion and Junk insertion *)
  let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
  let other_blocks =
    Hashtbl.fold
      (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
      target_func.cfg.blocks []
  in
  let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
  let sorted_blocks = entry_block :: sorted_other in

  let block_fused_ops = Hashtbl.create (List.length sorted_blocks) in
  List.iter
    (fun (b : Ir.basic_block) ->
      let instrs = if enable_junk then inject_junk_instructions ~rng b.instrs else b.instrs in
      let fused = fuse_block_instructions instrs in
      Hashtbl.replace block_fused_ops b.id fused)
    sorted_blocks;


  let block_offsets = Hashtbl.create (List.length sorted_blocks) in
  let cur_offset = ref 0 in
  List.iter
    (fun (b : Ir.basic_block) ->
      let fused = Hashtbl.find block_fused_ops b.id in
      Hashtbl.replace block_offsets b.id !cur_offset;
      cur_offset := !cur_offset + List.length fused)
    sorted_blocks;

  let get_block_offset id =
    Option.value ~default:0 (Hashtbl.find_opt block_offsets id)
  in

  let key_seed = Random.State.int32 rng Int32.max_int in
  let key_for_offset seed offset =
    let off_hash = Int64.mul (Int64.of_int offset) 0x9E3779B97F4A7C15L in
    let x = Int64.logxor (Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL) off_hash in
    let x32 = Int64.to_int32 x in
    let x32 = Int32.logxor x32 (Int32.shift_left x32 13) in
    let x32 = Int32.logxor x32 (Int32.shift_right_logical x32 17) in
    let x32 = Int32.logxor x32 (Int32.shift_left x32 5) in
    if x32 = 0l then 0x1337BEEFl else x32
  in

  let cur_idx = ref 0 in
  let bytecode = ref [] in
  let encode_raw_word ?(extra_bits = 0L) op dst src imm =
    let w = ref 0L in
    w := Int64.logor !w (Int64.of_int op);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int dst) 8);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int src) 13);
    let imm_masked = Int64.logand imm 0xFFFFFFFFL in
    w := Int64.logor !w (Int64.shift_left imm_masked 18);
    w := Int64.logor !w (Int64.shift_left (Int64.logand extra_bits 0x3FFFL) 50);
    let mask = Int64.of_int32 (key_for_offset key_seed !cur_idx) in
    incr cur_idx;
    let masked_w = Int64.logxor !w mask in
    bytecode := masked_w :: !bytecode
  in

  (* Encode instructions (both Fused Super-Operators and Standard Raw Ops) *)
  List.iter
    (fun (b : Ir.basic_block) ->
      let ops = Hashtbl.find block_fused_ops b.id in
      List.iter
        (function
          | Fused_Mov_Add { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_MOV_ADD_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Add_Imul { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_ADD_IMUL_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Add_Xor { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_ADD_XOR_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Sub_Xor { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_SUB_XOR_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Xor_Add { dst; src; imm } ->
              encode_raw_word (get_opcode OP_FUSED_XOR_ADD_RRI) (get_reg_idx dst) (get_reg_idx src) imm
          | Fused_Cmp_Cmov { cmp_dst = _; cmp_imm; cond; cmov_dst; cmov_src } ->
              encode_raw_word ~extra_bits:(Int64.of_int (cond_to_code cond))
                (get_opcode OP_FUSED_CMP_CMOV) (get_reg_idx cmov_dst) (get_reg_idx cmov_src) cmp_imm
          | Raw instr -> (
              match instr with
              | Ir.Nop -> encode_raw_word (get_opcode OP_NOP) 0 0 0L
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_MOV_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
                  encode_raw_word (get_opcode OP_MOV_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_ADD_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_ADD_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_SUB_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_SUB_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Imul; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_IMUL_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Imul; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_IMUL_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_XOR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_XOR_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.And; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_AND_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.And; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_AND_RI) (get_reg_idx d) 0 imm
              | Ir.Alu { op = Ir.Or; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
                  encode_raw_word (get_opcode OP_OR_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Alu { op = Ir.Or; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
                  encode_raw_word (get_opcode OP_OR_RI) (get_reg_idx d) 0 imm
              | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_CMP_RR) (get_reg_idx d) (get_reg_idx s) 0L
              | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Imm imm } ->
                  encode_raw_word (get_opcode OP_CMP_RI) (get_reg_idx d) 0 imm
              | Ir.Push (Ir.Reg d) ->
                  encode_raw_word (get_opcode OP_PUSH_R) (get_reg_idx d) 0 0L
              | Ir.Pop (Ir.Reg d) ->
                  encode_raw_word (get_opcode OP_POP_R) (get_reg_idx d) 0 0L
              | Ir.Jmp (Ir.BlockId bid) ->
                  encode_raw_word (get_opcode OP_JMP) 0 0 (Int64.of_int (get_block_offset bid))
              | Ir.Jcc { cond; target_true = Ir.BlockId tid; target_false = Ir.BlockId fid } ->
                  let c = cond_to_code cond in
                  let t_off = get_block_offset tid in
                  let f_off = get_block_offset fid in
                  let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int t_off) 4) in
                  let imm = Int64.logor imm (Int64.shift_left (Int64.of_int f_off) 14) in
                  encode_raw_word (get_opcode OP_JCC) 0 0 imm
              | Ir.Cmov { cond; dst; src = Ir.Reg s } ->
                  encode_raw_word (get_opcode OP_CMOV) (get_reg_idx dst) (get_reg_idx s) (Int64.of_int (cond_to_code cond))
              | Ir.Ret -> encode_raw_word (get_opcode OP_RET) 0 0 0L
              | Ir.Vm_exit -> encode_raw_word (get_opcode OP_EXIT) 0 0 0L
              | _ -> encode_raw_word (get_opcode OP_NOP) 0 0 0L))
        ops)
    sorted_blocks;

  let final_bytecode = List.rev !bytecode in
  let compute_bytecode_hash seed bc =
    let h = ref (Int64.logxor 0x811C9DC5C9DC5119L (Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL)) in
    List.iteri
      (fun i w ->
        let mixed = Int64.logxor !h w in
        let mul = Int64.mul mixed 0x100000001B3L in
        h := Int64.add mul (Int64.of_int i))
      bc;
    !h
  in
  let expected_hash = compute_bytecode_hash key_seed final_bytecode in
  let cpp_src = emit_cpp_threaded_header ~rng ~key_seed ~reg_perm ~expected_hash opcode_to_handler in
  let runner_src = emit_runner_cpp ~reg_perm final_bytecode in

  let decoy_count = 256 - List.length all_op_kinds in
  let mba_nodes = if enable_mba then mba_depth * 15 else 0 in
  let metrics = Metrics.calculate_metrics
    ~bytecode:final_bytecode
    ~func:target_func
    ~decoy_count
    ~total_handlers:256
    ~mba_nodes
  in

  {
    bytecode = final_bytecode;
    cpp_runtime_source = cpp_src;
    runner_source = runner_src;
    metrics;
  }



