# 🐫 DPX-OCaml: Module Architecture & Functional Pattern Report

- **Target Path:** `/Volumes/External/Code/ASGARD-5877`
- **Files Scanned:** `253`
- **Total Patterns & Findings:** `171`
- **Analysis Elapsed Time:** `0.219s`

## 📊 Breakdown by Category

| Category | Count |
|---|:---:|
| **MODULE_SYSTEM** | 15 |
| **FUNCTIONAL_IDIOM** | 38 |
| **BEHAVIORAL** | 4 |
| **TYPE_SAFETY** | 8 |
| **RESILIENCE** | 16 |
| **PRINCIPLE** | 90 |

## 📋 Detailed Pattern Findings

### #1 ABSTRACT_DATA_TYPE_INTERFACE on `Vanguard_types`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`
- **Summary:** Module 'Vanguard_types' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Vanguard_types' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`

### #2 ABSTRACT_DATA_TYPE_INTERFACE on `Ir_egraph`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`
- **Summary:** Module 'Ir_egraph' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'create'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Ir_egraph' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'create' -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`

### #3 ABSTRACT_DATA_TYPE_INTERFACE on `Egraph_types`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_types.ml:1:1`
- **Summary:** Module 'Egraph_types' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'create'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Egraph_types' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'create' -> `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_types.ml:1:1`

### #4 ABSTRACT_DATA_TYPE_INTERFACE on `Vector_config`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/domain/vector_config.ml:1:1`
- **Summary:** Module 'Vector_config' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Vector_config' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/domain/vector_config.ml:1:1`

### #5 ABSTRACT_DATA_TYPE_INTERFACE on `Generation_profile`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/domain/generation_profile.ml:1:1`
- **Summary:** Module 'Generation_profile' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Generation_profile' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/domain/generation_profile.ml:1:1`

### #6 ABSTRACT_DATA_TYPE_INTERFACE on `Rolling_key`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:102:1`
- **Summary:** Module 'Rolling_key' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Rolling_key' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:102:1`

### #7 FIRST_CLASS_MODULE on `Cli_protect_arm64`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:1:1`
- **Summary:** Module 'Cli_protect_arm64' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'Cli_protect_arm64' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:1:1`

### #8 FIRST_CLASS_MODULE on `Cli_protect`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`
- **Summary:** Module 'Cli_protect' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'Cli_protect' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`

### #9 FIRST_CLASS_MODULE on `Vm_alu_handlers`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_alu_handlers.ml:1:1`
- **Summary:** Module 'Vm_alu_handlers' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'Vm_alu_handlers' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_alu_handlers.ml:1:1`

### #10 FIRST_CLASS_MODULE on `C11_emitter_adapter`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`
- **Summary:** Module 'C11_emitter_adapter' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'C11_emitter_adapter' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`

### #11 FIRST_CLASS_MODULE on `Protect_pipeline`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/application/protect_pipeline.ml:1:1`
- **Summary:** Module 'Protect_pipeline' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'Protect_pipeline' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/lib/application/protect_pipeline.ml:1:1`

### #12 MODULE_INCLUSION_EXTENDER on `Compiler_adapter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/compiler_adapter/compiler_adapter.mli:1:1`
- **Summary:** Module 'Compiler_adapter' extends and composes functionality from 1 included module(s) (Ports.Compiler)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Compiler_adapter' extends and composes functionality from 1 included module(s) (Ports.Compiler) -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/compiler_adapter/compiler_adapter.mli:1:1`

### #13 MODULE_INCLUSION_EXTENDER on `Sail_export_adapter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_export/sail_export_adapter.mli:1:1`
- **Summary:** Module 'Sail_export_adapter' extends and composes functionality from 1 included module(s) (Ports.Sail_spec_writer)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Sail_export_adapter' extends and composes functionality from 1 included module(s) (Ports.Sail_spec_writer) -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_export/sail_export_adapter.mli:1:1`

### #14 MODULE_INCLUSION_EXTENDER on `Cpp_emitter_adapter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.mli:1:1`
- **Summary:** Module 'Cpp_emitter_adapter' extends and composes functionality from 1 included module(s) (Ports.Cpp_code_emitter)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Cpp_emitter_adapter' extends and composes functionality from 1 included module(s) (Ports.Cpp_code_emitter) -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.mli:1:1`

### #15 MODULE_INCLUSION_EXTENDER on `Rd_jit_emitter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_emitter.ml:1:1`
- **Summary:** Module 'Rd_jit_emitter' extends and composes functionality from 1 included module(s) (Rd_jit_types)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Rd_jit_emitter' extends and composes functionality from 1 included module(s) (Rd_jit_types) -> `/Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_emitter.ml:1:1`

### #16 POLYMORPHIC_VARIANTS on `Test_domain_invariants`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:1:1`
- **Summary:** Module 'Test_domain_invariants' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_domain_invariants' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:1:1`

