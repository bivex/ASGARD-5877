# ASGARD-5877: Project Roadmap & Status

> **Status**: All milestones of historical audit P0–P5 are 100% resolved.  
> The comprehensive historical audit specification is preserved in [`AUDIT_TODO.md`](AUDIT_TODO.md).  
> **Current Status (2026-10)**: All test suites passing cleanly with zero warnings under `-warn-error -a`.

---

## 1. Completed Milestones (Archive)

- [x] **P0: Core Engine Correctness** — 16-bit memory access (`ldrh`/`strh`), sign extension on loads (`ldrsb`/`ldrsh`/`movsx`/`movsxd`).
- [x] **P1: Safety and Fail-Closed Fault Tolerance** — eliminated silent fallback in `gpu_synth`, strict SMC mode (`ASGARD_SMC_STRICT`) with structured diagnostics.
- [x] **P2: Lifter Coverage** — x86-64 `div`/`idiv`/`mul` across all bit-widths B8–B64, sub-register write normalization (`subreg_write`), 3-address ALU canonicalization (`canonicalize_3addr_alu`).
- [x] **P3: Advanced Protection** — Anti-VMPredator address-bound bytecode with cryptographic binding of keystreams to concrete handler entrypoints.
- [x] **P4: Documentation and Test Matrices** — synchronized canonical test counters and architectural invariants.
- [x] **P5: Architectural Lifter and VM-IR Expansion**:
  - [x] **Level 1 (Quick Wins)**: Scalar floating-point (ARM64/RISC-V), host bit-manipulation primitives (`clz`/`ctz`/`popcnt`/`rev8`/`bswap`/`bt*`), x86 flags (`clc`/`stc`/`cmc`/`cld`/`std`), system traps (`syscall`, `cpuid`, `rdtsc`, `ecall`, `ebreak`, `eret`, CSR).
  - [x] **Level 2 (Medium)**: Bitfields (`ubfx`/`sbfx`/`bfi`/`extr`, BMI1/BMI2), 2-operand shifts (`shld`/`shrd`/`rcl`/`rcr`), multiply-accumulate (`smaddl`/`umaddl`/`smsubl`/`umsubl`/`smulh`/`umulh`), FP/Int conversions and square root (`cvtsi2ss/sd`, `cvtss2si/sd`, `fcvt.*`, `sqrtss`, `sqrtsd`, `fsqrt.s/d`), complex memory addressing (`ldp`/`stp`, `movbe`, `xlat`).
  - [x] **Level 3 (Hard)**: Full canonical EFLAGS model (`adc`/`sbb` B8–B64, `pushf`/`popf`, `lahf`/`sahf`, unified flags dispatcher), ARM64 conditional comparisons (`ccmp`/`ccmn`, selectors `csinc`/`csinv`/`csneg`, `adcs`/`sbcs`), x86 string operations with repeat prefixes (`rep`, `repe`, `repne`), SMP atomics and memory barriers (`fence`, `dmb`, `mfence`, `lock`, `xadd`, `cmpxchg`, `cmpxchg8b/16b`, `xchg`, LSE `swp`/`ldadd`, `lr`/`sc`/`amo*`), AVX-256 YMM registers (256/512 bit, upper zeroing on VEX-128, integer SIMD, explicit EVEX/ZMM traps).
  - [x] **Level 4 (Architectural)**: Parameterized RISC-V RVV 1.0 vector engine (`vsetvli`/`vsetivli`/`vsetvl`, CSR `vl`/`vtype`/`vlenb`, unit-stride/strided/indexed memory access, arithmetic/logic/shifts/div/rem, comparisons, masks, reductions, slides, and permutations).
  - [x] **x86_64 Specification**: moffs absolute offset addressing (`mov al/ax/eax/rax, [moffs]`), segment registers (`push/pop ds/es/fs/gs/ss`, `mov`, `rdfsbase/wrfsbase/rdgsbase/wrgsbase`), complete support for all three forms of `imul`.

---

## 2. Implemented Stage 3 Focus (2026-10)

