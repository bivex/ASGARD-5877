# 🏗️ DPX-OCaml: Architecture & Dependency Report

- **Target Path:** `/Volumes/External/Code/ASGARD-5877`
- **Dune Project:** Yes
- **Files Scanned:** `259`
- **Modules Count:** `162`
- **Dependency Edges:** `545`
- **Cycles / Circular Dependencies:** `0` (Clean DAG)
- **Scan Elapsed Time:** `0.24s`

## 📊 Architecture Health Summary

| Severity | Count | Status |
|---|:---:|---|
| **Errors (❌)** | **0** | **0 errors — No circular dependencies or broken abstractions** |
| **Warnings (⚠️)** | **0** | **0 warnings — All God Modules (>400 LOC) eradicated** |
| **Info (ℹ️)** | **24** | **Domain AST / ADT types & test runner hub (benign by design)** |

## 📚 Dune Libraries & Dependencies

| Library | Modules | Local Dependencies | External Dependencies |
|---|:---:|---|---|
| **arm64_lifter** | 9 | `vm_ir` | — |
| **c_macro_obf** | 9 | — | — |
| **cff** | 2 | `vm_ir` | — |
| **gpu_synth** | 1 | — | — |
| **mba_engine** | 6 | `vm_ir` | — |
| **multi_vm** | 3 | `native_vm`, `vm_ir` | — |
| **native_vm** | 20 | `cff`, `mba_engine`, `random_visa_domain`, `vm_ir` | `yojson` |
| **protect_adapters** | 7 | `arm64_lifter`, `c_macro_obf`, `multi_vm`, `native_vm`, `random_visa_ports`, `rd_jit_vm`, `vm_ir`, `x86_lifter` | `unix` |
| **random_visa_application** | 7 | `random_visa_domain`, `random_visa_ports` | — |
| **random_visa_assembler** | 1 | `random_visa_domain`, `random_visa_ports` | — |
| **random_visa_c11_emitter** | 1 | `random_visa_domain`, `random_visa_ports` | — |
| **random_visa_compiler_adapter** | 1 | `random_visa_domain`, `random_visa_ports` | `unix` |
| **random_visa_cpp_emitter** | 2 | `random_visa_domain`, `random_visa_ports` | — |
| **random_visa_domain** | 14 | — | — |
| **random_visa_ports** | 2 | `random_visa_domain` | — |
| **random_visa_sail_export** | 1 | `random_visa_domain`, `random_visa_ports` | — |
| **random_visa_sail_parser** | 2 | `random_visa_domain`, `random_visa_ports` | — |
| **rd_jit_vm** | 4 | `cff`, `native_vm`, `vm_ir` | — |
| **vanguard_9292** | 4 | `random_visa_domain` | — |
| **vm_ir** | 17 | — | — |
| **x86_lifter** | 2 | `vm_ir` | — |

## 🏛️ Hexagonal Architecture Layers

Dependencies must strictly point inward: `API / Entry Points → Domain Layer ← Adapters / Infrastructure`.

### API / Entry Points (9 modules)

| Module | File | LOC | Interface (.mli) | Dune Library |
|---|---|:---:|:---:|---|
| `Cli_isa` | `bin/cli_isa.ml` | 214 | No | `—` |
| `Cli_project` | `bin/cli_project.ml` | 218 | No | `—` |
| `Cli_protect` | `bin/cli_protect.ml` | 200 | No | `—` |
| `Cli_protect_arm64` | `bin/cli_protect_arm64.ml` | 123 | No | `—` |
| `Cli_vanguard` | `bin/cli_vanguard.ml` | 120 | No | `—` |
| `Gen_crackme_vm` | `bin/gen_crackme_vm.ml` | 71 | No | `—` |
| `Gen_crypto_crackme` | `bin/gen_crypto_crackme.ml` | 154 | No | `—` |
| `Main` | `bin/main.ml` | 19 | No | `—` |
| `Profile_bottlenecks` | `bin/profile_bottlenecks.ml` | 355 | No | `—` |

### Application & Ports Layer (9 modules)

| Module | File | LOC | Interface (.mli) | Dune Library |
|---|---|:---:|:---:|---|
| `Compile_and_verify` | `lib/application/compile_and_verify.ml` | 5 | Yes | `random_visa_application` |
| `Export_sail` | `lib/application/export_sail.ml` | 5 | Yes | `random_visa_application` |
| `Generate_emulator` | `lib/application/generate_emulator.ml` | 5 | Yes | `random_visa_application` |
| `Import_sail` | `lib/application/import_sail.ml` | 5 | Yes | `random_visa_application` |
| `Pipeline` | `lib/application/pipeline.ml` | 79 | Yes | `random_visa_application` |
| `Ports` | `lib/ports/ports.ml` | 24 | Yes | `random_visa_ports` |
| `Protect_pipeline` | `lib/application/protect_pipeline.ml` | 136 | Yes | `random_visa_application` |
| `Protect_ports` | `lib/ports/protect_ports.ml` | 99 | Yes | `random_visa_ports` |
| `Synthesize_isa` | `lib/application/synthesize_isa.ml` | 8 | Yes | `random_visa_application` |

### Domain Layer (14 modules)

