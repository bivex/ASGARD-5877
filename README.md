# ASGARD-5877

[![License: BUSL-1.1](https://img.shields.io/badge/license-BUSL--1.1-blue.svg)](LICENSE)
[![OCaml](https://img.shields.io/badge/OCaml-5.4.1-3be5b0.svg)](dune-project)
[![Release](https://img.shields.io/github/v/release/bivex/ASGARD-5877)](https://github.com/bivex/ASGARD-5877/releases)
[![Topics](https://img.shields.io/badge/topics-x86--64%20%7C%20ARM64%20%7C%20RISC--V%20%7C%20CFF%20%7C%20MBA%20%7C%20F%2A-blue?style=flat)](https://github.com/topics/virtual-machine)

An OCaml 5 toolchain for two related jobs:

- **vISA synthesizer** — randomizes a RISC-V-style vector ISA, exports a formal Sail model, and generates a C++/C11 emulator together with a hardware cost estimate.
- **VM-Protector** — lifts native ARM64, x86_64 and RISC-V code into a virtualized C++20 runtime and applies obfuscation passes to the result.

Both are exposed through one CLI, `random_visa`, over a hexagonal (ports and adapters) codebase.

## Requirements

- OCaml >= 4.14 (developed and tested on 5.4.1)
- Dune >= 3.0
- `clang++` with C++20, or `g++` 15+, or MSVC 19+
- Optional: Z3 (SMT verification), Python 3 (synthesis scripts), IDA Pro with `idasql` (binary audit), LLDB (virtual bytecode debugging)

## Installation

```bash
opam install dune menhir cmdliner alcotest qcheck qcheck-alcotest \
  yojson bos fpath ppx_deriving_yojson ocamlgraph
```

## Build

```bash
dune build bin/main.exe
```

The CLI lands in `_build/default/bin/main.exe`.

## Testing

```bash
./run_tests.sh
# or targeted:
dune build test/run_tests.exe
_build/default/test/run_tests.exe test "Stack-VM Execution Engine"
_build/default/test/run_tests.exe list    # all registered suites
```

Suites are matched by regex against the suite name. Per the rules in `AGENTS.md`: run only the suite covering the area you changed; full `dune runtest` is reserved for cross-cutting changes.

| Area | Suite name |
|---|---|
| x86 lifter | `x86_64 Lifter & CFG` |
| ARM64 lifter | `ARM64 Lifter & CFG` |
| RISC-V lifter | `RISC-V Lifter & CFG` |
| Native / threaded VM | `Native Threaded VM`, `Native VM Sub-width Semantics` |
| VM IR and flags | `VM-IR & Lazy Flags` |
| Stack-VM pipeline | `Stack-VM Execution Engine` |
| Stack-JIT chunker | `Stack-JIT VM & Chunker` |
| Register-driven JIT | `Register-Driven JIT VM` |
| Multi-VM nested stack | `Multi-VM Nested Stack` |
| Mach-O reader | `Mach-O Compact Unwind` |
| C++ EDSL | `Cpp Codegen` (standalone: `dune build test/test_cpp_codegen.exe`) |
| C macro obfuscator | `C Macro Obfuscation` |
| Anti-analysis | `Anti-Analysis (MBA & CFF)` |

## Usage

### Commands

| Command | Purpose |
|---|---|
| `generate` | Synthesize a randomized V-ISA, export Sail, generate a C++ emulator |
| `parse` | Parse a Sail specification and inspect its instructions |
| `assemble` | Assemble vector assembly into `.vbc` bytecode |
| `disassemble` | Decode `.vbc` back into vector assembly |
| `cost` | Evaluate hardware feasibility and silicon cost of an ISA spec |
| `protect` | Virtualize x86_64 assembly or C source |
| `protect-arm64` | Virtualize ARM64 assembly or C source |
| `protect-riscv` | Virtualize RISC-V assembly or C source |
| `c-obf` | Obfuscate C source with polymorphic macros and stack strings |
| `project` | Protect a multi-file C/C++ project under one runtime |
| `vanguard` | Generate Vanguard-9292 polymorphic bytecode and run it |
| `init-config` | Write an annotated JSON protection configuration |
| `macho-unwind` | Inspect and repair the compact unwind information of a Mach-O image |

`dune exec random_visa -- <command> --help=plain` lists every flag.

### Protecting code

Mark functions with the macros from `examples/asgard_obf.h`; signatures and callers stay untouched.

```c
#include "asgard_obf.h"

int64_t verify_license(int64_t hwid, int64_t serial) {
    int64_t valid = 0;

    ASGARD_BEGIN_ULTRA("LicenseCore");

    int64_t expected = ((hwid ^ 0x5877) * 42) + 0x1337;
    valid = (serial == expected);

    ASGARD_END();

    return valid;
}
```

Markers: `ASGARD_BEGIN_VIRTUALIZE`, `ASGARD_BEGIN_ULTRA`, `ASGARD_BEGIN_MUTATION`, `ASGARD_END`.

```bash
dune exec random_visa -- protect-arm64 \
  -i examples/license_check.c \
  -o ./protected_out \
  --engine=stack \
  --cff \
  --mba \
  --seed 1337 \
  --compile true
```

Output directory:

```text
protected_out/
├── app_arm64.s              # lifted assembly
├── app_obf.c                # source after macro obfuscation
├── app_virtualized.cpp      # trampolines into the VM
├── runner.cpp               # host program loading the bytecode
├── stack_vm_runtime.hpp     # generated Stack-VM runtime
├── jit_vm_runtime.hpp       # (engine=jit) Stack-JIT runtime
├── asg_tech_2601.hpp        # exception-handling shadowing
├── asg_tech_2603.hpp        # non-linear VPC dispatch
├── asg_tech_2608.hpp        # chaff memory pools
├── asg_comp_stall.hpp       # computational stalling
├── asgard_obf.h             # marker macros
└── protected.vanguard       # encrypted bytecode
```

Whole projects are protected in one pass:

```bash
dune exec random_visa -- project \
  --dir ./examples/multi_file_project/src \
  --output ./protected_app \
  --cff --mba --seed 42
```

### Engines

`--engine` selects the runtime.

| Engine | Description |
|---|---|
| `threaded` | Direct-threaded C++ VM with computed GOTO dispatch (default) |
| `stack` | Stack-VM: 28-pass hardening pipeline, per-block SipHash-1-2 keys |
| `stack_jit` / `jit` | Stack-JIT: sealed nano-chunk execution with elastic register window |
| `multi` | Two heterogeneous VMs bridged by an affine zero-bridge |

### Stack-VM hardening pipeline

`--engine=stack` runs a 28-phase pipeline. Phases are checked by `stack_phase_guard.ml` after each transformation:

| Phase | Pass | Purpose |
|---|---|---|
| 1 | IR Lowering | ARM64/x86/RISC-V VM-IR → Stack-IR |
| 2a | Superoperator Fusion (pre) | Fuse matched Stack-IR patterns before amplification |
| 2a-mult | Handler Multiplicity | Metamorphic opcode cloning with 5 neural-synthesized subtraction families |
| 2 | Bytecode Amplification | Horner polynomial, carry-chain, and def-use webbing expansion |
| 2a | Superoperator Fusion (post) | Fuse synthesized constant sequences |
| 2b | MBA Constant Synthesis | Replace `PushImm` with NOR/NAND/ADD sequences; E-graph equality saturation |
| 2c | Braided CFG Merging | Fuse live block pairs into isomorphic braided nodes |
| 2d | Homomorphic Operand Blinding | Ciphertext-space operand masking |
| 3 | Virtual CFG Flattening | Route jumps through polymorphic VPC dispatcher with Z3-verified opaque predicates |
| 4 | Spaghetti Block Splitting | Split blocks post-CFF |
| 5 | Ghost Stack Padding | Inject De Morgan zero-knot junk ops per block |
| 5b | Avid Junk Operands | Variable-size avid junk with flag-neutral Mul drain |
| 5g | T-Function Trace Closure | Close PDG edges to prevent backward slicing |
| 5d | Stateful Transducer Coupling | Couple ALU expressions to evolving state register |
| 5e | PolyMBA Non-Linear Expansion | Degree-2 quadratic cross-terms and dynamic shifts |
| 5h | Mixed-Characteristic Finite Field | Mersenne-31 and GF(2⁶⁴) arithmetic knots |
| 5c | Memory-Address Entanglement | Bind scratch ring through physical RAM loads/stores |
| 5i | I/O Sink Slicing Barrier | Bind intermediate state to observable sinks |
| 5j | Dual-Rail Complement Invariance | Dynamic rail evolution with sum/orthogonality checkpoints |
| 6b | Cross-Block Path Traps | Anti-DBI execution path integrity |
| 6c | DRCC Register Window | OEIS A003022 Golomb-4 physical register spilling |
| 6d | Galois LFSR Whitening | Non-linear memory diffing resistance |
| 6e | Wolfram Rule 30 Keystream | CA-driven non-linear keystream diffusion |
| 6f | Native Micro-Handler Interleaving | Interleave sealed native stubs |
| 6 | State-Feedback Rolling Key | Couple SipHash-1-2 cipher stream to register state |
| 7 | Stack Balance | Enforce zero exit delta across all blocks |
| 8 | Pipelined Stage Dispatch | Decouple fetch/chaff/dispatch epilogues |
| 9 | Encoding | Polymorphic opcode map, per-block keys, address binding |

The budget regulator (`stack_budget_regulator.ml`) throttles expansion passes in three zones (comfort ≤ 50%, throttle 50–85%, ceiling > 85%) to prevent multiplicative explosion.

### Stack-JIT VM

`--engine=jit` compiles functions into sealed nano-chunks executed by a register-driven JIT engine:

- **Elastic sliding register window** with automatic L1D `spill_stack` spilling (no fixed depth limit).
- **Dual-domain flags** (`NZCV` vs `vflags`) with non-clobbering ARM64 flag bridge.
- **Multi-block CFG chunking** with Kolakoski fission (OEIS A000002) and Thue-Morse dummy padding (OEIS A010060).
- **Differential fuzzer** (`test_stack_jit_fuzz.ml`): QCheck 1000-seed property suite with deterministic regression replay.
- **Instruction set**: ALU, shifts, division, mul-hi, CMOV, 3-reg CSEL, RESOLVE_SYM, extern calls, CMP_RI, ROR_RI, hardware bit ops (bswap/clz/ctz/rbit/popcnt), PUSH_FLAGS/POP_FLAGS.
- Nano-JIT buffer uses Rule 30 CA wipe instead of zero-fill in `atomic_zeroize`; `mprotect` eliminated on Darwin arm64.

The 19-function showcase (`examples/sjit_showcase/`) runs 77/77 exact assertions with DRS 93.7/100.0 and Composite DRS v2 100.0/100.0 on Apple Silicon:

```bash
examples/sjit_showcase/run_sjit_showcase.sh
```

### Multi-VM nested stack

`--engine=multi` bridges two heterogeneous VMs through an affine zero-bridge. The nested stack architecture (`lib/multi_vm/nested_stack.ml`) uses:

- OEIS A000108 Catalan Dyck word checksums for well-nestedness verification.
- OEIS A004001 self-referential tier dispatch.
- OEIS A005228/A030124 figure-figure complementary partition for tier vs honeypot slots.
- OEIS A061775 Matula-Goebel bijective tree encoding for topology digests.
- OEIS A287654/A249569 meta-Fibonacci jitter for inter-tier handoff.

### Configuration

```bash
dune exec random_visa -- init-config --output asgard.json --preset max
```

Presets: `min`, `light`, `default`, `high`, `max`, `stealth`. JSON overrides CLI flags; `samples/protection_config.full.json` is a complete annotated example.

Key JSON fields:

```json
{
  "cff": { "enabled": true },
  "mba": { "enabled": true, "egraph_rate": 30, "node_limit": 120 },
  "amplifier": { "profile": "light" },
  "vm_runtime": {
    "chameleon_handlers": true,
    "num_dispatch_domains": 4,
    "ephemeral_jit": true,
    "oblivious_memory": true
  },
  "anti_tamper": {
    "enabled": true,
    "hardware_timing_probes": true,
    "nanomites": true
  },
  "toolchain": { "opt_level": "-O1" }
}
```

`ASGARD_PHASE_TIMING=1` logs per-phase wall-clock times to stderr during packaging.

### C macro obfuscation (`c-obf`)

Applied automatically before lifting; also available standalone. Transforms the C source before the compiler sees it:

- **ASG_STR** — converts string literals to variadic static byte arrays decrypted at runtime.
- **ASG_BLIND** — additive and XOR constant splitting.
- **MBA algebraic rewriting** — depth-configurable AST rewrites.
- **Opaque predicates** — non-linear polynomial invariant guards.
- **API hashing** — compile-time FNV-1a import elimination.
- **Hardware timing probes** — cycle-delta threshold guards.
- **Dynamic nanomites** — signal-driven exception state machine.

### Other protection passes

| Pass | Location | Purpose |
|---|---|---|
| CFG flattening, opaque predicates | `lib/cff/` | IR-level dispatcher flattening; 299-variant Z3-verified catalog |
| MBA, E-graph equality saturation | `lib/mba_engine/` | Non-linear expansion, algebraic rewriting |
| Tech-2601 exception shadowing | `lib/tech_2601/` | Sealed ABI unwind metadata |
| Tech-2603 non-linear VPC dispatch | `lib/tech_2603/` | Removes monotonic VPC patterns |
| Tech-2608 anti-trace synthesis | `lib/tech_2608/` | Chaff pools, decoy side effects |
| Computational stalling | `lib/comp_stall/` | RSW time-lock puzzles, Chebyshev attractors, ergodic polynomials |
| Build-seed watermarking | `lib/watermark/` | Embedded per-build cryptographic watermarks |
| Anti-tamper and SMC | `lib/native_vm/` | W^X dual mapping, section hashing, timing watchdogs |
| Metamorphic handlers, domain salts | `lib/native_vm/` | Polymorphic handler bodies; simulated-annealing salt optimizer |
| Metal GPU synthesis | `lib/gpu_synth/` | Parallel MBA synthesis, avalanche checks |
| Vanguard-9292 codec | `lib/vanguard_9292/` | Polymorphic bytecode rolling-key codec |

## Formal verification

F* proofs in `fstar/` are extracted to OCaml and linked into the build:

| Theory | Verifies |
|---|---|
| `Bridge_Verified.fst` | Affine zero-bridge morphism correctness |
| `Cff_Verified.fst` | CFF dispatcher round-trip |
| `Codec_Verified.fst` | Bytecode encode/decode identity |
| `Flags_Verified.fst` | Lazy flag materialization |
| `Lifter_Verified.fst` | Lifter semantic preservation |
| `Mba_Verified.fst` | MBA algebraic equivalence |
| `Nullspace_MBA_Verified.fst` | Null-space synthesis soundness |
| `Poly_Verified.fst` | Polynomial knot identities |
| `Ring_Codec_Verified.fst` | Ring codec bijectivity |
| `Rns_Verified.fst` | Residue number system arithmetic |
| `Rolling_Key_Verified.fst` | Rolling key coupling |
| `Stack_Balance_Verified.fst` | Zero exit-delta invariant |
| `Superop_Verified.fst` | Superoperator semantic equivalence |
| `Transport_Verified.fst` | ABI transport soundness |

Z3 synthesis scripts under `scripts/`: `cff_opaque_synth.py` (299-variant opaque catalog), `zero_knot_synth.py` (25-family zero-knot library), `budget_scheduler_synth.py` (GFlowNet pass-rate schedules), `neural_opcode_synth.py` (TB-GFlowNet opcode synthesizer), `superop_discover.py` + `superop_codegen.py` (exhaustive superoperator pipeline).

## Debugging protected binaries

### LLDB plugin

`tools/lldb/asgard_lldb.py` — a full-featured LLDB Python extension for live inspection of Native Threaded VM and Stack-VM binaries:

- Live virtual register unmasking (affine permutation, SipHash-1-2 KDF, Costas-6 layout, VSP whitening).
- Bytecode disassembly, single-step, breakpoints, execution tracing, state export.
- Commands: `asg-status`, `asg-regs` (`asg-r`), `asg-stack` (`asg-vsp`), `asg-disas` (`asg-d`), `asg-step` (`asg-s`), `asg-break` (`asg-b`), `asg-trace`, `asg-set-reg`, `asg-export`.

```bash
lldb ./protected_app
command script import tools/lldb/asgard_lldb.py
asg-status
asg-regs
```

### IDA Pro plugin

`tools/ida_analyzer/` — GUI plugin with real-time Stack-VM bytecode disassembly, live register unmasking, and jump-to-handler navigation.

### Fuzzers

| Tool | Location | Purpose |
|---|---|---|
| Stack-VM fuzzer | `tools/vm_fuzz_harness/` | Coverage-guided structure-aware bytecode fuzzer |
| Tamper fuzzer | `tools/tamper_fuzzer/` | C++ fault-injection and anti-tamper fuzzer |
| JIT differential fuzzer | `test/test_stack_jit_fuzz.ml` | QCheck translate-trace vs reference-eval, 1000 seeds |
| C macro nanomite fuzzer | `scripts/fuzz_x87.py` | x87 FPU edge-case fuzzing |

## Repository layout

| Path | Contents |
|---|---|
| `lib/domain/` | vISA domain model, hardware cost model, Sail AST |
| `lib/ports/`, `lib/adapters/` | Sail export/parse, assemblers, C/C++ emitters, lifter adapters |
| `lib/application/` | Use-case pipelines and protection orchestrator |
| `lib/vm_ir/` | Shared VM IR, lazy flags, ring codec, rolling key, opaque predicates |
| `lib/arm64_lifter/` | ARM64 with NEON/FP/atomics/PAC/LSE lifter |
| `lib/x86_lifter/` | x86_64 lifter (scalar, SSE, AVX, x87) |
| `lib/riscv_lifter/` | RV64GC + RVV lifter |
| `lib/stack_vm/` | Stack-VM engine: 32 passes, chunker, budget regulator, dead-code analyzer, BV verifier |
| `lib/native_vm/` | Direct-threaded VM, metamorphic handlers, domain salt optimizer, anti-tamper |
| `lib/multi_vm/` | Multi-VM zero-bridge, homomorphic bridge, nested stack (OEIS sequences) |
| `lib/rd_jit_vm/` | Register-driven JIT: buffer, synthesizer, emitter, nano-JIT slots |
| `lib/mba_engine/`, `lib/cff/` | MBA E-graph saturation, CFG flattening, opaque predicate catalog |
| `lib/cpp_codegen/` | Typed C++20/C11 AST, EDSL combinators, printer, scrambler, pre-flight validator |
| `lib/c_macro_obf/` | Macro obfuscator: stack strings, constant blinding, nanomites, MBA rewrites |
| `lib/bytecode_crypto/` | SHA-256, HMAC-SHA256, Speck, SipHash-1-2, block key derivation |
| `lib/tech_2601/`, `lib/tech_2603/`, `lib/tech_2608/` | Research passes: EH shadowing, VPC dispatch, anti-trace |
| `lib/comp_stall/` | Computational stalling: RSW puzzles, Chebyshev, ergodic polynomials |
| `lib/watermark/` | Build-seed watermark embed/extract |
| `lib/macho/` | Mach-O reader with compact unwind and `LC_ROUTINES` support |
| `lib/gpu_synth/` | Metal GPU MBA synthesis |
| `lib/vanguard_9292/` | Polymorphic bytecode codec |
| `lib/constants/` | Magic numbers registry (`magic_numbers.ml`) |
| `lib/ports/` | Domainslib domain pool, parallel utilities |
| `bin/` | CLI drivers |
| `test/` | ~671 test cases across all suites |
| `fstar/` | 15 F* proof theories + OCaml extractions |
| `examples/` | License check, SJIT showcase, multi-VM, JIT, fuzzing corpora |
| `tools/` | LLDB plugin, IDA Pro plugin, VM fuzzer, tamper fuzzer |
| `scripts/` | Z3 synthesizers, benchmarks, audit runners |
| `docs/` | Architecture specs, threat model, OEIS sequence catalog |
| `samples/` | Annotated configuration presets |

## Audits and benchmarks

```bash
scripts/audit_protected_binary.sh <binary> [bytecode]
scripts/run_real_world_benchmarks.sh    # OpenSSL, Coreutils, SQLite, WireGuard, zstd
scripts/run_benchmark_arm64.sh          # entropy, SMT recovery, avalanche, divergence
scripts/build_corpus_arm64.sh           # eight-seed polymorphic corpus
dune exec random_visa -- macho-unwind --input ./protected_app
```

`audit_protected_binary.sh` checks for leftover symbols/strings, parasitic imports, and decompiler resilience; exits non-zero on any finding.

`macho-unwind` reads `LC_ROUTINES`/`LC_ROUTINES64`, checks the routine table against `__TEXT,__text` and `__TEXT,__unwind_info`, and exits non-zero on disagreement. The protection pipeline runs the same check automatically and includes the result in the protection report.

## Documentation

- [`docs/VM_PROTECTOR.md`](docs/VM_PROTECTOR.md) — VM design, handler set, trampolines, compact unwind, per-phase mathematical models.
- [`docs/STACK_JIT_VM_PROTOTYPE.md`](docs/STACK_JIT_VM_PROTOTYPE.md) — Stack-JIT architecture, OEIS grounding, AFP bisimulation.
- [`docs/MULTI_VM_NESTED_STACK_PLAN.md`](docs/MULTI_VM_NESTED_STACK_PLAN.md) — Multi-VM nesting plan with AFP/OEIS mapping.
- [`docs/OEIS_MATHEMATICAL_SEQUENCES.md`](docs/OEIS_MATHEMATICAL_SEQUENCES.md) — Every OEIS sequence used and where.
- [`docs/ENTROPY_MODEL.md`](docs/ENTROPY_MODEL.md) — Threat model, DRS v2 scoring methodology.
- [`docs/REAL_WORLD_BENCHMARKS.md`](docs/REAL_WORLD_BENCHMARKS.md) — Production corpus results.
- [`docs/PIPELINE_COMPAT_AUDIT.md`](docs/PIPELINE_COMPAT_AUDIT.md) — Per-phase invariant audit.
- [`docs/FORMAL_VERIFICATION.md`](docs/FORMAL_VERIFICATION.md) — F* and Z3 proof workflow.
- [`docs/C_MACRO_OBF.md`](docs/C_MACRO_OBF.md) — `c-obf` engine.
- [`docs/DEAD_CODE_ANALYSIS.md`](docs/DEAD_CODE_ANALYSIS.md) — Stack-VM dead code causality analyzer.
- [`docs/DIFFERENTIAL_FUZZING_GUIDE.md`](docs/DIFFERENTIAL_FUZZING_GUIDE.md) — Fuzzer setup and known bug classes.
- [`docs/PARALLELS_WINDOWS_DEBUGGING.md`](docs/PARALLELS_WINDOWS_DEBUGGING.md) — Running under Parallels/Windows ARM64.
- [`CHANGELOG.md`](CHANGELOG.md)

## License

**Business Source License 1.1 (BUSL-1.1)** — full text in [`LICENSE`](LICENSE).

- **Open source is free.** Use, modify and redistribute under any OSI-approved open source license as long as the full source is published.
- **Commercial use is licensed.** Using the tool in a proprietary product, embedding it in a closed-source product, or offering it as a hosted or embedded service requires a commercial license.
- **Converts automatically.** Three years after a version is published it converts to Apache License 2.0.

The source is public and stays public: the license restricts commercial *use*, not *reading*. Evaluation, testing, prototyping, research, and education are unrestricted.
