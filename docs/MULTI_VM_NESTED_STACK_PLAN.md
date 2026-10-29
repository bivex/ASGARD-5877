# Multi-VM Nested Stack Plan (VM-in-VM)

Planning document for a nested virtual-machine stack in ASGARD-5877: any VM
tier can host the sealed program of another tier as its payload, so the
protected program is interpreted by a *stack of machines*, each layer hidden
behind the one above it. The plan combines two sources:

- Formal grounding from the Archive of Formal Proofs (AFP): verified compiler
  composition and tier-by-tier bisimulation of interpreter stacks.
- OEIS integer sequences that drive nesting discipline, tier dispatch,
  tier-space partitioning, topology integrity and inter-layer decorrelation.

Status: planning only. Nothing in this document is implemented yet; every
section names the modules it would touch.

## Purpose

Single-layer virtualization is peeled by one devirtualization cycle. A nested
stack forces an attacker to repeat the full lift-and-model cycle for every
layer, while each layer's schedule and layout remain mutually decorrelated.
The engineering goal is a depth-3 to depth-4 nesting with per-tier
differential verification, so that semantic equivalence is a tested property
instead of an assumption.

## Formal Foundation (AFP)

The nesting contract follows two AFP entries directly.

### VeriComp: composition of verified compilers

VeriComp (https://isa-afp.org/entries/VeriComp.html) provides locales
abstracting language semantics, program behaviours, forward and backward
simulations, and compiler composition, with general partial-correctness
theorems. The relevant law for this plan:

```text
bisim(T0, T1) and bisim(T1, T2)  =>  behaviour(T2 program) = behaviour(T0 program)
```

Compiler composition is the reason a stack of N nested tiers preserves the
host-visible semantics of the innermost payload.

### Interpreter_Optimizations: a proven three-tier interpreter stack

Interpreter_Optimizations (https://isa-afp.org/entries/Interpreter_Optimizations.html)
formalizes exactly a stack of three virtual machines, `Std -> Inca -> Ubx`,
where each adjacent pair is connected by:

- a compilation function (`Std_to_Inca_compiler`, `Inca_to_Ubx_compiler`);
- an erasure function `norm_instr : Instr(Ti) -> Instr(Ti-1)` that maps each
  optimized instruction back to the reference tier;
- an inductive simulation relation `match` between tier states;
- `backward_lockstep_simulation` and `forward_lockstep_simulation` lemmas,
  which together yield a bisimulation.

This is the proof template for each ASGARD tier boundary: erase, match,
lockstep both directions.

### Supporting entries

- Jinja (https://isa-afp.org/entries/Jinja.html) and JinjaThreads
  (https://isa-afp.org/entries/JinjaThreads.html): unified source + VM +
  compiler model; weak bisimilarity between source small-step semantics and
  the defensive virtual machine. Template for the outermost (threaded) tier
  and for big-step versus small-step equivalence of the nesting dispatcher.
- Compiling-Exceptions-Correctly
  (https://isa-afp.org/entries/Compiling-Exceptions-Correctly.html): handler
  frames dynamically pushed and popped on a stack. Template for nested VM
  context frames (`EnterVM`/`ExitVM` brackets).

## Architecture

### Tier stack

| Tier | Engine (existing module) | Role in the nest | State region |
|---|---|---|---|
| T0 | native trampoline host (`lib/adapters/protect_adapters/c_trampoline_adapter.ml`) | entry stub, no semantics | host stack |
| T1 | threaded VM (`lib/native_vm`) | outer interpreter, hosts T2 payload | per-frame context |
| T2 | stack VM / SJIT chunker (`lib/stack_vm/stack_jit_chunker.ml`) | bytecode tier, hosts T3 payload | window slots 12..15 + spill |
| T3 | RD-JIT nano arena (`lib/rd_jit_vm`) | innermost native tier | Golomb slots, Padovan split |

Nesting means: the sealed bytecode of tier `i+1` is an operand stream inside
tier `i`. Execution brackets are explicit:

```text
EnterVM(tier) ... payload ... ExitVM(tier)
```

Every `EnterVM` pushes a tier frame (registers, VPC, flags, digest) and every
`ExitVM` pops it, mirroring the exception-frame discipline of
Compiling-Exceptions-Correctly.

### Nesting diagram

```text
T0  trampoline
 \  
  T1 threaded VM          EnterVM ---- figure-figure partition of slot space
   \  
    T2 SJIT chunker       EnterVM ---- Kolakoski fission, ruler wipe cascade
     \  
      T3 RD-JIT arena     innermost payload, Rule 30 wipe
```

### Tier transition contract

For each adjacent pair `(Ti-1, Ti)`, following Interpreter_Optimizations:

1. Define `erase_i : Instr(Ti) -> Instr(Ti-1)` (the `norm_instr` analogue).
2. Define `match_i` as an inductive relation between tier states, requiring
   well-formedness of both sides and instruction-level agreement after
   erasure.
3. Prove lockstep simulation in both directions: any step of `Ti` is matched
   by a step of `Ti-1` and vice versa, final states correspond.
4. Conclude `bisim(Ti-1, Ti)`; composition across the stack is the VeriComp
   composition law.

In OCaml these are tested properties, not HOL proofs: the differential fuzzer
pattern of `test/test_stack_jit_fuzz.ml` is instantiated per tier pair with
`reference_eval` as the oracle of `Ti-1`.

## OEIS Sequence Assignments

New sequences introduced by this plan. Constants go to
`lib/constants/magic_numbers.ml` per repository rule 3.

| Sequence | Property used | Nesting application | Module |
|---|---|---|---|
| A000108 Catalan | Dyck words count well-nested brackets | Well-nestedness invariant of `EnterVM`/`ExitVM`; nesting checksum = rank of the Dyck word; forced early `ExitVM` breaks the rank | `lib/stack_vm/stack_ir.ml`, balance pass |
| A004001 Hofstadter-Conway | `a(n) = a(a(n-1)) + a(n-a(n-1))`, `a(n) ~ n/2` | Self-referential tier dispatch: the tier interpreting step `n` is selected by the sequence's own past values; clustering near `n/2` keeps handoff fanout near 2 and depth growth logarithmic | `lib/multi_vm` dispatcher |
| A005228 / A030124 Figure-Figure | Complementary pair R and S partition the integers | Table-free ownership split of the nested slot space into tier-owned and honeypot units; gaps grow non-linearly, harder to invert than the Beatty split | arena partitioning |
| A061775 Matula-Goebel (relatives A184155, A198323) | Bijection between naturals and rooted trees | Encode the whole VM containment tree (which tier hosts which) as one 64-bit topology digest; any topology tamper changes the digest | topology integrity |
| A287654, A249569 meta-Fibonacci | Chaotic nested recurrences | Inter-layer handoff jitter: decorrelates adjacent layers' traces so a single tracer cannot align tier boundaries | `lib/multi_vm` scheduling |

Sequences already registered in the repository and reused per tier:

| Sequence | Existing use | Per-tier reuse |
|---|---|---|
| A000002 Kolakoski | chunk fission | fission with tier-scaled run lengths |
| A001511 ruler | fractal wipe | wipe cascade across depth `d`: level `<= A001511(t) - d` |
| A010060 Thue-Morse | dummy padding | per-layer dummy injection with layer offset |
| A000201 / A001950 Beatty | arena real/honeypot split | kept for the flat (depth-1) arena |
| A000931 Padovan | buffer split | one code/meta/spill triple per tier |
| A000166 derangements | register shuffle | shuffle at every tier boundary |
| A002487 Stern | affine transfer factors | transfer encryption between tiers |
| A000695 Moser-de Bruijn | immediate blinding | cross-tier immediate transport |
| A269160 Rule 30 | wipe gamma | per-tier wipe gamma |
| A003022 Golomb | slot placement | slot placement per tier |

## Tier Dispatch Detail (A004001)

The Hofstadter-Conway sequence indexes itself twice per step, which is the
structural analogue of a VM interpreting a VM. Its Conolly property (`a(n)`
is the frequency of `floor((n+1)/2)`, and `a(n) ~ n/2`) means:

- the dispatch value at step `n` stays near `n/2`, so the tier index (taken
  modulo depth) alternates in short runs rather than oscillating wildly;
- handoff fanout is bounded near 2, keeping the nesting depth effectively
  logarithmic in the step count.

The dispatch table is precomputed offline at packaging time (offline
invariant, no network), stored sealed, and the runtime branch is a single
masked table lookup.

## Topology Integrity (A061775)

The containment relation of a nested build is a rooted tree: T0 contains T1
contains T2 contains T3, plus any sibling payloads. The Matula-Goebel number
of that tree is a single 64-bit value computed at packaging time. At exit the
digest is recomputed and compared; a mismatch means the nesting shape was
altered at runtime (injected tier or skipped layer) and the run aborts into
the decoy manifold.

## Verification Plan

1. Per-tier differential fuzz: extend `test/test_stack_jit_fuzz.ml` into a
   parameterized harness; oracle is the reference evaluator of the tier
   below; three fission scales per tier, as in the existing fuzzer.
2. Well-nestedness property: for every generated program, the bracket prefix
   condition `#EnterVM >= #ExitVM` holds and totals are equal (Dyck
   condition); the Catalan-rank checksum is checked by the same harness.
3. Determinism: same seed produces the same Matula topology digest and the
   same dispatch table (golden test).
4. Hardware end-to-end: `sjit_showcase`-style assertion sets executed at
   nesting depths 2 and 3 on Apple Silicon, exact-value comparison.
5. Negative controls: reverting any erasure or schedule fix must turn the
   corresponding fuzz property red, mirroring the practice documented for the
   SJIT fuzzer.

## Implementation Phases

1. N1: bracket opcodes and Catalan checksum in `lib/stack_vm/stack_ir.ml`,
   enforced by `Stack_balance_pass`.
2. N2: A004001 dispatch table and dispatcher hook in `lib/multi_vm`, behind a
   config flag, default off.
3. N3: figure-figure arena partition for nested slot ownership.
4. N4: Matula topology digest computation and runtime comparison.
5. N5: meta-Fibonacci inter-layer jitter of handoff timing.
6. N6: erasure/match/bisimulation harness instantiated for each tier pair,
   registered in `test/run_tests.ml`.

Each phase is independently shippable and reversible via its config flag.

## Threat-Model Impact

- Peeling one layer no longer recovers semantics; each layer costs a full
  reversing cycle multiplied by the depth.
- Tier schedules are mutually decorrelated (meta-Fibonacci jitter), so
  cross-layer trace alignment fails.
- Topology tampering (layer skipping, tier injection) is detected by the
  Matula digest.

Limitations: dispatch overhead grows roughly linearly with depth
(approximately 2-3x per tier), so the practical depth cap is 3 to 4; nested
state increases memory by one context frame per tier.

## Related Documents

- [OEIS Mathematical Sequences](./OEIS_MATHEMATICAL_SEQUENCES.md) for the
  sequences already in production.
- [VM Protector](./VM_PROTECTOR.md) for the overall protection pipeline.
- [Stack JIT VM Prototype](./STACK_JIT_VM_PROTOTYPE.md) for the SJIT tier.

## References

- VeriComp, AFP: https://isa-afp.org/entries/VeriComp.html
- Interpreter_Optimizations, AFP: https://isa-afp.org/entries/Interpreter_Optimizations.html
- Jinja, AFP: https://isa-afp.org/entries/Jinja.html
- JinjaThreads, AFP: https://isa-afp.org/entries/JinjaThreads.html
- Compiling-Exceptions-Correctly, AFP: https://isa-afp.org/entries/Compiling-Exceptions-Correctly.html
- OEIS A000108: https://oeis.org/A000108
- OEIS A004001: https://oeis.org/A004001
- OEIS A005228: https://oeis.org/A005228
- OEIS A030124: https://oeis.org/A030124
- OEIS A061775: https://oeis.org/A061775
- OEIS A287654: https://oeis.org/A287654
- OEIS A249569: https://oeis.org/A249569
