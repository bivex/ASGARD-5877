# ASGARD-5877: Audit TODO — Unfinished Features and Silent Degradations

> **Source**: Engine audit from 2026-09-23 (HEAD `898a4ee`, `dune runtest` passing).
> Not to be confused with `docs/archive/CPP_TODO.md` — all items there are marked DONE; the items below were tracked separately. Order = priority.
> **Current Status (2026-10)**: Baseline P0–P4 limitations resolved; test registry contains comprehensive test suites (100% pass rate). Below is the extended P5 roadmap for advancing lifters and VM-IR to production-grade coverage.

---

## P0 — Engine Correctness (Breakages on Standard `-O2` Code)

### 1. Missing 16-Bit Memory Access: `ldrh`/`strh` read/write 1 byte instead of 2 — COMPLETED 2026-09-23

- Implemented per specification: added opcodes `OP_LOAD_16`/`OP_STORE_16` in `vm_transform.ml` (OCaml emitter and C++ dispatch table synchronized; anti-pushan golden vectors do not depend on opcodes and remain passing), C++ handlers `H_LOAD_16`/`H_STORE_16` in `vm_mem_handlers.ml` (`uint16_t`, zero-extended matching `ldrh wX`), and `B16` branches in load/store width pattern matches in `vm_emitter.ml`.
- Tests: unit test `ARM64 Lift Halfword Memory (strh/ldrh)` in `test_arm64_lifter.ml` (asserts exactly 1 B16-store and 1 B16-load in IR + evaluator output 0xBFAD); native `native_b16_word_memory` (word slot via `[rsp-16]`, both bytes: 0xCACAFE; legacy byte-only bug produced 0xFE); full E2E `e2e_uint16_pipeline` (uint16 arithmetic inside `ASGARD_BEGIN_VIRTUALIZE` across entire pipeline, protected application exits 0) and `e2e_uint16_clang_o2_o3` (same region compiled under clang -O2/-O3, lifted + `asgard_vm_call`, result 0xF6AA; old bug produced 0x5A) in `test/test_native_semantics.ml`.
- **Ancillary Root Cause Found (same class as item 9)**: The ARM64 lifter was silently mislifting 3-operand ALU instructions with shifted operands — `add w8, w8, w0, lsr #16` (standard Clang uint16 idiom) matched a catch-all as `+0`, while old explicit `orr/eor` patterns with `lsl/lsr` encoded `src1 != dst`, which the emitter dropped. Fixed in `arm64_alu.ml`: unified `emit_shifted_alu` materializing shift in `vtmp1`, then dispatching via `emit_3addr_alu` preserving the `src1 = dst` convention; `add/sub/orr/eor` now share a single helper.
- Residual limitations: `ldrsh` (sign-extending load) originally zero-extended — resolved under item 2.

### 2. Missing Sign Extension on Loads: `ldrsb`/`ldrsh`/`movsx`/`movsxd` — COMPLETED 2026-09-24

- Implemented per specification:
  - Opcodes `OP_LOAD_S8` / `OP_LOAD_S16` / `OP_LOAD_S32` in `vm_transform.ml`, native C++ handlers `H_LOAD_S8` / `H_LOAD_S16` / `H_LOAD_S32` in `vm_mem_handlers.ml` (`(uint64_t)(int64_t)(*reinterpret_cast<const int8_t*/int16_t*/int32_t*>)`), with branches in `vm_emitter.ml` checking `m.is_signed`.
  - Added `is_signed : bool` flag to `Ir.mem_ref`, supported in `Vm_eval.read_mem` with sign extension to int64.
  - ARM64: in `arm64_parser.ml` and `arm64_mem.ml`, segregated `ldrsb`/`ldrsh`/`ldrsw`/`ldursb`/`ldursh`/`ldursw` (`is_signed = true`, width B8/B16/B32) from `ldrb`/`ldrh`/`ldur`/`ldurb` (`is_signed = false`).
  - x86: in `lifter.ml`, segregated `movsx`/`movsxd` (and aliases `movsxb`/`movsxw`/`movsbq`/`movswq`/`movslq`) from `movzx`. For memory operands, `is_signed = true` is set; for register operands, accurate sign extension is materialized via `Shl`/`Sar` pair on B64 (followed by `subreg_write` zeroing upper half for B32 dst). For `movzx` with register source, masking via `And` (`0xFF`/`0xFFFF`) was added.
  - **Ancillary Fix**: register parser `Register.of_string` previously failed unconditionally on non-numeric suffixes when checking the `d` prefix for FP registers `d0`..`d31`, blocking x86 registers `dx`, `di`, `dil`, `dl`. Fixed: non-numeric `d`- and `s`-registers fall through to the general pattern match.
- Tests: 6 new unit and E2E tests:
  - ARM64: unit `ARM64 Lift Signed Memory (ldrsb/ldrsh/ldrsw)` in `test_arm64_lifter.ml` (-5, -300, -100000 -> -100305).
  - x86: 3 units in `test_x86_lifter.ml` (`lift_and_eval_movsx_mem`, `lift_and_eval_movsx_reg`, `lift_and_eval_movzx_reg`).
  - Native & E2E: `native_signed_loads` (stack signed loads in threaded VM) and `e2e_signed_loads_clang_o2_o3` (C function with `volatile signed char/short/int`, Clang -O2/-O3 compilation, signed mem ops verification in IR, producing -100305 via `asgard_vm_call`) in `test_native_semantics.ml`.