- [x] **Windows PE / MSVC Toolchain & Native Runtime Parity (`lib/native_vm`)**:
  - [x] `runtime_syscalls`: Target OS dispatch (`target_os = [ \`Darwin | \`Linux | \`Windows | \`Auto ]`), stealth PEB probing (`__readgsqword(0x60)` / `__readfsdword(0x30)` -> `BeingDebugged`, `NtGlobalFlag`), Win32 I/O and process primitives.
  - [x] `runtime_dual_map`: W^X dual-mapping for Windows using `CreateFileMappingW` (pagefile-backed section) + split RW and RX `MapViewOfFile` mappings with cleanup via `UnmapViewOfFile`.
  - [x] `runtime_smc`: `_WIN32` support in `ASGARD_SMC_STRICT`, instruction cache invalidation via `FlushInstructionCache`, timer via `__rdtsc()`, and nanomite exception dispatch via `AddVectoredExceptionHandler`.
  - [x] `vm_control_handlers`: Emission of `__debugbreak()` nanomite traps for `_WIN32` targets.
  - [x] `runtime_probes`: Hardware breakpoint scanning across `Dr0..Dr7` via `GetThreadContext`, suspicious RWX page detection via `VirtualQuery`, and high-resolution timing differentials via `QueryPerformanceCounter`.
  - [x] `runtime_ephemeral_jit`: Instruction cache flushing with `FlushInstructionCache` and MSVC header bindings for ephemeral JIT.
- [x] **Advanced 5th-Order MBA Synthesis (`lib/mba_engine`)**:
  - [x] `mba.ml`: Degree-5 null polynomials over $\mathbb{Z}_{2^{64}}$ ($2^{61} \cdot x(x-1)(x-2)(x-3)(x-4) \equiv 0$) and nonlinear degree-5 cross-compositions over disjoint boolean partitions.
  - [x] `mba.mli`: Type `order = [ \`Deg4 | \`Deg5 ]`, extended signatures for `rewrite` and `obfuscate_alu`, exported polynomial invariant declarations.
  - [x] `egraph_rules.ml`: 5th-order expansion rules (`mul_nl_deg5_poly`, `mul_nl_deg5_cross`, `add_deg5_opaque`, `xor_deg5_opaque`), `rules_deg5`, `all_rules` (28 rules), and `verify_all_rules`.
  - [x] Verification and property-based equivalence tests for degree-5 MBA (`test_mba_deg5_polynomial_invariants`, `test_mba_deg5_rewrite_equivalence`).
- [x] **Configurable Junk Density and Size Budgets (`bloat_config.junk_density` & `target_size_budget_kb`)**:
  - [x] Parameterized junk instruction injection `inject_junk_instructions ?(density = 0.5)`: from 0.0 (fully disabled) to 2.0 (100% probability with multi-burst junk sequences).
  - [x] Integration with `vm_emitter`: ties `junk_density` to dynamic compaction when meeting strict binary size constraints (`target_size_budget_kb`).
- [x] **Dispatch Domain Diversification (`vm_runtime_emitter.ml` & `docs/VM_PROTECTOR.md`)**:
  - [x] Structural diversification of 216+ decoy slots across all domains $d \in [0, num\_domains - 1]$ (`(base_idx + d * 7 + i * 3) mod 16`).
  - [x] Preservation of opcode semantics across domains with distinct memory layout jump tables and unified hashing in `compute_handlers_hash`.
  - [x] Architectural trade-off: zero overhead direct threading ($O(1)$ dispatch via `goto *dispatch_domains[d][op]`) without indirection matrices, combined with decoy slot permutation.
