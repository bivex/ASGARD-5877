# Changelog

All notable changes to ASGARD-5877 are documented in this file.

The format follows Keep a Changelog, and the project uses Semantic Versioning.

## [Unreleased]

### Added

- Add Stack-VM execution engine with universal logic reduction (NOR/NAND), stateful rolling key encryption, and stack balancing (`lib/stack_vm/`).
- Add keyed payload integrity tag for Stack-VM (`Stack_encoder.payload_tag`, `tag_keys`, `derive_payload_tag`, `payload_tag_of_keys`): SipHash-1-2 in CBC mode over the word-padded cipher image, binding both the image length and every 64-bit word, domain-separated from the per-block key halves and invariant under `apply_addr_mask`. The C++ runtime verifies it in `asg_payload_auth_ok` before the first fetch, with a constant-time compare, and refuses to decode an unauthenticated image.
- Add Anti-VMPredator address-bound bytecode keys for Stack-VM: pre-XOR stored seed and block key literals with ASLR/PIE-invariant handler address delta hash $D$ while preserving ciphertext bytes, and fold mask back at runtime entry.
- Add two-stage probe compilation stage in protection pipeline (`addr_probe.cpp`, `rebind_address`) to evaluate $D$ at build time and rebind generated C++ runtime header.
- Add comprehensive unit, divergence, and E2E C++ probe-and-execution tests for address-bound bytecode (`test_addr_mask_unit`, `test_addr_mask_wrong_key`, `test_address_bound_c_runtime_probe_and_run`).
- Add `--engine=stack` option to protection pipelines (`cli_protect.ml`, `cli_protect_arm64.ml`).
- Add `idasql.md` guide for auditing and verifying protected binaries via SQL queries on IDA Pro databases.
- Add `ASGARD_DEBUG_SYMBOLS=1` toolchain mode to preserve DWARF symbols and types for white-box VM auditing in IDA.
- Add full RISC-V 64-bit lifter (`RV64I`, `RV64M`, `RV64A`, `RV64F/D`, `RVV`) and pipeline adapter.
- Add comprehensive test suite for RISC-V instruction lifting and CFG reconstruction (`test/test_riscv_lifter.ml`).
- Add Register-Driven JIT (RD-JIT) support for `AND`, `OR`, `SHL`, `SHR`, `SAR`, `NOT`, `NEG`, and 64-bit `LOAD`/`STORE` across ARM64, x86_64, and interpreter backends.
- Add floating-point binops, comparisons, conversions, atomics, and symbol resolution (`OP_RESOLVE_SYM`) in reference VM evaluator.
- Add return flow preservation in C-macro Nanomite transformations with `ASG_NANOMITE_CHECK_RET`.
- Add test coverage for C-macro string escape parsing, char literals, multiline defines, and C trampoline signature variations.
- Add explicit test coverage for one-operand `mul` and `imul` with implicit `RDX:RAX` across 64-bit, 32-bit, 16-bit, and memory operands.

### Changed

- Update test suite registry to 255 tests across 35 suites (including Stack-VM primitives, logic reduction, rolling keys, and branch extensions).
- Harden Stack-VM C++ runtime with Fail-Closed stack underflow/overflow bounds checks (`4096`), context slot bounds checks, and sanitization against empty symbol `dlsym` calls.
- Harden Stack-VM operand fetch: `stack_vm_t` gains `bc_size`, set from the size handed to `stack_vm_run`, and every `fetch_byte` refuses to read past it, so a truncated instruction can no longer decode adjacent `.rodata` as instructions or feed it into the key stream.
- Harden Stack-VM guest memory access: `READ_MEM` / `WRITE_MEM` now admit an address only through `asg_mem_access_ok` (encodable width, non-zero, naturally aligned, canonical, no wrap at the top of the address space) and halt otherwise, closing the raw-pointer dereference of arbitrary VSP values. Mirrored in the reference interpreter as `Stack_eval.mem_access_ok`.
- Add tests for payload authentication and the guest memory policy (`test_payload_tag_unit`, `test_guest_mem_policy`, `test_payload_auth_c_runtime`).
- Ensure compiler pipeline always compiles C sources to assembly via toolchain even when macro obfuscation is disabled.
- Automatically copy and configure `asgard_obf.h` header in output directory for C protection pipeline.

### Fixed

- Fix signed correction in 64-bit `lift_x86_mul64` where multiplicand sign masks were cross-applied against `a` and `b`, ensuring exact mathematical high-half results in `RDX`.
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