---

## P1 — Silent Protection Degradation (Security-Critical)

### 3. `gpu_synth` Silently Returning Insecure Data on Failure — COMPLETED 2026-09-24

- **Location**: `lib/gpu_synth/gpu_synth.ml` and `lib/gpu_synth/gpu_synth.mli`.
- **Implementation**:
  - Removed silent fallback that returned cleartext bytecode (`List.map (fun _ -> bytecode) keys`), dummy constant `0x9E3779B97F4A7C15L`, and dummy SAC `50.0`.
  - Introduced explicit error type `type gpu_error = Gpu_unavailable | Gpu_execution_failed of string` with formatter `string_of_error : gpu_error -> string`.
  - All operations (`synthesize_mba_gpu`, `batch_encrypt_gpu`, `verify_sac_gpu`) return `(..., gpu_error) result`.
  - C stub exceptions (`caml_failwith` on Metal/GPU failure) and `Sys_error` are caught and converted to `Error (Gpu_execution_failed msg)`, while GPU absence returns `Error Gpu_unavailable`.
- **Tests**:
  - `test/test_gpu_synth.ml` updated: all tests match `Ok` and fail explicitly on `Error`.
  - Added error formatting test `test_gpu_error_formatting`.

### 4. SMC Degrading into No-Op Without Diagnostics — COMPLETED 2026-09-24

- **Location**: `lib/native_vm/runtime_smc.ml`, `lib/native_vm/runtime_dual_map.ml`, `lib/native_vm/vm_runtime_emitter.ml`, `lib/native_vm/protection_types.ml(i)`, `lib/native_vm/protection_presets.ml`, `lib/native_vm/protection_json.ml`.
- **Implementation**:
  - Eliminated silent degradation:
    - Introduced `enum SmcStatus : uint32_t { SMC_STATUS_NOT_EXECUTED = 0, SMC_STATUS_ACTIVE = 1, SMC_STATUS_DEGRADED = 2, SMC_STATUS_FAILED = 3 };`
    - Added diagnostic queries `get_smc_status()`, `get_smc_status_string()`, `is_smc_active()`, `is_smc_degraded()`.
    - Added platform support check `DualMappedBuffer::is_supported()`.
  - Implemented strict SMC mode (`ASGARD_SMC_STRICT`):
    - Compile-time: if the target platform lacks dual-mapping support (`!defined(__APPLE__) && (!defined(__linux__) || !defined(MFD_CLOEXEC))`) while strict SMC is active, compilation fails: `#error "ASGARD Security Violation: Strict SMC requested (max_security profile), but target platform does not support dual-mapping W^X memory aliasing!"`.
    - Runtime: if dual-mapping allocation fails in strict mode, status transitions to `SMC_STATUS_FAILED`, diagnostics are logged, and error token `0xDEAD53C0CAFE0001ULL` corrupts the VM register context (`ctx.reg_mask`), halting execution fail-closed.
    - In non-strict mode, status transitions to `SMC_STATUS_DEGRADED` with diagnostic logging instead of silent no-op.
  - Added `smc_strict : bool` flag to `anti_tamper_config` (enabled by default in `max_security`, serialized in JSON, emits `#define ASGARD_SMC_STRICT 1` in generated VM headers).
- **Tests**:
  - `test_smc_diagnostics_and_modes` in `test_anti_tamper_smc.ml`: verifies initial `NOT_EXECUTED`, transition to `SMC_STATUS_ACTIVE` / `"FULL_SMC"`, and `is_smc_active()`.
  - `test_smc_strict_mode_and_max_security` in `test_anti_tamper_smc.ml`: checks `smc_strict` flag in `max_security`, header generation, Clang++ compilation, and runtime execution with `ASGARD_SMC_STRICT`.
  - JSON roundtrip in `test_protection_config.ml`: verifies preservation and parsing of `anti_tamper.smc_strict`.

---

## P2 — Lifter Coverage

### 5. x86-64 Lifter: Missing `div`/`idiv`/`mul`, Zero SIMD — COMPLETED 2026-09-24

- Implemented in `lib/x86_lifter/lifter.ml`:
  - `div`/`idiv` across B8/B16/B32/B64 (register/memory): quotient and remainder write to architectural sub-registers with exact B8 `AH:AL` splitting and zero-divisor fault handling.
  - Sign extensions `cdq`/`cltd`/`cqo`/`cqto`/`cwd` and `cdqe`/`cltq`.
  - 1-operand `mul`/`imul` supporting B8/B16/B32/B64, including 64-bit high halves.
  - SSE/AVX mov and packed operations partitioned into integer lanes and IEEE F32/F64 lanes.
- Division-by-zero and signed-overflow trigger VM faults; native runtime sets `ctx.trapped` and halts with error.
- Tests: B8/B16/B32/B64 arithmetic/division, zero-divisor faults, IEEE SSE/AVX, B8/B16 merge, and native C++ E2E.

### 6. Partial Writes to 32-Bit Sub-Registers Unmodeled — COMPLETED 2026-09-24

