# Pipeline Phase Compatibility Audit

Phase-by-phase compatibility audit of the ASGARD-5877 Stack-VM protection pipeline. The audit answers one question: when the ten protection passes run one after another, which pass breaks which invariant of the previous phase?

The audit has two halves. The OCaml side emits a machine-readable dump of the Stack IR at every phase boundary. The MATLAB side re-implements the runtime invariants independently and compares the program-observable state of consecutive phases. Both halves agree on the verdict for every phase, so a divergence between the model and the runtime is itself a finding.

## Purpose

The ten passes of `Stack_vm_packager` rewrite the same program ten times: fusion, mathematical amplification, MBA constant synthesis, control-flow flattening, spaghetti splitting, ghost padding, state feedback, and stack balancing. Each pass assumes that the previous pass left the program in a well-defined state. When that assumption breaks, the result is not a crash but a silently different protected binary.

The audit makes those assumptions explicit and checkable:

- Every phase is checked against the runtime invariants of `lib/stack_vm/stack_invariants.ml`.
- Every transition is checked for semantic preservation: the register writes, the stack contents and the outcome of every flag consumer must be identical before and after the pass.
- The result is a compatibility matrix that localizes an incompatibility to a specific pass.

## What is audited

| Phase | Pass | Module |
|---|---|---|
| `1-lowered` | lowering output | `Stack_vm.Ir_to_stack` |
| `2a-pre-superop` | superoperator fusion | `Stack_vm.Stack_superop_pass` |
| `2-amplified` | mathematical bytecode amplification | `Stack_vm.Bytecode_amplifier` |
| `2a-post-superop` | superoperator fusion on synthesized constants | `Stack_vm.Stack_superop_pass` |
| `2b-mba` | MBA constant synthesis | `Stack_vm.Stack_mba_pass` |
| `3-cff` | virtual control-flow flattening | `Stack_vm.Stack_cff_pass` |
| `4-spaghetti` | spaghetti control-flow splitting | `Stack_vm.Stack_spaghetti_pass` |
| `5-ghost` | ghost stack padding | `Stack_vm.Stack_ghost_pass` |
| `6-feedback` | state-feedback rolling key | `Stack_vm.Stack_feedback_pass` |
| `7-balance` | stack balance repair | `Stack_vm.Stack_balance_pass` |

The phase list is defined in `lib/adapters/protect_adapters/vm_packagers.ml` (module `Stack_vm_packager`).

## Requirements

- The opam environment for the OCaml toolchain:

  ```bash
  eval "$(opam env)"
  ```

- GNU Octave 7 or newer (tested with 11.3), or MATLAB R2016b or newer. The audit needs `jsondecode` and no additional toolbox.
- Always start Octave with `--no-gui -q`. Without `-q` Octave drops into an interactive prompt after the script and the command appears to hang.

> [!WARNING]
> MATLAB and Octave both **saturate** integer arithmetic, while the runtime uses wrapping `int64`. A naive `uint64(a) + uint64(b)` is therefore wrong in the ring. Every ring operation in the audit goes through the explicit carry chain in `scripts/asgard_mod64.m`.

## Quick start

Generate the phase dumps:

```bash
eval "$(opam env)"
dune exec examples/pipeline_dump/dump_pipeline.exe -- binaries/pipeline_dump
```

The command prints the shape of the program at every phase and writes one JSON file per phase:

```text
  1-lowered          blocks=3    ops=25     ctx_slots=32    invariants: OK
  2a-pre-superop     blocks=3    ops=24     ctx_slots=32    invariants: OK
  2-amplified        blocks=3    ops=460    ctx_slots=48    invariants: OK
  2a-post-superop    blocks=3    ops=362    ctx_slots=48    invariants: OK
  2b-mba             blocks=3    ops=416    ctx_slots=48    invariants: OK
  3-cff              blocks=7    ops=432    ctx_slots=49    invariants: OK
  4-spaghetti        blocks=9    ops=434    ctx_slots=49    invariants: OK
  5-ghost            blocks=9    ops=1097   ctx_slots=147   invariants: OK
  6-feedback         blocks=9    ops=1104   ctx_slots=147   invariants: OK
  7-balance          blocks=9    ops=1104   ctx_slots=147   invariants: OK
```

