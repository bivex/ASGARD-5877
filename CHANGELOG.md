# Changelog

All notable changes to ASGARD-5877 are documented in this file.

The format follows Keep a Changelog, and the project uses Semantic Versioning.

## [Unreleased]

### Added

- Add full RISC-V 64-bit lifter (`RV64I`, `RV64M`, `RV64A`, `RV64F/D`, `RVV`) and pipeline adapter.
- Add comprehensive test suite for RISC-V instruction lifting and CFG reconstruction (`test/test_riscv_lifter.ml`).
- Add Register-Driven JIT (RD-JIT) support for `AND`, `OR`, `SHL`, `SHR`, `SAR`, `NOT`, `NEG`, and 64-bit `LOAD`/`STORE` across ARM64, x86_64, and interpreter backends.
- Add floating-point binops, comparisons, conversions, atomics, and symbol resolution (`OP_RESOLVE_SYM`) in reference VM evaluator.
- Add return flow preservation in C-macro Nanomite transformations with `ASG_NANOMITE_CHECK_RET`.
- Add test coverage for C-macro string escape parsing, char literals, multiline defines, and C trampoline signature variations.

### Changed

- Update test suite registry to 239 tests across 34 suites (including RISC-V lifter and extended C macro suites).
- Ensure compiler pipeline always compiles C sources to assembly via toolchain even when macro obfuscation is disabled.
- Automatically copy and configure `asgard_obf.h` header in output directory for C protection pipeline.

### Fixed

- Fix 128-bit `RDX:RAX` division lowering in x86_64 lifter and overflow flag (`OF`) computation in `H_FUSED_CMP_CMOV`.
- Fix canonicalization of `Ir.Cmp`, `Ir.Test`, and `Ir.Cmov` instructions with memory operands into registers with SIB support.
- Fix x86-64 parser to support both `scale*reg` (e.g. `8*rdx`) and `reg*scale` SIB forms.
- Fix x86-64 marker jump peeling (`jmp` before ASGARD markers) and flush trailing epilogue blocks as `Ret` terminators.
- Move `H_NEG_RR` and `H_NOT_RR` opcode labels outside ephemeral JIT `#if/#else` block so handlers are always emitted in dispatch table.
- Prevent duplicate trampoline embedding when processing multiple C source files and preserve intermediate obfuscated files (`app_obf.c`).
- Fix C macro obfuscator string unescaping for hex (`\xHH`), octal (`\OOO`), char literals (`'`, `"`), and multiline `#define` continuations.
- Fix C trampoline parser to handle comment/string-aware nested brace matching, default parameter values (`=`), and array parameters (`[]`).
- Fix C trampoline return type parsing for `void`, pointer types, and 64-bit scalars without truncation.
- Fix 64-bit SIMD lane packing/unpacking and prevent zero `lane_bits` loops in VM memory handlers.
- Synchronize `RSP` and `VSP` stack registers, and evaluate arithmetic flags and shift counts according to operand bit widths.
- Fix FP register operand indexing in native VM memory handlers.

## [0.1.0] - 2026-09-25

### Added

- Add x86-64 lowering for one-operand `mul` and `imul`, including exact 64-bit high-half results.
- Add B8, B16, and B32 `div` and `idiv` lowering with quotient, remainder, and `AH:AL` semantics.
- Add SSE and AVX packed operations with distinct integer, IEEE F32, and IEEE F64 lane semantics.
- Add register-driven JIT support for external symbols and platform-specific native call sequences.
- Add ephemeral polymorphic native JIT execution and parallel MBA processing.
- Add address-bound bytecode keys derived from runtime handler addresses.
- Add Apple Metal acceleration for MBA synthesis and SAC verification.
- Add strict SMC status reporting and failure diagnostics.

### Changed

- Expand the native vector register bank to eight 64-bit lanes per register.
- Encode vector element type explicitly in VM IR and native bytecode.
- Canonicalize three-address ALU operations before native and RD-JIT emission.
- Normalize B8, B16, and B32 subregister writes before terminator patching.
- Use direct Nanomite dispatch on Apple instead of hardware signal delivery.
- Keep Linux signal-based Nanomite dispatch and Windows vectored exception handling.
- Update active documentation to the current 225-test registry across 33 suites.

### Fixed

- Fix B8 and B16 partial-register writes to preserve the upper backing-register bits.
- Fix B32 writes and ARM64 `w14` through `w28` and `w30` aliases to zero-extend correctly.
- Fix `cdq`, `cltd`, `cqo`, `cqto`, `cwd`, `cdqe`, and `cltq` sign-extension lowering.
- Trap on division by zero and signed `INT64_MIN / -1` overflow in evaluator and native VM paths.
- Fix native lowering of unary `neg` and `not` operations.
- Fix Apple Silicon variadic calling conventions and ARM64 JIT memory-protection transitions.
- Fix assembler parser string escaping and x86-64 parser handling of vector memory operands.
- Synchronize native opcode tables, handler labels, and randomized dispatch mappings.

### Security

- Fail closed on invalid SMC allocation in strict mode and expose degraded status in non-strict mode.
- Bind anti-analysis bytecode keys to runtime handler addresses to resist static key recovery.
- Avoid installing native Nanomite signal handlers on Apple, avoiding unreliable signal-resume behavior.
- Dispatch registered C-macro Nanomite branches directly on Apple while preserving platform-specific handlers elsewhere.

### Validation

- Require `dune build` to complete successfully.
- Require all 225 registered tests in 33 suites to pass with `dune runtest`.
- Cover arithmetic, subregister, vector, FFI, Nanomite, SMC, and native runtime behavior with regression tests.