- Implemented: unified `lib/vm_ir/subreg_write.ml` normalizes B8/B16 merge and B32 zero-extension for x86 GPR and ARM `w14`–`w28`/`w30` aliases.
- B8/B16 writes preserve upper bits of backing register; B32 writes append `shl 32 / shr 32` without modifying condition flags.
- Hooked into x86/ARM lifters prior to terminator patching; native VM and evaluator share identical normalized semantics.
- Tests cover evaluator, native B32/idiv, native B8/B16 merge, and ARM `w18`.

### 9. Emitter Silently Dropping `src1 ≠ dst` on RR-ALU — COMPLETED 2026-09-24

- **Prior Issue**: `lib/native_vm/vm_emitter.ml` and `lib/rd_jit_vm/rd_jit_emitter.ml` — branches matching `Alu { op; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s }` encoded only `(d, s)` and ignored `src1`. Native handlers evaluate `dst = dst OP src`, requiring `src1 = dst`.
- **Implementation**:
  - Implemented normalization pass `canonicalize_3addr_alu` in `lib/native_vm/vm_transform.ml`:
    - When `src1 = dst`: no change (standard 2-address canonical form).
    - When `src1 ≠ dst`:
      - For `src2 = Imm imm`: `Mov dst, src1` + `Alu dst, dst, imm`.
      - For `src2 = Reg s2` where `s2 ≠ dst`: `Mov dst, src1` + `Alu dst, dst, s2` (preserving `s2`).
      - For `src2 = Reg s2` where `s2 == dst` (hazard clobber case):
        - Commutative ops (`Add`, `Imul`, `Mul`, `Xor`, `And`, `Or`): operand swap `Alu dst, dst, src1` — zero additional instructions, preserves flags.
        - Non-commutative ops (`Sub`, `Div`, `Idiv`, shifts): preserves old `dst` in scratch register (`vtmp0`/`vtmp1`/`vtmp2`), loads `dst := src1`, evaluates `Alu dst, dst, scratch`.
      - For `Unary`: `Mov dst, src` + `Unary dst, dst`.
  - Integrated into `vm_emitter.ml` (prior to `fuse_block_instructions` and after MBA; enabling `Mov + Alu` sequences to fuse into super-operators `Fused_Mov_Add`) and `rd_jit_emitter.ml`.
  - Added strict assertion `assert_src1_eq_dst`: unnormalized 3-address operations trigger an immediate compile-time exception instead of silent bytecode corruption.
  - Supported opcode `Ir.Mul` (alongside `Ir.Imul`) in `vm_emitter.ml`, `rd_jit_emitter.ml`, and `arm64_common.ml`.
  - Fixed bug in `arm64_alu.ml` for `bic/bics/orn/eon`: `src2` operand is explicitly copied to `vtmp1` prior to bitwise `Not` inversion.
- **Tests**:
  - Unit `canonicalize_3addr_alu_unit` in `test_native_semantics.ml`: verifies all lowering branches (distinct registers, commutative hazard swap, non-commutative scratch preservation, immediate).
  - Native `native_3addr_alu` in `test_native_semantics.ml`: direct native execution of 3-address IR (add, sub-hazard, imul, idiv) in `execute_threaded`.
  - Lifter unit `ARM64 Lift 3-Address ALU (madd/msub/sdiv/bic)` in `test_arm64_lifter.ml`: reference VM evaluation.
  - Native E2E `native_arm64_3addr_madd_msub_sdiv_bic` in `test_native_semantics.ml`: end-to-end pipeline from ARM64 assembly (madd, msub, sdiv, bic) to native execution in threaded VM (result 310).

---

## P3 — Advanced Security Features

### 7. Anti-VMPredator Address-Bound Bytecode — COMPLETED 2026-09-24

- **Context**: Standard rolling keys are vulnerable to linear dumping if keystreams lack binding to live process memory.
- **Design & Implementation**:
  - Decryption keys and runtime keystreams are cryptographically bound to concrete in-memory VM handler addresses:
    - Added `address_bound : bool` in `anti_pushan_config` (`lib/native_vm/protection_types.ml(i)`, `protection_config.mli`, `protection_presets.ml`, `protection_json.ml`).
    - `lib/native_vm/vm_context_emitter.ml`: `compute_handlers_hash(all_dispatch_domains, num_domains)` calculates cryptographic hash of live handler pointers across all dispatch domains.
    - `anchor_key(seed, off, addr_hash)` and `reanchor_running_key(off, addr_hash)` fold handler address hash into block key seeds, ensuring nonlinear diffusion into every block word.
    - `lib/native_vm/vm_control_handlers.ml`: all branch terminators (`H_JMP`, `H_JCC`, `H_CALL`) re-anchor chains passing `g_handlers_hash`.
    - `lib/native_vm/vm_runtime_emitter.ml`: emits metadata `g_block_offsets` and `g_block_lengths`, synthesizes `bound_bc[idx] = bytecode[idx] ^ k_pos ^ rk(g_handlers_hash)` at runtime in ephemeral memory, reads from `bound_bc`, and scrubs it via `SCRUB_WORD` on VM exit.
    - `lib/native_vm/vm_emitter.ml`: under `address_bound`, `.rodata` bytecode masks only `k_pos`, deferring dynamic key binding to runtime initialization; computes `block_spans`.
    - Enforced `#if defined(ASGARD_VECTOR_ISA)` guard on unsafe SIMD NEON/SSE handlers in `vm_mem_handlers.ml` and `vm_runtime_emitter.ml`.
