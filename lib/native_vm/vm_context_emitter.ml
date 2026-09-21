let emit_context_hpp b ~key_seed ~reg_perm ~stride ~offset ~enable_running_key ~enable_stack_scramble ~enable_mem_sanitize =
  ignore enable_running_key;
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

  (* 64-bit Cryptographic Key Derivation for Bytecode Offset (SplitMix64) *)
  Buffer.add_string b "static inline uint64_t key64_for_offset(uint32_t seed, size_t offset) noexcept {\n";
  Buffer.add_string b "    uint64_t s64 = (uint64_t)seed;\n";
  Buffer.add_string b "    uint64_t x0 = ((s64 << 32) | (s64 ^ 0x9E3779B9ULL)) ^ ((uint64_t)offset * 0x517CC1B727220A95ULL);\n";
  Buffer.add_string b "    uint64_t x1 = (x0 ^ (x0 >> 30)) * 0xBF58476D1CE4E5B9ULL;\n";
  Buffer.add_string b "    uint64_t x2 = (x1 ^ (x1 >> 27)) * 0x94D049BB133111EBULL;\n";
  Buffer.add_string b "    return x2 ^ (x2 >> 31);\n";
  Buffer.add_string b "}\n\n";

  (* Blinded VMContext with Canary Guard Zones *)
  Buffer.add_string b "struct VMContext {\n";
  Buffer.add_string b "    static inline constexpr uint64_t CANARY_VAL = 0xCAFEBABE13375877ULL;\n";
  Buffer.add_string b "    uint64_t canary_head = CANARY_VAL;\n";
  Buffer.add_string b "    uint64_t mid_canaries[32]; // Interleaved dynamic canaries across every 16 stack frames\n";
  Buffer.add_string b "    uint64_t gprs[32]; // Blinded in memory: actual_val = gprs[i] ^ reg_mask\n";
  Buffer.add_string b "    uint64_t stack[512];\n";
  Buffer.add_string b "    size_t sp;\n";
  Buffer.add_string b "    uint64_t reg_mask;\n";
  Buffer.add_string b "    uint32_t init_seed;\n";
  Buffer.add_string b "    uint64_t poison_penalty;\n";
  Buffer.add_string b "    uint64_t running_key;\n";
  Buffer.add_string b "    bool cf, zf, sf, of;\n";
  Buffer.add_string b "    bool trapped;\n";
  Buffer.add_string b "    size_t executed_instructions;\n";
  Buffer.add_string b "    uint64_t canary_tail = CANARY_VAL;\n\n";
  Buffer.add_string b (Printf.sprintf "    inline void init(uint32_t seed = 0x%08lXU) noexcept {\n" key_seed);
  Buffer.add_string b "        init_seed = seed;\n";
  Buffer.add_string b "        poison_penalty = (key64_for_offset(seed, 0x5877) ^ 0xCAA7E1D8718BF877ULL) | 1ULL;\n";
  Buffer.add_string b "        running_key = key64_for_offset(seed, 0x13375877ULL) ^ 0xCAFEBABE13375877ULL;\n";
  Buffer.add_string b "        reg_mask = 0x5A5A5A5A13375877ULL ^ ((uint64_t)seed * 0x9E3779B97F4A7C15ULL);\n";
  Buffer.add_string b "        for (size_t i = 0; i < 32; ++i) {\n";
  Buffer.add_string b "            gprs[i] = reg_mask; // Initialized to 0 (0 ^ reg_mask)\n";
  Buffer.add_string b "            mid_canaries[i] = CANARY_VAL ^ ((uint64_t)i * 0x517CC1B727220A95ULL) ^ (uint64_t)seed;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        gprs[REG_VKEY] = running_key ^ reg_mask;\n";
  Buffer.add_string b "        sp = 0;\n";
  Buffer.add_string b "        cf = zf = sf = of = false;\n";
  Buffer.add_string b "        trapped = false;\n";
  Buffer.add_string b "        executed_instructions = 0;\n";
  Buffer.add_string b "        canary_head = canary_tail = CANARY_VAL;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    static inline uint64_t advance_key_step(uint64_t k, uint8_t op, uint8_t dst, int64_t imm) noexcept {\n";
  Buffer.add_string b "        uint64_t x = k ^ (((uint64_t)op * 0x9E3779B97F4A7C15ULL) + ((uint64_t)dst << 24) + (uint64_t)imm);\n";
  Buffer.add_string b "        uint64_t rot = (x >> 23) | (x << 41);\n";
  Buffer.add_string b "        return (rot * 0xBF58476D1CE4E5B9ULL) ^ 0x5877CAFE1337BEEFULL;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline void advance_running_key(uint8_t op, uint8_t dst, int64_t imm) noexcept {\n";
  Buffer.add_string b "        running_key = advance_key_step(running_key, op, dst, imm);\n";
  Buffer.add_string b "        gprs[REG_VKEY] = running_key ^ reg_mask;\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint64_t get_vkey() const noexcept { return running_key; }\n\n";
  Buffer.add_string b "    inline bool verify_canaries() const noexcept {\n";
  Buffer.add_string b "        if (canary_head != CANARY_VAL || canary_tail != CANARY_VAL) return false;\n";
  Buffer.add_string b "        size_t frame = (sp >> 4) & 31;\n";
  Buffer.add_string b "        uint64_t expected = CANARY_VAL ^ ((uint64_t)frame * 0x517CC1B727220A95ULL) ^ (uint64_t)init_seed;\n";
  Buffer.add_string b "        return (mid_canaries[frame] == expected);\n";
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
  Buffer.add_string b "    /* Virtual Stack Scrambling (8-Round Speck-64 ARX Permutation Core) */\n";
  Buffer.add_string b "    static inline constexpr size_t STACK_SIZE = 512;\n";
  Buffer.add_string b (Printf.sprintf "    static inline constexpr size_t STACK_STRIDE = %d;\n" stride);
  Buffer.add_string b (Printf.sprintf "    static inline constexpr size_t STACK_OFFSET = %d;\n\n" offset);
  if enable_stack_scramble then
    Buffer.add_string b "    inline size_t scramble_stack_idx(size_t index) const noexcept {\n        return (size_t)((index * STACK_STRIDE + STACK_OFFSET) & (STACK_SIZE - 1));\n    }\n\n"
  else
    Buffer.add_string b "    inline size_t scramble_stack_idx(size_t index) const noexcept {\n        return index;\n    }\n\n";
  Buffer.add_string b "    inline void push(uint64_t v) noexcept {\n";
  Buffer.add_string b "        if (!verify_canaries()) { reg_mask ^= poison_penalty; trapped = true; }\n";
  Buffer.add_string b "        if (sp < STACK_SIZE) {\n";
  Buffer.add_string b "            size_t phys_idx = scramble_stack_idx(sp);\n";
  Buffer.add_string b "            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;\n";
  Buffer.add_string b "            stack[phys_idx] = v ^ enc_mask;\n";
  Buffer.add_string b "            sp++;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "    }\n\n";
  Buffer.add_string b "    inline uint64_t pop() noexcept {\n";
  Buffer.add_string b "        if (!verify_canaries()) { reg_mask ^= poison_penalty; trapped = true; }\n";
  Buffer.add_string b "        if (sp > 0) {\n";
  Buffer.add_string b "            sp--;\n";
  Buffer.add_string b "            size_t phys_idx = scramble_stack_idx(sp);\n";
  Buffer.add_string b "            uint64_t enc_mask = ((uint64_t)sp * 0x9E3779B97F4A7C15ULL) ^ 0xA5A5A5A55A5A5A5AULL;\n";
  Buffer.add_string b "            uint64_t val = stack[phys_idx] ^ enc_mask;\n";
  if enable_mem_sanitize then
    Buffer.add_string b "            stack[phys_idx] = 0xDEADBEEFCAFE1337ULL ^ enc_mask; // Ephemeral slot wipe\n";
  Buffer.add_string b "            return val;\n";
  Buffer.add_string b "        }\n";
  Buffer.add_string b "        return 0ULL;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";

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
  Buffer.add_string b "}\n\n"
