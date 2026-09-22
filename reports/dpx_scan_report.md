# 🐫 DPX-OCaml: Module Architecture & Functional Pattern Report

- **Target Path:** `/Volumes/External/Code/ASGARD-5877`
- **Files Scanned:** `181`
- **Total Patterns & Findings:** `105`
- **Analysis Elapsed Time:** `0.167s`

## 📊 Breakdown by Category

| Category | Count |
|---|:---:|
| **MODULE_SYSTEM** | 14 |
| **FUNCTIONAL_IDIOM** | 11 |
| **BEHAVIORAL** | 4 |
| **TYPE_SAFETY** | 6 |
| **RESILIENCE** | 3 |
| **PRINCIPLE** | 67 |

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
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:100:1`
- **Summary:** Module 'Rolling_key' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Rolling_key' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:100:1`

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

### #9 FIRST_CLASS_MODULE on `Vm_handlers_emitter`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_handlers_emitter.ml:1:1`
- **Summary:** Module 'Vm_handlers_emitter' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'Vm_handlers_emitter' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_handlers_emitter.ml:1:1`

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

### #15 POLYMORPHIC_VARIANTS on `Cli_vanguard`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:1:1`
- **Summary:** Module 'Cli_vanguard' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_vanguard' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:1:1`

### #16 POLYMORPHIC_VARIANTS on `Cli_isa`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`
- **Summary:** Module 'Cli_isa' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_isa' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`

### #17 POLYMORPHIC_VARIANTS on `Cli_protect`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`
- **Summary:** Module 'Cli_protect' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_protect' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`

### #18 POLYMORPHIC_VARIANTS on `Cli_project`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`
- **Summary:** Module 'Cli_project' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Cli_project' adopts Polymorphic Variants (``Error, ``Error) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`

### #19 POLYMORPHIC_VARIANTS on `Vanguard_types`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`
- **Summary:** Module 'Vanguard_types' adopts Polymorphic Variants (``Corrupted_field, ``Junk_opcode) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Vanguard_types' adopts Polymorphic Variants (``Corrupted_field, ``Junk_opcode) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`

### #20 POLYMORPHIC_VARIANTS on `Vanguard_9292`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_9292.mli:1:1`
- **Summary:** Module 'Vanguard_9292' adopts Polymorphic Variants (``Dst, ``Src1) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Vanguard_9292' adopts Polymorphic Variants (``Dst, ``Src1) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_9292.mli:1:1`

### #21 POLYMORPHIC_VARIANTS on `Protection_json`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`
- **Summary:** Module 'Protection_json' adopts Polymorphic Variants (``Assoc, ``Assoc) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_json' adopts Polymorphic Variants (``Assoc, ``Assoc) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`

### #22 POLYMORPHIC_VARIANTS on `Protection_types`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_types.mli:1:1`
- **Summary:** Module 'Protection_types' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_types' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_types.mli:1:1`

### #23 POLYMORPHIC_VARIANTS on `Hardened_runtime`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/hardened_runtime.ml:1:1`
- **Summary:** Module 'Hardened_runtime' adopts Polymorphic Variants (``Darwin, ``Linux) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Hardened_runtime' adopts Polymorphic Variants (``Darwin, ``Linux) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/hardened_runtime.ml:1:1`

### #24 POLYMORPHIC_VARIANTS on `Protection_presets`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_presets.ml:1:1`
- **Summary:** Module 'Protection_presets' adopts Polymorphic Variants (``Balanced, ``Egraph) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_presets' adopts Polymorphic Variants (``Balanced, ``Egraph) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_presets.ml:1:1`

### #25 POLYMORPHIC_VARIANTS on `Protection_config`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_config.mli:1:1`
- **Summary:** Module 'Protection_config' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Protection_config' adopts Polymorphic Variants (``Egraph, ``Poly) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_config.mli:1:1`

### #26 CLOSURE_CURRYING_STRATEGY on `Profile_bottlenecks.time_it`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:29:1`
- **Summary:** Function 'time_it' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'time_it' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:29:1`

### #27 CLOSURE_CURRYING_STRATEGY on `Partitioner.partition_function`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:44:1`
- **Summary:** Function 'partition_function' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'partition_function' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:44:1`

### #28 CLOSURE_CURRYING_STRATEGY on `Semantic_transform.transform_func`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/semantic_transform.ml:137:1`
- **Summary:** Function 'transform_func' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'transform_func' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/semantic_transform.ml:137:1`

### #29 CLOSURE_CURRYING_STRATEGY on `Cfg_transform.transform`
- **Category:** `behavioral`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/cfg_transform.ml:49:1`
- **Summary:** Function 'transform' accepts higher-order strategy parameter 'f' for dynamic algorithm injection