- **Tests**:
  - `anti_vmpredator_address_bound_execution` in `test_anti_pushan.ml`: E2E compilation and execution of control-flow loops under `address_bound = true`, verifying `bound_bc` buffer and output correctness (factorial 5 = 120).
  - `anti_vmpredator_tamper_detection` in `test_anti_pushan.ml`: verifies tamper detection — executing without live address binding (`g_handlers_hash`) desynchronizes `running_key` at branches and immediately halts.
  - JSON roundtrip in `test_protection_config.ml`: verifies `anti_pushan.address_bound`.

---

## P4 — Documentation

### 8. Counter Desynchronization — COMPLETED 2026-09-23

- Synchronized badges and all references across `README.md` and `CPP_TODO.md`.
- Canonical suite registry maintained in `test/run_tests.ml`.
- Partitioned merged documentation into distinct sections for "Native Threaded VM" and "Devirtualization Metrics".

---

## P5 — Advancing RV64GCV / AArch64 / x86-64 Lifters and VM-IR to Production Coverage

> **Context**: Initial lifters covered baseline `-O2` integer code and scalar vector operations. Production binary virtualization required closing semantic gaps across memory ordering, condition flags, dynamic RVV vectors, and bit-manipulation extensions.
>
> **Priority Execution Order**:
> 1. **VM flags + memory semantics** (EFLAGS/NZCV models, addressing, atomics/barriers).
> 2. **RVV (RISC-V Vector)** (parameterized VL/VTYPE/VLMUL/SEW model).
> 3. **x86 bit/BMI + SSE/AVX FP** (scalar FP, AVX-256 zeroing, AVX-512 boundaries).
> 4. **AArch64 FP/NEON + bit manipulation + atomics**.
> 5. **System instructions, CSR, and environment boundaries (System / CSR / Fence)**.

---

### Implementation Checklist by Complexity Tier

#### Level 1: Quick Wins — COMPLETED 2026-10-07
- [x] **1.1. Scalar Floating-Point in ARM64 and RISC-V Lifters**:
  - [x] ARM64: mapped `fadd`, `fsub`, `fmul`, `fdiv`, `fcmp`, `fmov`, `fcsel`, `fcvtzs`, `scvtf` in `arm64_lifter`.
  - [x] RISC-V: mapped `fadd.s/d`, `fsub.s/d`, `fmul.s/d`, `fdiv.s/d`, `fmin.s/d`, `fmax.s/d`, `feq.s/d`, `flt.s/d`, `fle.s/d`, `flw/fld`, `fsw/fsd`, `fmv.*` in `riscv_lifter`.
- [x] **1.2. Host Bit-Manipulation Primitives**:
  - [x] x86 & ARM64: `clz`, `ctz` / `bsf`, `bsr`, `popcnt`, `lzcnt`, `tzcnt` (via host intrinsics `__builtin_clzll`, `__builtin_popcountll`).
  - [x] Byte/bit reversal: `bswap` (x86), `rev`, `rev16`, `rev32`, `rbit` (ARM64), `rev8` (RISC-V).
  - [x] Bit tests: `bt`, `bts`, `btr`, `btc` (lowered via And/Or/Xor + bitmask shift).
- [x] **1.3. x86 Flag Controllers**:
  - [x] `clc`, `stc`, `cmc` (CF = 0 / 1 / ~CF).
  - [x] `cld`, `std` (DF = 0 / 1).
- [x] **1.4. System Boundaries and Explicit Traps**:
  - [x] x86: `syscall`, `sysret`, `cpuid`, `rdtsc`, `rdtscp`, `xgetbv` -> mapped to `Ir.Trap` / `Ir.Call_Extern`.
  - [x] ARM64: `eret` -> `Ir.Trap`.
  - [x] RISC-V: `ecall`, `ebreak` -> `Ir.Trap`; baseline CSR `csrrw/csrrs/csrrc` (timers `cycle`, `time`).

#### Level 2: Medium Complexity — COMPLETED 2026-10-07
- [x] **2.1. Bitfields and Masks**:
  - [x] ARM64: `ubfx`, `sbfx`, `bfi`, `bfxil`, `extr` (lowered to Shl/Shr/Sar/And/Or sequences).
  - [x] x86 (BMI1/BMI2): `andn`, `bextr`, `bzhi`, `rorx`, `sarx`, `shlx`, `shrx`, `pext`, `pdep`.
- [x] **2.2. Two-Operand Shifts in x86**:
  - [x] `shld`, `shrd` (destination register shift funneling source bits).
  - [x] `rcl`, `rcr` (rotate through carry flag CF).
- [x] **2.3. Extended Multiply-Accumulate**:
  - [x] ARM64: `smaddl`, `umaddl`, `smsubl`, `umsubl` (32x32 -> 64 + acc), `smulh`, `umulh` (upper 64-bit half).
- [x] **2.4. Type Conversions (FP <-> Integer) and Scalar Square Root**:
  - [x] x86: `cvtsi2ss/sd`, `cvtss2si/sd`, `cvtsd2ss`, `cvtss2sd`, `sqrtss`, `sqrtsd`.
  - [x] ARM64: `scvtf/ucvtf`, `fcvtzs/fcvtzu`, `fcvt`, `fsqrt`.
  - [x] RISC-V: `fcvt.w.s/d`, `fcvt.l.s/d`, `fcvt.s.w/l`, `fcvt.d.w/l`, `fsqrt.s/d`.