| Module | File | LOC | Interface (.mli) | Dune Library |
|---|---|:---:|:---:|---|
| `Dispatch_strategy` | `lib/domain/dispatch_strategy.ml` | 88 | Yes | `random_visa_domain` |
| `Errors` | `lib/domain/errors.ml` | 39 | Yes | `random_visa_domain` |
| `Generation_profile` | `lib/domain/generation_profile.ml` | 49 | Yes | `random_visa_domain` |
| `Hw_cost` | `lib/domain/hw_cost.ml` | 73 | Yes | `random_visa_domain` |
| `Instruction_class` | `lib/domain/instruction_class.ml` | 44 | Yes | `random_visa_domain` |
| `Instruction_family` | `lib/domain/instruction_family.ml` | 54 | Yes | `random_visa_domain` |
| `Isa_grammar` | `lib/domain/isa_grammar.ml` | 219 | Yes | `random_visa_domain` |
| `Mutation_profile` | `lib/domain/mutation_profile.ml` | 47 | Yes | `random_visa_domain` |
| `Sail_ast` | `lib/domain/sail_ast.ml` | 136 | Yes | `random_visa_domain` |
| `Types` | `lib/domain/types.ml` | 239 | Yes | `random_visa_domain` |
| `Vector_config` | `lib/domain/vector_config.ml` | 41 | Yes | `random_visa_domain` |
| `Vector_instruction` | `lib/domain/vector_instruction.ml` | 127 | Yes | `random_visa_domain` |
| `Vector_isa_spec` | `lib/domain/vector_isa_spec.ml` | 109 | Yes | `random_visa_domain` |
| `Vm_runtime_profile` | `lib/domain/vm_runtime_profile.ml` | 19 | Yes | `random_visa_domain` |

### Adapters / Infrastructure (15 modules)

| Module | File | LOC | Interface (.mli) | Dune Library |
|---|---|:---:|:---:|---|
| `Arm64_lifter_adapter` | `lib/adapters/protect_adapters/arm64_lifter_adapter.ml` | 25 | Yes | `protect_adapters` |
| `Assembler_adapter` | `lib/adapters/assembler/assembler_adapter.ml` | 341 | Yes | `random_visa_assembler` |
| `Ast` | `lib/adapters/sail_parser/ast.ml` | 35 | No | `random_visa_sail_parser` |
| `C11_emitter_adapter` | `lib/adapters/c11_emitter/c11_emitter_adapter.ml` | 288 | Yes | `random_visa_c11_emitter` |
| `C_macro_obf_adapter` | `lib/adapters/protect_adapters/c_macro_obf_adapter.ml` | 78 | Yes | `protect_adapters` |
| `C_trampoline_adapter` | `lib/adapters/protect_adapters/c_trampoline_adapter.ml` | 112 | Yes | `protect_adapters` |
| `Clang_toolchain_adapter` | `lib/adapters/protect_adapters/clang_toolchain_adapter.ml` | 48 | Yes | `protect_adapters` |
| `Compiler_adapter` | `lib/adapters/compiler_adapter/compiler_adapter.ml` | 77 | Yes | `random_visa_compiler_adapter` |
| `Config_adapter` | `lib/adapters/protect_adapters/config_adapter.ml` | 71 | Yes | `protect_adapters` |
| `Cpp_emitter_adapter` | `lib/adapters/cpp_emitter/cpp_emitter_adapter.ml` | 226 | Yes | `random_visa_cpp_emitter` |
| `Cpp_header_emitters` | `lib/adapters/cpp_emitter/cpp_header_emitters.ml` | 164 | No | `random_visa_cpp_emitter` |
| `Sail_export_adapter` | `lib/adapters/sail_export/sail_export_adapter.ml` | 23 | Yes | `random_visa_sail_export` |
| `Sail_parser_adapter` | `lib/adapters/sail_parser/sail_parser_adapter.ml` | 219 | Yes | `random_visa_sail_parser` |
| `Vm_packagers` | `lib/adapters/protect_adapters/vm_packagers.ml` | 69 | Yes | `protect_adapters` |
| `X86_lifter_adapter` | `lib/adapters/protect_adapters/x86_lifter_adapter.ml` | 27 | Yes | `protect_adapters` |

### VM, Decompilation & Hardening Pipeline (112 modules)

