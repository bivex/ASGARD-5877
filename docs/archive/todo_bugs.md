# TODO: Known Bugs and Test Regressions

Date: 2026-10-16. Discovered during differential fuzzing verification (`dune runtest`, 467 tests, 8 failures). Neither group is related to the FP-taint rewriter fix (`c_arith_rewriter.ml`) — documented for subsequent resolution.

## 1. Native VM Sub-width Semantics — 7 Failures (ARM64 Lifter)

```
ASSERT uint16_pipeline failed: Lifter failed (arm64): Unsupported or invalid ARM64 instruction: sturh
```

- Suite: `Native VM Sub-width Semantics`, test cases `e2e_uint16_pipeline` and adjacent tests (run cache: `_build/default/test/_build/_tests/Random_vISA_Tests/Native VM Sub-width Semantics.00{4,5,8,9}.output`, `.01{0,1,2}.output`).
- Root Cause: The ARM64 lifter lacks support for the `sturh` instruction (unscaled store halfword, `lib/arm64_lifter/`).
- File to update: Instruction parser and dispatch table in the ARM64 lifter — add decoding for `sturh` (and consider neighboring unscaled load/store instructions: `ldurh`, `ldurb`, `sturb`, `ldursb`, `ldursh`).
- Semantics: `sturh Wt, [Xn, #imm9]` — store lower 16 bits of the register to an unaligned memory address; does not modify condition flags.

## 2. Anti-Pushan Rolling Key — 1 Failure

```
Cache: `_build/default/test/_build/_tests/Random_vISA_Tests/Anti-Pushan Rolling Key.009.output`
```

- Test: `anti_vmpredator_ta...` (index 9 in suite).
- Reproduction command: `_build/default/test/run_tests.exe test 'Anti-Pushan Rolling Key'`.
- Status: Under investigation, root cause pending analysis.

## 3. (Resolved in Tree) MBA Rewriter Breaking FP Code

`double q2 = q + p.d;` -> `ASG_MBA_ADD(q, p.d)` -> `double ^ double` — invalid C++, causing compilation failure in obfuscated translation units. Discovered by the differential runner (`examples/diff_fuzz/`) during the initial project pipeline run.

Fix: Added FP-taint analysis in `lib/c_macro_obf/c_arith_rewriter.ml` and `c_expr_parser.ml` (gathers FP declarations across the TU, tracks dependency chains, filters FP literals, casts, and math built-ins; tainted expressions bypass MBA rewriting). Regression test: `arithmetic_rewriter_fp_taint` in `test/test_c_macro_obf.ml` (passing).
