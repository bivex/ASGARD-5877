# AGENTS.md

Working rules for coding agents in this repository.

## 1. Test only the area you touched

Do **not** run the full test suite (`dune runtest`) after every change. It
takes minutes and it is almost never the fastest way to find a regression.
Run the suite that covers the area you changed, and the individual test case
inside it when you touched a single behaviour.

The suites are registered in `test/run_tests.ml`. Select one by name; the
argument is a regular expression matched against the **suite** names:

```bash
dune build test/run_tests.exe
_build/default/test/run_tests.exe test "x86_64 Lifter"     # one suite
_build/default/test/run_tests.exe list                    # the registered suites
```

A single case is addressed by its number, which the compact output prints next
to the name:

```bash
_build/default/test/run_tests.exe test "x86_64 Lifter" 33
```

Which suite to pick:

| Area | Suite |
|---|---|
| x86 lifter | `x86_64 Lifter & CFG` |
| ARM64 lifter | `ARM64 Lifter & CFG` |
| RISC-V lifter | `RISC-V Lifter & CFG` |
| native / threaded VM | `Native Threaded VM`, `Native VM Sub-width Semantics` |
| VM IR and flags | `VM-IR & Lazy Flags` |
| Stack VM | `Stack-VM Execution Engine` |
| Mach-O reader and unwind model | `Mach-O Compact Unwind (LC_ROUTINES)` |

Run the whole suite only when the change is cross-cutting (the IR, the VM
runtime, the register allocator, the protection pipeline) or before a release.
Say so in the report when you do.

Build the target you need instead of the default alias
(`dune build test/run_tests.exe`): an unrelated scratch file under `bin/` can
break the alias while the target you care about is fine.

A change counts as verified only after the affected path has been exercised.
A build alone proves nothing. For instruction semantics, take the expected
values from the hardware - the x86-64 programs were assembled and run on a real
x86-64 machine (Rosetta on Apple Silicon), the ARM64 ones natively on arm64 -
and not from memory.

## 2. Emit C/C++ through the typed EDSL, never through string buffers

C and C++ code in this repository is **not** assembled with `Buffer.add_string`,
`Printf.sprintf` concatenation, or raw text templates. Every C/C++ artifact -
VM runtimes, handler tables, headers, trampolines, shims, macro headers - is
built as a typed AST and printed by the EDSL that the engine implements in
`lib/cpp_codegen/`:

| Module | Role |
|---|---|
| `cpp_ast.ml` | the types: `ctype`, `expr`, `stmt`, `struct_member`, `top_decl` |
| `cpp_dsl.ml` | the combinators: `func_decl`, `let_u64`, `:=`, `if_then_else`, `call`, `preproc_if`, ... |
| `cpp_printer.ml` | the renderer: `render_top_decls`, `render_header_unit`, `render_top_decl` |
| `cpp_ast_obf.ml` | the scrambler; every new AST node needs a traversal case here |
| `cpp_validator.ml` | structural and compiler validation of the rendered text |

- Build the declarations with the `Cpp_dsl` combinators and render them with
  `Cpp_printer.render_top_decls` (or `render_header_unit` for a header unit).
  Do not splice C++ text into a `Buffer` yourself, not even for a single line:
  `Buffer.add_string b (Printf.sprintf "    %s: {\n" label)` is the anti-pattern.
- When the C++ construct you need has no EDSL counterpart yet, **add the
  counterpart to the EDSL first** and then use it: the type or constructor in
  `cpp_ast.ml`, the combinator in `cpp_dsl.ml`, the printing rule in
  `cpp_printer.ml`, the traversal case in `cpp_ast_obf.ml`. Never work around
  a missing constructor with string concatenation - extending the EDSL is the
  fix, the string is the bug.
- `Raw`, `RawTop`, `MemberRaw` and the `Cpp_dsl.emit_pp_*` helpers are
  Buffer-level escape hatches. Use them only for a construct that is not worth
  modelling; prefer the typed `preproc_if` / `preproc_ifdef` /
  `preproc_ifndef` declarations for preprocessor blocks.
- The rule governs C/C++ emission only. Ordinary OCaml text - reports, metric
  tables, log lines, test fixtures - may still use `Buffer.add_string`.
- Call sites that still concatenate C++ into a `Buffer` (for example
  `lib/native_vm/vm_mem_handlers.ml`) are known debt: when you touch such a
  file, convert the C++ part to the EDSL instead of extending the string path.
- After extending the EDSL, run its suite:

  ```bash
  dune build test/test_cpp_codegen.exe
  _build/default/test/test_cpp_codegen.exe
  ```

## 3. Every change ships with a changelog entry and a commit

- Update `CHANGELOG.md` under `## [Unreleased]` for every user-visible change:
  `### Added` for new behaviour, `### Fixed` for corrections, `### Changed` for
  changes in the behaviour of something that already existed. One bullet per
  change, in the past tense, stating what changed, where (`lib/...`) and why.
  Extend the existing bullet of a topic instead of adding a second one for the
  same topic.
- Commit the change. The history uses Conventional Commits with the area as
  the scope: `feat(x86): ...`, `fix(macho): ...`, `test(arm64): ...`,
  `docs(agents): ...`.
- One commit per logical change. Do not mix unrelated fixes into one commit,
  and do not leave a finished feature uncommitted.
- Never commit scratch files, probe programs, generated headers or build
  output. Files that another agent is working on stay uncommitted.

## 4. Report the evidence

Report what was actually run: the command, the suite, the number of tests, and
the observed result. Do not claim a behaviour is verified when only a build
was run, and do not describe an inferred result as an observed one.
