# deobf_probe — does the bytecode simplify?

Offline attack harness answering two questions about a protected build,
with no knowledge of the pass seeds:

1. **Peephole attack** (`peephole_eval.py`): how much of the decoded
   program does a one-pass pattern deobfuscator (D810-style) remove?
   Universal stack identities (`Swap³→Swap`, `Dup·Swap²→Dup`, `Rot⁴→Rot`,
   `PushReg r,[Dup|PushReg r],PopReg r→PushReg r`) plus dead-slot junk
   rules (`PushImm v,PopReg s→ε` and friends, sound only when the slot is
   provably dead).  Slot deadness is answered in O(log n) from per-slot
   event lists — final programs exceed 10^6 ops.
2. **Dispatch topology** (`dispatch_topology.py`): bytecode layer rebuilds
   the block CFG from a phase dump (max in-degree = CFF hub concentration);
   machine-code layer disassembles `stack_vm_run` of an unstripped `-O0`
   build and reports, per indirect-branch site, how many direct branches
   share its block — the compiler can merge identical handler epilogues
   into one trampoline and re-centralize the dispatch the source tried to
   disperse.

`run_probe.sh SEED` protects `examples/license_check.c` twice (full
config, and the same config with `multiplicity`/`avid` off), sanity-runs
the protected binary, then runs both analyses.

## Findings (2026-10-26, seed 1337, full config)

- **avid and multiplicity are fully pattern-reversible.** With both on,
  the final program is 1,080,563 ops; the one-pattern attack removes
  284,026 (26.3%) — every avid cluster (`junk:PushImm+Dup+Sub` 66,870
  hits alone) and every multiplicity identity (`2a-multiplicity` reduces
  exactly back to the pre-pass op count 9,589). With both off the same
  attack recovers 0.0% of the final program: amplifier/MBA/ghost/feedback
  junk survives pattern reduction because it reads its junk slots later.
- **Bytecode CFG is dispersed**: the CFF dispatchers peak at in-degree 55
  of 1,080 edges (5.1%) — no unflattening hub.
- **The compiler re-centralizes the machine dispatch**: `stack_vm_run`
  (67,536 bytes, handlers inlined, 0 out-of-line calls) has a *single*
  `br x8` site whose block is reached by 257 direct branches — clang
  merged the per-handler epilogues into one shared trampoline. The
  "0 CFG hubs" claim of `docs/Pipelined_stage_dispatch.md` §4 does not
  hold in the compiled artifact; one hardware breakpoint on that block
  steps virtual instructions, the exact attack the design targets.
  (The legacy centralized `ASG_DISPATCH_STEP` macro shares this fate —
  this is a codegen-level issue, not a regression of the pipelined pass.)

## Usage

```sh
bash examples/deobf_probe/run_probe.sh 1337
# or on existing dumps:
python3 examples/deobf_probe/peephole_eval.py /tmp/asg_probe/dumpA
python3 examples/deobf_probe/dispatch_topology.py \
  --phase-json "/tmp/asg_probe/dumpA/phase_7-balance_(final).json" \
  --binary /tmp/asg_probe/probeA_O0
```

Dependencies: python3 stdlib only; `nm` + `otool`/`llvm-objdump` for the
machine-code layer; `bin/main.exe` for protection.
