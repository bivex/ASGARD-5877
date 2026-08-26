# 🐫 DPX-OCaml: Module Architecture & Functional Pattern Report

- **Target Path:** `/Volumes/External/Code/ASGARD-5877`
- **Files Scanned:** `96`
- **Total Patterns & Findings:** `73`
- **Analysis Elapsed Time:** `0.051s`

## 📊 Breakdown by Category

| Category | Count |
|---|:---:|
| **MODULE_SYSTEM** | 6 |
| **FUNCTIONAL_IDIOM** | 17 |
| **TYPE_SAFETY** | 8 |
| **RESILIENCE** | 13 |
| **PRINCIPLE** | 29 |

## 📋 Detailed Pattern Findings

### #1 ABSTRACT_DATA_TYPE_INTERFACE on `Vector_config`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/domain/vector_config.ml:1:1`
- **Summary:** Module 'Vector_config' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Vector_config' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/domain/vector_config.ml:1:1`

### #2 ABSTRACT_DATA_TYPE_INTERFACE on `Generation_profile`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/domain/generation_profile.ml:1:1`
- **Summary:** Module 'Generation_profile' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make'

#### Evidence Trail:
- `+80%` **[ABSTRACT_DATA_TYPE_SIGNATURE]** Module 'Generation_profile' encapsulates Abstract Data Type (ADT) via primary type `t` with constructor 'make' -> `/Volumes/External/Code/ASGARD-5877/lib/domain/generation_profile.ml:1:1`

### #3 FIRST_CLASS_MODULE on `C11_emitter_adapter`
- **Category:** `module_system`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`
- **Summary:** Module 'C11_emitter_adapter' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection

#### Evidence Trail:
- `+85%` **[FIRST_CLASS_MODULE_DISPATCH]** Module 'C11_emitter_adapter' utilizes First-Class Modules for dynamic runtime dispatch and pluggable strategy injection -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:1:1`

### #4 MODULE_INCLUSION_EXTENDER on `Compiler_adapter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/compiler_adapter/compiler_adapter.mli:1:1`
- **Summary:** Module 'Compiler_adapter' extends and composes functionality from 1 included module(s) (Ports.Compiler)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Compiler_adapter' extends and composes functionality from 1 included module(s) (Ports.Compiler) -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/compiler_adapter/compiler_adapter.mli:1:1`

### #5 MODULE_INCLUSION_EXTENDER on `Sail_export_adapter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_export/sail_export_adapter.mli:1:1`
- **Summary:** Module 'Sail_export_adapter' extends and composes functionality from 1 included module(s) (Ports.Sail_spec_writer)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Sail_export_adapter' extends and composes functionality from 1 included module(s) (Ports.Sail_spec_writer) -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_export/sail_export_adapter.mli:1:1`

### #6 MODULE_INCLUSION_EXTENDER on `Cpp_emitter_adapter`
- **Category:** `module_system`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.mli:1:1`
- **Summary:** Module 'Cpp_emitter_adapter' extends and composes functionality from 1 included module(s) (Ports.Cpp_code_emitter)

#### Evidence Trail:
- `+80%` **[MODULE_INCLUSION_EXTENSION]** Module 'Cpp_emitter_adapter' extends and composes functionality from 1 included module(s) (Ports.Cpp_code_emitter) -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.mli:1:1`

### #7 POLYMORPHIC_VARIANTS on `Test_domain_invariants`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:1:1`
- **Summary:** Module 'Test_domain_invariants' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_domain_invariants' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:1:1`

### #8 POLYMORPHIC_VARIANTS on `Test_vm_ir`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`
- **Summary:** Module 'Test_vm_ir' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_vm_ir' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`

### #9 POLYMORPHIC_VARIANTS on `Test_vanguard_9292`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`
- **Summary:** Module 'Test_vanguard_9292' adopts Polymorphic Variants (``Junk_opcode, ``Unknown_opcode) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_vanguard_9292' adopts Polymorphic Variants (``Junk_opcode, ``Unknown_opcode) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`

### #10 POLYMORPHIC_VARIANTS on `Test_hw_cost`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:1:1`
- **Summary:** Module 'Test_hw_cost' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_hw_cost' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:1:1`

### #11 POLYMORPHIC_VARIANTS on `Test_native_vm_and_metrics`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:1:1`
- **Summary:** Module 'Test_native_vm_and_metrics' adopts Polymorphic Variants (``Quick, ``Slow) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_native_vm_and_metrics' adopts Polymorphic Variants (``Quick, ``Slow) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:1:1`