- [x] **2.5. Complex Memory Addressing**:
  - [x] ARM64: `ldp`/`stp` across all addressing forms (pre-index `[sp, #-16]!`, post-index `[sp], #16`, signed offset `[x29, #32]`).
  - [x] x86: `movbe` (load/store + bswap), table substitution `xlat`.

#### Level 3: High Complexity — COMPLETED (2026-10)
- [x] **3.1. Full Canonical EFLAGS Model**:
  - [x] All operand sizes for `adc` and `sbb` with exact calculation of condition flags (`CF`, `OF`, `AF`, `PF`, `ZF`, `SF`).
  - [x] Flag stack instructions: `pushf`/`popf`, flag store/load `lahf`/`sahf` (via universal `Ir.Get_flags` and `Ir.Set_flags`).
  - [x] Unified EFLAGS dispatcher for `setcc`, `cmovcc`, `jcc`.
- [x] **3.2. ARM64 Conditional Comparisons**:
  - [x] `ccmp`, `ccmn` (conditional NZCV flag updates without CFG branching, supported in Native C++ VM and Evaluator).
  - [x] Conditional selectors: `csinc`, `csinv`, `csneg`, `cinc`, `cinv`, `cneg`.
  - [x] Arithmetic with carry/borrow: `adc`, `adcs`, `sbc`, `sbcs`, `ngc`, `ngcs`.
- [x] **3.3. x86 String Operations with Repeat Prefixes**:
  - [x] `stosb/w/d/q`, `lodsb/w/d/q`, `scas*`, `cmps*`.
  - [x] Prefixes `rep`, `repe`/`repz`, `repne`/`repnz` generating internal basic block loop structures.
- [x] **3.4. SMP Atomics and Memory Ordering Barriers**:
  - [x] Explicit memory barrier model: `fence` (RISC-V), `dmb` (ARM64), `mfence` (x86).
  - [x] x86: `lock` prefix, `xadd`, `cmpxchg`, `cmpxchg8b/16b`, memory `xchg`.
  - [x] ARM64: `ldxr`/`stxr`, `ldar`/`stlr`, LSE atomics `swp`, `ldadd`, `ldclr`, `ldset`, `ldeor`.
  - [x] RISC-V: `lr`/`sc`, `amoswap`, `amoadd`, `amomin`/`max`, `amoxor`/`and`/`or`.
- [x] **3.5. AVX-256 YMM Registers**:
  - [x] Expanded vector bank from 128 to 256 bits for `ymm0..ymm15` (B128, B256, B512 in `Register.width`, 512-bit banks in C++ `VMContext` and `Vm_eval`).
  - [x] Hardware zeroing of upper YMM half on XMM write via VEX-128 (`Vec_clear_upper`), plus `vzeroupper`/`vzeroall` support (`Vec_zero_upper`).
  - [x] Vector integer ops: `vpsll*`, `vpsrl*`, `vpsra*`, `vpcmpeq*`, `vpcmpgt*`, `vpmov*` (`pmovmskb`/`vpmovmskb`), `vpunpck*`, `vpack*`, `vpshuf*`, `vblend*`, `vpmin*`, `vpmax*`, `vpabs*`.
  - [x] Explicit trap boundary for EVEX / ZMM (`Trap "AVX-512 EVEX is unsupported"`).

#### Level 4: Architectural Sub-Project — COMPLETED (2026-10)
- [x] **4.1. Parameterized RISC-V Vector Engine (RVV 1.0)**:
  - [x] Architectural state in `VMContext`: `VL`, `VTYPE`, `VLEN` ($\ge 128$), `SEW` (8, 16, 32, 64), `LMUL` (1/8 .. 8), `vstart`, `vmask` (`v0`).
  - [x] Dynamic vector configuration: `vsetvli`, `vsetivli`, `vsetvl`.
  - [x] Vector memory: unit-stride (`vle*.v`/`vse*.v`), strided (`vlse`/`vsse`), indexed (`vluxei`/`vsuxei`).
  - [x] Vector arithmetic/logic/shifts: `vadd`, `vsub`, `vrsub`, `vmul`, `vdiv`, `vrem`, `vand`, `vor`, `vxor`, `vsll`, `vsrl`, `vsra`, `vmin`, `vmax`.
  - [x] Vector comparisons and mask operations: `vmseq`, `vmsne`, `vmslt`, `vmsle`, `vmerge`, `vmv`, mask logic (`vmand`/`vmor`/`vmxor`).
  - [x] Reductions and permutations: `vredsum`, `vredmax`, `vredmin`, `vslideup`, `vslidedown`, `vrgather`, `vcompress`.

---

### 1. VM Architectural State (VMContext Core State Model)

To execute arbitrary binary code, `VMContext` represents:
* **GPR**: 64-bit general-purpose registers of host and guest architectures.
* **PC & SP**: Program counter and stack pointer with platform alignment (16 bytes for ARM64/x86-64 ABI).
* **Architectural Condition State**:
  * *x86-64*: Canonical six flags `CF`, `OF`, `SF`, `ZF`, `AF`, `PF`.
  * *AArch64*: Condition flags `NZCV` (Negative, Zero, Carry, Overflow).
  * *RISC-V*: Direct register comparison in branches, plus FP status flags (`NV`, `DZ`, `OF`, `UF`, `NX`).
  * *Invariant*: Rejection of forced reduction of ARM64/RISC-V flags to x86 EFLAGS — native state modeling is preserved.
