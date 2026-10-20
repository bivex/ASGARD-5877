# Roadmap: Migration of C++20/C11 Code Generation to Typed EDSL (ASGARD-5877)

## Overview

Elimination of string concatenation vulnerabilities (`Printf.sprintf`, `Buffer.add_string`, raw text blocks) in favor of a secure, typed C++20/C11 AST generator ([`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/)).

### Migration Goals

1. **Type Safety**: Eliminate syntax errors, formatting specifier mismatches (`%` vs `%%`), and C++ type mismatches at OCaml compile time.
2. **Guaranteed Absence of Undefined Behavior (UB)**: Strict enforcement of signedness, overflow semantics, and alignment during code generation.
3. **AST Mutations and Obfuscation**: Enable transformations directly on the C++ AST (statement shuffling, expression substitution, injection of `std::atomic_signal_fence` memory barriers).
4. **Cross-Platform C++20 / C11 Support**: Unified AST supporting code generation across LLVM/Clang, MSVC, and GCC dialects.

---

## Stage Status

| Stage | Description | Status | Commit |
|---|---|:---:|:---:|
| **Stage 1** | Core Typed EDSL (`Cpp_ast`, `Cpp_dsl`, `Cpp_printer`, `Cpp_ast_obf`) + 5 Tier 4 Next-Gen modules | Completed | `33c1a54` |
| **Stage 2** | E-graph equivalence, ALU and Decoy handlers (`egraph_cpp_emitter.ml`, `vm_alu_handlers.ml`, `vm_mem_handlers.ml`) | Completed | `62f984a` |
| **Stage 3** | Control Flow, super-operators, VMContext, and modular Vanguard headers | Completed | `3.1, 3.2, 3.3` |
| **Stage 4** | Stack-VM handlers, Multi-VM contexts, and pre-flight syntax validator | Completed | `4.1, 4.2` |
| **Stage 5** | RD-JIT VM, Vector ISA, Tech-2603/2608, Vanguard 9292 Decoder, Stack-VM Superops & Trampoline | Completed | `1c22026`, `e8aacea` |
| **Stage 6** | C11 ISA, GPU MBA, C Nanomites, Multi-VM Bridge, Whitebox & RNS-4 Garner CRT | Completed | `e548e9c` .. `1d493ad` |
| **Stage 6.3** | Computed Goto, Preprocessor AST, Trampoline Chunk, Stack-VM & Native VM Dispatch | Completed | `bf7f634` |
| **Stage 7.1** | Typed C++20 EDSL Stack-VM Header Migration & Decommissioning in Stack/Multi-VM | Completed | `7fc48ab` |
| **Stage 7.2** | Native Threaded VM EDSL Migration & 100% Jingoo Decommissioning from Repo | Completed | `HEAD` |

---

## Completed Stages

### Stage 1: Core Typed EDSL and Tier 4 Next-Gen (`33c1a54`)
- [x] Implemented core AST module [`lib/cpp_codegen/cpp_ast.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_ast.ml) (types, literals, binary/unary expressions, function calls, `If`, `While`, `Goto`, `Label`, `Raw`).
- [x] Implemented combinator DSL [`lib/cpp_codegen/cpp_dsl.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_dsl.ml) with VM register helpers (`reg_dst`, `reg_src`, `set_reg`, `fetch_next`, `probe_start`, `probe_check`).
- [x] Implemented pretty-printer [`lib/cpp_codegen/cpp_printer.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_printer.ml) with automated indentation and formatting.
- [x] Created randomized AST scrambler [`lib/cpp_codegen/cpp_ast_obf.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_ast_obf.ml).
- [x] Migrated 5 Tier 4 Next-Gen modules:
  - Branchless VIP (`branchless_vip.ml`)
  - 2D Variable Entanglement (`two_dim_entanglement.ml`)
  - Oblivious Memory (`oblivious_mem.ml`)
  - VM-to-VM Bridge (`vm_bridge.ml`)
  - Self-Wiping Nano-JIT (`nano_jit.ml`)
- [x] Verification: `test_tier4_nextgen.exe` — 100% PASS.

### Stage 2: E-graph, ALU & Decoy Handlers (`62f984a`)
- [x] Extended EDSL with signed and floating-point types (`Int8`..`Int64`, `Float`, `Double`), string literals (`LitStr`), and loop control statements (`Break`, `Continue`).
- [x] Migrated [`lib/native_vm/egraph_cpp_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/egraph_cpp_emitter.ml) to `Cpp_ast.expr` generation.
- [x] Migrated all 5 algebraic polynomial ALU expansions (`pick_poly_add_ast`, `pick_poly_sub_ast`, `pick_poly_xor_ast`, `pick_poly_and_ast`, `pick_poly_or_ast`) in [`lib/native_vm/vm_alu_handlers.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_alu_handlers.ml).
- [x] Migrated memory barrier handlers (`H_FENCE`), vector register copies (`H_MOV_VR`, `H_MOV_RV`), and 16 classes of decoy handlers (`H_DECOY_0`..`H_DECOY_15`, `H_DECOY`) in [`lib/native_vm/vm_mem_handlers.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_mem_handlers.ml).
- [x] Verification: `test_cpp_codegen.exe`, `E-graph Equality Expansion.*` (11/11), `Metamorphic ISA & Ring Codec` (6/6) — PASS.

### Stage 3.1: Control Flow & Super-Operators (`lib/native_vm/vm_control_handlers.ml`)
- [x] Extended EDSL core: added `ReinterpretCast of ctype * expr` in [`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/).
- [x] Migrated all control-flow instructions to typed `stmt list`:
  - `H_JMP` (direct jump, nanomite trap support via `__debugbreak()` / `raise(SIGTRAP)`).
  - `H_JCC` (conditional flag branch, branchless vIP calculation).
  - `H_CMOV` (conditional register copy).
  - `H_SETCC` (conditional byte set).
  - `H_CALL` / `H_RET` / `H_EXIT` (stack frame emulation, pointer calculation).
  - `H_IJMP_R` / `H_ICALL_R` (indirect jumps and native FFI dispatch).
  - `H_BRIDGE_TO_FLOW` / `H_BRIDGE_TO_MATH` (Multi-VM domain bridges).
- [x] Migrated super-operators (`emit_super_operators`):
  - `H_FUSED_MOV_ADD_RRI`
  - `H_FUSED_ADD_IMUL_RRI`
  - `H_FUSED_ADD_XOR_RRI`
  - `H_FUSED_SUB_XOR_RRI`
  - `H_FUSED_XOR_ADD_RRI`
  - `H_FUSED_CMP_CMOV`
- [x] Preserved strict dispatcher label formatting `    H_<NAME>:` for compatibility with `transform_domain_labels`.
- [x] Verification: Steps 6 and 7 in `test_cpp_codegen.ml` — 100% PASS.

### Stage 3.2: VMContext & Structural Declarations (`lib/native_vm/vm_context_emitter.ml`)
- [x] Extended EDSL core: added `StructDef`, `struct_member` (`MemberField`, `MemberMethod`, `MemberStaticConstexpr`, `MemberRaw`), `EnumDecl`, `RawTop`, `CommentTop`, and assignment operator `( *= )`.
- [x] Migrated `VMContext` to typed C++ declarations:
  - Register fields: affine offset randomization `(REG_AFFINE_A * idx + REG_AFFINE_B) & 31` via `reg_phys_idx`.
  - Guard canaries `canary_head`, `canary_tail`, and dynamic inter-frame canaries array `mid_canaries` with `verify_canaries()` validator.
  - Register accessors `get_reg`, `set_reg`, vector accessors `get_vreg_lane`, `set_vreg`, and named ABI registers.
  - Rolling cryptographic key methods: `advance_running_key`, `reanchor_running_key`, `apply_poly_merge_update`.
  - Dynamic masking: `evolve_mask`, `evolve_slot_mask`, virtual Speck-64 stack `scramble_stack_idx`, `push`, `pop`.
  - Standalone typed C++ functions: `eval_condition`, `compute_sub_flags`, `compute_add_flags`, `key64_for_offset`, `compute_handlers_hash`.
- [x] Verification: Step 8 in `test_cpp_codegen.ml` — 100% PASS (63,040 bytes of valid C++20 emitted).

### Stage 3.3: Modularizing Monolithic Templates (`native_vm_templates.ml`)
- [x] Extracted static runtime components from monolithic Jingoo literals (`threaded_header_template`) into modular `.hpp` headers under `runtime/include/vanguard/`:
  - [`platform_compat.hpp`](file:///Volumes/External/Code/ASGARD-5877/runtime/include/vanguard/platform_compat.hpp) (MSVC / Clang / GCC macros, intrinsics `__builtin_expect`, `clock_gettime`).
  - [`crypto_primitives.hpp`](file:///Volumes/External/Code/ASGARD-5877/runtime/include/vanguard/crypto_primitives.hpp) (FNV-1a, Mach-O Dyld Exports Trie Resolver, Dynamic Symbol Decryption).
  - [`sanitization.hpp`](file:///Volumes/External/Code/ASGARD-5877/runtime/include/vanguard/sanitization.hpp) (ephemeral memory scrubbing `SCRUB_WORD`, canary checks).
- [x] Dual-mode delivery strategy: `#if __has_include("vanguard/platform_compat.hpp")` for modular builds + inlining for autonomous single-header artifacts.
- [x] Replaced loose Jingoo flags with strictly typed `Runtime_policy` module in [`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml).
- [x] Verification: Step 9 in `test_cpp_codegen.ml` — 100% PASS (298,323 bytes emitted).

### Stage 4.1: Stack-VM Handlers Migration (`lib/stack_vm/stack_handlers_emitter.ml`)
- [x] Created typed Stack-VM handler generator [`lib/stack_vm/stack_handlers_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_handlers_emitter.ml).
- [x] Migrated typed AST handlers:
  - `h_push_imm`, `h_push_imm32`
  - `h_push_reg`, `h_pop_reg`
  - `h_dup`, `h_dup2`, `h_rot`, `h_swap`
- [x] Integrated VSP whitening macros (`VSP_ENCODE(slot, val)`).
- [x] Replaced hardcoded strings in [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml) and connected to [`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml).
- [x] Verification: Step 10 in `test_cpp_codegen.ml` (5,034 bytes) + all 38 `Stack-VM Execution Engine` tests — 100% PASS.

### Stage 4.2: Multi-VM Structures, Bridges, and Validation (`lib/multi_vm/multi_vm_context_emitter.ml`, `lib/cpp_codegen/cpp_validator.ml`)
- [x] Extended EDSL core: added `UnionDecl` and `UnionDef` across `Cpp_ast`, `Cpp_dsl`, `Cpp_printer`, `Cpp_ast_obf`.
- [x] Implemented typed Multi-VM context generator [`lib/multi_vm/multi_vm_context_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/multi_vm_context_emitter.ml):
  - `MathVMContext` (GPRs, VIP, RNS slots, trace digest, `init` method).
  - `FlowVMContext` (virtual stack vstack, vsp, vip, state_var, trace digest, `init` method).
  - `SharedVMContext` (`union` of `MathVMContext`, `FlowVMContext`, `raw[1024]`).
  - Cross-domain affine bridges `bridge_switch_to_flow`, `bridge_switch_to_math`.
- [x] Replaced raw `asgard_multi_vm` text block in [`lib/multi_vm/multi_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/multi_vm_templates.ml) with typed generation.
- [x] Implemented pre-flight structural and compiler validator [`lib/cpp_codegen/cpp_validator.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_validator.ml):
  - Character-by-character line and column lexical tracking.
  - Delimiter balancing checks for `()`, `[]`, `{}` with opening position stack.
  - Skip logic for string/character literals, raw strings, escape sequences, single-line and multi-line comments.
  - Verification of absence of unresolved template tags (`{{`, `}}`, `{%`, `%}`).
  - Clang pre-flight integration via `clang++ -fsyntax-only` prior to disk emission.
- [x] Verification: Steps 11 and 12 in `test_cpp_codegen.ml` + 8/8 `Multi-VM & Direct Zero-Bridge` tests — 100% PASS.

### Stage 5.1: Vanguard 9292, Stack-VM Superops, RD-JIT & Chunks (`1c22026`)
- [x] Extended EDSL core: added `MemberConstructor` construct (`Cpp_ast`, `Cpp_dsl`, `Cpp_printer`, `Cpp_ast_obf`) for explicit, inline, noexcept C++ constructors with field initializer lists (`init_list`).
- [x] Migrated Vanguard-9292 Decoder ([`lib/vanguard_9292/vanguard_decoder.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_decoder.ml)):
  - Struct `RollingKey` converted to `Cpp_ast.StructDef` with typed constructor and `next()`, `next64()` methods.
  - Class `VanguardDecoder` converted to typed AST with `decode_and_execute`, bitmasks, `DecodedInstruction` population, and opcode switch/decoy traps.
- [x] Migrated Stack-VM super-operators ([`lib/stack_vm/stack_handlers_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_handlers_emitter.ml)):
  - Handlers `h_cmp`, `h_test`, `h_add_imm`, `h_sub_imm`, `h_add_ii`, `h_sub_ii` converted to typed `FuncDecl`.
  - Replaced string templates in [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml) with `{{ stack_superop_handlers }}`.
- [x] Migrated Trampoline Chunk structures ([`lib/adapters/protect_adapters/c_trampoline_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml)):
  - Declaration `AsgardBytecodeChunk` converted to typed `Cpp_ast.StructDecl`.
- [x] Verification: Steps 13 and 14 in `test_cpp_codegen.ml` + 38/38 `Stack-VM Execution Engine` tests + `Vanguard Emulator E2E` — 100% PASS.

### Stage 5.2: Completing All Stack-VM Handlers Migration (`e8aacea`)
- [x] Migrated remaining 10 Stack-VM handlers in [`lib/stack_vm/stack_handlers_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_handlers_emitter.ml):
  - Control & Lifecycle: `h_jmp_rel`, `h_jcc_rel` (with `layout_jcc_target_first` support), `h_key_adjust`, `h_exit`.
  - Conditionals & Symbols: `h_resolve_sym` (via C++20 `reinterpret_cast<uint64_t>`), `h_setcc`, `h_cmov` (with `layout_cmov_slot_first` support).
  - Register Immediates & Feedback: `h_set_reg_imm`, `h_add_reg_imm`, `h_key_feedback`.
- [x] Replaced raw strings in [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml) with `{{ stack_control_handlers }}`, `{{ stack_cond_handlers }}`, `{{ stack_reg_imm_handlers }}`.
- [x] Verification: Step 15 in `test_cpp_codegen.ml` + 38/38 `Stack-VM Execution Engine` tests — 100% PASS.

### Stage 5.3: Vector ISA C++ Emulator and Tech-2603 NonLinearVPCDispatcher
- [x] Extended EDSL core:
  - Added attributes `InlineFn`, `Nodiscard`.
  - Added structure members `MemberMethodDecl`, `MemberVisibility (Public | Private | Protected)`, `MemberStaticAssert`.
  - Added class and template declarations `ClassDef`, `TemplateStructDef`, `TemplateClassDef`.
- [x] Migrated Vector ISA C++ Emulator:
  - [`lib/adapters/cpp_emitter/cpp_header_emitters.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_header_emitters.ml): classes `VRegFile`, `EmulatorState`, `Decoder`, and `InstructionExecutor` converted to typed AST.
  - [`lib/adapters/cpp_emitter/cpp_emitter_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.ml): operations generator `generate_c_op_expr`, dispatcher `InstructionExecutor::execute`, instruction handlers `exec_<mnemonic>`, and class `VectorEmulator` converted to typed `FuncDecl` and `ClassDef`.
- [x] Migrated Tech-2603 NonLinearVPCDispatcher ([`lib/tech_2603/tech_2603_engine.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/tech_2603/tech_2603_engine.ml)):
  - Converted struct `NonLinearVPCDispatcher` to `TemplateStructDef` with `static_assert` verification and methods `logical_to_physical`, `physical_to_logical`, `next_physical`.
- [x] Verification: Steps 16 and 17 in `test_cpp_codegen.ml`, `C++ Emulator E2E`, and `Tech-2603 Anti-VPC Tracking` (7/7) — 100% PASS.

### Stage 5.4: C11 ISA, GPU MBA, C Nanomites, Multi-VM Bridge, Whitebox, RNS-4, Tech-2603/2608, Trampoline & E2E Mains (`e548e9c` .. `HEAD`)
- [x] Extended EDSL core:
  - Added `GlobalVar` (supporting 1D/2D arrays, `static`, `constexpr`, `const`, `volatile`), `InitList` (nested list and scalar auto-formatting), `LitU8` (byte literals), `CCast` (C-style cast `(T)(e)` for C11 compatibility).
  - Added `let_u32`, `const_u32`, `namespace_def`, and constructor attribute `Constructor` (`__attribute__((constructor))`).
  - Added escaping for special C characters (`\n`, `\t`, `\"`, `\\`) in `LitStr`.
  - Corrected uninitialized local variable rendering `DeclVar` (`T name;` instead of `T name{};` for C11 standard conformance).
- [x] Migrated C11 Vector ISA Emulator ([`lib/adapters/c11_emitter/c11_emitter_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml)):
  - Converted `CSRState`, `EmulatorState`, `DecodedInst`, and `emit_c11_prototypes` to typed `StructDecl` and `FuncProto`.
- [x] Migrated Vector ISA C++ Emulator Main & Constants ([`lib/adapters/cpp_emitter/cpp_header_emitters.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_header_emitters.ml), [`lib/adapters/cpp_emitter/cpp_emitter_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.ml)):
  - Converted constants `VLEN`, `VLEN_BYTES`, `NUM_VREGS`, `NUM_XREGS` to typed `ConstexprGlobal`.
  - Converted functions `setup_test_state`, `run_self_tests`, and `main` in `emit_main_cpp` to typed `FuncDecl`.
- [x] Migrated RD-JIT VM arrays, descriptors, and entry points ([`lib/rd_jit_vm/rd_jit_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_emitter.ml)):
  - Converted `JITInstr` and `JITBlock` array emission to typed `global_var` and `init_list`.
  - Converted standalone runner entry point `main` to typed AST `emit_rd_jit_main_def`.
  - Converted RNS-4 modules (`RNS_M1`..`M4`), CRT decoder, and `RNS_Register::mul` in [`lib/rd_jit_vm/rd_jit_buffer.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_buffer.ml) to typed EDSL.
  - Converted external symbol table `g_rd_jit_external_symbols` in [`lib/rd_jit_vm/rd_jit_synth.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_synth.ml) to typed `global_var`.
- [x] Migrated Trampoline Chunk & Assembler ([`lib/adapters/protect_adapters/c_trampoline_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml)):
  - Converted bytecode arrays `chunks[]`, global assembly buffer `embedded_bytecode[]`, `assembled` state, canary verification and decryption `embedded_bytecode_ensure_assembled()`, constructor `auto_init()`, and trampoline body `build_trampoline_body` to typed `global_var`, `func_decl`, and statements.
- [x] Migrated GPU MBA Substitution Matrix ([`lib/gpu_synth/gpu_matrix.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/gpu_synth/gpu_matrix.ml)):
  - Converted substitution matrices `MBA_FORWARD_MATRIX` and `MBA_INVERSE_MATRIX` to typed AST `emit_cpp_constants_ast`.
- [x] Migrated C Nanomite Preamble ([`lib/c_macro_obf/c_nanomites.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml)):
  - Converted branch functions `asgbranch_t_*`, `asgbranch_f_*` and auto-init constructor `_asg_nanomite_init` to typed `FuncDecl`.
- [x] Migrated Multi-VM Direct Zero-Bridge ([`lib/multi_vm/bridge.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/bridge.ml)):
  - Converted affine matrices $GL_{16}(\mathbb{Z}/2^{64}\mathbb{Z})$ `BRIDGE_FWD_MAT`, `BRIDGE_INV_MAT`, `ASGARD_INITIAL_DIGEST`, and functions `in_place_morph_*` to typed AST.
- [x] Migrated Whitebox Seed Derivation ([`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml)):
  - Converted tables `T0_0`..`T1_3`, functions `rotl32`, `derive_seed` within `namespace asgard_whitebox`, and `asgard_wbox_derive_seed` to typed EDSL.
- [x] Migrated Residue Number System (RNS-4) Garner CRT ([`lib/vm_ir/rns.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/rns.ml)):
  - Converted header `asgard_rns` with modulus constants, inversions, struct `RNSVal`, and functions `encode`, `add`, `sub`, `mul`, `decode` to typed EDSL (`emit_cpp_rns_ast`).
- [x] Migrated Tech-2603 and Tech-2608 headers ([`lib/tech_2603/tech_2603_engine.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/tech_2603/tech_2603_engine.ml), [`lib/tech_2608/tech_2608_engine.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/tech_2608/tech_2608_engine.ml)):
  - Converted `ChaffMemoryPool` to `template_struct_def`, and header generators `emit_tech_2603_cpp_header` and `emit_tech_2608_cpp_header` to `render_top_decls`.
- [x] Verification: Steps 1..27 in `test_cpp_codegen.ml`, `C++ Emulator E2E`, `C11 Emulator E2E`, `Multi-VM & Direct Zero-Bridge` (8/8), `Register-Driven JIT VM & RNS` (5/5), `C Macro Obfuscation` (12/12), `Tech-2603` (7/7), `Tech-2608` (4/4) — 100% PASS.

### Stage 5.5: EDSL SDK Expansion and VM Runners Migration (`HEAD`)
- [x] Extended EDSL core:
  - Added `LitNull` (`nullptr`), `SizeOfType of ctype` (`sizeof(T)`), linkage flags `is_extern_c : bool` and `is_weak : bool` in `GlobalVar` (`Cpp_ast`).
  - In `Cpp_dsl`: added combinators `nullptr`, `sizeof_ty`, `include_sys`, `include_local`; extended `global_var` with named arguments `?is_extern_c` and `?is_weak`.
  - In `Cpp_printer`: implemented printing for `nullptr`, `sizeof(T)`, prefixes `extern "C" ` and `__attribute__((weak)) ` for global variables.
  - In `Cpp_ast_obf`: added safe transformations for `LitNull` and `SizeOfType`.
- [x] Migrated Native VM Runner ([`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml)):
  - Converted entry point `main` to typed AST `emit_native_runner_main_def`.
  - Converted `emit_runner_cpp` from Jingoo templating to typed EDSL with dynamic memory sanitization.
- [x] Migrated Stack-VM Runner & Probe ([`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml)):
  - Converted entry points `main` for runner and address probe to typed `emit_stack_runner_main_def` and `emit_stack_probe_main_def`.
  - Converted functions `emit_runner_cpp` and `emit_probe_cpp` from Jingoo templating to typed EDSL `render_top_decls`.
- [x] Migrated Multi-VM Runner ([`lib/multi_vm/multi_vm_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/multi_vm_emitter.ml)):
  - Converted entry point `main` to typed AST `emit_multi_vm_runner_main_def`.
  - Converted weak-linkage globals `extern "C" __attribute__((weak))` and runner `runner_cpp` to typed EDSL.

### Stage 6.2: Core EDSL SDK Expansion & Decoupling Jingoo Loops (`lib/cpp_codegen/`, `lib/native_vm/`, `lib/stack_vm/`, `lib/multi_vm/`)
- [x] Extended EDSL SDK Core ([`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/)):
  - Added `Pragma of string` (`#pragma ...`) and `MacroDef of string * expr option` (`#define NAME [VALUE]`) in `Cpp_ast.top_decl`.
  - Added statement `DoWhile of expr * stmt list` (`do { ... } while (...);`) in `Cpp_ast.stmt`.
  - In `Cpp_dsl`: added combinators `pragma`, `macro_def`, `do_while`.
  - In `Cpp_printer` and `Cpp_ast_obf`: implemented rendering and transformations for all new constructs.
- [x] Migrated Address-Bound tables in Native VM ([`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml)):
  - Implemented typed generator `emit_block_spans_tables_ast` (`g_num_blocks`, `g_block_offsets`, `g_block_lengths`).
  - Eliminated raw Jinja loops `for b in block_spans` in [`lib/native_vm/native_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/native_vm_templates.ml).
- [x] Migrated offset and key tables in Stack-VM ([`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml)):
  - Implemented typed generator `emit_stack_block_tables_ast` (`g_stack_block_offsets`, `g_stack_block_keys`, `g_stack_tag_keys`, demasking macros).
  - Eliminated Jinja loops `for off in block_offsets` and `for k in block_keys` in [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml).
- [x] Completely removed Jingoo from Heterogeneous Multi-VM ([`lib/multi_vm/multi_vm_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/multi_vm_emitter.ml)):
  - Implemented `emit_multi_vm_header_decls` and `emit_multi_vm_header_source` on pure typed EDSL.
  - `multi_vm_emitter.ml` is fully autonomous and no longer invokes `Jg_template.from_string`.
- [x] Verification:
  - Steps 1..36 in `test_cpp_codegen.ml` — 100% PASS.
  - `Native Threaded VM` (12/12) — PASS.
  - `Stack-VM Execution Engine` (38/38) — PASS.
  - `Multi-VM & Direct Zero-Bridge` (8/8) — PASS.
  - `Register-Driven JIT VM & RNS` (5/5) — PASS.
  - `Tech-2603 Anti-VPC Tracking` (7/7) — PASS.
  - `Tech-2608 Anti-Trace-Synthesis` (4/4) — PASS.
  - `Tier 4 Next-Gen` (5/5) — PASS.
  - `Chameleon & Delayed-Commit Handlers` (3/3) — PASS.
  - `Bytecode Amplifier & Treewidth Expander` (7/7) — PASS.

### Stage 6.3: Computed Goto, Preprocessor AST, Trampoline Chunk, Stack-VM & Native VM Dispatch (`HEAD`)
- [x] Extended EDSL SDK Core ([`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/)):
  - In `Cpp_ast.expr`: added `LabelAddr of string` (`&&label`), `DesignatedIndex of expr * expr` (`[idx] = val`), `DesignatedRange of expr * expr * expr` (`[start ... end] = val`).
  - In `Cpp_ast.stmt`: added `ComputedGoto of expr` (`goto *expr;`), `PreprocIfStmt of string * stmt list * stmt list` (`#if cond ... #else ... #endif`), added `is_static : bool` flag in `DeclVar`, extended `Switch` to support annotated cases: `(expr * string option * stmt list) list`.
  - In `Cpp_ast.top_decl`: added `PreprocIf`, `PreprocIfdef`, `PreprocIfndef`.
  - In `Cpp_dsl`: added combinators `label_addr`, `desig_idx`, `desig_range`, `computed_goto`, `preproc_if_stmt`, `preproc_if`, `preproc_ifdef`, `preproc_ifndef`, `switch_annotated`, `case`.
  - In `Cpp_printer`: added uppercase formatting for `LitU8` (`0x%02X`), array initialization support in `DeclVar`, strict newline breaks `@\n` for preprocessor directives.
  - In `Cpp_ast_obf`: added handling for all new AST nodes.
- [x] Migrated Trampoline Chunk Definition ([`lib/adapters/protect_adapters/c_trampoline_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml)):
  - Converted `chunk_struct_def` to typed EDSL AST (`preproc_ifndef`, `pragma "pack(push, 1)"`, `typedef`, etc.).
  - Eliminated duplicate `#include` directives.
- [x] Migrated Stack-VM Dispatch ([`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml), [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml)):
  - Implemented `emit_stack_dispatch_stmts` and `emit_stack_dispatch_source` in EDSL.
  - Supported GCC/Clang computed goto table (`dispatch_table[256]` with designated ranges `[0 ... 255] = &&lbl_default`) and MSVC fallback (`switch_annotated`).
  - Eliminated 45 lines of Jinja template loops `for op in opcodes` in `stack_vm_templates.ml`.
- [x] Migrated Native VM Dispatch Tables & Loops ([`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml), [`lib/native_vm/native_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/native_vm_templates.ml)):
  - Implemented `emit_native_domain_salt_ast`, `emit_native_dispatch_domains_stmts`, `emit_native_msvc_switch_cases_source`, `emit_native_valid_hashes_ast`.
  - Replaced all Jinja loops (`valid_hashes`, `domain_salts`, `raw_domain*`, `raw_all_domains`, and MSVC switch cases).
  - Zero Jinja `for` loops remain in `threaded_header_template`.
- [x] Verification:
  - Steps 37 and 38 added to [`test/test_cpp_codegen.ml`](file:///Volumes/External/Code/ASGARD-5877/test/test_cpp_codegen.ml) — all 38/38 steps 100% PASS.
  - `Native Threaded VM` (12/12) — PASS.
  - `Stack-VM Execution Engine` (38/38) — PASS.
  - `./build_license.sh` compiles and executes `protected_app` with 0 warnings.

### Stage 7.1: Typed C++20 EDSL Stack-VM Header Migration & Complete Jingoo Decommissioning (`HEAD`)
- [x] Extended EDSL SDK Core ([`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/)):
  - In `Cpp_ast.stmt`: added `align_as : int option` and `is_thread_local : bool` in `DeclVar`, added `MacroUndefStmt of string` (`#undef NAME`).
  - In `Cpp_ast.struct_member`: added `is_volatile : bool` in `MemberField`.
  - In `Cpp_ast.top_decl`: added `align_as : int option` and `is_thread_local : bool` in `GlobalVar`, added `MacroUndef of string` (`#undef NAME`).
  - In `Cpp_dsl`: added combinators `macro_undef`, `macro_undef_stmt`, updated `decl_var`, `member_field`, `global_var`.
  - In `Cpp_printer`: implemented printing for `alignas(...)`, `thread_local`, `volatile`, `#undef NAME`.
  - In `Cpp_ast_obf`: added transformation support for all new AST nodes.
  - In [`lib/domain/isa_metamorphic_synth.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/domain/isa_metamorphic_synth.ml): switched to `decl_var` constructor.
- [x] Complete typed migration of Stack-VM Header ([`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml)):
  - Implemented typed generator `emit_h_call_extern : target_arch -> top_decl` with architecture-specific ABI argument handling (RV64, AArch64, X86_64).
  - Implemented `emit_stack_runtime_hpp_decls : ?external_symbols -> ?constants -> ?enc -> runtime_config -> program -> top_decl list`:
    - Preamble and platform-compatible `asg_strcmp`.
    - Struct definition `AsgardConstantEntry` with `volatile int32_t ready;` and constant resolution functions.
    - Struct definition `asgard_ext_sym_t` and external symbol resolver traversing the Apple Dyld exports trie and system `dlsym` / `GetProcAddress`.
    - Block and key demasking tables.
    - Namespace `asgard_stack_vm`: struct `stack_vm_t`, shift/feedback helpers, VSP whitening macros, handler table `g_stack_handler_table`, SIPHash payload authentication, `stack_vm_run` (with typed dispatcher invocation), `stack_vm_call`.
    - Namespace `vanguard_threaded_vm`: function `asgard_vm_call`.
  - Migrated `generate_c_runtime` to direct rendering via `Cpp_printer.render_top_decls`. Completely eliminated all Jinja/Jingoo models (`constants_model`, `symbols_model`, `block_offsets_model`, `block_keys_model`, `mk_case`).
- [x] Complete decommissioning of Jingoo templates in Stack-VM and Multi-VM:
  - Removed deprecated files `lib/multi_vm/multi_vm_templates.ml`, `lib/multi_vm/multi_vm_templates.mli`, `lib/stack_vm/stack_vm_templates.ml`, `lib/stack_vm/stack_vm_templates.mli`.
  - Removed `jingoo` dependency from [`lib/multi_vm/dune`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/dune) and [`lib/stack_vm/dune`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/dune).
- [x] Verification:
  - Added Step 39 to [`test/test_cpp_codegen.ml`](file:///Volumes/External/Code/ASGARD-5877/test/test_cpp_codegen.ml) — all 39/39 steps 100% PASS.
  - `Stack-VM Execution Engine` (38/38) — PASS.
  - `./build_license.sh` compiles `stack_vm_runtime.hpp` and executes `protected_app` with 0 warnings and 0 errors.

### Stage 7.2: Native Threaded VM EDSL Migration & 100% Jingoo Decommissioning (`HEAD`)
- [x] Complete typed C++20 EDSL migration of Native Threaded VM:
  - In [`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml) and [`.mli`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.mli):
    - Implemented `emit_native_runtime_hpp_decls : ... -> top_decl list` for typed generation of `threaded_vm.hpp`.
    - Implemented `generate_wbox_seed_derivation_decls : rng:Random.State.t -> int32 -> top_decl list`.
    - Completely removed Jinja/Jingoo model dictionaries (`models`, `to_dict`, `to_models` in `Runtime_policy`).
    - Switched `emit_cpp_threaded_header` to `render_top_decls (emit_native_runtime_hpp_decls ...)`.
  - In [`lib/native_vm/vm_context_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_context_emitter.ml):
    - Exported `emit_context_decls`, returning `top_decl list` to embed `struct VMContext` and context helpers in the header AST.
  - In [`lib/native_vm/native_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/native_vm_templates.ml) and [`.mli`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/native_vm_templates.mli):
    - Removed all Jingoo templates (`threaded_header_template`, `runner_template`, `let env`, `let render`, `open Jingoo`).
    - Retained static header strings (`platform_compat_header`, `crypto_primitives_header`, `sanitization_header`).
- [x] Complete elimination of `jingoo` from repository dependencies:
  - Removed `jingoo` library from [`lib/native_vm/dune`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/dune).
  - Removed `jingoo` dependency from [`dune-project`](file:///Volumes/External/Code/ASGARD-5877/dune-project) and [`random_visa.opam`](file:///Volumes/External/Code/ASGARD-5877/random_visa.opam).
  - Zero Jingoo calls or dependencies remain anywhere in the project.
- [x] Verification:
  - Added Step 40 to [`test/test_cpp_codegen.ml`](file:///Volumes/External/Code/ASGARD-5877/test/test_cpp_codegen.ml) — all 40/40 steps 100% PASS.
  - `Native Threaded VM` (12/12) — PASS.
  - `Stack-VM Execution Engine` (38/38) — PASS.
  - Script `./build_license.sh` compiles ARM64 runtime and executes `protected_app` cleanly (0 warnings, 0 errors).

---

## Architectural Invariants and Safety Rules

1. **Dispatcher Label Formatting**:
   Every emitted AST handler label must be formatted with the prefix `    H_<OPCODE>:` (4 leading spaces) so that `Vm_handlers_emitter.transform_domain_labels` can transparently append domain suffixes (`_D1`, `_D2`) for multi-domain dispatchers.

2. **C++ Type Safety**:
   - All unsigned integer register operations must use `ULL` suffixes (`LitU64`) to prevent signed overflow undefined behavior under `clang -O3`.
   - Signed arithmetic must explicitly state cast target types via `static_cast<int64_t>`.

3. **Targeted Test Execution**:
   - Do **NOT** run the complete `dune runtest` suite for isolated changes.
   - Run specific target test runners:
     ```bash
     eval $(opam env) && ./_build/default/test/test_cpp_codegen.exe
     eval $(opam env) && ./_build/default/test/test_tier4_nextgen.exe
     eval $(opam env) && ./_build/default/test/run_tests.exe test "Metamorphic ISA.*"
     eval $(opam env) && ./_build/default/test/run_tests.exe test "E-graph Equality Expansion.*"
     ```