### #12 POLYMORPHIC_VARIANTS on `Test_families_generation`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`
- **Summary:** Module 'Test_families_generation' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_families_generation' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`

### #13 POLYMORPHIC_VARIANTS on `Test_isa_grammar`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_isa_grammar.ml:1:1`
- **Summary:** Module 'Test_isa_grammar' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_isa_grammar' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_isa_grammar.ml:1:1`

### #14 POLYMORPHIC_VARIANTS on `Test_cli`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:1:1`
- **Summary:** Module 'Test_cli' adopts Polymorphic Variants (``Slow, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_cli' adopts Polymorphic Variants (``Slow, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:1:1`

### #15 POLYMORPHIC_VARIANTS on `Test_x86_lifter`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_x86_lifter.ml:1:1`
- **Summary:** Module 'Test_x86_lifter' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_x86_lifter' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_x86_lifter.ml:1:1`

### #16 POLYMORPHIC_VARIANTS on `Test_multi_vlen`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:1:1`
- **Summary:** Module 'Test_multi_vlen' adopts Polymorphic Variants (``Slow, ``Slow) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_multi_vlen' adopts Polymorphic Variants (``Slow, ``Slow) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:1:1`

### #17 POLYMORPHIC_VARIANTS on `Test_assembler`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:1:1`
- **Summary:** Module 'Test_assembler' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_assembler' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:1:1`

### #18 POLYMORPHIC_VARIANTS on `Test_anti_analysis`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`
- **Summary:** Module 'Test_anti_analysis' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_anti_analysis' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`

### #19 POLYMORPHIC_VARIANTS on `Test_sail_parser_roundtrip`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:1:1`
- **Summary:** Module 'Test_sail_parser_roundtrip' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_sail_parser_roundtrip' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:1:1`

### #20 POLYMORPHIC_VARIANTS on `Test_assembler_deep`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler_deep.ml:1:1`
- **Summary:** Module 'Test_assembler_deep' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_assembler_deep' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler_deep.ml:1:1`

### #21 POLYMORPHIC_VARIANTS on `Test_c_macro_obf`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`
- **Summary:** Module 'Test_c_macro_obf' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Test_c_macro_obf' adopts Polymorphic Variants (``Quick, ``Quick) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/test/test_c_macro_obf.ml:1:1`

### #22 POLYMORPHIC_VARIANTS on `Main`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/main.ml:1:1`
- **Summary:** Module 'Main' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Main' adopts Polymorphic Variants (``Error, ``Ok) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/bin/main.ml:1:1`

### #23 POLYMORPHIC_VARIANTS on `Vanguard_9292`
- **Category:** `functional_idiom`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_9292.mli:1:1`
- **Summary:** Module 'Vanguard_9292' adopts Polymorphic Variants (``Dst, ``Src1) providing open tag subtyping without nominal declarations

#### Evidence Trail:
- `+80%` **[POLYMORPHIC_OPEN_VARIANTS]** Module 'Vanguard_9292' adopts Polymorphic Variants (``Dst, ``Src1) providing open tag subtyping without nominal declarations -> `/Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_9292.mli:1:1`

### #24 UNCHECKED_EXCEPTION_RAISE on `Test_hw_cost.spec_with`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:3:1`
- **Summary:** Type Safety Audit: Function 'spec_with' in 'Test_hw_cost' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'spec_with' in 'Test_hw_cost' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:3:1`

### #25 UNCHECKED_EXCEPTION_RAISE on `Test_cli.cur`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:22:1`
- **Summary:** Type Safety Audit: Function 'cur' in 'Test_cli' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'cur' in 'Test_cli' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:22:1`

### #26 UNCHECKED_EXCEPTION_RAISE on `Test_helpers.res`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_helpers.ml:7:1`
- **Summary:** Type Safety Audit: Function 'res' in 'Test_helpers' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead

#### Evidence Trail:
- `+80%` **[UNCHECKED_EXCEPTION_THROW]** Type Safety Audit: Function 'res' in 'Test_helpers' throws unhandled runtime exception (`failwith`/`raise`); return typed `Result.t` or `Option.t` instead -> `/Volumes/External/Code/ASGARD-5877/test/test_helpers.ml:7:1`

### #27 DEFENSIVE_CATCH_ALL_EXN on `Test_cpp_emulator.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cpp_emulator.ml:10:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cpp_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cpp_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_cpp_emulator.ml:10:1`

### #28 DEFENSIVE_CATCH_ALL_EXN on `Test_native_vm_and_metrics.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:116:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_native_vm_and_metrics' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_native_vm_and_metrics' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:116:1`

### #29 DEFENSIVE_CATCH_ALL_EXN on `Test_cli.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:68:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cli' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_cli' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:68:1`

### #30 DEFENSIVE_CATCH_ALL_EXN on `Test_multi_vlen.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:13:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_multi_vlen' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_multi_vlen' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_multi_vlen.ml:13:1`

### #31 DEFENSIVE_CATCH_ALL_EXN on `Test_assembler.tmp_vbc`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:146:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_vbc' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_vbc' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:146:1`

### #32 DEFENSIVE_CATCH_ALL_EXN on `Test_assembler.bad_res`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:166:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'bad_res' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'bad_res' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:166:1`

### #33 DEFENSIVE_CATCH_ALL_EXN on `Test_assembler.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:175:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_assembler' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_assembler.ml:175:1`

### #34 DEFENSIVE_CATCH_ALL_EXN on `Test_sail_parser_roundtrip.tmp_file`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:72:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_file' in 'Test_sail_parser_roundtrip' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_file' in 'Test_sail_parser_roundtrip' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:72:1`

### #35 DEFENSIVE_CATCH_ALL_EXN on `Test_c11_emulator.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_c11_emulator.ml:46:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_c11_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_c11_emulator' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_c11_emulator.ml:46:1`

### #36 DEFENSIVE_CATCH_ALL_EXN on `Test_vanguard_emulator_e2e.tmp_dir`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:9:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_vanguard_emulator_e2e' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'tmp_dir' in 'Test_vanguard_emulator_e2e' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:9:1`

### #37 DEFENSIVE_CATCH_ALL_EXN on `Main.bin_path`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/main.ml:495:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'bin_path' in 'Main' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'bin_path' in 'Main' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/main.ml:495:1`

### #38 DEFENSIVE_CATCH_ALL_EXN on `Main.pkg`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/main.ml:375:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'pkg' in 'Main' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'pkg' in 'Main' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/bin/main.ml:375:1`

### #39 DEFENSIVE_CATCH_ALL_EXN on `C_macro_obf.d`
- **Category:** `resilience`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:282:1`
- **Summary:** Resilience Smell (Defensive Catch-All): Function 'd' in 'C_macro_obf' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only

#### Evidence Trail:
- `+85%` **[DEFENSIVE_CATCH_ALL_SWALLOW]** Resilience Smell (Defensive Catch-All): Function 'd' in 'C_macro_obf' swallows all exceptions (`with _ -> ...`); catch specific expected exceptions only -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:282:1`

### #40 MUTABLE_REF_OVERUSE on `C_macro_obf`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'C_macro_obf' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'C_macro_obf' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`

### #41 MUTABLE_REF_OVERUSE on `Assembler_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Assembler_adapter' defines 8 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Assembler_adapter' defines 8 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`

### #42 MUTABLE_REF_OVERUSE on `Sail_parser_adapter`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:1:1`
- **Summary:** Functional Purity Audit: Module 'Sail_parser_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Sail_parser_adapter' defines 5 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:1:1`

### #43 MUTABLE_REF_OVERUSE on `Vm_eval`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/vm_eval.mli:1:1`
- **Summary:** Functional Purity Audit: Module 'Vm_eval' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators

#### Evidence Trail:
- `+75%` **[MUTABLE_STATE_OVERUSE]** Functional Purity Audit: Module 'Vm_eval' defines 6 mutable references / fields, breaking immutability; favor pure recursive accumulators -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/vm_eval.mli:1:1`

### #44 PHYSICAL_EQUALITY_SMELL on `Test_sail_parser_roundtrip.NUM_VREGS`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:12:1`
- **Summary:** Type Safety Hazard (Physical Equality): Function 'NUM_VREGS' in 'Test_sail_parser_roundtrip' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs

#### Evidence Trail:
- `+80%` **[PHYSICAL_EQUALITY_COMPARISON]** Type Safety Hazard (Physical Equality): Function 'NUM_VREGS' in 'Test_sail_parser_roundtrip' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs -> `/Volumes/External/Code/ASGARD-5877/test/test_sail_parser_roundtrip.ml:12:1`

### #45 PHYSICAL_EQUALITY_SMELL on `C_macro_obf.add`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:42:1`
- **Summary:** Type Safety Hazard (Physical Equality): Function 'add' in 'C_macro_obf' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs

#### Evidence Trail:
- `+80%` **[PHYSICAL_EQUALITY_COMPARISON]** Type Safety Hazard (Physical Equality): Function 'add' in 'C_macro_obf' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:42:1`

### #46 PHYSICAL_EQUALITY_SMELL on `C11_emitter_adapter.expr`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:91:1`
- **Summary:** Type Safety Hazard (Physical Equality): Function 'expr' in 'C11_emitter_adapter' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs

#### Evidence Trail:
- `+80%` **[PHYSICAL_EQUALITY_COMPARISON]** Type Safety Hazard (Physical Equality): Function 'expr' in 'C11_emitter_adapter' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:91:1`

### #47 PHYSICAL_EQUALITY_SMELL on `C11_emitter_adapter.word`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:144:1`
- **Summary:** Type Safety Hazard (Physical Equality): Function 'word' in 'C11_emitter_adapter' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs

#### Evidence Trail:
- `+80%` **[PHYSICAL_EQUALITY_COMPARISON]** Type Safety Hazard (Physical Equality): Function 'word' in 'C11_emitter_adapter' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml:144:1`

### #48 PHYSICAL_EQUALITY_SMELL on `Sail_ast.func`
- **Category:** `type_safety`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/domain/sail_ast.ml:57:1`
- **Summary:** Type Safety Hazard (Physical Equality): Function 'func' in 'Sail_ast' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs

#### Evidence Trail:
- `+80%` **[PHYSICAL_EQUALITY_COMPARISON]** Type Safety Hazard (Physical Equality): Function 'func' in 'Sail_ast' uses physical pointer equality (`==` / `!=`); use structural value equality (`=` / `<>`) to avoid subtle value comparison bugs -> `/Volumes/External/Code/ASGARD-5877/lib/domain/sail_ast.ml:57:1`

### #49 GOD_MODULE_SRP on `Test_vm_ir`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_vm_ir' defines 44 functions across 220 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_vm_ir' defines 44 functions across 220 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_vm_ir.ml:1:1`

### #50 GOD_MODULE_SRP on `Test_vanguard_9292`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_vanguard_9292' defines 39 functions across 150 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_vanguard_9292' defines 39 functions across 150 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_9292.ml:1:1`

### #51 GOD_MODULE_SRP on `Test_native_vm_and_metrics`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_native_vm_and_metrics' defines 32 functions across 169 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_native_vm_and_metrics' defines 32 functions across 169 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:1:1`

### #52 GOD_MODULE_SRP on `Test_families_generation`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_families_generation' defines 37 functions across 233 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_families_generation' defines 37 functions across 233 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:1:1`

### #53 GOD_MODULE_SRP on `Test_anti_analysis`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Test_anti_analysis' defines 50 functions across 214 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Test_anti_analysis' defines 50 functions across 214 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/test/test_anti_analysis.ml:1:1`

### #54 GOD_MODULE_SRP on `Main`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/bin/main.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Main' defines 76 functions across 565 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Main' defines 76 functions across 565 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/bin/main.ml:1:1`

### #55 GOD_MODULE_SRP on `C_macro_obf`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'C_macro_obf' defines 44 functions across 310 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'C_macro_obf' defines 44 functions across 310 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_obf.ml:1:1`

### #56 GOD_MODULE_SRP on `Assembler_adapter`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Assembler_adapter' defines 57 functions across 363 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Assembler_adapter' defines 57 functions across 363 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:1:1`

### #57 GOD_MODULE_SRP on `Register`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/register.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Register' defines 34 functions across 157 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Register' defines 34 functions across 157 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/register.ml:1:1`

### #58 GOD_MODULE_SRP on `Flags`
- **Category:** `principle`
- **Confidence:** **85%** [VERY_HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/flags.ml:1:1`
- **Summary:** SRP Violation (God Module): Module 'Flags' defines 38 functions across 250 lines of code, indicating multiple mixed domain responsibilities

#### Evidence Trail:
- `+85%` **[SRP_GOD_MODULE]** SRP Violation (God Module): Module 'Flags' defines 38 functions across 250 lines of code, indicating multiple mixed domain responsibilities -> `/Volumes/External/Code/ASGARD-5877/lib/vm_ir/flags.ml:1:1`

### #59 CYCLOMATIC_COMPLEXITY_KISS on `Assembler_adapter.res`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:87:1`
- **Summary:** KISS Violation (High Complexity): Function 'res' in 'Assembler_adapter' has cyclomatic complexity of 20; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'res' in 'Assembler_adapter' has cyclomatic complexity of 20; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/assembler/assembler_adapter.ml:87:1`

### #60 CYCLOMATIC_COMPLEXITY_KISS on `Sail_parser_adapter.b`
- **Category:** `principle`
- **Confidence:** **75%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:110:1`
- **Summary:** KISS Violation (High Complexity): Function 'b' in 'Sail_parser_adapter' has cyclomatic complexity of 16; decompose nested pattern matches into helper functions

#### Evidence Trail:
- `+75%` **[KISS_HIGH_MATCH_COMPLEXITY]** KISS Violation (High Complexity): Function 'b' in 'Sail_parser_adapter' has cyclomatic complexity of 16; decompose nested pattern matches into helper functions -> `/Volumes/External/Code/ASGARD-5877/lib/adapters/sail_parser/sail_parser_adapter.ml:110:1`

### #61 DUPLICATE_CODE_DRY on `Test_domain_invariants.vd`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:77:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vd, Assembler_adapter.vd

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vd, Assembler_adapter.vd -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:77:1`

### #62 DUPLICATE_CODE_DRY on `Test_domain_invariants.funct3`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:78:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.funct3, Vector_isa_spec.funct3

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.funct3, Vector_isa_spec.funct3 -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:78:1`

### #63 DUPLICATE_CODE_DRY on `Test_domain_invariants.vs1`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:79:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs1, Assembler_adapter.vs1

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs1, Assembler_adapter.vs1 -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:79:1`

### #64 DUPLICATE_CODE_DRY on `Test_domain_invariants.vs2`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:80:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs2, Assembler_adapter.vs2

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vs2, Assembler_adapter.vs2 -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:80:1`

### #65 DUPLICATE_CODE_DRY on `Test_domain_invariants.vm`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:81:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vm, Assembler_adapter.vm

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_domain_invariants.vm, Assembler_adapter.vm -> `/Volumes/External/Code/ASGARD-5877/test/test_domain_invariants.ml:81:1`

### #66 DUPLICATE_CODE_DRY on `Test_hw_cost.inst1`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:43:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Test_hw_cost.inst1, Test_assembler.inst_vv, Test_assembler_deep.inst1

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Test_hw_cost.inst1, Test_assembler.inst_vv, Test_assembler_deep.inst1 -> `/Volumes/External/Code/ASGARD-5877/test/test_hw_cost.ml:43:1`

### #67 DUPLICATE_CODE_DRY on `Test_native_vm_and_metrics.oc_h`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:121:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.oc_h, Main.oc_h

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.oc_h, Main.oc_h -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:121:1`

### #68 DUPLICATE_CODE_DRY on `Test_native_vm_and_metrics.oc_r`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:126:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.oc_r, Main.oc_r

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.oc_r, Main.oc_r -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:126:1`

### #69 DUPLICATE_CODE_DRY on `Test_native_vm_and_metrics.out_buf`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:148:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.out_buf, Test_vanguard_emulator_e2e.out_buf

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.out_buf, Test_vanguard_emulator_e2e.out_buf -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:148:1`

### #70 DUPLICATE_CODE_DRY on `Test_native_vm_and_metrics.status`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:155:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.status, Test_vanguard_emulator_e2e.status

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_native_vm_and_metrics.status, Test_vanguard_emulator_e2e.status -> `/Volumes/External/Code/ASGARD-5877/test/test_native_vm_and_metrics.ml:155:1`

### #71 DUPLICATE_CODE_DRY on `Test_families_generation.by_base`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:27:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 4 location(s): Test_families_generation.by_base, Test_families_generation.weights, Test_properties.by_f6

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 4 location(s): Test_families_generation.by_base, Test_families_generation.weights, Test_properties.by_f6 -> `/Volumes/External/Code/ASGARD-5877/test/test_families_generation.ml:27:1`

### #72 DUPLICATE_CODE_DRY on `Test_cli.buf`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:3:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 3 location(s): Test_cli.buf, Test_assembler.buf, Test_c11_emulator.buf

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 3 location(s): Test_cli.buf, Test_assembler.buf, Test_c11_emulator.buf -> `/Volumes/External/Code/ASGARD-5877/test/test_cli.ml:3:1`

### #73 DUPLICATE_CODE_DRY on `Test_vanguard_emulator_e2e.oc`
- **Category:** `principle`
- **Confidence:** **80%** [HIGH]
- **Primary Location:** `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:26:1`
- **Summary:** DRY Violation: Identical function logic duplicated across 2 location(s): Test_vanguard_emulator_e2e.oc, Main.oc

#### Evidence Trail:
- `+80%` **[DRY_CODE_DUPLICATION]** DRY Violation: Identical function logic duplicated across 2 location(s): Test_vanguard_emulator_e2e.oc, Main.oc -> `/Volumes/External/Code/ASGARD-5877/test/test_vanguard_emulator_e2e.ml:26:1`