- [x] **Full Virtual Machine Handler Metamorphism (`vm_control_handlers.ml`, `vm_mem_handlers.ml`, `vm_alu_handlers.ml`)**:
  - [x] **100% metamorphic coverage across the complete VM ISA (131 out of 131 handlers)**:
    - **ALU (51/51, 100%)**: Arithmetic and immediate ops (`ADD`, `SUB`, `IMUL`, `DIV`, `IDIV`, `MULH`, `IMULH`, `XOR`, `AND`, `OR`), shifts and rotates (`SHL`, `SHR`, `SAR`, `ROL`, `ROR` in RR/RI forms), bitwise and unary ops (`CLZ`, `CTZ`, `POPCNT`, `RBIT`, `BSWAP`, `NOT`, `NEG`), condition flags (`ADC`, `SBB`, `CCMP`, `CCMN`, `CMP_RR/RI`, `GET_FLAGS`, `SET_FLAGS`, `MOV_HIGH`, `NOP`).
    - **Control Flow (17/17, 100%)**: Branch and call skeleton (`JMP`, `JCC`, `CMOV`, `SETCC`, `CALL`, `RET`, `EXIT`, `IJMP_R`, `ICALL_R`, domain bridges `H_BRIDGE_TO_FLOW`/`MATH`), and 6 fused super-operators (`H_FUSED_MOV_ADD_RRI`, `H_FUSED_ADD_IMUL_RRI`, `H_FUSED_ADD_XOR_RRI`, `H_FUSED_SUB_XOR_RRI`, `H_FUSED_XOR_ADD_RRI`, `H_FUSED_CMP_CMOV`).
    - **Memory, Atomics, FP, SIMD & System (63/63, 100%)**: 8/16/32/64-bit load/store (`LOAD_*`, `STORE_*`, `LOAD_S32/S16/S8`), stack operations (`PUSH_R`, `POP_R`), vector register transfers (`MOV_VR`, `MOV_RV`, `VEC_MOV`), SIMD vector math (`VADD_VV`, `VSUB_VV`, `VMUL_VV`, `VXOR_VV`), SMP atomics (`ATOMIC_LOAD`, `ATOMIC_STORE`, `ATOMIC_CAS`, `ATOMIC_ADD`, `ATOMIC_SWP`), scalar FP (`FADD`, `FSUB`, `FMUL`, `FDIV`, `FSQRT`, `FCMP`, `FCVT*`, `FCSEL`), dynamic symbol resolution (`RESOLVE_SYM`), and all 16 decoy traps (`H_DECOY_0..15`).
  - [x] RNG substream domain separation (`split_rng`) across 6 domain tags in `vm_handlers_emitter.ml` (ALU=101, Control=102, Fused=103, Mem=104, Decoy=105, SIMD=106) to prevent cascading generation drift when editing modules.
  - [x] Combinatorial state space of emitted C++ code: $3^{131} \approx 2.7 \times 10^{62}$ unique syntactic configurations, orthogonal to random register permutations ($32! \approx 2.6 \times 10^{35}$) and decoy jump table diversification.
  - [x] Diversification tests in `test/test_anti_tamper_smc.ml` verifying multivalent block variations across all 11 instruction categories.
- [x] **Cross-Platform Section Integrity Hashing (`runtime_probes.ml`, `vm_context_emitter.ml`)**:
  - [x] Computes hash of `.text` and `.rodata` sections across macOS (`_dyld_get_image_header(0)` / `getsectiondata`), Linux (`dl_iterate_phdr` / `PF_X`), and Windows (`IMAGE_DOS_HEADER` / `IMAGE_NT_HEADERS`).
  - [x] Folds section hash into `compute_handlers_hash()` to cryptographically bind the Anti-Pushan rolling key (`rk`) and address decryption to the binary image.
  - [x] Dynamic memory drift detection in `evaluate_memory_integrity()` for immediate detection of inline hooks and breakpoints.
- [x] **Opaque Predicate Activation in CFF (`cff.ml` & `protection_presets.ml`)**:
  - [x] Splits basic blocks into a predicate header (`pred_block`) and operational body (`body_block`), eliminating `Ir.Jcc` infinite loop hazards.
  - [x] Mathematical invariant $((x \land (x + 1)) \land 1 \equiv 0)$ routing to `trap_block_id` on violation.
  - [x] Enabled by default in `max_security`, `high`, and `stealth` presets.
  - [x] End-to-end compilation and execution tests for C++ runtimes combining CFF with opaque predicates.

---

## 3. Future Directions (Stage 3 Backlog)

- [ ] **JIT Engine (`rd_jit_vm`)**:
  - [ ] Extend JIT emitter to support vector and atomic instructions in native runtime execution.
  - [ ] Optimize hot loops via dynamic devirtualization and host machine code compilation.
- [ ] **E2E Benchmarks and Stress Testing**:
  - [ ] Test suite of real-world C/C++ targets (OpenSSL, SQLite, Coreutils) compiled under Clang `-O3`.
  - [ ] Stress-testing against automated deobfuscators and symbolic engines (angr, Triton, Ghidra, IDA Pro).
- [ ] **Enrich NCFG Grammars with Novel Nonlinear Operators**.