| Module | File | LOC | Interface (.mli) | Dune Library |
|---|---|:---:|:---:|---|
| `Arm64_alu` | `lib/arm64_lifter/arm64_alu.ml` | 236 | Yes | `arm64_lifter` |
| `Arm64_branch` | `lib/arm64_lifter/arm64_branch.ml` | 74 | Yes | `arm64_lifter` |
| `Arm64_common` | `lib/arm64_lifter/arm64_common.ml` | 89 | Yes | `arm64_lifter` |
| `Arm64_lifter` | `lib/arm64_lifter/arm64_lifter.ml` | 179 | Yes | `arm64_lifter` |
| `Arm64_mem` | `lib/arm64_lifter/arm64_mem.ml` | 183 | Yes | `arm64_lifter` |
| `Arm64_parser` | `lib/arm64_lifter/arm64_parser.ml` | 303 | Yes | `arm64_lifter` |
| `Arm64_regs` | `lib/arm64_lifter/arm64_regs.ml` | 88 | Yes | `arm64_lifter` |
| `Arm64_types` | `lib/arm64_lifter/arm64_types.ml` | 32 | Yes | `arm64_lifter` |
| `Bridge` | `lib/multi_vm/bridge.ml` | 153 | Yes | `multi_vm` |
| `C_arith_rewriter` | `lib/c_macro_obf/c_arith_rewriter.ml` | 76 | No | `c_macro_obf` |
| `C_expr_lexer` | `lib/c_macro_obf/c_expr_lexer.ml` | 156 | No | `c_macro_obf` |
| `C_expr_parser` | `lib/c_macro_obf/c_expr_parser.ml` | 314 | No | `c_macro_obf` |
| `C_macro_config` | `lib/c_macro_obf/c_macro_config.ml` | 41 | Yes | `c_macro_obf` |
| `C_macro_guards` | `lib/c_macro_obf/c_macro_guards.ml` | 327 | No | `c_macro_obf` |
| `C_macro_header` | `lib/c_macro_obf/c_macro_header.ml` | 50 | No | `c_macro_obf` |
| `C_macro_obf` | `lib/c_macro_obf/c_macro_obf.ml` | 215 | Yes | `c_macro_obf` |
| `C_macro_templates` | `lib/c_macro_obf/c_macro_templates.ml` | 186 | No | `c_macro_obf` |
| `C_nanomites` | `lib/c_macro_obf/c_nanomites.ml` | 334 | No | `c_macro_obf` |
| `Cff` | `lib/cff/cff.ml` | 135 | Yes | `cff` |
| `Cfg_transform` | `lib/vm_ir/cfg_transform.ml` | 71 | Yes | `vm_ir` |
| `Coverage_audit` | `scripts/coverage_audit.ml` | 71 | No | `—` |
| `Defuse_scrambler` | `lib/native_vm/defuse_scrambler.ml` | 51 | Yes | `native_vm` |
| `Egraph` | `lib/mba_engine/egraph.ml` | 113 | Yes | `mba_engine` |
| `Egraph_cpp_emitter` | `lib/native_vm/egraph_cpp_emitter.ml` | 99 | No | `native_vm` |
| `Egraph_extract` | `lib/mba_engine/egraph_extract.ml` | 194 | No | `mba_engine` |
| `Egraph_rules` | `lib/mba_engine/egraph_rules.ml` | 160 | No | `mba_engine` |
| `Egraph_types` | `lib/mba_engine/egraph_types.ml` | 117 | Yes | `mba_engine` |
| `Equivalence` | `lib/vm_ir/equivalence.ml` | 68 | Yes | `vm_ir` |
| `Flags` | `lib/vm_ir/flags.ml` | 228 | Yes | `vm_ir` |
| `Gpu_synth` | `lib/gpu_synth/gpu_synth.ml` | 25 | Yes | `gpu_synth` |
| `Hardened_runtime` | `lib/native_vm/hardened_runtime.ml` | 7 | Yes | `native_vm` |
| `Ir` | `lib/vm_ir/ir.ml` | 200 | Yes | `vm_ir` |
| `Ir_egraph` | `lib/vm_ir/ir_egraph.ml` | 184 | Yes | `vm_ir` |
| `Ir_pipeline` | `lib/vm_ir/ir_pipeline.ml` | 46 | Yes | `vm_ir` |
| `Ir_verify` | `lib/vm_ir/ir_verify.ml` | 56 | Yes | `vm_ir` |
| `Lifter` | `lib/x86_lifter/lifter.ml` | 300 | Yes | `x86_lifter` |
| `Literal_stitcher` | `lib/arm64_lifter/literal_stitcher.ml` | 23 | Yes | `arm64_lifter` |
| `Mba` | `lib/mba_engine/mba.ml` | 234 | Yes | `mba_engine` |
| `Metrics` | `lib/native_vm/metrics.ml` | 86 | Yes | `native_vm` |
| `Multi_vm_emitter` | `lib/multi_vm/multi_vm_emitter.ml` | 175 | Yes | `multi_vm` |
| `Ncfg_synth` | `lib/mba_engine/ncfg_synth.ml` | 51 | Yes | `mba_engine` |
| `Opaque_predicates` | `lib/vm_ir/opaque_predicates.ml` | 46 | Yes | `vm_ir` |
| `Partitioner` | `lib/multi_vm/partitioner.ml` | 83 | Yes | `multi_vm` |
| `Pop_coupler` | `lib/cff/pop_coupler.ml` | 55 | Yes | `cff` |
| `Protection_config` | `lib/native_vm/protection_config.ml` | 23 | Yes | `native_vm` |
| `Protection_json` | `lib/native_vm/protection_json.ml` | 268 | No | `native_vm` |
| `Protection_presets` | `lib/native_vm/protection_presets.ml` | 316 | No | `native_vm` |
| `Protection_types` | `lib/native_vm/protection_types.ml` | 75 | Yes | `native_vm` |
| `Rd_jit_buffer` | `lib/rd_jit_vm/rd_jit_buffer.ml` | 193 | Yes | `rd_jit_vm` |
| `Rd_jit_emitter` | `lib/rd_jit_vm/rd_jit_emitter.ml` | 143 | Yes | `rd_jit_vm` |
| `Rd_jit_synth` | `lib/rd_jit_vm/rd_jit_synth.ml` | 259 | Yes | `rd_jit_vm` |
| `Rd_jit_types` | `lib/rd_jit_vm/rd_jit_types.ml` | 7 | Yes | `rd_jit_vm` |
| `Reference_vm` | `lib/vm_ir/reference_vm.ml` | 25 | Yes | `vm_ir` |
| `Register` | `lib/vm_ir/register.ml` | 189 | Yes | `vm_ir` |
| `Register_allocator` | `lib/vm_ir/register_allocator.ml` | 83 | Yes | `vm_ir` |
| `Rns` | `lib/vm_ir/rns.ml` | 177 | Yes | `vm_ir` |
| `Rolling_key` | `lib/vm_ir/rolling_key.ml` | 41 | Yes | `vm_ir` |
| `Run_tests` | `test/run_tests.ml` | 35 | No | `—` |
| `Runtime_dual_map` | `lib/native_vm/runtime_dual_map.ml` | 64 | Yes | `native_vm` |
| `Runtime_probes` | `lib/native_vm/runtime_probes.ml` | 121 | Yes | `native_vm` |
| `Runtime_smc` | `lib/native_vm/runtime_smc.ml` | 187 | Yes | `native_vm` |
| `Runtime_syscalls` | `lib/native_vm/runtime_syscalls.ml` | 232 | Yes | `native_vm` |
| `Seed` | `lib/vm_ir/seed.ml` | 65 | Yes | `vm_ir` |
| `Semantic_transform` | `lib/vm_ir/semantic_transform.ml` | 135 | Yes | `vm_ir` |
| `Superoperator` | `lib/vm_ir/superoperator.ml` | 48 | Yes | `vm_ir` |
| `Test_anti_analysis` | `test/test_anti_analysis.ml` | 198 | No | `—` |
| `Test_anti_pushan` | `test/test_anti_pushan.ml` | 264 | No | `—` |
| `Test_anti_tamper_smc` | `test/test_anti_tamper_smc.ml` | 333 | No | `—` |
| `Test_arm64_lifter` | `test/test_arm64_lifter.ml` | 152 | No | `—` |
| `Test_arxiv_innovations` | `test/test_arxiv_innovations.ml` | 143 | No | `—` |
| `Test_assembler` | `test/test_assembler.ml` | 207 | No | `—` |
| `Test_assembler_deep` | `test/test_assembler_deep.ml` | 62 | No | `—` |
| `Test_c11_emulator` | `test/test_c11_emulator.ml` | 85 | No | `—` |
| `Test_c_macro_obf` | `test/test_c_macro_obf.ml` | 318 | No | `—` |
| `Test_cli` | `test/test_cli.ml` | 85 | No | `—` |
| `Test_compiler_pipeline` | `test/test_compiler_pipeline.ml` | 100 | No | `—` |
| `Test_cpp_emulator` | `test/test_cpp_emulator.ml` | 39 | No | `—` |
| `Test_domain_invariants` | `test/test_domain_invariants.ml` | 176 | No | `—` |
| `Test_egraph_expansion` | `test/test_egraph_expansion.ml` | 257 | No | `—` |
| `Test_families_generation` | `test/test_families_generation.ml` | 219 | No | `—` |
| `Test_golden` | `test/test_golden.ml` | 30 | No | `—` |
| `Test_gpu_synth` | `test/test_gpu_synth.ml` | 27 | No | `—` |
| `Test_helpers` | `test/test_helpers.ml` | 89 | No | `—` |
| `Test_hw_cost` | `test/test_hw_cost.ml` | 116 | No | `—` |
| `Test_isa_grammar` | `test/test_isa_grammar.ml` | 129 | No | `—` |
| `Test_metrics` | `test/test_metrics.ml` | 80 | No | `—` |
| `Test_multi_vlen` | `test/test_multi_vlen.ml` | 33 | No | `—` |
| `Test_multi_vm` | `test/test_multi_vm.ml` | 124 | No | `—` |
| `Test_native_semantics` | `test/test_native_semantics.ml` | 283 | No | `—` |
| `Test_native_vm` | `test/test_native_vm.ml` | 280 | No | `—` |
| `Test_properties` | `test/test_properties.ml` | 95 | No | `—` |
| `Test_protection_config` | `test/test_protection_config.ml` | 73 | No | `—` |
| `Test_rd_jit_vm` | `test/test_rd_jit_vm.ml` | 90 | No | `—` |
| `Test_runtime_profile` | `test/test_runtime_profile.ml` | 43 | No | `—` |
| `Test_sail_parser_roundtrip` | `test/test_sail_parser_roundtrip.ml` | 147 | No | `—` |
| `Test_vanguard_9292` | `test/test_vanguard_9292.ml` | 135 | No | `—` |
| `Test_vanguard_emulator_e2e` | `test/test_vanguard_emulator_e2e.ml` | 98 | No | `—` |
| `Test_vm_ir` | `test/test_vm_ir.ml` | 187 | No | `—` |
| `Test_x86_lifter` | `test/test_x86_lifter.ml` | 174 | No | `—` |
| `Vanguard_9292` | `lib/vanguard_9292/vanguard_9292.ml` | 86 | Yes | `vanguard_9292` |
| `Vanguard_asm` | `lib/vanguard_9292/vanguard_asm.ml` | 144 | No | `vanguard_9292` |
| `Vanguard_decoder` | `lib/vanguard_9292/vanguard_decoder.ml` | 107 | No | `vanguard_9292` |
| `Vanguard_types` | `lib/vanguard_9292/vanguard_types.ml` | 184 | Yes | `vanguard_9292` |
| `Vm_alu_handlers` | `lib/native_vm/vm_alu_handlers.ml` | 127 | Yes | `native_vm` |
| `Vm_context_emitter` | `lib/native_vm/vm_context_emitter.ml` | 199 | No | `native_vm` |
| `Vm_control_handlers` | `lib/native_vm/vm_control_handlers.ml` | 121 | Yes | `native_vm` |
| `Vm_emitter` | `lib/native_vm/vm_emitter.ml` | 351 | Yes | `native_vm` |
| `Vm_eval` | `lib/vm_ir/vm_eval.ml` | 312 | Yes | `vm_ir` |
| `Vm_handlers_emitter` | `lib/native_vm/vm_handlers_emitter.ml` | 8 | Yes | `native_vm` |
| `Vm_mem_handlers` | `lib/native_vm/vm_mem_handlers.ml` | 239 | Yes | `native_vm` |
| `Vm_runtime_emitter` | `lib/native_vm/vm_runtime_emitter.ml` | 291 | No | `native_vm` |
| `Vm_transform` | `lib/native_vm/vm_transform.ml` | 276 | No | `native_vm` |
| `X86_parser` | `lib/x86_lifter/x86_parser.ml` | 292 | Yes | `x86_lifter` |