#### Evidence Trail:
- `+75%` **[CURRIED_STRATEGY_INJECTION]** Function 'transform' accepts higher-order strategy parameter 'f' for dynamic algorithm injection -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/cfg_transform.ml:49:1`

### #30 UNCHECKED_EXCEPTION_RAISE on `Profile_bottlenecks.sample_func`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:216:1`
- **Summary:** Type Safety Audit: Function 'sample_func' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'sample_func' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:216:1`

### #31 UNCHECKED_EXCEPTION_RAISE on `Profile_bottlenecks.regs`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:332:1`
- **Summary:** Type Safety Audit: Function 'regs' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'regs' in 'Profile_bottlenecks' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:332:1`

### #32 UNCHECKED_EXCEPTION_RAISE on `Gen_crackme_vm.rng`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:53:1`
- **Summary:** Type Safety Audit: Function 'rng' in 'Gen_crackme_vm' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'rng' in 'Gen_crackme_vm' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:53:1`

### #33 UNCHECKED_EXCEPTION_RAISE on `Gen_crypto_crackme.base_config`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:75:1`
- **Summary:** Type Safety Audit: Function 'base_config' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'base_config' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:75:1`

### #34 UNCHECKED_EXCEPTION_RAISE on `Gen_crypto_crackme.asm`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:91:1`
- **Summary:** Type Safety Audit: Function 'asm' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'asm' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:91:1`

### #35 UNCHECKED_EXCEPTION_RAISE on `Gen_crypto_crackme.st`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:95:1`
- **Summary:** Type Safety Audit: Function 'st' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'st' in 'Gen_crypto_crackme' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:95:1`

### #36 DEFENSIVE_CATCH_ALL_EXN on `Profile_bottlenecks.tmp_prof_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:283:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_prof_dir' in 'Profile_bottlenecks' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_prof_dir' in 'Profile_bottlenecks' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:283:1`

### #37 DEFENSIVE_CATCH_ALL_EXN on `Cli_protect.bin_path`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:197:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'bin_path' in 'Cli_protect' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'bin_path' in 'Cli_protect' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:197:1`

### #38 DEFENSIVE_CATCH_ALL_EXN on `Cli_project.build_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:34:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'build_dir' in 'Cli_project' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'build_dir' in 'Cli_project' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:34:1`

### #39 MUTABLE_REF_OVERUSE on `Profile_bottlenecks`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Profile_bottlenecks' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Profile_bottlenecks' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:1:1`

### #40 MUTABLE_REF_OVERUSE on `Cli_project`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Cli_project' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Cli_project' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`

### #41 MUTABLE_REF_OVERUSE on `Gen_crypto_crackme`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Gen_crypto_crackme' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Gen_crypto_crackme' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`

### #42 MUTABLE_REF_OVERUSE on `Coverage_audit`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/scripts/coverage_audit.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Coverage_audit' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Coverage_audit' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/scripts/coverage_audit.ml:1:1`

### #43 MUTABLE_REF_OVERUSE on `Vanguard_asm`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Vanguard_asm' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Vanguard_asm' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`

### #44 MUTABLE_REF_OVERUSE on `Arm64_lifter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Arm64_lifter' defines 10 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Arm64_lifter' defines 10 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`

### #45 MUTABLE_REF_OVERUSE on `Partitioner`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Partitioner' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Partitioner' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/multi_vm/partitioner.ml:1:1`

### #46 MUTABLE_REF_OVERUSE on `C_expr_parser`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_parser.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_expr_parser' defines 19 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_expr_parser' defines 19 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_parser.ml:1:1`

### #47 MUTABLE_REF_OVERUSE on `C_macro_obf`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_macro_obf' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_macro_obf' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`

### #48 MUTABLE_REF_OVERUSE on `C_nanomites`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_nanomites' defines 29 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_nanomites' defines 29 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`

### #49 MUTABLE_REF_OVERUSE on `C_expr_lexer`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_lexer.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_expr_lexer' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_expr_lexer' defines 4 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_expr_lexer.ml:1:1`