Run the audit:

```bash
octave --no-gui -q scripts/run_pipeline_compat.m
```

The runner takes the dump directory and an optional verbosity mode:

```bash
octave --no-gui -q scripts/run_pipeline_compat.m binaries/pipeline_dump verbose
```

## Running the audit on a real protected binary

The protector writes the same JSON dumps when `ASGARD_DUMP_JSON_DIR` is set:

```bash
eval "$(opam env)"
ASGARD_DUMP_JSON_DIR=binaries/protected_dump \
  dune exec bin/main.exe -- protect-arm64 --input ./app.s --output-dir ./out --seed 1337
```

The human-readable listing of the same phases is available through the `--dump-bytecode` flag or the `ASGARD_DUMP_BYTECODE=1` environment variable:

```bash
ASGARD_DUMP_BYTECODE=1 dune exec bin/main.exe -- protect-arm64 --input ./app.s --output-dir ./out
```

Both views describe the same program state: the JSON dump is written next to the listing at each phase boundary.

## Negative controls

The audit is only meaningful if it can fail. The harness provides two adversarial modes.

### Unbalanced input

```bash
dune exec examples/pipeline_dump/dump_pipeline.exe -- binaries/pipeline_dump_unbal --unbalanced
octave --no-gui -q scripts/run_pipeline_compat.m binaries/pipeline_dump_unbal
```

The input block leaves values on the stack, so every phase inherits a non-zero exit delta. The matrix shows the violation from the first phase and the repair:

```text
  invariant              1    2    3    4    5    6    7    8    9
  exit_delta_zero        .    .    .    .    .    .    .    .    F
```

`F` marks the transition that repairs the invariant: only the balance pass (phase 7) inserts the `PopReg` dummies that drain the stack.

### Declared context larger than the allocator

```bash
dune exec examples/pipeline_dump/dump_pipeline.exe -- binaries/pipeline_dump_adv --adversarial-context
octave --no-gui -q scripts/run_pipeline_compat.m binaries/pipeline_dump_adv
```

The program declares a context larger than the slot count the allocator knows about, and uses register slots in the gap. The amplifier must not shrink the declared context, otherwise those accesses fall out of range; the matrix must show `slots_in_range` holding in every phase.

## Reading the report

The audit prints four sections and writes a machine-readable summary to `compatibility_report.json` in the dump directory.

### Section 1: per-phase invariant profile

One row per phase with the block count, the operation count, the declared context size, the verdict of the MATLAB model, the verdict of the runtime checker and whether the two agree.

```text
  phase              blocks     ops  slots | MATLAB    runtime   agree   | notes
  1-lowered               3      25     32 | OK        OK        OK      |
  2a-pre-superop          3      24     32 | OK        OK        OK      |
  2-amplified             3     460     48 | OK        OK        OK      |
```

A disagreement in the `agree` column means the model and the runtime disagree about the phase, which is a defect in one of the two.

### Section 2: transition compatibility

One row per pass. `d_ops`, `d_blocks` and `d_slots` are the shape deltas, `invariants` names the invariants that the transition breaks or repairs, and `semantics` reports the semantic comparison.

```text
  from               -> to                    d_ops d_blocks d_slots | invariants semantics
  2a-pre-superop     -> 2-amplified            +436      +0    +16 | unchanged  3 blk, OK
  2-amplified        -> 2a-post-superop         -98      +0     +0 | unchanged  3 blk, OK
```

### Section 3: compatibility matrix

Rows are invariants, columns are transitions. `H` means the invariant holds, `X` means the transition breaks it, `F` means the transition repairs it, `.` means it was already broken.

```text
  invariant              1    2    3    4    5    6    7    8    9
  stack_underflow        H    H    H    H    H    H    H    H    H
  exit_delta_zero        H    H    H    H    H    H    H    H    H
  merge_depth_equal      H    H    H    H    H    H    H    H    H
  entry_present          H    H    H    H    H    H    H    H    H
  targets_present        H    H    H    H    H    H    H    H    H
  terminator_present     H    H    H    H    H    H    H    H    H
  slots_in_range         H    H    H    H    H    H    H    H    H
  key_coherent           H    H    H    H    H    H    H    H    H
```