## 📐 Martin Component Metrics (Coupling & Stability)

| Module | Dune Library | Layer | LOC | Ca | Ce | Instability (I) | Abstractness (A) | Distance (D) |
|---|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `Arm64_alu` | `arm64_lifter` | unknown | 236 | 1 | 5 | 0.83 | 1.00 | 0.83 |
| `Arm64_branch` | `arm64_lifter` | unknown | 74 | 1 | 4 | 0.80 | 1.00 | 0.80 |
| `Arm64_common` | `arm64_lifter` | unknown | 89 | 3 | 4 | 0.57 | 1.00 | 0.57 |
| `Arm64_lifter` | `arm64_lifter` | unknown | 179 | 5 | 6 | 0.55 | 0.00 | 0.46 |
| `Arm64_lifter_adapter` | `protect_adapters` | adapters | 25 | 1 | 3 | 0.75 | 1.00 | 0.75 |
| `Arm64_mem` | `arm64_lifter` | unknown | 183 | 1 | 4 | 0.80 | 1.00 | 0.80 |
| `Arm64_parser` | `arm64_lifter` | unknown | 303 | 2 | 2 | 0.50 | 1.00 | 0.50 |
| `Arm64_regs` | `arm64_lifter` | unknown | 88 | 1 | 1 | 0.50 | 1.00 | 0.50 |
| `Arm64_types` | `arm64_lifter` | unknown | 32 | 6 | 1 | 0.14 | 0.00 | 0.86 |
| `Assembler_adapter` | `random_visa_assembler` | adapters | 341 | 3 | 5 | 0.62 | 1.00 | 0.62 |
| `Ast` | `random_visa_sail_parser` | adapters | 35 | 1 | 0 | 0.00 | 0.00 | 1.00 |
| `Bridge` | `multi_vm` | unknown | 153 | 3 | 0 | 0.00 | 1.00 | 0.00 |
| `C11_emitter_adapter` | `random_visa_c11_emitter` | adapters | 288 | 1 | 5 | 0.83 | 1.00 | 0.83 |
| `C_arith_rewriter` | `c_macro_obf` | unknown | 76 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `C_expr_lexer` | `c_macro_obf` | unknown | 156 | 2 | 0 | 0.00 | 0.00 | 1.00 |
| `C_expr_parser` | `c_macro_obf` | unknown | 314 | 1 | 1 | 0.50 | 0.00 | 0.50 |
| `C_macro_config` | `c_macro_obf` | unknown | 41 | 3 | 0 | 0.00 | 0.00 | 1.00 |
| `C_macro_guards` | `c_macro_obf` | unknown | 327 | 1 | 0 | 0.00 | 0.00 | 1.00 |
| `C_macro_header` | `c_macro_obf` | unknown | 50 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `C_macro_obf` | `c_macro_obf` | unknown | 215 | 5 | 4 | 0.44 | 0.00 | 0.56 |
| `C_macro_obf_adapter` | `protect_adapters` | adapters | 78 | 2 | 3 | 0.60 | 1.00 | 0.60 |
| `C_macro_templates` | `c_macro_obf` | unknown | 186 | 1 | 0 | 0.00 | 0.00 | 1.00 |
| `C_nanomites` | `c_macro_obf` | unknown | 334 | 1 | 1 | 0.50 | 0.00 | 0.50 |
| `C_trampoline_adapter` | `protect_adapters` | adapters | 112 | 3 | 1 | 0.25 | 1.00 | 0.25 |
| `Cff` | `cff` | unknown | 135 | 4 | 3 | 0.43 | 0.00 | 0.57 |
| `Cfg_transform` | `vm_ir` | unknown | 71 | 1 | 4 | 0.80 | 1.00 | 0.80 |
| `Clang_toolchain_adapter` | `protect_adapters` | adapters | 48 | 2 | 1 | 0.33 | 1.00 | 0.33 |
| `Cli_isa` | `—` | api | 214 | 1 | 8 | 0.89 | 0.00 | 0.11 |
| `Cli_project` | `—` | api | 218 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Cli_protect` | `—` | api | 200 | 1 | 8 | 0.89 | 0.00 | 0.11 |
| `Cli_protect_arm64` | `—` | api | 123 | 1 | 8 | 0.89 | 0.00 | 0.11 |
| `Cli_vanguard` | `—` | api | 120 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Compile_and_verify` | `random_visa_application` | ports | 5 | 1 | 1 | 0.50 | 1.00 | 0.50 |
| `Compiler_adapter` | `random_visa_compiler_adapter` | adapters | 77 | 3 | 2 | 0.40 | 1.00 | 0.40 |
| `Config_adapter` | `protect_adapters` | adapters | 71 | 2 | 2 | 0.50 | 1.00 | 0.50 |
| `Coverage_audit` | `—` | unknown | 71 | 0 | 0 | 0.00 | 0.00 | 1.00 |
| `Cpp_emitter_adapter` | `random_visa_cpp_emitter` | adapters | 226 | 5 | 6 | 0.55 | 1.00 | 0.55 |
| `Cpp_header_emitters` | `random_visa_cpp_emitter` | adapters | 164 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Defuse_scrambler` | `native_vm` | unknown | 51 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Dispatch_strategy` | `random_visa_domain` | domain | 88 | 2 | 0 | 0.00 | 0.00 | 1.00 |
| `Egraph` | `mba_engine` | unknown | 113 | 3 | 6 | 0.67 | 0.00 | 0.33 |
| `Egraph_cpp_emitter` | `native_vm` | unknown | 99 | 2 | 2 | 0.50 | 0.00 | 0.50 |
| `Egraph_extract` | `mba_engine` | unknown | 194 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Egraph_rules` | `mba_engine` | unknown | 160 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Egraph_types` | `mba_engine` | unknown | 117 | 3 | 1 | 0.25 | 0.00 | 0.75 |
| `Equivalence` | `vm_ir` | unknown | 68 | 2 | 4 | 0.67 | 0.00 | 0.33 |
| `Errors` | `random_visa_domain` | domain | 39 | 34 | 0 | 0.00 | 0.00 | 1.00 |
| `Export_sail` | `random_visa_application` | ports | 5 | 1 | 2 | 0.67 | 1.00 | 0.67 |
| `Flags` | `vm_ir` | unknown | 228 | 12 | 1 | 0.08 | 0.00 | 0.92 |
| `Gen_crackme_vm` | `—` | api | 71 | 0 | 3 | 1.00 | 0.00 | 0.00 |
| `Gen_crypto_crackme` | `—` | api | 154 | 0 | 7 | 1.00 | 0.00 | 0.00 |
| `Generate_emulator` | `random_visa_application` | ports | 5 | 1 | 2 | 0.67 | 1.00 | 0.67 |
| `Generation_profile` | `random_visa_domain` | domain | 49 | 6 | 2 | 0.25 | 0.00 | 0.75 |
| `Gpu_synth` | `gpu_synth` | unknown | 25 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Hardened_runtime` | `native_vm` | unknown | 7 | 2 | 4 | 0.67 | 0.00 | 0.33 |
| `Hw_cost` | `random_visa_domain` | domain | 73 | 3 | 3 | 0.50 | 0.00 | 0.50 |
| `Import_sail` | `random_visa_application` | ports | 5 | 1 | 2 | 0.67 | 1.00 | 0.67 |
| `Instruction_class` | `random_visa_domain` | domain | 44 | 8 | 1 | 0.11 | 0.00 | 0.89 |
| `Instruction_family` | `random_visa_domain` | domain | 54 | 3 | 3 | 0.50 | 0.00 | 0.50 |
| `Ir` | `vm_ir` | unknown | 200 | 35 | 2 | 0.05 | 0.00 | 0.95 |
| `Ir_egraph` | `vm_ir` | unknown | 184 | 2 | 1 | 0.33 | 0.33 | 0.33 |
| `Ir_pipeline` | `vm_ir` | unknown | 46 | 1 | 8 | 0.89 | 0.00 | 0.11 |
| `Ir_verify` | `vm_ir` | unknown | 56 | 2 | 2 | 0.50 | 0.00 | 0.50 |
| `Isa_grammar` | `random_visa_domain` | domain | 219 | 14 | 8 | 0.36 | 1.00 | 0.36 |
| `Lifter` | `x86_lifter` | unknown | 300 | 11 | 4 | 0.27 | 0.00 | 0.73 |
| `Literal_stitcher` | `arm64_lifter` | unknown | 23 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Main` | `—` | api | 19 | 0 | 5 | 1.00 | 0.00 | 0.00 |
| `Mba` | `mba_engine` | unknown | 234 | 10 | 2 | 0.17 | 0.00 | 0.83 |
| `Metrics` | `native_vm` | unknown | 86 | 10 | 1 | 0.09 | 1.00 | 0.09 |
| `Multi_vm_emitter` | `multi_vm` | unknown | 175 | 2 | 6 | 0.75 | 0.00 | 0.25 |
| `Mutation_profile` | `random_visa_domain` | domain | 47 | 2 | 0 | 0.00 | 0.00 | 1.00 |
| `Ncfg_synth` | `mba_engine` | unknown | 51 | 1 | 1 | 0.50 | 1.00 | 0.50 |
| `Opaque_predicates` | `vm_ir` | unknown | 46 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Partitioner` | `multi_vm` | unknown | 83 | 2 | 1 | 0.33 | 0.00 | 0.67 |
| `Pipeline` | `random_visa_application` | ports | 79 | 1 | 9 | 0.90 | 0.00 | 0.10 |
| `Pop_coupler` | `cff` | unknown | 55 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Ports` | `random_visa_ports` | ports | 24 | 8 | 2 | 0.20 | 1.00 | 0.20 |
| `Profile_bottlenecks` | `—` | api | 355 | 0 | 14 | 1.00 | 0.00 | 0.00 |
| `Protect_pipeline` | `random_visa_application` | ports | 136 | 2 | 1 | 0.33 | 1.00 | 0.33 |
| `Protect_ports` | `random_visa_ports` | ports | 99 | 10 | 0 | 0.00 | 0.25 | 0.75 |
| `Protection_config` | `native_vm` | unknown | 23 | 12 | 3 | 0.20 | 0.08 | 0.72 |
| `Protection_json` | `native_vm` | unknown | 268 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Protection_presets` | `native_vm` | unknown | 316 | 2 | 1 | 0.33 | 0.00 | 0.67 |
| `Protection_types` | `native_vm` | unknown | 75 | 3 | 0 | 0.00 | 0.00 | 1.00 |
| `Rd_jit_buffer` | `rd_jit_vm` | unknown | 193 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Rd_jit_emitter` | `rd_jit_vm` | unknown | 143 | 2 | 10 | 0.83 | 0.00 | 0.17 |
| `Rd_jit_synth` | `rd_jit_vm` | unknown | 259 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Rd_jit_types` | `rd_jit_vm` | unknown | 7 | 1 | 1 | 0.50 | 0.00 | 0.50 |
| `Reference_vm` | `vm_ir` | unknown | 25 | 3 | 3 | 0.50 | 0.00 | 0.50 |
| `Register` | `vm_ir` | unknown | 189 | 36 | 0 | 0.00 | 0.00 | 1.00 |
| `Register_allocator` | `vm_ir` | unknown | 83 | 2 | 3 | 0.60 | 0.00 | 0.40 |
| `Rns` | `vm_ir` | unknown | 177 | 5 | 0 | 0.00 | 0.00 | 1.00 |
| `Rolling_key` | `vm_ir` | unknown | 41 | 2 | 0 | 0.00 | 1.00 | 0.00 |
| `Run_tests` | `—` | unknown | 35 | 0 | 32 | 1.00 | 0.00 | 0.00 |
| `Runtime_dual_map` | `native_vm` | unknown | 64 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Runtime_probes` | `native_vm` | unknown | 121 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Runtime_smc` | `native_vm` | unknown | 187 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Runtime_syscalls` | `native_vm` | unknown | 232 | 1 | 0 | 0.00 | 0.00 | 1.00 |
| `Sail_ast` | `random_visa_domain` | domain | 136 | 5 | 1 | 0.17 | 0.00 | 0.83 |
| `Sail_export_adapter` | `random_visa_sail_export` | adapters | 23 | 1 | 3 | 0.75 | 1.00 | 0.75 |
| `Sail_parser_adapter` | `random_visa_sail_parser` | adapters | 219 | 2 | 11 | 0.85 | 1.00 | 0.85 |
| `Seed` | `vm_ir` | unknown | 65 | 8 | 0 | 0.00 | 1.00 | 0.00 |
| `Semantic_transform` | `vm_ir` | unknown | 135 | 3 | 3 | 0.50 | 1.00 | 0.50 |
| `Superoperator` | `vm_ir` | unknown | 48 | 1 | 3 | 0.75 | 1.00 | 0.75 |
| `Synthesize_isa` | `random_visa_application` | ports | 8 | 1 | 5 | 0.83 | 1.00 | 0.83 |
| `Test_anti_analysis` | `—` | unknown | 198 | 1 | 7 | 0.88 | 0.00 | 0.12 |
| `Test_anti_pushan` | `—` | unknown | 264 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_anti_tamper_smc` | `—` | unknown | 333 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_arm64_lifter` | `—` | unknown | 152 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Test_arxiv_innovations` | `—` | unknown | 143 | 1 | 7 | 0.88 | 0.00 | 0.12 |
| `Test_assembler` | `—` | unknown | 207 | 1 | 8 | 0.89 | 0.00 | 0.11 |
| `Test_assembler_deep` | `—` | unknown | 62 | 1 | 5 | 0.83 | 0.00 | 0.17 |
| `Test_c11_emulator` | `—` | unknown | 85 | 1 | 9 | 0.90 | 0.00 | 0.10 |
| `Test_c_macro_obf` | `—` | unknown | 318 | 1 | 2 | 0.67 | 0.00 | 0.33 |
| `Test_cli` | `—` | unknown | 85 | 1 | 0 | 0.00 | 0.00 | 1.00 |
| `Test_compiler_pipeline` | `—` | unknown | 100 | 1 | 11 | 0.92 | 0.00 | 0.08 |
| `Test_cpp_emulator` | `—` | unknown | 39 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_domain_invariants` | `—` | unknown | 176 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Test_egraph_expansion` | `—` | unknown | 257 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Test_families_generation` | `—` | unknown | 219 | 1 | 8 | 0.89 | 0.00 | 0.11 |
| `Test_golden` | `—` | unknown | 30 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Test_gpu_synth` | `—` | unknown | 27 | 1 | 1 | 0.50 | 0.00 | 0.50 |
| `Test_helpers` | `—` | unknown | 89 | 2 | 0 | 0.00 | 0.00 | 1.00 |
| `Test_hw_cost` | `—` | unknown | 116 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Test_isa_grammar` | `—` | unknown | 129 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Test_metrics` | `—` | unknown | 80 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Test_multi_vlen` | `—` | unknown | 33 | 1 | 5 | 0.83 | 0.00 | 0.17 |
| `Test_multi_vm` | `—` | unknown | 124 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_native_semantics` | `—` | unknown | 283 | 0 | 6 | 1.00 | 0.00 | 0.00 |
| `Test_native_vm` | `—` | unknown | 280 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Test_properties` | `—` | unknown | 95 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_protection_config` | `—` | unknown | 73 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_rd_jit_vm` | `—` | unknown | 90 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Test_runtime_profile` | `—` | unknown | 43 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Test_sail_parser_roundtrip` | `—` | unknown | 147 | 1 | 10 | 0.91 | 0.00 | 0.09 |
| `Test_vanguard_9292` | `—` | unknown | 135 | 1 | 1 | 0.50 | 0.00 | 0.50 |
| `Test_vanguard_emulator_e2e` | `—` | unknown | 98 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_vm_ir` | `—` | unknown | 187 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Test_x86_lifter` | `—` | unknown | 174 | 1 | 4 | 0.80 | 0.00 | 0.20 |
| `Types` | `random_visa_domain` | domain | 239 | 23 | 1 | 0.04 | 0.00 | 0.96 |
| `Vanguard_9292` | `vanguard_9292` | unknown | 86 | 3 | 5 | 0.62 | 0.33 | 0.04 |
| `Vanguard_asm` | `vanguard_9292` | unknown | 144 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Vanguard_decoder` | `vanguard_9292` | unknown | 107 | 1 | 3 | 0.75 | 0.00 | 0.25 |
| `Vanguard_types` | `vanguard_9292` | unknown | 184 | 3 | 0 | 0.00 | 0.33 | 0.67 |
| `Vector_config` | `random_visa_domain` | domain | 41 | 10 | 2 | 0.17 | 0.00 | 0.83 |
| `Vector_instruction` | `random_visa_domain` | domain | 127 | 20 | 2 | 0.09 | 0.00 | 0.91 |
| `Vector_isa_spec` | `random_visa_domain` | domain | 109 | 25 | 5 | 0.17 | 0.00 | 0.83 |
| `Vm_alu_handlers` | `native_vm` | unknown | 127 | 1 | 1 | 0.50 | 1.00 | 0.50 |
| `Vm_context_emitter` | `native_vm` | unknown | 199 | 1 | 0 | 0.00 | 0.00 | 1.00 |
| `Vm_control_handlers` | `native_vm` | unknown | 121 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Vm_emitter` | `native_vm` | unknown | 351 | 11 | 11 | 0.50 | 0.00 | 0.50 |
| `Vm_eval` | `vm_ir` | unknown | 312 | 6 | 3 | 0.33 | 0.00 | 0.67 |
| `Vm_handlers_emitter` | `native_vm` | unknown | 8 | 1 | 3 | 0.75 | 1.00 | 0.75 |
| `Vm_mem_handlers` | `native_vm` | unknown | 239 | 1 | 0 | 0.00 | 1.00 | 0.00 |
| `Vm_packagers` | `protect_adapters` | adapters | 69 | 2 | 7 | 0.78 | 1.00 | 0.78 |
| `Vm_runtime_emitter` | `native_vm` | unknown | 291 | 1 | 6 | 0.86 | 0.00 | 0.14 |
| `Vm_runtime_profile` | `random_visa_domain` | domain | 19 | 3 | 2 | 0.40 | 0.00 | 0.60 |
| `Vm_transform` | `native_vm` | unknown | 276 | 2 | 3 | 0.60 | 0.00 | 0.40 |
| `X86_lifter_adapter` | `protect_adapters` | adapters | 27 | 1 | 3 | 0.75 | 1.00 | 0.75 |
| `X86_parser` | `x86_lifter` | unknown | 292 | 4 | 1 | 0.20 | 0.00 | 0.80 |