* **Memory and Memory Ordering**:
  * Memory barriers: `SeqCst`, `Acquire`, `Release`, `AcqRel`, `Relaxed`.
  * Explicit ordering primitives (`FENCE` / `DMB` / `MFENCE`) across all three ISAs.
* **FP / Vector Registers & Control/Status**:
  * 128/256-bit vector banks and scalar FP accumulators.
  * FP control registers: `MXCSR` (x86), `FPCR`/`FPSR` (ARM64), `fcsr` (RISC-V).

---

### 2. Orthogonal VM-IR Extension

Rather than proliferating ad-hoc opcodes, the core `lib/vm_ir/ir.ml` is structured around orthogonal primitives:

| IR Group | Primitives | Semantics |
| :--- | :--- | :--- |
| **FLAGS** | `Flags_get`, `Flags_set`, `Flags_merge`, `Flags_materialize`, `Lazy_flags` | Flag extraction/store, partial update merging, GPR materialization, SSA flag tracking. |
| **MEMORY** | `Load`, `Store`, `Load_signed`, `Load_zero_ext`, `Atomic_rmw`, `Fence` | Typed memory accesses B8–B64, atomic RMW (Add, Sub, And, Or, Xor, Min, Max), memory barriers. |
| **ADDRESS** | `Lea`, `Address`, `Pc_rel` | Effective address calculation (Base + Index*Scale + Disp), segment bases, PC-relative addressing. |
| **CONTROL** | `Indirect_jmp`, `Indirect_call`, `Return`, `Switch`, `Tailcall`, `Trap`, `Syscall` | Indirect dispatch, jump tables (switch), system call boundaries, exception isolation. |
| **EXT / BIT** | `Sign_ext`, `Zero_ext`, `Trunc`, `Bitcast`, `Clz`, `Ctz`, `Bswap`, `Bit_test`, `Bit_set`, `Bit_clear`, `Bit_toggle` | Bit-width conversions without shift hacks, bit tests, zero counting, byte/bit reversal. |
| **SHIFT** | `Shld`, `Shrd`, `Rotate`, `Rcl`, `Rcr` | Funnel shifts, rotations, rotate-through-carry. |
| **FP** | `Fadd`, `Fsub`, `Fmul`, `Fdiv`, `Fsqrt`, `Fcmp`, `Fconv` | Scalar single (F32) and double (F64) arithmetic, square root, comparisons, `int <-> fp` conversions. |
| **VECTOR** | `Vec_splat`, `Vec_extract`, `Vec_insert`, `Vec_shift`, `Vec_compare`, `Vec_shuffle`, `Vadd`, `Vsub`, `Vmul`, `Vperm`, `Vreduce` | Parameterized vector primitives: broadcasting, lane insertion/extraction, shifts, shuffles, reductions. |
| **SYSTEM** | `Fence`, `Csr_read`, `Csr_write` | Instruction/memory synchronization, user/system CSR register access. |

---

### 3. x86_64 Coverage Specification

1. **Memory, Segmentation, and String Operations**:
   - Byte swapping: `movbe`, `bswap` — **COMPLETED (2026-10)**.
   - Table translation: `xlat` / `xlatb` — **COMPLETED (2026-10)**.
   - String instructions: `stosb/stosw/stosd/stosq`, `lodsb/lodsw/lodsd/lodsq`, `scasb/scasw/scasd/scasq`, `cmpsb/cmpsw/cmpsd/cmpsq` — **COMPLETED (2026-10)**.
   - String repeat prefixes: `rep`, `repe`/`repz`, `repne`/`repnz` with automatic `RCX` decrement and `ZF` check — **COMPLETED (2026-10)**.
   - Segment addressing: `FS:` and `GS:` override prefixes (TLS) — **COMPLETED (2026-10)**.
   - Absolute offset addressing: `moffs` forms of `mov` (`mov al/ax/eax/rax, [moffs]`) — **COMPLETED (2026-10)**.
   - Segment register push/pop in low-level context virtualization (`push/pop ds/es/fs/gs/ss`, `mov`, `rdfsbase/wrfsbase/rdgsbase/wrgsbase`) — **COMPLETED (2026-10)**.
2. **Integer Arithmetic and EFLAGS**:
   - `adc` and `sbb`: all operand sizes (B8, B16, B32, B64) with exact calculation of all six flags (`CF`, `ZF`, `SF`, `OF`, `AF`, `PF`) — **COMPLETED (2026-10)**.
   - `imul`: complete support for all three forms (1-operand implicit RDX:RAX, 2-operand `reg, r/m`, 3-operand `reg, r/m, imm`) — **COMPLETED (2026-10)**.
   - Bit tests: `bt`, `bts`, `btr`, `btc` (setting `CF` flag) — **COMPLETED (2026-10)**.
   - Bit scanning and counting: `bsf`, `bsr`, `tzcnt`, `lzcnt`, `popcnt` — **COMPLETED (2026-10)**.
   - BMI1 / BMI2: `bextr`, `bzhi`, `andn`, `rorx`, `sarx`, `shlx`, `shrx`, `pdep`, `pext` — **COMPLETED (2026-10)**.
   - Shifts: `shld`, `shrd` (funnel shifts) — **COMPLETED (2026-10)**, `rcl`, `rcr` (rotate-through-carry) — **COMPLETED (2026-10)**.