### #50 MUTABLE_REF_OVERUSE on `Assembler_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Assembler_adapter' defines 8 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Assembler_adapter' defines 8 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`

### #51 MUTABLE_REF_OVERUSE on `Sail_parser_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Sail_parser_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Sail_parser_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:1:1`

### #52 MUTABLE_REF_OVERUSE on `C_trampoline_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_trampoline_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_trampoline_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml:1:1`

### #53 MUTABLE_REF_OVERUSE on `Ir_egraph`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Ir_egraph' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Ir_egraph' defines 7 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`

### #54 MUTABLE_REF_OVERUSE on `Vm_eval`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/vm_eval.mli:1:1`
- **Summary:** Functional Purity Audit: Module 'Vm_eval' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Vm_eval' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/vm_eval.mli:1:1`

### #55 MUTABLE_REF_OVERUSE on `Egraph_types`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_types.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Egraph_types' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Egraph_types' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_types.ml:1:1`

### #56 GOD_MODULE_SRP on `Cli_isa`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Cli_isa' defines 35 functions across 227 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Cli_isa' defines 35 functions across 227 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:1:1`

### #57 GOD_MODULE_SRP on `Profile_bottlenecks`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Profile_bottlenecks' defines 104 functions across 513 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Profile_bottlenecks' defines 104 functions across 513 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:1:1`

### #58 GOD_MODULE_SRP on `Cli_protect`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Cli_protect' defines 47 functions across 277 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Cli_protect' defines 47 functions across 277 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect.ml:1:1`

### #59 GOD_MODULE_SRP on `Cli_project`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Cli_project' defines 57 functions across 244 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Cli_project' defines 57 functions across 244 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/cli_project.ml:1:1`

### #60 GOD_MODULE_SRP on `Gen_crypto_crackme`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Gen_crypto_crackme' defines 36 functions across 165 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Gen_crypto_crackme' defines 36 functions across 165 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crypto_crackme.ml:1:1`

### #61 GOD_MODULE_SRP on `Vanguard_types`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Vanguard_types' defines 47 functions across 203 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Vanguard_types' defines 47 functions across 203 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:1:1`

### #62 GOD_MODULE_SRP on `Vanguard_asm`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Vanguard_asm' defines 34 functions across 152 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Vanguard_asm' defines 34 functions across 152 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:1:1`

### #63 GOD_MODULE_SRP on `Arm64_lifter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Arm64_lifter' defines 58 functions across 775 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Arm64_lifter' defines 58 functions across 775 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/arm64_lifter/arm64_lifter.ml:1:1`

### #64 GOD_MODULE_SRP on `Protection_json`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Protection_json' defines 34 functions across 295 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Protection_json' defines 34 functions across 295 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/native_vm/protection_json.ml:1:1`

### #65 GOD_MODULE_SRP on `C_macro_obf`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C_macro_obf' defines 30 functions across 233 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C_macro_obf' defines 30 functions across 233 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`

### #66 GOD_MODULE_SRP on `C_nanomites`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C_nanomites' defines 50 functions across 345 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C_nanomites' defines 50 functions across 345 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml:1:1`

### #67 GOD_MODULE_SRP on `C11_emitter_adapter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C11_emitter_adapter' defines 30 functions across 306 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C11_emitter_adapter' defines 30 functions across 306 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`

### #68 GOD_MODULE_SRP on `Assembler_adapter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Assembler_adapter' defines 57 functions across 363 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Assembler_adapter' defines 57 functions across 363 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`

### #69 GOD_MODULE_SRP on `Ir_egraph`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Ir_egraph' defines 36 functions across 199 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Ir_egraph' defines 36 functions across 199 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/ir_egraph.ml:1:1`

### #70 GOD_MODULE_SRP on `Register`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/register.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Register' defines 45 functions across 206 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Register' defines 45 functions across 206 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/register.ml:1:1`

### #71 GOD_MODULE_SRP on `Flags`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/flags.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Flags' defines 38 functions across 250 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Flags' defines 38 functions across 250 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/flags.ml:1:1`

### #72 GOD_MODULE_SRP on `Egraph_rules`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_rules.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Egraph_rules' defines 37 functions across 172 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Egraph_rules' defines 37 functions across 172 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/mba_engine/egraph_rules.ml:1:1`