## 🔍 Architecture Issues Breakdown

| Severity | Code / Kind | Subject | Message |
|---|---|---|---|
| ℹ️ **INFO** | `hub_module` | `Run_tests` | hub/spaghetti module: Run_tests depends on 32 other modules |
| ℹ️ **INFO** | `leaky_interface` | `Arm64_lifter.Arm64_types` | leaky interface: Arm64_types.mli exports 5 types, but none are abstract. Implementation details are fully exposed to 6 clients. |
| ℹ️ **INFO** | `leaky_interface` | `C_macro_obf.C_macro_obf` | leaky interface: C_macro_obf.mli exports 2 types, but none are abstract. Implementation details are fully exposed to 5 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Mba_engine.Egraph` | leaky interface: Egraph.mli exports 2 types, but none are abstract. Implementation details are fully exposed to 3 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Mba_engine.Egraph_types` | leaky interface: Egraph_types.mli exports 2 types, but none are abstract. Implementation details are fully exposed to 3 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Native_vm.Protection_types` | leaky interface: Protection_types.mli exports 11 types, but none are abstract. Implementation details are fully exposed to 3 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Random_visa_domain.Hw_cost` | leaky interface: Hw_cost.mli exports 2 types, but none are abstract. Implementation details are fully exposed to 3 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Random_visa_domain.Sail_ast` | leaky interface: Sail_ast.mli exports 5 types, but none are abstract. Implementation details are fully exposed to 5 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Random_visa_domain.Types` | leaky interface: Types.mli exports 8 types, but none are abstract. Implementation details are fully exposed to 23 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Vm_ir.Flags` | leaky interface: Flags.mli exports 3 types, but none are abstract. Implementation details are fully exposed to 12 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Vm_ir.Ir` | leaky interface: Ir.mli exports 12 types, but none are abstract. Implementation details are fully exposed to 35 clients. |
| ℹ️ **INFO** | `leaky_interface` | `Vm_ir.Register` | leaky interface: Register.mli exports 4 types, but none are abstract. Implementation details are fully exposed to 36 clients. |
| ℹ️ **INFO** | `leaky_interface` | `X86_lifter.X86_parser` | leaky interface: X86_parser.mli exports 4 types, but none are abstract. Implementation details are fully exposed to 4 clients. |
| ℹ️ **INFO** | `zone_of_pain` | `Mba_engine.Mba` | zone of pain: Mba is rigidly concrete (A=0.00) yet heavily depended on by 10 modules (I=0.17, D=0.83) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Random_visa_domain.Sail_ast` | zone of pain: Sail_ast is rigidly concrete (A=0.00) yet heavily depended on by 5 modules (I=0.17, D=0.83) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Random_visa_domain.Types` | zone of pain: Types is rigidly concrete (A=0.00) yet heavily depended on by 23 modules (I=0.04, D=0.96) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Random_visa_domain.Vector_instruction` | zone of pain: Vector_instruction is rigidly concrete (A=0.00) yet heavily depended on by 20 modules (I=0.09, D=0.91) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Random_visa_domain.Vector_isa_spec` | zone of pain: Vector_isa_spec is rigidly concrete (A=0.00) yet heavily depended on by 25 modules (I=0.17, D=0.83) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Vm_ir.Flags` | zone of pain: Flags is rigidly concrete (A=0.00) yet heavily depended on by 12 modules (I=0.08, D=0.92) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Vm_ir.Ir` | zone of pain: Ir is rigidly concrete (A=0.00) yet heavily depended on by 35 modules (I=0.05, D=0.95) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Vm_ir.Register` | zone of pain: Register is rigidly concrete (A=0.00) yet heavily depended on by 36 modules (I=0.00, D=1.00) (domain AST / data model: benign by design) |
| ℹ️ **INFO** | `zone_of_pain` | `Vm_ir.Rns` | zone of pain: Rns is rigidly concrete (A=0.00) yet heavily depended on by 5 modules (I=0.00, D=1.00) (domain AST / data model: benign by design) |

## ✅ Clean DAG & Zero-Cycle Confirmation

- **Circular Dependencies Detected:** `0`
- **God Modules Remaining:** `0`
- **Pure Directed Acyclic Graph (DAG):** VERIFIED ✅