The checked invariants are the runtime invariants of `lib/stack_vm/stack_invariants.ml`: stack underflow, zero exit delta, equal depth at merge points, a present entry block, existing jump targets, a terminator in every block, context slots within range, and a coherent rolling key at merge points.

### Section 4: summary

The overall verdict and the counts of broken invariants and of transitions with a semantic change.

## The Z_{2^64} parameter generator

The same ring arithmetic powers the obfuscation parameter generator:

```bash
octave --no-gui -q scripts/run_mba_mod64_params.m
```

It writes three artifacts:

- `scripts/bench_data/mba_mod64_params.json` — randomized amplification profiles, Horner vectors, ring keys and a mask pool.
- `scripts/bench_data/mba_mod64_params.csv` — a flat summary of the same data.
- `test/data/mba_mod64_golden.json` — the golden fixture consumed by the cross-check test.

The generator is deterministic: the same seed reproduces the same files byte for byte.

The fixture is verified against the runtime by the OCaml test:

```bash
eval "$(opam env)"
dune exec test/test_mba_mod64_crosscheck.exe
```

The test re-evaluates every exported Horner vector with the runtime's own `Bytecode_amplifier.eval_horner_polynomial` and checks every ring key with `Mba_engine.Metamorphic_ring.inv_mod_2_64`, both under native wrapping `int64`. A divergence between the generator and the runtime fails the test instead of shipping mismatched constants.

## Troubleshooting

### `dune: command not found`

The opam environment is not loaded in this shell:

```bash
eval "$(opam env)"
```

### Octave does not return to the shell

Start Octave with `--no-gui -q`:

```bash
octave --no-gui -q scripts/run_pipeline_compat.m
```

### `error: 'u64_or' undefined`

A stale copy of `scripts/mba_mod64_params.m` predates the refactor onto the shared ring module. Update the working tree and regenerate the fixture:

```bash
git pull
octave --no-gui -q scripts/run_mba_mod64_params.m
```

### `pipeline_compat: no phase dumps found`

The audit was pointed at a directory without `phase_*.json` files. Generate the dumps first, or pass the correct directory as the first argument.

### `Invalid_argument: block N: KeyFeedback expects ctx[M] = 0x...`

The encoder refuses to encrypt a program whose state-feedback coupling is not reproducible. The runtime hashes the live register on a `KeyFeedback`, while the encryptor can only hash a static constant, so the coupled value must be statically known: either the feedback immediately follows the write of that value into the slot, or the entry context is declared with `~initial_ctx`. See the module documentation of `lib/stack_vm/stack_encoder.ml`.

### The audit reports a violation that the runtime does not report

Check the `agree` column of section 1. A disagreement means the model and the runtime compute the invariant differently, for example because the model lacks an operation that a pass emits. The authoritative operation metadata is in the dump: every operation carries the stack delta and the flag classification computed by the runtime, and the model compares its own tables against those values.

## Extending the audit

To audit a new pass, add it to the harness `examples/pipeline_dump/dump_pipeline.ml` in the same order as `Stack_vm_packager`, and add its phase name to the canonical order list in `scripts/pipeline_compat.m`.

To add an invariant, implement the check in `analyse_phase` inside `scripts/pipeline_compat.m`, extend `invariant_vector` with the new column, and add the name to `invariant_names`. The order of the entries in `invariant_vector` and `invariant_names` must match.

## Limitations

- The model evaluates each block sequence with a zeroed register file and a zeroed memory. It therefore verifies the value semantics of the straight-line block sequences, not the full path-sensitive semantics of the program.
- Flags are compared by the outcome observed at each consumer, not by their representation. A pass that re-encodes the flags as raw RFLAGS is not reported.
- The audit covers the Stack-VM pipeline only. The native VM path (C and C++ emitters, SMC, anti-emulation, memory protection) is not modelled.
- The phase order in the analyzer is a fixed list. A pass that runs twice, or a pipeline variant with a different order, needs an update there.

## Related documents

- [`docs/VM_PROTECTOR.md`](VM_PROTECTOR.md): VM architecture, handlers, CFF and trampoline generation.
- [`docs/ENTROPY_MODEL.md`](ENTROPY_MODEL.md): devirtualization resistance and entropy models.
- [`docs/markdown-style-guide.md`](markdown-style-guide.md): documentation and formatting standards.