### #73 CYCLOMATIC_COMPLEXITY_KISS on `Vanguard_asm.parse_ops`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:73:1`
- **Summary:** KISS Violation (High Complexity): Function 'parse_ops' in 'Vanguard_asm' has cyclomatic complexity of 12; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'parse_ops' in 'Vanguard_asm' has cyclomatic complexity of 12; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:73:1`

### #74 CYCLOMATIC_COMPLEXITY_KISS on `Assembler_adapter.res`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:87:1`
- **Summary:** KISS Violation (High Complexity): Function 'res' in 'Assembler_adapter' has cyclomatic complexity of 20; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'res' in 'Assembler_adapter' has cyclomatic complexity of 20; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:87:1`

### #75 CYCLOMATIC_COMPLEXITY_KISS on `Sail_parser_adapter.b`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:110:1`
- **Summary:** KISS Violation (High Complexity): Function 'b' in 'Sail_parser_adapter' has cyclomatic complexity of 16; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'b' in 'Sail_parser_adapter' has cyclomatic complexity of 16; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:110:1`

### #76 DUPLICATE_CODE_DRY on `Cli_vanguard.rng`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:7:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Cli_vanguard.rng, Cli_isa.rng, Cli_project.rng

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Cli_vanguard.rng, Cli_isa.rng, Cli_project.rng -> `/Volumes/External/Code/ASGARD-5877/bin/cli_vanguard.ml:7:1`

### #77 DUPLICATE_CODE_DRY on `Cli_isa.s`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:34:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 4 location(s): Cli_isa.s, Cli_protect_arm64.s, Cli_protect.s

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 4 location(s): Cli_isa.s, Cli_protect_arm64.s, Cli_protect.s -> `/Volumes/External/Code/ASGARD-5877/bin/cli_isa.ml:34:1`

### #78 DUPLICATE_CODE_DRY on `Profile_bottlenecks.bc_buf`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:37:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.bc_buf, C_trampoline_adapter.bc_buf

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.bc_buf, C_trampoline_adapter.bc_buf -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:37:1`

### #79 DUPLICATE_CODE_DRY on `Profile_bottlenecks.i`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:52:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.i, C_trampoline_adapter.i

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.i, C_trampoline_adapter.i -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:52:1`

### #80 DUPLICATE_CODE_DRY on `Profile_bottlenecks.rfind_char`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:84:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.rfind_char, C_trampoline_adapter.rfind_char

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.rfind_char, C_trampoline_adapter.rfind_char -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:84:1`

### #81 DUPLICATE_CODE_DRY on `Profile_bottlenecks.args_to_pass`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:104:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.args_to_pass, C_trampoline_adapter.args_to_pass

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.args_to_pass, C_trampoline_adapter.args_to_pass -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:104:1`

### #82 DUPLICATE_CODE_DRY on `Profile_bottlenecks.param_str`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:111:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.param_str, C_trampoline_adapter.param_str

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.param_str, C_trampoline_adapter.param_str -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:111:1`

### #83 DUPLICATE_CODE_DRY on `Profile_bottlenecks.raw_params`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:114:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.raw_params, C_trampoline_adapter.raw_params

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.raw_params, C_trampoline_adapter.raw_params -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:114:1`

### #84 DUPLICATE_CODE_DRY on `Profile_bottlenecks.tokens`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:117:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.tokens, C_trampoline_adapter.tokens

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.tokens, C_trampoline_adapter.tokens -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:117:1`

### #85 DUPLICATE_CODE_DRY on `Profile_bottlenecks.clean`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:120:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.clean, C_trampoline_adapter.clean

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.clean, C_trampoline_adapter.clean -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:120:1`

### #86 DUPLICATE_CODE_DRY on `Profile_bottlenecks.find_closing`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:128:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.find_closing, C_trampoline_adapter.find_closing

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.find_closing, C_trampoline_adapter.find_closing -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:128:1`

### #87 DUPLICATE_CODE_DRY on `Profile_bottlenecks.after_body`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:138:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.after_body, C_trampoline_adapter.after_body

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.after_body, C_trampoline_adapter.after_body -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:138:1`

### #88 DUPLICATE_CODE_DRY on `Profile_bottlenecks.full_out`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:143:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.full_out, C_trampoline_adapter.full_out

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Profile_bottlenecks.full_out, C_trampoline_adapter.full_out -> `/Volumes/External/Code/ASGARD-5877/bin/profile_bottlenecks.ml:143:1`

### #89 DUPLICATE_CODE_DRY on `Cli_protect_arm64.base_cfg`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:13:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.base_cfg, Cli_protect.base_cfg

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.base_cfg, Cli_protect.base_cfg -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:13:1`