3. **Flag Management**:
   - Instructions: `lahf`, `sahf`, `pushf`/`pushfq`, `popf`/`popfq`, `clc`, `stc`, `cmc`, `cld`, `std` — **COMPLETED (2026-10)**.
   - Unified canonical EFLAGS model for `setcc`, `cmovcc`, `jcc` predicates — **COMPLETED (2026-10)**.
4. **SSE / AVX / AVX2**:
   - Support boundaries:
     * `SSE (128-bit)` -> **Supported**
     * `AVX-128 (VEX 128-bit)` -> **Supported**
     * `AVX2 (VEX 256-bit YMM ymm0..ymm15/31)` -> **Supported** with mandatory zeroing of upper 128-bit YMM half upon XMM write.
     * `AVX-512 (EVEX 512-bit ZMM + Opmask k0..k7)` -> **Explicit Unsupported / Trap Boundary**.
   - Vector integer ops: `vpsll*`, `vpsrl*`, `vpsra*`, `vpcmpeq*`, `vpcmpgt*`, `vpmov*`, `vpunpck*`, `vpack*`, `vpshuf*`, `vperm*`, `vblend*`, `vmin*`, `vmax*`, `vpabs*`, `vpmuludq`, `vpmadd*`, `vpsadbw`, `vzeroupper` — **COMPLETED (2026-10)**.
   - Scalar FP: `addss/addsd`, `subss/subsd`, `mulss/mulsd`, `divss/divsd`, `comiss/ucomiss`, `comisd/ucomisd`, `sqrtss/sqrtsd`, conversions `cvtsi2ss/cvtsi2sd`, `cvtss2si/cvtsd2si`, `cvtsd2ss`, `cvtss2sd` — **COMPLETED (2026-10)**.
5. **SMP Atomics**:
   - `lock` bus-locking prefix — **COMPLETED (2026-10)**.
   - Instructions: `xadd`, `cmpxchg`, `cmpxchg8b`, `cmpxchg16b` — **COMPLETED (2026-10)**.
   - Memory operand `xchg` (implicit atomicity without lock prefix) — **COMPLETED (2026-10)**.

---

### 4. ARM64 (AArch64) Coverage Specification

1. **Memory and Exclusive Access**:
   - Loads/stores: `ldrb/ldrh/ldrsb/ldrsh`, unprivileged `ldtr/sttr` (`ldtr`, `ldtrb`, `ldtrh`, `ldtrsw`, `sttr`, `sttrb`, `sttrh`) — **COMPLETED (2026-10)**.
   - Non-temporal pair accesses: `ldnp/stnp` — **COMPLETED (2026-10)**.
   - Vector NEON load/store: `ld1/st1` (single- and multi-structure).
   - One-way barriers (Acquire/Release): `ldar/ldarb/ldarh`, `stlr/stlrb/stlrh` — **COMPLETED (2026-10)**.
   - Exclusive accesses: `ldxrb/ldxrh/ldxr`, `stxrb/stxrh/stxr`, `ldaxrb/ldaxrh/ldaxr`, `stlxrb/stlxrh/stlxr` — **COMPLETED (2026-10)**.
   - Atomic RMW (LSE): `swp`, `ldadd`, `ldclr`, `ldset`, `ldeor` (including `a`/`l`/`al`/`b`/`h` variants), store variants `stadd`, `stclr`, `stset`, `steor` — **COMPLETED (2026-10)**.
2. **Conditional Instructions**:
   - `ccmp`, `ccmn` (Conditional Compare with default NZCV flags) — **COMPLETED (2026-10)**.
   - `cinc`, `cinv`, `cneg`, `csinc`, `csinv`, `csneg` (Conditional Select with increment/invert/negate) — **COMPLETED (2026-10)**.
3. **Bit Manipulation**:
   - `clz`, `cls` (count leading zeros / sign bits) — **COMPLETED (2026-10)**.
   - `rbit` (bit reversal) — **COMPLETED (2026-10)**.
   - Byte reversal: `rev`, `rev16`, `rev32` — **COMPLETED (2026-10)**.
   - Bitfields: `ubfx`, `sbfx`, `bfi`, `bfxil`, `ubfm`, `sbfm` — **COMPLETED (2026-10)**.
   - Double-register bit extraction: `extr` — **COMPLETED (2026-10)**.
4. **Integer Arithmetic**:
   - Multiplications: `smaddl`, `smsubl`, `umaddl`, `umsubl`, `smulh`, `umulh`, `smull`, `umull` — **COMPLETED (2026-10)**.
   - Sign/zero extension: `sxtb/sxth/sxtw`, `uxtb/uxth/uxtw` — **COMPLETED (2026-10)**.
   - Carry arithmetic: `adc`, `adcs`, `sbc`, `sbcs`, `ngc`, `ngcs` — **COMPLETED (2026-10)**.
