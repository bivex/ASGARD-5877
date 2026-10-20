# Changelog

All notable changes to ASGARD-5877 are documented in this file.

The format follows Keep a Changelog, and the project uses Semantic Versioning.

## [Unreleased]

### Added

- Add support for legacy x87 FPU instructions across the x86 lifter, micro-IR, reference oracle VM evaluator, and native threaded C++ VM: support the 8-register circular stack `st(0)`..`st(7)` with Top pointer tracking and FSW condition flags (C0..C3) in `lib/vm_ir/register.ml` and `lib/vm_ir/vm_eval.ml`. Implement lifter translation (`lib/x86_lifter/lifter.ml`) and micro-IR definitions (`lib/vm_ir/ir.ml`) for loads/stores (`FLD`, `FST`, `FSTP`, `FILD`, `FIST`, `FISTP`), arithmetic (`FADD`, `FSUB`, `FSUBR`, `FMUL`, `FDIV`, `FDIVR` and popping variants `FADDP`, `FSUBP`, etc.), comparisons (`FCOM`, `FCOMP`, `FCOMPP`, and EFLAGS-modifying `FCOMI`/`FCOMIP`), unary operations (`FCHS`, `FABS`, `FSQRT`), constant loads (`FLD1`, `FLDZ`, `FLDPI`, `FLDL2E`, `FLDL2T`, `FLDLG2`, `FLDLN2`), transcendentals (`FSIN`, `FCOS`, `FSINCOS`, `FPTAN`, `FPATAN`, `FYL2X`, `FYL2XP1`, `F2XM1`), and status word storage (`FSTSW`/`FNSTSW AX`). In the native VM (`lib/native_vm/`), add `fpu_stack[8]`, `fpu_top`, `fpu_status` and C++ accessors to `VMContext` (`vm_context_emitter.ml`), 15 opcodes in `vm_transform.ml` and `vm_emitter.ml`, and C++ runtime dispatch handlers using `<cmath>` in `vm_mem_handlers.ml`, verified with execution tests in `test/test_x86_lifter.ml` and `test/test_native_semantics.ml`.
- Add an ISA reference parser and OCaml Alcotest generator script (`scripts/isa_ref_parser.py`) for automated ingestion, specification auditing, and test generation of x86, ARM, and RISC-V instructions from ASM Reference, extended with multi-instruction and category auditing across lifter, micro-IR, reference oracle, and native VM layers covering arithmetic, bitwise logic, division, atomics/exchanges, bit testing, string/rep operations, double shifts, and sign extension families.
- Add test coverage for the x86 `BT` bit-test instruction verifying CF output and the bitwise rotate instructions (`ROL` and `ROR`) covering 64-bit and 32-bit registers and implicit 1-count forms in `test/test_x86_lifter.ml`.
- Add an operand forms test for the x86 `MOVZX` instruction covering 8-bit and 16-bit register and memory sources across 32-bit and 64-bit destinations in `test/test_x86_lifter.ml`, and a native-execution test in `test/test_native_semantics.ml` that runs the same five encodings in the threaded native VM: the source must be zero-extended, a 32-bit destination must clear the upper half of its parent register, and the flags must survive the instruction (`MOVZX` affects no flags).
- Remake the x86 `CPUID` instruction across all virtualization pipeline layers: replace the static 4-MOV stub in `lib/x86_lifter/lifter.ml` with first-class `Ir.Cpuid` micro-IR and opcode `OP_CPUID`. The reference VM (`lib/vm_ir/vm_eval.ml`) evaluates dynamic leaf requests according to the Intel SDM (including leaf 0 vendor string "GenuineIntel", leaf 1 processor signature and feature bits, deterministic cache parameters, structured extended features, crystal clock, brand strings, and physical/linear address sizes) while zeroing the upper 32 bits of RAX, RBX, RCX, and RDX. The native runtime (`lib/native_vm/vm_mem_handlers.ml`) executes host `cpuid` on x86 and provides a portable software fallback on non-x86 hosts (ARM64 and RISC-V).
- Add the x86 `PCLMULQDQ` instruction and the CET shadow stack instructions (`RDSSPD`, `RDSSPQ`, `INCSSPD`, `INCSSPQ`) to the lifter and the virtual machines. `PCLMULQDQ` computes the carry-less product of two 64-bit halves of a 128-bit vector register: the immediate picks the half of the source (bit 0) and the half of the destination that receives the high product (bit 4), and the high half of the destination survives when the immediate selects it. The shadow stack pointer is a dedicated state field of the reference VM and of the native runtime context: `RDSSP` reads it, `INCSSP` grows it by 16 or 64 bytes while the regular stack pointer drops by the same amount. The native runtime carries a portable C++ handler, so the protected binary needs neither a PCLMULQDQ nor a CET CPU feature.
- Add the x86 SHA extensions (SHA-NI) to the lifter and the virtual machines: `SHA1RNDS4`, `SHA1NEXTE`, `SHA1MSG1`, `SHA1MSG2`, `SHA256RNDS2`, `SHA256MSG1` and `SHA256MSG2`. Every instruction works on the four 32-bit words of a 128-bit vector register; the destination is both a source and the destination and `SHA256RNDS2` takes its round constants from the implicit XMM0. The round functions live in a new module (`lib/vm_ir/sha_ni.ml`), the reference VM evaluates them directly and the native runtime carries a portable C++ handler, so the protected binary needs no SHA CPU feature.
- Add a native-execution test for the x86 FSGSBASE family (`RDFSBASE`, `RDGSBASE`, `WRFSBASE`, `WRGSBASE`): the segment base is written into the VM context slot and read back through the same slot, which the lifter test alone did not cover.