### #90 DUPLICATE_CODE_DRY on `Cli_protect_arm64.resolved_mba_depth`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:34:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.resolved_mba_depth, Cli_protect.resolved_mba_depth

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.resolved_mba_depth, Cli_protect.resolved_mba_depth -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:34:1`

### #91 DUPLICATE_CODE_DRY on `Cli_protect_arm64.effective_cfg`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:40:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.effective_cfg, Cli_protect.effective_cfg

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.effective_cfg, Cli_protect.effective_cfg -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:40:1`

### #92 DUPLICATE_CODE_DRY on `Cli_protect_arm64.rng`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:47:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.rng, Cli_protect.rng

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.rng, Cli_protect.rng -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:47:1`

### #93 DUPLICATE_CODE_DRY on `Cli_protect_arm64.trampoline_engine`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:57:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.trampoline_engine, Cli_protect.trampoline_engine

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Cli_protect_arm64.trampoline_engine, Cli_protect.trampoline_engine -> `/Volumes/External/Code/ASGARD-5877/bin/cli_protect_arm64.ml:57:1`

### #94 DUPLICATE_CODE_DRY on `Gen_crackme_vm.out_dir`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:58:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Gen_crackme_vm.out_dir, Gen_crypto_crackme.default_out_dir, Gen_crypto_crackme.sample_cpp_path

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Gen_crackme_vm.out_dir, Gen_crypto_crackme.default_out_dir, Gen_crypto_crackme.sample_cpp_path -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:58:1`

### #95 DUPLICATE_CODE_DRY on `Gen_crackme_vm.oc_h`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:62:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_h, Gen_crypto_crackme.oc_h

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_h, Gen_crypto_crackme.oc_h -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:62:1`

### #96 DUPLICATE_CODE_DRY on `Gen_crackme_vm.oc_r`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:65:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_r, Gen_crypto_crackme.oc_r

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_r, Gen_crypto_crackme.oc_r -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:65:1`

### #97 DUPLICATE_CODE_DRY on `Gen_crackme_vm.oc_b`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:68:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_b, Gen_crypto_crackme.oc_b

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Gen_crackme_vm.oc_b, Gen_crypto_crackme.oc_b -> `/Volumes/External/Code/ASGARD-5877/bin/gen_crackme_vm.ml:68:1`

### #98 DUPLICATE_CODE_DRY on `Vanguard_types.n`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:77:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.n, Opcode_map.n

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.n, Opcode_map.n -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:77:1`

### #99 DUPLICATE_CODE_DRY on `Vanguard_types.next_state`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:116:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.next_state, Rolling_key.next_state

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.next_state, Rolling_key.next_state -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:116:1`

### #100 DUPLICATE_CODE_DRY on `Vanguard_types.w2`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:122:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.w2, Rolling_key.w2

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_types.w2, Rolling_key.w2 -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_types.ml:122:1`

### #101 DUPLICATE_CODE_DRY on `Vanguard_asm.push`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:7:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.push, Assembler_adapter.push

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.push, Assembler_adapter.push -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:7:1`

### #102 DUPLICATE_CODE_DRY on `Vanguard_asm.c`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:14:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.c, Assembler_adapter.c

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Vanguard_asm.c, Assembler_adapter.c -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_asm.ml:14:1`

### #103 DUPLICATE_CODE_DRY on `C11_emitter_adapter.tbl`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:20:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.tbl, Cpp_header_emitters.tbl

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.tbl, Cpp_header_emitters.tbl -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:20:1`

### #104 DUPLICATE_CODE_DRY on `C11_emitter_adapter.cur`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:23:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.cur, Cpp_header_emitters.cur

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.cur, Cpp_header_emitters.cur -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:23:1`

### #105 DUPLICATE_CODE_DRY on `C11_emitter_adapter.sorted`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:29:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.sorted, Cpp_header_emitters.sorted

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): C11_emitter_adapter.sorted, Cpp_header_emitters.sorted -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:29:1`
