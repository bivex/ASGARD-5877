# ASGARD-5877

[![License: BUSL-1.1](https://img.shields.io/badge/license-BUSL--1.1-blue.svg)](LICENSE)
[![OCaml](https://img.shields.io/badge/OCaml-5.4.1-3be5b0.svg)](dune-project)
[![Topics](https://img.shields.io/github/topics/bivex/ASGARD-5877?color=blue)](https://github.com/bivex/ASGARD-5877#readme)

An OCaml 5 toolchain for two related jobs:

- **vISA synthesizer** — randomizes a RISC-V-style vector ISA, exports a formal Sail model, and generates a C++/C11 emulator together with a hardware cost estimate.
- **VM-Protector** — lifts native ARM64, x86_64 and RISC-V code into a virtualized C++20 runtime and applies obfuscation passes to the result.

Both are exposed through one CLI, `random_visa`, over a hexagonal (ports and adapters) codebase.

## Requirements

- OCaml >= 4.14 (developed and tested on 5.4.1)
- Dune >= 3.0
- `clang++` with C++20, or `g++` 15+, or MSVC 19+
- Optional: GNU Octave or MATLAB (benchmark scripts), Z3 (SMT benchmark), Python 3 (differential fuzzing), IDA Pro with `idasql` (binary audit)

## Installation

```bash
opam install dune menhir cmdliner alcotest qcheck qcheck-alcotest \
  yojson bos fpath ppx_deriving_yojson ocamlgraph
```

## Build

```bash
make build
```

The CLI lands in `_build/default/bin/main.exe`. Run it with `dune exec random_visa -- <command>`.

## Testing

```bash
make test        # dune runtest
./run_tests.sh   # same, plus stale-process cleanup and signal handling
```

`test/run_tests.exe` aggregates 44 suites. Ten standalone executables cover the parts that need a separate process:

```bash
dune exec test/test_cpp_codegen.exe            # typed C++20/C11 EDSL and pre-flight validator
dune exec test/test_bytecode_amplifier.exe
dune exec test/test_pipeline_phase_guard.exe
dune exec test/test_key_feedback_consistency.exe
dune exec test/test_cff_key_coupling.exe
dune exec test/test_mba_mod64_crosscheck.exe
dune exec test/test_mba_noise.exe
dune exec test/test_hw_binding.exe
dune exec test/test_chameleon_handlers.exe
dune exec test/test_tier4_nextgen.exe
```

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

Mark the functions to virtualize with the macros from `examples/asgard_obf.h`; signatures and callers stay untouched.

```c
#include "asgard_obf.h"

int64_t verify_license_module(int64_t hwid, int64_t user_serial) {
    int64_t valid = 0;

    ASGARD_BEGIN_ULTRA("LicenseCore");

    int64_t expected = ((hwid ^ 0x5877) * 42) + 0x1337;
    valid = (user_serial == expected);

    ASGARD_END();

    return valid;
}
```

Markers: `ASGARD_BEGIN_VIRTUALIZE`, `ASGARD_BEGIN_ULTRA`, `ASGARD_BEGIN_MUTATION`, `ASGARD_END`.

Run the protector. `--seed` takes a decimal integer.

```bash
dune exec random_visa -- protect-arm64 \
  -i examples/license_check.c \
  -o ./protected_out \
  --engine=stack \
  --cff \
  --mba \
  --mba-depth 4 \
  --seed 1337 \
  --compile true
```

The output directory holds the rewritten sources, the generated runtime and the encrypted bytecode:

```text
protected_out/
├── app_arm64.s              # lifted assembly
├── app_obf.c                # source after macro obfuscation
├── app_virtualized.cpp      # trampolines into the VM
├── runner.cpp               # host program loading the bytecode
├── stack_vm_runtime.hpp     # generated VM runtime
├── asg_tech_2601.hpp        # exception-handling shadowing
├── asg_tech_2603.hpp        # non-linear VPC dispatch
├── asg_tech_2608.hpp        # chaff memory pools
├── asgard_obf.h             # marker macros
└── protected.vanguard       # encrypted bytecode
```

A whole project is protected in one pass, and every marked function shares a single runtime:

```bash
dune exec random_visa -- project \
  --dir ./examples/multi_file_project/src \
  --output ./protected_app \
  --cff \
  --mba \
  --seed 42
```

### Engines

`--engine` selects the runtime the protected code executes on.

| Engine | Description |
|---|---|
| `threaded` | Direct-threaded C++ VM with computed GOTO dispatch (default) |
| `stack` | Stack-VM: NOR/NAND universal logic, per-block encrypted keys, ten-phase pipeline |
| `multi` | Two heterogeneous VMs bridged by an affine zero-bridge |
| `jit` | Register-driven JIT with modular (RNS) arithmetic |

`protect-riscv` defaults `--compile` to `false`; the other protectors default it to `true`.

### Stack-VM pipeline

`--engine=stack` runs ten passes in order and checks the program invariants after each one (`lib/stack_vm/stack_phase_guard.ml`):

1. Lowering from VM-IR to Stack IR.
2. Superoperator fusion, before amplification.
3. Bytecode amplification: Horner polynomials, carry chains, def-use webbing.
4. Superoperator fusion, after amplification.
5. MBA constant synthesis: `PushImm` replaced by NOR/NAND/ADD sequences.
6. Virtual CFG flattening with a VPC dispatcher.
7. Spaghetti CFG splitting.
8. Ghost stack padding.
9. State-feedback rolling key, coupled to the VPC.
10. Stack balance repair.

Encoding follows: a per-build polymorphic opcode map, optional compact immediates and randomized field layout, per-block SipHash-1-2 keys, a payload tag verified before the first fetch, and optional address-bound keys.

### Configuration

```bash
dune exec random_visa -- init-config --output asgard.json --preset max
```

Presets: `min`, `light`, `default`, `high`, `max`, `stealth`. The JSON file overrides the command-line flags; `samples/protection_config.full.json` is a complete example.

### Other protection passes

| Pass | Location | Purpose |
|---|---|---|
| CFG flattening, opaque predicates | `lib/cff/` | IR-level dispatcher flattening |
| MBA, e-graph equality saturation | `lib/mba_engine/` | Non-linear expansion, algebraic rewriting |
| Tech-2601 exception shadowing | `lib/tech_2601/` | Sealed ABI unwind metadata |
| Tech-2603 non-linear VPC dispatch | `lib/tech_2603/` | Removes monotonic VPC patterns |
| Tech-2608 anti-trace synthesis | `lib/tech_2608/` | Chaff pools, decoy side effects |
| C/C++ macro obfuscation | `lib/c_macro_obf/` | Polymorphic macros, stack strings, nanomites |
| Anti-tamper and SMC | `lib/native_vm/` | W^X dual mapping, section hashing, timing watchdogs |
| Metamorphic handlers, ring codec | `lib/native_vm/` | Polymorphic handler bodies, value-space automorphism |
| Metal GPU synthesis | `lib/gpu_synth/` | Parallel MBA synthesis, avalanche checks |

## Repository layout

| Path | Contents |
|---|---|
| `lib/domain/` | vISA domain model, hardware cost model, Sail AST |
| `lib/ports/`, `lib/adapters/` | Sail export and parse, assemblers, C/C++ emitters, compiler and lifter adapters |
| `lib/application/` | Use-case pipelines |
| `lib/vm_ir/` | Shared VM IR, lazy flags, ring codec, rolling key, opaque predicates |
| `lib/arm64_lifter/`, `lib/x86_lifter/`, `lib/riscv_lifter/` | Native lifters: ARM64 with NEON, x86_64, RV64GC plus RVV |
| `lib/mba_engine/`, `lib/cff/` | MBA expansion and e-graph saturation, CFG flattening, path digest |
| `lib/stack_vm/` | Stack-VM engine and the ten passes |
| `lib/native_vm/` | Direct-threaded VM, metamorphic handlers, anti-tamper runtime |
| `lib/multi_vm/`, `lib/rd_jit_vm/` | Multi-VM zero-bridge, register-driven JIT |
| `lib/cpp_codegen/` | Typed C++20/C11 AST, printer, pre-flight validator |
| `lib/bytecode_crypto/` | SHA-256, HMAC-SHA256, Speck, block key derivation |
| `lib/tech_2601/`, `lib/tech_2603/`, `lib/tech_2608/` | Runtime headers for the three research passes |
| `lib/macho/` | Mach-O reader with `LC_ROUTINES` / `LC_ROUTINES64` support and compact unwind checks |
| `lib/c_macro_obf/`, `lib/gpu_synth/`, `lib/vanguard_9292/` | Macro obfuscator, Metal synthesis, polymorphic bytecode codec |
| `bin/` | CLI drivers and auxiliary executables |
| `test/` | Test suites and golden fixtures |
| `examples/` | Protection examples, corpora, fuzzers |
| `scripts/` | Benchmark, audit and backup runners |
| `fstar/` | F* proofs and the OCaml extracted from them |
| `docs/` | Specifications and guides |

## Benchmarks and audits

```bash
scripts/run_real_world_benchmarks.sh   # OpenSSL, Coreutils, SQLite, WireGuard, Zstandard
scripts/run_benchmark_arm64.sh         # entropy, SMT recovery, avalanche, divergence
scripts/build_corpus_arm64.sh          # eight-seed polymorphic corpus
scripts/audit_protected_binary.sh <binary> [bytecode]
make diff-fuzz-libfuzzer               # differential fuzzing against the native build
```

`scripts/audit_protected_binary.sh` checks a built binary for leftover strings and symbols, parasitic imports and decompiler resilience, and exits non-zero when an assertion fails.

The compact unwind information of a Mach-O image is audited separately:

```bash
dune exec random_visa -- macho-unwind --input ./protected_app
```

The command reads the `LC_ROUTINES` and `LC_ROUTINES64` load commands, checks the routine table against `__TEXT,__text` and `__TEXT,__unwind_info`, and exits non-zero when the two disagree. The protection pipeline runs the same check on the binary it produced and reports it in the protection summary.

## Documentation

- [VM Protector architecture](docs/VM_PROTECTOR.md): VM design, handler set, trampolines, Mach-O compact unwind support.
- [Devirtualization resistance and entropy model](docs/ENTROPY_MODEL.md): threat model, DRS scoring.
- [Real-world benchmarks](docs/REAL_WORLD_BENCHMARKS.md): production corpus results.
- [Pipeline compatibility audit](docs/PIPELINE_COMPAT_AUDIT.md): per-phase invariant audit.
- [Formal verification](docs/FORMAL_VERIFICATION.md): F* and Z3 proof workflow.
- [Macro obfuscator](docs/C_MACRO_OBF.md): the `c-obf` engine.
- [Differential fuzzing guide](docs/DIFFERENTIAL_FUZZING_GUIDE.md): setup and known bug classes.
- [Windows ARM64 debugging](docs/PARALLELS_WINDOWS_DEBUGGING.md): running under Parallels.
- [Markdown style guide](docs/markdown-style-guide.md): documentation rules for this repository.
- [Archive](docs/archive/): completed roadmaps and specifications.
- [Changelog](CHANGELOG.md).

## License

**Business Source License 1.1 (BUSL-1.1)** — the full text is in [`LICENSE`](LICENSE).

- **Open source is free.** You may use, modify and redistribute the code, including in production, as long as the project is distributed under an open source license approved by the OSI and the full source — yours and the modifications — is published under that license.
- **Commercial use is licensed.** Using the tool in a proprietary product, embedding it into a closed-source product, or offering it as a hosted or embedded service needs a commercial license.
- **It opens up on its own.** Three years after a version is published it converts to the Apache License 2.0.

The source code in this repository is public and stays public: the license restricts commercial *use*, not *reading*. Evaluation, testing, prototyping, research and education are allowed for everyone.
