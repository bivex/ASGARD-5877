# Changelog

All notable changes to ASGARD-5877 are documented in this file.

The format follows Keep a Changelog, and the project uses Semantic Versioning.

## [Unreleased]

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