5. **NEON and Floating Point**:
   - Scalar FP: `fadd/fsub/fmul/fdiv`, `scvtf/ucvtf`, `fcvtzs/fcvtzu`, `fmadd`, `fmsub`, `fnmadd`, `fnmsub`, `fneg`, `fabs`, `fcsel`, `fmin`, `fmax`, `fcmp`, `fcvt` — **COMPLETED (2026-10)**.
   - NEON vector memory: `ldr/str` SIMD, `ld1/st1` — **COMPLETED (2026-10)**.
   - NEON arithmetic/logic/shifts: vector `add/sub/mul`, `and/orr/eor/bic`, `shl/sshr/ushr`, `smin/smax/umin/umax`, `abs`, `dup`, `mov` — **COMPLETED (2026-10)**.
   - Table lookups and shuffles: `tbl`, `tbx`, `ext`, `zip1/zip2`, `uzp1/uzp2`, `trn1/trn2` — **COMPLETED (2026-10)**.

---

### 5. RISC-V (RV64GCV) Coverage Specification

1. **Standard Integer M, Zba, and Zbb Extensions**:
   - Multiplication and division: `mul/mulw`, `div/divw`, `divu/divuw`, `rem/remw`, `remu/remuw`, `mulh`, `mulhu`, `mulhsu` — **COMPLETED (2026-10)**.
   - Bit manipulation (Zbb): `clz/clzw`, `ctz/ctzw`, `cpop/cpopw`, `rev8`, `orc.b`, `sext.b/h`, `zext.h`, `min/max`, `minu/maxu`, `andn`, `orn`, `xnor`, `rol/rolw`, `ror/rori/rorw/roriw` — **COMPLETED (2026-10)**.
   - Address calculation (Zba): `sh1add/sh1adduw`, `sh2add/sh2adduw`, `sh3add/sh3adduw` — **COMPLETED (2026-10)**.
2. **Scalar Floating-Point (RV64FD F and D Extensions)**:
   - Memory: `flw`, `fld`, `fsw`, `fsd` — **COMPLETED (2026-10)**.
   - Arithmetic: `fadd.s/d`, `fsub.s/d`, `fmul.s/d`, `fdiv.s/d`, `fmin.s/d`, `fmax.s/d`, `fsqrt.s/d` — **COMPLETED (2026-10)**.
   - Comparisons: `feq.s/d`, `flt.s/d`, `fle.s/d` — **COMPLETED (2026-10)**.
   - Sign injection: `fsgnj.s/d`, `fsgnjn.s/d`, `fsgnjx.s/d`, `fneg.s/d`, `fabs.s/d` — **COMPLETED (2026-10)**.
   - Fused Multiply-Add: `fmadd.s/d`, `fmsub.s/d`, `fnmsub.s/d`, `fnmadd.s/d` — **COMPLETED (2026-10)**.
   - Conversions: `fcvt.*` (`fcvt.w.*`, `fcvt.l.*`, `fcvt.*.w`, `fcvt.*.l`) — **COMPLETED (2026-10)**.
3. **Vector Extension V (RVV Dynamic Vector Engine) — COMPLETED (2026-10)**:
   - Dynamic parameterization: `VL/VTYPE/VLMUL/SEW`, `vlen` $\ge 128$.
   - Configuration: `vsetvli`, `vsetivli`, `vsetvl`.
   - Memory:
     * Unit-stride: `vle8/16/32/64.v`, `vse8/16/32/64.v`.
     * Strided: `vlse*.v`, `vsse*.v`.
     * Indexed: `vluxei*`, `vloxei*`, `vsuxei*`, `vsoxei*`.
   - Arithmetic and logic:
     * `vadd`, `vsub`, `vrsub`, `vmul`, `vdiv`, `vrem`.
     * `vand`, `vor`, `vxor`, `vnot`.
     * `vsll`, `vsrl`, `vsra`.
     * `vmin`, `vmax`.
   - Comparisons and masks:
     * `vmseq`, `vmsne`, `vmslt`, `vmsle` (signed/unsigned).
     * `vmerge`, `vmv`.
     * Mask logic: `vmand`, `vmor`, `vmxor`.
   - Reductions and permutations:
     * `vredsum`, `vredmax`, `vredmin`.
     * `vslideup`, `vslidedown`.
     * `vrgather`, `vcompress`.
4. **System Instructions, Barriers, Atomics, and CSRs**:
   - `ecall`, `ebreak` — **COMPLETED (2026-10)**.
   - Memory ordering: `fence`, `fence.i`, `fence.tso` — **COMPLETED (2026-10)**.
   - Standard A-extension atomics (`lr.w/d`, `sc.w/d`, `amoswap.w/d`, `amoadd.w/d`, `amomin.w/d`, `amomax.w/d`, `amominu.w/d`, `amomaxu.w/d`, `amoxor.w/d`, `amoand.w/d`, `amoor.w/d` with `.aq`, `.rl`, `.aqrl` ordering modifiers) — **COMPLETED (2026-10)**.
   - Control and Status Registers: `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` — **COMPLETED (2026-10)**.

---

## Universal Acceptance Criteria

1. Target test suites pass without regressions.
2. E2E: Clean C code enclosed in `ASGARD_BEGIN_VIRTUALIZE` / `ASGARD_END()` compiles, lifts, and executes with identical native semantics and exit code 0.
3. Zero warnings under strict flags (`-warn-error -a`).
4. Whenever opcode tables are updated, golden vectors in `test/test_anti_pushan.ml` must be verified.