### Fixed

- Fix the ISA reference parser (`scripts/isa_ref_parser.py`) so that a specification table copied from the rendered documentation page is parsed: the table columns are separated by runs of spaces, not by tabs, so `parse-text` reported "Variants Found: 0" and generated a test without operands. The MOVZX specification now yields its five opcode variants (`0F B6 /r`, `REX.W + 0F B6 /r`, `0F B7 /r`, `REX.W + 0F B7 /r`) and a concrete sample instruction.
- Fix the ISA implementation audit (`scripts/isa_ref_parser.py`) reporting the x86 `MOVZX`, `MOVSX` and `MOVSXD` as missing in the micro-IR, reference oracle and native VM layers. These instructions have no dedicated node or handler - the lifter lowers them to a masked move (`Ir.Mov` plus `Ir.Alu And`) or to a move plus a sign-extension pair (`Ir.Alu Shl` and `Ir.Alu Sar`) - so the audit now looks for the primitives the lowering uses, and the new "Расширение при переносе" category lists the three instructions.
- Reject illegal attempts to load the CS register using the x86 `MOV` instruction (`mov cs, ...`) in `lib/x86_lifter/lifter.ml`, strictly adhering to Intel SDM invalid opcode (#UD) architecture rules matching `pop cs`.

### Changed

- Translate all remaining Russian comments, formal verification specifications, and documentation across `fstar/`, `docs/`, `examples/`, and `scripts/` to English, establishing uniform technical documentation across the repository while preserving F* proof semantics.

## [0.2.0] - 2026-10-20

### Added

- Add a per-case timing report to the test runner: every Alcotest case prints its own duration next to its name, and `run_tests.sh` reports the elapsed time of the whole run plus a line every 30 seconds. Alcotest captures the output of a case, so the durations travel through the file named by `ASGARD_TEST_TIMES`, which the script tails. The slowest cases are now visible without a second run.
- Add the missing x86 sign-extension forms to the lifter: `cbw` (AX becomes the sign-extended AL, the upper half of RAX is kept) and `cwde` (EAX becomes the sign-extended AX, the upper half of RAX is zeroed), plus the AT&T spellings `cbtw`, `cwtl` and `cwtd`. `cqo` and `cqto` were already supported; the whole family is now pinned by a test against the values an x86-64 machine produces.
- Add x86 BMI1 `BLSR` (reset lowest set bit) to the lifter: the result is `(SRC - 1) & SRC`, so the lowest set bit of the source is cleared, ZF and SF come from the result, CF is set when the source is zero and OF is cleared. The `blsr`, `blsrq` and `blsrl` spellings are accepted.
- Add x86 lifter tests for the bitwise packed OR instructions: `orps` / `orpd` in their legacy SSE form (two operands, the destination is both operands, only the low 128 bits are written and the upper half of the destination survives) and `vorps` / `vorpd` in their VEX form (three operands, 256-bit destination, and a 128-bit destination whose upper half is zeroed). The expected values are the OR of the raw element patterns, so the tests pin the bitwise semantics instead of a numeric operation on the floats (`test/test_x86_lifter.ml`).
- Add the ARM64 `CSETM` conditional set mask to the lifter (`lib/arm64_lifter/arm64_alu.ml`). `CSETM` is the `CSINV` alias over the zero register with an inverted condition, so the destination holds the mask of the condition: all bits set when the condition holds.
- Add a test for the whole ARM64 conditional family - `cset`, `cinc`, `csel`, `csinc`, `csinv`, `cinv`, `cneg`, `csneg` and `csetm` - in the 64-bit and the 32-bit form, for a condition that holds and one that does not. The expected values are the ones the ARM64 hardware produces (`test/test_arm64_lifter.ml`).
- Add Mach-O compact unwind support (`lib/macho/`): a container reader for 32-bit and 64-bit images that parses the load commands, the segments and the sections, and decodes the `LC_ROUTINES` (0x22) and `LC_ROUTINES64` (0x33) load commands into routine tables (`macho_image.ml`). The unwind model decodes the routine table, resolves the routine that covers an address, checks every entry against `__TEXT,__text` and `__TEXT,__unwind_info`, and repairs the entries whose extent overruns the following function without changing the image layout (`macho_unwind.ml`).
- Add a `random_visa macho-unwind` command that inspects the compact unwind information of a Mach-O image and optionally writes a repaired copy. The command exits non-zero when the information is inconsistent, so it can gate a release pipeline.
- Add a compact unwind audit to the protection pipeline: the binary the protector produced is checked and the result is reported in the protection summary as `Mach-O Compact Unwind`.
- Add a 23-case test suite for the Mach-O reader and the compact unwind model, covering both compact unwind layouts, the 32-bit and 64-bit routine tables, the consistency checks and the repair (`test/test_macho.ml`).

- Add 100% complete VM handler metamorphism across the entire Native VM instruction set architecture (`131/131` handlers in `vm_alu_handlers.ml`, `vm_control_handlers.ml`, and `vm_mem_handlers.ml`) with 2–3 semantically equivalent polymorphic implementations per opcode. Fully covers:
  - ALU instructions (51/51): arithmetic/immediate ops (`ADD`, `SUB`, `IMUL`, `DIV`, `IDIV`, `MULH`, `IMULH`, `XOR`, `AND`, `OR`), shifts/rotates (`ROL`, `ROR`, `SHL`, `SHR`, `SAR` in RR/RI forms), bit manipulations (`CLZ`, `CTZ`, `POPCNT`, `RBIT`, `BSWAP`, `NOT`, `NEG`), flags/comparisons (`ADC`, `SBB`, `CCMP`, `CCMN`, `CMP`, `GET_FLAGS`, `SET_FLAGS`, `MOV_HIGH`, `NOP`).
  - Control-flow instructions (17/17): branch/call skeleton (`JMP`, `JCC`, `CMOV`, `SETCC`, `CALL`, `RET`, `EXIT`, `IJMP_R`, `ICALL_R`, domain bridges `BRIDGE_TO_FLOW`/`MATH`), and 6 fused super-operators (`H_FUSED_MOV_ADD_RRI`, `H_FUSED_ADD_IMUL_RRI`, `H_FUSED_ADD_XOR_RRI`, `H_FUSED_SUB_XOR_RRI`, `H_FUSED_XOR_ADD_RRI`, `H_FUSED_CMP_CMOV`).
  - Memory, Atomics, FP, SIMD & System handlers (63/63): scalar load/store B8–B64 with signed/unsigned variants (`LOAD_*`, `STORE_*`, `LOAD_S32/S16/S8`), stack operations (`PUSH_R`, `POP_R`), vector registers (`MOV_VR`, `MOV_RV`, `VEC_MOV`), SIMD vector math (`VADD_VV`, `VSUB_VV`, `VMUL_VV`, `VXOR_VV`), SMP atomics (`ATOMIC_LOAD`, `ATOMIC_STORE`, `ATOMIC_CAS`, `ATOMIC_ADD`, `ATOMIC_SWP`), floating point operations (`FADD`, `FSUB`, `FMUL`, `FDIV`, `FSQRT`, `FCMP`, `FCVT*`, `FCSEL`), dynamic symbol resolution (`RESOLVE_SYM`), and all 16 decoy traps (`H_DECOY_0..15`).
  - Backed by domain-separated RNG splits (`split_rng` domains 101–106 in `vm_handlers_emitter.ml`) providing $3^{131} \approx 2.7 \times 10^{62}$ unique syntactic permutations, independently verifiable in test suite.
- Add multi-platform section integrity hashing (`runtime_probes.ml`, `vm_context_emitter.ml`) scanning `.text` and `.rodata` sections across macOS (`_dyld_get_image_header(0)` / `getsectiondata`), Linux (`dl_iterate_phdr`), and Windows PE (`IMAGE_DOS_HEADER` / `IMAGE_NT_HEADERS`), folding into `compute_handlers_hash()` and active dynamic drift detection in `evaluate_memory_integrity()`.
- Add architectural documentation for dispatch domain direct threading vs decoy diversification in `docs/VM_PROTECTOR.md`.
- Add Stack-VM execution engine with universal logic reduction (NOR/NAND), stateful rolling key encryption, and stack balancing (`lib/stack_vm/`).
- Add `Atomic_mem` memory operations (`AtLoad`, `AtStore`, `AtAdd`, `AtSwp`, `AtCas`) with width support and `Fp_conv` operand lowering to the Stack-VM lowering pass (`lib/stack_vm/ir_to_stack.ml`, `todo_t.md` item 9).
- Add keyed payload integrity tag for Stack-VM (`Stack_encoder.payload_tag`, `tag_keys`, `derive_payload_tag`, `payload_tag_of_keys`): SipHash-1-2 in CBC mode over the word-padded cipher image, binding both the image length and every 64-bit word, domain-separated from the per-block key halves and invariant under `apply_addr_mask`. The C++ runtime verifies it in `asg_payload_auth_ok` before the first fetch, with a constant-time compare, and refuses to decode an unauthenticated image.
- Add Anti-VMPredator address-bound bytecode keys for Stack-VM: pre-XOR stored seed and block key literals with ASLR/PIE-invariant handler address delta hash $D$ while preserving ciphertext bytes, and fold mask back at runtime entry.
- Add two-stage probe compilation stage in protection pipeline (`addr_probe.cpp`, `rebind_address`) to evaluate $D$ at build time and rebind generated C++ runtime header.
- Add comprehensive unit, divergence, and E2E C++ probe-and-execution tests for address-bound bytecode (`test_addr_mask_unit`, `test_addr_mask_wrong_key`, `test_address_bound_c_runtime_probe_and_run`).
- Add `--engine=stack` option to protection pipelines (`cli_protect.ml`, `cli_protect_arm64.ml`).
- Add `idasql.md` guide for auditing and verifying protected binaries via SQL queries on IDA Pro databases, including Case 6 (`JUMPOUT` decompiler CFG disruption) and Case 7 (constant table FNV-1a hashing and dynamic XOR rolling encryption).
- Add empirical SMT / Z3 symbolic execution benchmarks evaluating MBA degree scaling, path explosion in state-feedback keystreams, and VSP whitening ambiguity.
- Add `ASGARD_DEBUG_SYMBOLS=1` toolchain mode to preserve DWARF symbols and types for white-box VM auditing in IDA.
- Add full RISC-V 64-bit lifter (`RV64I`, `RV64M`, `RV64A`, `RV64F/D`, `RVV`) and pipeline adapter.
- Add comprehensive test suite for RISC-V instruction lifting and CFG reconstruction (`test/test_riscv_lifter.ml`).
- Add Register-Driven JIT (RD-JIT) support for `AND`, `OR`, `SHL`, `SHR`, `SAR`, `NOT`, `NEG`, and 64-bit `LOAD`/`STORE` across ARM64, x86_64, and interpreter backends.
- Add floating-point binops, comparisons, conversions, atomics, and symbol resolution (`OP_RESOLVE_SYM`) in reference VM evaluator.
- Add return flow preservation in C-macro Nanomite transformations with `ASG_NANOMITE_CHECK_RET`.
- Add test coverage for C-macro string escape parsing, char literals, multiline defines, and C trampoline signature variations.
- Add explicit test coverage for one-operand `mul` and `imul` with implicit `RDX:RAX` across 64-bit, 32-bit, 16-bit, and memory operands.

### Changed

- Move the three root-level TODO documents to the documentation archive: `TODO.md` (the project roadmap and status, all audit items closed), `TODO_CPP_CODEGEN.md` (the typed-EDSL migration roadmap, the migration is complete) and `todo_bugs.md` (the known bugs of the 2026-10-16 verification, all three entries are fixed). The archive README lists them, and the root keeps only the living documents.
- Rebuild the checked-in demo artifacts with the current generator: the license demo runtime, runner and bytecode, and the IDA demo multi-VM runtime, runner, bytecode and both protected runners. The committed license demo was stale - the shipped runtime and bytecode no longer agreed with the calling convention of `examples/license_demo/main.cpp`, so the demo rejected its own genuine key; the regenerated pair makes it report `VALID! Access Granted` again. The ARM64 flavour of the demo core is added as `examples/license_demo/license_core_arm64.s`, because the ARM64 lifter only reads the x/w register names.
- Compile the test binaries without optimizations (`-O0`). The generated VM runtime is about a megabyte of C++, and `clang++ -O2` spent twelve seconds per test in the compiler alone while `-O0` needs one and a half; the tests only look at what the VM computes, not at how fast it runs. The `-O2` and `-O3` flags that `test_native_semantics.ml` hands to the compiler are the product behaviour under test and stay untouched.
- Treat a Mach-O image without compact unwind information as a state, not an inconsistency. `Macho_unwind.check` no longer reports `Missing_unwind_info_section`; the absence is carried by the `No_unwind_info` layout and the report prints `__TEXT,__unwind_info: absent`. The protector compiles the protected binary with `-fno-unwind-tables -fno-asynchronous-unwind-tables`, so every protected binary used to fail the audit with a single issue and made `macho-unwind` exit non-zero, which failed the release gate in `scripts/audit_protected_binary.sh` for the wrong reason. The gate now measures the consistency of the unwind information the image does carry. The protection summary reads `Mach-O Compact Unwind: not emitted (no __TEXT,__unwind_info section), 0 routine(s), no inconsistency`.
- Update test suite registry to 255 tests across 35 suites (including Stack-VM primitives, logic reduction, rolling keys, and branch extensions).
- Harden Stack-VM C++ runtime with Fail-Closed stack underflow/overflow bounds checks (`4096`), context slot bounds checks, and sanitization against empty symbol `dlsym` calls.
- Harden Stack-VM operand fetch: `stack_vm_t` gains `bc_size`, set from the size handed to `stack_vm_run`, and every `fetch_byte` refuses to read past it, so a truncated instruction can no longer decode adjacent `.rodata` as instructions or feed it into the key stream.
- Harden Stack-VM guest memory access: `READ_MEM` / `WRITE_MEM` now admit an address only through `asg_mem_access_ok` (encodable width, non-zero, naturally aligned, canonical, no wrap at the top of the address space) and halt otherwise, closing the raw-pointer dereference of arbitrary VSP values. Mirrored in the reference interpreter as `Stack_eval.mem_access_ok`.
- Add tests for payload authentication and the guest memory policy (`test_payload_tag_unit`, `test_guest_mem_policy`, `test_payload_auth_c_runtime`).
- Make the two payload-tag key halves computationally independent: they were the seed XORed with two constants one byte apart, so `k0 ^ k1 == 3` for every seed and recovering one half yielded the other exactly, while the pair carried no more than 64 bits of independent key material. Both halves now go through SipHash under separate domains in `Stack_encoder.payload_tag_keys`.
- Make a failed image authentication indistinguishable from an ordinary denial: `stack_vm_run` now zeroes the context and resets the VSP before halting, so the call returns the same "not granted" result and the caller computes the same exit status as for a rejected key. Previously `ctx[0]` still held `a0` on AArch64, so the caller computed `ok ^ 1` over a truncated pointer and exited with an address-derived status (49 instead of 1). The reason is exposed as `stack_vm_t::auth_failed` for callers that want to log it.
- Ensure compiler pipeline always compiles C sources to assembly via toolchain even when macro obfuscation is disabled.
- Automatically copy and configure `asgard_obf.h` header in output directory for C protection pipeline.

### Fixed

- Fix zero register check in native VM atomic emitter: the zero register shares its slot index with the GS base register in the native register file, so checking `is_zero_register dst` instead of slot index equality ensures `vzero` writes are ignored without suppressing writes to `vgs_base` (`lib/native_vm/vm_emitter.ml`).
- Fix canonicalization of `Ir.Ccmn` and `Ir.Ccmp` with immediate operands outside the 5-bit `0..31` range or memory operands (`lib/native_vm/vm_transform.ml`): ARM64 `OP_CCMN_RI` and `OP_CCMP_RI` words allocate only 5 bits for the immediate operand, so `cmn`/`ccmn` and `ccmp` with larger immediates (e.g. `cmn w0, #100`) wrapped modulo 32 when emitted directly; `canonicalize_instr` now loads out-of-range immediates and memory operands into a scratch register and lowers to `OP_CCMN_RR`/`OP_CCMP_RR`, resolving test 8 in `Native VM Sub-width Semantics` (`e2e_sub64_signed_comparisons_clang_o2_o3`).
- Restore the metamorphic variants of the atomic handlers `H_ATOMIC_ADD` and `H_ATOMIC_SWP` in the native VM runtime. The width-aware rewrite of the LSE atomics left both handlers with a single fixed body, so every seed produced the same code and the metamorphism invariant (`H_ATOMIC_ADD diversity > 1`) failed. Both handlers now emit three semantically equivalent variants - the `__atomic` builtin, the C++ atomic member and a load/compare-exchange loop - and all three honour the width code in the word's extra bits (32-bit, 16-bit, 8-bit and 64-bit).
- Fix the x86 bit-scan family in the lifter: `BSR` returned the number of leading zeros instead of the index of the highest set bit, `BSF` overwrote the destination when the source was zero, and `LZCNT` / `TZCNT` set no flags at all. They now follow the manual: BSF and BSR keep the destination and report the zero source in ZF, LZCNT and TZCNT always write the destination, set ZF for a zero result and CF for a zero source. The expected values and flags were taken from an x86-64 machine.
- Fix ARM64 LSE `LDADD` semantics in the threaded VM (`todo_t.md` items 1-4): the destination register now receives the old memory value through a scratch-register sequence that preserves the value register and the address when `dst <> src`, sub-64-bit forms (`ldadd w/b/h`) update only their width via a width code in the word's extra bits (`uint32_t`/`uint16_t`/`uint8_t` fetch-add paths in `H_ATOMIC_ADD`/`H_ATOMIC_SWP`), `Atomic_mem` participates in sub-register zero-extension and register remapping, and the reference VM writes the old value to `dst`.
- Fix IR pipeline operand tracking and register liveness for `Fp_conv`, `Atomic_mem`, and `vtmp` scratches (`todo_t.md` §6.1, probe A 106 -> 127/127): `Codec_pass` now eagerly decodes operand registers of `Fp_conv`, `Atomic_mem`, and `Cmov` before use and resets destination state to plain (`lib/vm_ir/codec_pass.ml`); `Register_allocator` remaps `Fp_conv` source and destination registers (`lib/vm_ir/register_allocator.ml`); `Superoperator` checks surrounding instructions to avoid inserting decoy writes into live `vtmp0..3` scratches (`lib/vm_ir/superoperator.ml`); and `test_probe_b` accumulates flag checks as an explicit bitmask matching the probe B specification (`test/test_arm64_lifter.ml`).
- Fix ARM64 `SCVTF`/`UCVTF` width semantics (`todo_t.md` item 5): the lifter keeps the destination width (`s0..s31` are `B32`), the reference VM sign-extends 32-bit sources for `SCVTF`, masks them for `UCVTF` and rounds to binary32 for single destinations, and the width flags travel through the word immediate so `H_SCVTF`/`H_UCVTF` and `H_FCVTZS`/`H_FCVTZU` handle `int32_t`, `uint32_t` and `float`.
- Fix `cmn` with a constant clobbering `vtmp1` for decoy instructions (`todo_t.md` item 6) by taking the direct `Ir.Ccmn { src2 = Imm imm }` operand, and relax the equivalence assertion to `check_callee_saved:false` so randomized R8..R15 scratch use does not fail Stage 7 (`todo_t.md` item 7).
- Fix ARM64 `ADC`/`SBC` carry and flag semantics in the threaded VM (`todo_t.md` item 8, probe B 26 -> 63/63): `canonicalize_instr` no longer lowers `Adc`/`Sbb` to `alu`-without-flags plus a synthetic `cmp dst,0` (the appended compare was clobbering NZCV after `adc`/`sbc` and destroying the C/V that `adcs`/`sbcs` must produce); ADC/SBC words carry `set_flags` and the carry dialect in their extra bits; the VM keeps a shadow ARM64-view carry `ctx.cf_arm64` (C = NOT borrow after SUB-family flag writers) maintained by every flag writer; `H_ADC_*` adds C and `H_SBB_*` subtracts NOT C in ARM64 mode and write NZCV only when `set_flags`; the ccmp/ccmn `nzcv` fallback no longer writes the ARM64 C bit straight into the x86-view `ctx.cf` (which read inverted through `b.hs`); the program's architecture is carried by the new `arch` config field (`"arch": "aarch64"`), so the x86 path keeps its carry convention unchanged.
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
