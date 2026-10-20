<!--
Keep the checklist honest: it mirrors the rules in AGENTS.md.
-->

### What does this change?

<!-- One paragraph: the behaviour that changes and why. -->

### Areas touched

<!-- e.g. lib/vm_ir, lib/native_vm, lib/x86_lifter, test/ -->

### Checklist

- [ ] The change is covered by a test that exercises the changed path (not only a build).
- [ ] The affected test suite was run, and the command and result are in the description below.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` (`### Added` / `### Fixed` / `### Changed`).
- [ ] The commit message follows Conventional Commits with the area as the scope (`feat(x86): ...`, `fix(macho): ...`, `test(arm64): ...`).
- [ ] Instruction semantics are taken from the hardware specification (Intel SDM / ARM ARM), not from memory.
- [ ] No scratch files, probes, generated headers or build output are committed.

### Verification

<!--
Command and observed result, for example:

  _build/default/test/run_tests.exe test "x86_64 Lifter & CFG"
  Test Successful. 89 tests run.
-->

```text

```

### Notes for the reviewer

<!-- Anything a reviewer should look at first, or known follow-ups. -->