### #17 POLYMORPHIC_VARIANTS on `Test_vm_ir`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`
- **Summary:** Module 'Test_vm_ir' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_vm_ir' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`

### #18 POLYMORPHIC_VARIANTS on `Test_protection_config`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_protection_config.ml:1:1`
- **Summary:** Module 'Test_protection_config' adopts Polymorphic Variants (``Ncfg, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_protection_config' adopts Polymorphic Variants (``Ncfg, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_protection_config.ml:1:1`

### #19 POLYMORPHIC_VARIANTS on `Test_vanguard_9292`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`
- **Summary:** Module 'Test_vanguard_9292' adopts Polymorphic Variants (``Junk_opcode, ``Unknown_opcode) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_vanguard_9292' adopts Polymorphic Variants (``Junk_opcode, ``Unknown_opcode) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`

### #20 POLYMORPHIC_VARIANTS on `Test_hw_cost`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:1:1`
- **Summary:** Module 'Test_hw_cost' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_hw_cost' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:1:1`

### #21 POLYMORPHIC_VARIANTS on `Test_gpu_synth`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_gpu_synth.ml:1:1`
- **Summary:** Module 'Test_gpu_synth' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_gpu_synth' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_gpu_synth.ml:1:1`

### #22 POLYMORPHIC_VARIANTS on `Test_families_generation`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`
- **Summary:** Module 'Test_families_generation' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_families_generation' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`

### #23 POLYMORPHIC_VARIANTS on `Test_egraph_expansion`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:1:1`
- **Summary:** Module 'Test_egraph_expansion' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_egraph_expansion' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:1:1`

### #24 POLYMORPHIC_VARIANTS on `Test_isa_grammar`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_isa_grammar.ml:1:1`
- **Summary:** Module 'Test_isa_grammar' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_isa_grammar' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_isa_grammar.ml:1:1`

### #25 POLYMORPHIC_VARIANTS on `Test_cli`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:1:1`
- **Summary:** Module 'Test_cli' adopts Polymorphic Variants (``Slow, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_cli' adopts Polymorphic Variants (``Slow, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:1:1`

### #26 POLYMORPHIC_VARIANTS on `Test_x86_lifter`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_x86_lifter.ml:1:1`
- **Summary:** Module 'Test_x86_lifter' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_x86_lifter' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_x86_lifter.ml:1:1`

### #27 POLYMORPHIC_VARIANTS on `Test_multi_vlen`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:1:1`
- **Summary:** Module 'Test_multi_vlen' adopts Polymorphic Variants (``Slow, ``Slow) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_multi_vlen' adopts Polymorphic Variants (``Slow, ``Slow) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:1:1`

### #28 POLYMORPHIC_VARIANTS on `Test_native_vm`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm.ml:1:1`
- **Summary:** Module 'Test_native_vm' adopts Polymorphic Variants (``Slow, ``Slow) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_native_vm' adopts Polymorphic Variants (``Slow, ``Slow) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm.ml:1:1`

### #29 POLYMORPHIC_VARIANTS on `Test_anti_pushan`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:1:1`
- **Summary:** Module 'Test_anti_pushan' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_anti_pushan' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:1:1`

### #30 POLYMORPHIC_VARIANTS on `Test_arxiv_innovations`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:1:1`
- **Summary:** Module 'Test_arxiv_innovations' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_arxiv_innovations' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:1:1`

### #31 POLYMORPHIC_VARIANTS on `Test_assembler`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:1:1`
- **Summary:** Module 'Test_assembler' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_assembler' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:1:1`

### #32 POLYMORPHIC_VARIANTS on `Test_anti_analysis`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`
- **Summary:** Module 'Test_anti_analysis' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_anti_analysis' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`

### #33 POLYMORPHIC_VARIANTS on `Test_runtime_profile`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_runtime_profile.ml:1:1`
- **Summary:** Module 'Test_runtime_profile' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_runtime_profile' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_runtime_profile.ml:1:1`

### #34 POLYMORPHIC_VARIANTS on `Test_metrics`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_metrics.ml:1:1`
- **Summary:** Module 'Test_metrics' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_metrics' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_metrics.ml:1:1`

### #35 POLYMORPHIC_VARIANTS on `Test_compiler_pipeline`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_compiler_pipeline.ml:1:1`
- **Summary:** Module 'Test_compiler_pipeline' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_compiler_pipeline' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_compiler_pipeline.ml:1:1`

### #36 POLYMORPHIC_VARIANTS on `Test_anti_tamper_smc`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_tamper_smc.ml:1:1`
- **Summary:** Module 'Test_anti_tamper_smc' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_anti_tamper_smc' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_tamper_smc.ml:1:1`

### #37 POLYMORPHIC_VARIANTS on `Test_arm64_lifter`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_arm64_lifter.ml:1:1`
- **Summary:** Module 'Test_arm64_lifter' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_arm64_lifter' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_arm64_lifter.ml:1:1`

### #38 POLYMORPHIC_VARIANTS on `Test_sail_parser_roundtrip`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:1:1`
- **Summary:** Module 'Test_sail_parser_roundtrip' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_sail_parser_roundtrip' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:1:1`

### #39 POLYMORPHIC_VARIANTS on `Test_assembler_deep`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler_deep.ml:1:1`
- **Summary:** Module 'Test_assembler_deep' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_assembler_deep' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler_deep.ml:1:1`

### #40 POLYMORPHIC_VARIANTS on `Test_multi_vm`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:1:1`
- **Summary:** Module 'Test_multi_vm' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_multi_vm' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:1:1`

### #41 POLYMORPHIC_VARIANTS on `Test_c_macro_obf`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`
- **Summary:** Module 'Test_c_macro_obf' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_c_macro_obf' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`

### #42 POLYMORPHIC_VARIANTS on `Test_rd_jit_vm`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_rd_jit_vm.ml:1:1`
- **Summary:** Module 'Test_rd_jit_vm' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_rd_jit_vm' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_rd_jit_vm.ml:1:1`

### #43 POLYMORPHIC_VARIANTS on `Cli_vanguard`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:1:1`
- **Summary:** Module 'Cli_vanguard' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_vanguard' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:1:1`

### #44 POLYMORPHIC_VARIANTS on `Cli_isa`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`
- **Summary:** Module 'Cli_isa' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_isa' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`

### #45 POLYMORPHIC_VARIANTS on `Cli_protect`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`
- **Summary:** Module 'Cli_protect' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_protect' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`

### #46 POLYMORPHIC_VARIANTS on `Cli_project`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`
- **Summary:** Module 'Cli_project' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_project' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`

### #47 POLYMORPHIC_VARIANTS on `Vanguard_types`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`
- **Summary:** Module 'Vanguard_types' adopts Polymorphic Variants (``Corrupted_field, ``Junk_opcode) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Vanguard_types' adopts Polymorphic Variants (``Corrupted_field, ``Junk_opcode) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`

### #48 POLYMORPHIC_VARIANTS on `Vanguard_9292`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_9292.mli:1:1`
- **Summary:** Module 'Vanguard_9292' adopts Polymorphic Variants (``Dst, ``Src1) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Vanguard_9292' adopts Polymorphic Variants (``Dst, ``Src1) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_9292.mli:1:1`

### #49 POLYMORPHIC_VARIANTS on `Protection_json`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`
- **Summary:** Module 'Protection_json' adopts Polymorphic Variants (``Assoc, ``Assoc) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_json' adopts Polymorphic Variants (``Assoc, ``Assoc) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`

### #50 POLYMORPHIC_VARIANTS on `Protection_types`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_types.mli:1:1`
- **Summary:** Module 'Protection_types' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_types' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_types.mli:1:1`

### #51 POLYMORPHIC_VARIANTS on `Runtime_syscalls`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/runtime_syscalls.ml:1:1`
- **Summary:** Module 'Runtime_syscalls' adopts Polymorphic Variants (``Darwin, ``Linux) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Runtime_syscalls' adopts Polymorphic Variants (``Darwin, ``Linux) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/runtime_syscalls.ml:1:1`

### #52 POLYMORPHIC_VARIANTS on `Protection_presets`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_presets.ml:1:1`
- **Summary:** Module 'Protection_presets' adopts Polymorphic Variants (``Balanced, ``Egraph) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_presets' adopts Polymorphic Variants (``Balanced, ``Egraph) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_presets.ml:1:1`

### #53 POLYMORPHIC_VARIANTS on `Protection_config`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_config.mli:1:1`
- **Summary:** Module 'Protection_config' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_config' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_config.mli:1:1`

### #54 CLOSURE_CURRYING_STRATEGY on `Profile_bottlenecks.time_it`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:29:1`
- **Summary:** Function 'time_it' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'time_it' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:29:1`

### #55 CLOSURE_CURRYING_STRATEGY on `Partitioner.partition_function`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:44:1`
- **Summary:** Function 'partition_function' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'partition_function' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:44:1`

### #56 CLOSURE_CURRYING_STRATEGY on `Semantic_transform.transform_func`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/semantic_transform.ml:137:1`
- **Summary:** Function 'transform_func' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'transform_func' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/semantic_transform.ml:137:1`

### #57 CLOSURE_CURRYING_STRATEGY on `Cfg_transform.transform`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/cfg_transform.ml:49:1`
- **Summary:** Function 'transform' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'transform' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/cfg_transform.ml:49:1`

### #58 UNCHECKED_EXCEPTION_RAISE on `Test_arxiv_innovations.exp`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:121:1`
- **Summary:** Type Safety Audit: Function 'exp' in 'Test_arxiv_innovations' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'exp' in 'Test_arxiv_innovations' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:121:1`

### #59 UNCHECKED_EXCEPTION_RAISE on `Test_helpers.res`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_helpers.ml:7:1`
- **Summary:** Type Safety Audit: Function 'res' in 'Test_helpers' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'res' in 'Test_helpers' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/test/test_helpers.ml:7:1`

### #60 UNCHECKED_EXCEPTION_RAISE on `Profile_bottlenecks.sample_func`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:104:1`
- **Summary:** Type Safety Audit: Function 'sample_func' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'sample_func' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:104:1`

### #61 UNCHECKED_EXCEPTION_RAISE on `Profile_bottlenecks.regs`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:220:1`
- **Summary:** Type Safety Audit: Function 'regs' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'regs' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:220:1`

### #62 UNCHECKED_EXCEPTION_RAISE on `Gen_crackme_vm.rng`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:53:1`
- **Summary:** Type Safety Audit: Function 'rng' in 'Gen_crackme_vm' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'rng' in 'Gen_crackme_vm' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:53:1`

### #63 UNCHECKED_EXCEPTION_RAISE on `Gen_crypto_crackme.base_config`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:75:1`
- **Summary:** Type Safety Audit: Function 'base_config' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'base_config' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:75:1`

### #64 UNCHECKED_EXCEPTION_RAISE on `Gen_crypto_crackme.asm`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:91:1`
- **Summary:** Type Safety Audit: Function 'asm' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'asm' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:91:1`

### #65 UNCHECKED_EXCEPTION_RAISE on `Gen_crypto_crackme.st`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:95:1`
- **Summary:** Type Safety Audit: Function 'st' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'st' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:95:1`

### #66 DEFENSIVE_CATCH_ALL_EXN on `Test_cpp_emulator.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cpp_emulator.ml:10:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cpp_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cpp_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_cpp_emulator.ml:10:1`

### #67 DEFENSIVE_CATCH_ALL_EXN on `Test_egraph_expansion.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:189:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_egraph_expansion' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_egraph_expansion' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:189:1`

### #68 DEFENSIVE_CATCH_ALL_EXN on `Test_cli.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:69:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cli' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cli' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:69:1`

### #69 DEFENSIVE_CATCH_ALL_EXN on `Test_multi_vlen.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:13:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_multi_vlen' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_multi_vlen' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:13:1`

### #70 DEFENSIVE_CATCH_ALL_EXN on `Test_anti_pushan.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:18:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_anti_pushan' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_anti_pushan' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:18:1`

### #71 DEFENSIVE_CATCH_ALL_EXN on `Test_assembler.tmp_vbc`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:146:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_vbc' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_vbc' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:146:1`

### #72 DEFENSIVE_CATCH_ALL_EXN on `Test_assembler.bad_res`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:166:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'bad_res' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'bad_res' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:166:1`

### #73 DEFENSIVE_CATCH_ALL_EXN on `Test_assembler.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:175:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:175:1`

### #74 DEFENSIVE_CATCH_ALL_EXN on `Test_anti_tamper_smc.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_tamper_smc.ml:254:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_anti_tamper_smc' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_anti_tamper_smc' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_tamper_smc.ml:254:1`

### #75 DEFENSIVE_CATCH_ALL_EXN on `Test_sail_parser_roundtrip.tmp_file`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:72:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_file' in 'Test_sail_parser_roundtrip' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_file' in 'Test_sail_parser_roundtrip' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:72:1`

### #76 DEFENSIVE_CATCH_ALL_EXN on `Test_c11_emulator.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c11_emulator.ml:46:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_c11_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_c11_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_c11_emulator.ml:46:1`

### #77 DEFENSIVE_CATCH_ALL_EXN on `Test_vanguard_emulator_e2e.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:9:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_vanguard_emulator_e2e' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_vanguard_emulator_e2e' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:9:1`

### #78 DEFENSIVE_CATCH_ALL_EXN on `Test_rd_jit_vm.out_str`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_rd_jit_vm.ml:89:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'out_str' in 'Test_rd_jit_vm' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'out_str' in 'Test_rd_jit_vm' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_rd_jit_vm.ml:89:1`

### #79 DEFENSIVE_CATCH_ALL_EXN on `Profile_bottlenecks.tmp_prof_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:171:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_prof_dir' in 'Profile_bottlenecks' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_prof_dir' in 'Profile_bottlenecks' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:171:1`

### #80 DEFENSIVE_CATCH_ALL_EXN on `Cli_protect.bin_path`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:202:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'bin_path' in 'Cli_protect' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'bin_path' in 'Cli_protect' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:202:1`

### #81 DEFENSIVE_CATCH_ALL_EXN on `Cli_project.build_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:34:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'build_dir' in 'Cli_project' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'build_dir' in 'Cli_project' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:34:1`

### #82 MUTABLE_REF_OVERUSE on `Test_c_macro_obf`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Test_c_macro_obf' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Test_c_macro_obf' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`

### #83 MUTABLE_REF_OVERUSE on `Cli_project`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Cli_project' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Cli_project' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`

### #84 MUTABLE_REF_OVERUSE on `Gen_crypto_crackme`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Gen_crypto_crackme' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Gen_crypto_crackme' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`

### #85 MUTABLE_REF_OVERUSE on `Coverage_audit`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/scripts/coverage_audit.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Coverage_audit' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Coverage_audit' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/scripts/coverage_audit.ml:1:1`

### #86 MUTABLE_REF_OVERUSE on `Vanguard_asm`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Vanguard_asm' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Vanguard_asm' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`

### #87 MUTABLE_REF_OVERUSE on `Arm64_lifter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Arm64_lifter' defines 10 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Arm64_lifter' defines 10 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`

### #88 MUTABLE_REF_OVERUSE on `Partitioner`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Partitioner' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Partitioner' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:1:1`

### #89 MUTABLE_REF_OVERUSE on `C_expr_parser`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_parser.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_expr_parser' defines 19 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_expr_parser' defines 19 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_parser.ml:1:1`

### #90 MUTABLE_REF_OVERUSE on `C_macro_obf`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_macro_obf' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_macro_obf' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`

### #91 MUTABLE_REF_OVERUSE on `C_nanomites`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_nanomites' defines 29 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_nanomites' defines 29 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`

### #92 MUTABLE_REF_OVERUSE on `C_expr_lexer`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_lexer.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_expr_lexer' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_expr_lexer' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_lexer.ml:1:1`

### #93 MUTABLE_REF_OVERUSE on `Assembler_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Assembler_adapter' defines 8 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Assembler_adapter' defines 8 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`

### #94 MUTABLE_REF_OVERUSE on `Sail_parser_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Sail_parser_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Sail_parser_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:1:1`

### #95 MUTABLE_REF_OVERUSE on `C_trampoline_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_trampoline_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_trampoline_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml:1:1`

### #96 MUTABLE_REF_OVERUSE on `Ir_egraph`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Ir_egraph' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Ir_egraph' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`

### #97 MUTABLE_REF_OVERUSE on `Vm_eval`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/vm_eval.mli:1:1`
- **Summary:** Functional Purity Audit: Module 'Vm_eval' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Vm_eval' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/vm_eval.mli:1:1`

### #98 MUTABLE_REF_OVERUSE on `Egraph_types`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_types.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Egraph_types' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Egraph_types' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_types.ml:1:1`

### #99 GOD_MODULE_SRP on `Test_vm_ir`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_vm_ir' defines 44 functions across 220 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_vm_ir' defines 44 functions across 220 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`

### #100 GOD_MODULE_SRP on `Test_vanguard_9292`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_vanguard_9292' defines 39 functions across 150 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_vanguard_9292' defines 39 functions across 150 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`

### #101 GOD_MODULE_SRP on `Test_families_generation`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_families_generation' defines 37 functions across 233 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_families_generation' defines 37 functions across 233 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`

### #102 GOD_MODULE_SRP on `Test_egraph_expansion`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_egraph_expansion' defines 62 functions across 279 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_egraph_expansion' defines 62 functions across 279 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:1:1`

### #103 GOD_MODULE_SRP on `Test_anti_pushan`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_anti_pushan' defines 53 functions across 282 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_anti_pushan' defines 53 functions across 282 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:1:1`

### #104 GOD_MODULE_SRP on `Test_arxiv_innovations`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_arxiv_innovations' defines 38 functions across 161 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_arxiv_innovations' defines 38 functions across 161 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:1:1`

### #105 GOD_MODULE_SRP on `Test_anti_analysis`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_anti_analysis' defines 56 functions across 225 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_anti_analysis' defines 56 functions across 225 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`

### #106 GOD_MODULE_SRP on `Test_compiler_pipeline`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_compiler_pipeline.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_compiler_pipeline' defines 37 functions across 114 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_compiler_pipeline' defines 37 functions across 114 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_compiler_pipeline.ml:1:1`

### #107 GOD_MODULE_SRP on `Test_anti_tamper_smc`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_tamper_smc.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_anti_tamper_smc' defines 31 functions across 377 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_anti_tamper_smc' defines 31 functions across 377 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_tamper_smc.ml:1:1`

### #108 GOD_MODULE_SRP on `Test_multi_vm`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_multi_vm' defines 35 functions across 137 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_multi_vm' defines 35 functions across 137 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:1:1`

### #109 GOD_MODULE_SRP on `Test_c_macro_obf`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_c_macro_obf' defines 50 functions across 364 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_c_macro_obf' defines 50 functions across 364 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`

### #110 GOD_MODULE_SRP on `Cli_isa`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Cli_isa' defines 35 functions across 227 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Cli_isa' defines 35 functions across 227 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`

### #111 GOD_MODULE_SRP on `Profile_bottlenecks`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Profile_bottlenecks' defines 78 functions across 401 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Profile_bottlenecks' defines 78 functions across 401 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:1:1`

### #112 GOD_MODULE_SRP on `Cli_protect`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Cli_protect' defines 47 functions across 282 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Cli_protect' defines 47 functions across 282 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`

### #113 GOD_MODULE_SRP on `Cli_project`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Cli_project' defines 57 functions across 244 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Cli_project' defines 57 functions across 244 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`

### #114 GOD_MODULE_SRP on `Gen_crypto_crackme`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Gen_crypto_crackme' defines 36 functions across 165 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Gen_crypto_crackme' defines 36 functions across 165 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`

### #115 GOD_MODULE_SRP on `Vanguard_types`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Vanguard_types' defines 48 functions across 205 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Vanguard_types' defines 48 functions across 205 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`

### #116 GOD_MODULE_SRP on `Vanguard_asm`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Vanguard_asm' defines 34 functions across 152 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Vanguard_asm' defines 34 functions across 152 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`

### #117 GOD_MODULE_SRP on `Arm64_lifter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Arm64_lifter' defines 30 functions across 200 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Arm64_lifter' defines 30 functions across 200 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`

### #118 GOD_MODULE_SRP on `Protection_json`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Protection_json' defines 34 functions across 295 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Protection_json' defines 34 functions across 295 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`

### #119 GOD_MODULE_SRP on `C_macro_obf`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C_macro_obf' defines 30 functions across 233 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C_macro_obf' defines 30 functions across 233 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`

### #120 GOD_MODULE_SRP on `C_nanomites`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C_nanomites' defines 50 functions across 345 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C_nanomites' defines 50 functions across 345 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`

### #121 GOD_MODULE_SRP on `C11_emitter_adapter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C11_emitter_adapter' defines 30 functions across 306 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C11_emitter_adapter' defines 30 functions across 306 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`

### #122 GOD_MODULE_SRP on `Assembler_adapter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Assembler_adapter' defines 57 functions across 363 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Assembler_adapter' defines 57 functions across 363 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`

### #123 GOD_MODULE_SRP on `Ir_egraph`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Ir_egraph' defines 36 functions across 199 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Ir_egraph' defines 36 functions across 199 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`

### #124 GOD_MODULE_SRP on `Register`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/register.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Register' defines 45 functions across 206 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Register' defines 45 functions across 206 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/register.ml:1:1`

### #125 GOD_MODULE_SRP on `Flags`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/flags.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Flags' defines 38 functions across 250 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Flags' defines 38 functions across 250 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/flags.ml:1:1`

### #126 GOD_MODULE_SRP on `Egraph_rules`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_rules.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Egraph_rules' defines 37 functions across 172 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Egraph_rules' defines 37 functions across 172 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_rules.ml:1:1`

### #127 CYCLOMATIC_COMPLEXITY_KISS on `Vanguard_asm.parse_ops`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:73:1`
- **Summary:** KISS Violation (High Complexity): Function 'parse_ops' in 'Vanguard_asm' has cyclomatic complexity of 12; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'parse_ops' in 'Vanguard_asm' has cyclomatic complexity of 12; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:73:1`

### #128 CYCLOMATIC_COMPLEXITY_KISS on `Assembler_adapter.res`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:87:1`
- **Summary:** KISS Violation (High Complexity): Function 'res' in 'Assembler_adapter' has cyclomatic complexity of 20; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'res' in 'Assembler_adapter' has cyclomatic complexity of 20; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:87:1`

### #129 CYCLOMATIC_COMPLEXITY_KISS on `Sail_parser_adapter.b`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:110:1`
- **Summary:** KISS Violation (High Complexity): Function 'b' in 'Sail_parser_adapter' has cyclomatic complexity of 16; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'b' in 'Sail_parser_adapter' has cyclomatic complexity of 16; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:110:1`

### #130 DUPLICATE_CODE_DRY on `Test_domain_invariants.vd`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:77:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vd, Assembler_adapter.vd

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vd, Assembler_adapter.vd -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:77:1`

### #131 DUPLICATE_CODE_DRY on `Test_domain_invariants.funct3`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:78:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.funct3, Vector_isa_spec.funct3

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.funct3, Vector_isa_spec.funct3 -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:78:1`

### #132 DUPLICATE_CODE_DRY on `Test_domain_invariants.vs1`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:79:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs1, Assembler_adapter.vs1

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs1, Assembler_adapter.vs1 -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:79:1`

### #133 DUPLICATE_CODE_DRY on `Test_domain_invariants.vs2`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:80:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs2, Assembler_adapter.vs2

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs2, Assembler_adapter.vs2 -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:80:1`

### #134 DUPLICATE_CODE_DRY on `Test_domain_invariants.vm`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:81:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vm, Assembler_adapter.vm

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vm, Assembler_adapter.vm -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:81:1`

### #135 DUPLICATE_CODE_DRY on `Test_protection_config.asm`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_protection_config.ml:57:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 5 location(s): Test_protection_config.asm, Test_x86_lifter.asm, Test_native_vm.asm

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 5 location(s): Test_protection_config.asm, Test_x86_lifter.asm, Test_native_vm.asm -> `/Volumes/External/Code/ASGARD-5877/test/test_protection_config.ml:57:1`

### #136 DUPLICATE_CODE_DRY on `Test_vanguard_9292.prop_vanguard_roundtrip`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:114:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 4 location(s): Test_vanguard_9292.prop_vanguard_roundtrip, Test_properties.prop_no_encoding_collisions, Test_properties.prop_sail_roundtrip_identity

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 4 location(s): Test_vanguard_9292.prop_vanguard_roundtrip, Test_properties.prop_no_encoding_collisions, Test_properties.prop_sail_roundtrip_identity -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:114:1`

### #137 DUPLICATE_CODE_DRY on `Test_hw_cost.inst1`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:44:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Test_hw_cost.inst1, Test_assembler.inst_vv, Test_assembler_deep.inst1

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Test_hw_cost.inst1, Test_assembler.inst_vv, Test_assembler_deep.inst1 -> `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:44:1`

### #138 DUPLICATE_CODE_DRY on `Test_families_generation.by_base`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:27:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 5 location(s): Test_families_generation.by_base, Test_families_generation.weights, Test_properties.by_f6

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 5 location(s): Test_families_generation.by_base, Test_families_generation.weights, Test_properties.by_f6 -> `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:27:1`

### #139 DUPLICATE_CODE_DRY on `Test_egraph_expansion.block`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:126:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.block, Test_anti_analysis.block

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.block, Test_anti_analysis.block -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:126:1`

### #140 DUPLICATE_CODE_DRY on `Test_egraph_expansion.tmp_dir`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:189:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.tmp_dir, Test_anti_tamper_smc.tmp_dir

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.tmp_dir, Test_anti_tamper_smc.tmp_dir -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:189:1`

### #141 DUPLICATE_CODE_DRY on `Test_egraph_expansion.comp_status`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:247:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.comp_status, Test_anti_tamper_smc.comp_status

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.comp_status, Test_anti_tamper_smc.comp_status -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:247:1`

### #142 DUPLICATE_CODE_DRY on `Test_egraph_expansion.out_buf`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:251:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.out_buf, Test_anti_tamper_smc.out_buf

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion.out_buf, Test_anti_tamper_smc.out_buf -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:251:1`

### #143 DUPLICATE_CODE_DRY on `Test_egraph_expansion._`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:257:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion._, Test_anti_tamper_smc._

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_egraph_expansion._, Test_anti_tamper_smc._ -> `/Volumes/External/Code/ASGARD-5877/test/test_egraph_expansion.ml:257:1`

### #144 DUPLICATE_CODE_DRY on `Test_cli.buf`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:3:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Test_cli.buf, Test_assembler.buf, Test_c11_emulator.buf

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Test_cli.buf, Test_assembler.buf, Test_c11_emulator.buf -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:3:1`

### #145 DUPLICATE_CODE_DRY on `Test_anti_pushan.out_buf`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:39:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Test_anti_pushan.out_buf, Test_helpers.out_buf, Test_vanguard_emulator_e2e.out_buf

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Test_anti_pushan.out_buf, Test_helpers.out_buf, Test_vanguard_emulator_e2e.out_buf -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_pushan.ml:39:1`

### #146 DUPLICATE_CODE_DRY on `Test_arxiv_innovations.f_scrambled`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:55:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_arxiv_innovations.f_scrambled, Test_arxiv_innovations.f_s

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_arxiv_innovations.f_scrambled, Test_arxiv_innovations.f_s -> `/Volumes/External/Code/ASGARD-5877/test/test_arxiv_innovations.ml:55:1`

### #147 DUPLICATE_CODE_DRY on `Test_assembler.status`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:209:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Test_assembler.status, Test_c11_emulator.status, Test_vanguard_emulator_e2e.status

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Test_assembler.status, Test_c11_emulator.status, Test_vanguard_emulator_e2e.status -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:209:1`

### #148 DUPLICATE_CODE_DRY on `Test_multi_vm.asm`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:95:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_multi_vm.asm, Test_rd_jit_vm.asm

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_multi_vm.asm, Test_rd_jit_vm.asm -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:95:1`

### #149 DUPLICATE_CODE_DRY on `Test_multi_vm.oc_h`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:113:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_multi_vm.oc_h, Test_rd_jit_vm.oc_h

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_multi_vm.oc_h, Test_rd_jit_vm.oc_h -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:113:1`

### #150 DUPLICATE_CODE_DRY on `Test_multi_vm.oc_r`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:118:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_multi_vm.oc_r, Test_rd_jit_vm.oc_r

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_multi_vm.oc_r, Test_rd_jit_vm.oc_r -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vm.ml:118:1`

### #151 DUPLICATE_CODE_DRY on `Test_vanguard_emulator_e2e.oc`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:26:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_vanguard_emulator_e2e.oc, Cli_vanguard.oc

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_vanguard_emulator_e2e.oc, Cli_vanguard.oc -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:26:1`

### #152 DUPLICATE_CODE_DRY on `Test_vanguard_emulator_e2e.oc_r`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:59:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_vanguard_emulator_e2e.oc_r, Cli_vanguard.oc_r

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_vanguard_emulator_e2e.oc_r, Cli_vanguard.oc_r -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:59:1`

### #153 DUPLICATE_CODE_DRY on `Test_c_macro_obf.found`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:9:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_c_macro_obf.found, C_macro_header.found

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_c_macro_obf.found, C_macro_header.found -> `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:9:1`

### #154 DUPLICATE_CODE_DRY on `Cli_vanguard.rng`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:7:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Cli_vanguard.rng, Cli_isa.rng, Cli_project.rng

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Cli_vanguard.rng, Cli_isa.rng, Cli_project.rng -> `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:7:1`

### #155 DUPLICATE_CODE_DRY on `Cli_isa.s`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:34:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 4 location(s): Cli_isa.s, Cli_protect_arm64.s, Cli_protect.s

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 4 location(s): Cli_isa.s, Cli_protect_arm64.s, Cli_protect.s -> `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:34:1`

### #156 DUPLICATE_CODE_DRY on `Cli_protect_arm64.base_cfg`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:12:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.base_cfg, Cli_protect.base_cfg

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.base_cfg, Cli_protect.base_cfg -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:12:1`

### #157 DUPLICATE_CODE_DRY on `Cli_protect_arm64.resolved_mba_depth`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:33:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.resolved_mba_depth, Cli_protect.resolved_mba_depth

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.resolved_mba_depth, Cli_protect.resolved_mba_depth -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:33:1`

### #158 DUPLICATE_CODE_DRY on `Cli_protect_arm64.effective_cfg`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:39:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.effective_cfg, Cli_protect.effective_cfg

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.effective_cfg, Cli_protect.effective_cfg -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:39:1`

### #159 DUPLICATE_CODE_DRY on `Cli_protect_arm64.rng`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:46:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.rng, Cli_protect.rng

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.rng, Cli_protect.rng -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:46:1`

### #160 DUPLICATE_CODE_DRY on `Cli_protect_arm64.trampoline_engine`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:62:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.trampoline_engine, Cli_protect.trampoline_engine

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.trampoline_engine, Cli_protect.trampoline_engine -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:62:1`

### #161 DUPLICATE_CODE_DRY on `Gen_crackme_vm.out_dir`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:58:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Gen_crackme_vm.out_dir, Gen_crypto_crackme.default_out_dir, Gen_crypto_crackme.sample_cpp_path

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Gen_crackme_vm.out_dir, Gen_crypto_crackme.default_out_dir, Gen_crypto_crackme.sample_cpp_path -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:58:1`

### #162 DUPLICATE_CODE_DRY on `Gen_crackme_vm.oc_h`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:62:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_h, Gen_crypto_crackme.oc_h

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_h, Gen_crypto_crackme.oc_h -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:62:1`

### #163 DUPLICATE_CODE_DRY on `Gen_crackme_vm.oc_r`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:65:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_r, Gen_crypto_crackme.oc_r

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_r, Gen_crypto_crackme.oc_r -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:65:1`

### #164 DUPLICATE_CODE_DRY on `Gen_crackme_vm.oc_b`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:68:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_b, Gen_crypto_crackme.oc_b

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_b, Gen_crypto_crackme.oc_b -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:68:1`

### #165 DUPLICATE_CODE_DRY on `Vanguard_types.n`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:77:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.n, Opcode_map.n

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.n, Opcode_map.n -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:77:1`

### #166 DUPLICATE_CODE_DRY on `Vanguard_types.next_state`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:118:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.next_state, Rolling_key.next_state

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.next_state, Rolling_key.next_state -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:118:1`

### #167 DUPLICATE_CODE_DRY on `Vanguard_types.w2`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:124:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.w2, Rolling_key.w2

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.w2, Rolling_key.w2 -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:124:1`

### #168 DUPLICATE_CODE_DRY on `Vanguard_asm.push`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:7:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.push, Assembler_adapter.push

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.push, Assembler_adapter.push -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:7:1`

### #169 DUPLICATE_CODE_DRY on `Vanguard_asm.c`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:14:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.c, Assembler_adapter.c

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.c, Assembler_adapter.c -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:14:1`

### #170 DUPLICATE_CODE_DRY on `C11_emitter_adapter.cur`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:23:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.cur, Cpp_header_emitters.cur

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.cur, Cpp_header_emitters.cur -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:23:1`

### #171 DUPLICATE_CODE_DRY on `C11_emitter_adapter.sorted`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:29:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.sorted, Cpp_header_emitters.sorted

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.sorted, Cpp_header_emitters.sorted -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:29:1`
