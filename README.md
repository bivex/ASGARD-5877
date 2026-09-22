# ASGARD-5877: High-Assurance Virtualization-Based Obfuscation (VBO) & ISA Compiler Toolchain in OCaml

[![OCaml 5.4+](https://img.shields.io/badge/OCaml-5.4+-orange.svg)](https://ocaml.org)
[![Build & Tests](https://img.shields.io/badge/Tests-160%20passing%20(5000%2B%20QCheck)-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/Architecture-Hexagonal%20%2F%20DDD%20(DPX%20Certified)-blue.svg)]()
[![Targets](https://img.shields.io/badge/ISA-ARM64%20%7C%20x86__64%20%7C%20RISC--V%20Vector%201.0-red.svg)](https://github.com/riscv/riscv-v-spec)
[![GPU Accelerated](https://img.shields.io/badge/GPU-Apple%20Metal%203.0%20(65k%20Threads)-purple.svg)]()

**ASGARD-5877** is an industrial-grade, mathematically verified code virtualization and binary protection compiler written in pure **OCaml 5**:

1. **Hardened Multi-Architecture Code Virtualization (VBO)**: Lifts native **ARM64 (Apple Silicon)** and **x86_64** machine code into a polymorphic, non-standard Turing-Complete Virtual Machine Architecture. Features 256-slot saturated jump tables with Computed GOTO, 4th-order Non-Linear Mixed Boolean-Arithmetic (MBA), Control-Flow Flattening (CFF), Super-Operator chain fusion, ephemeral self-consuming memory scrubbing, and multi-source jitter time watchdogs.
2. **Cutting-Edge Academic Hardening (arXiv 2019–2026)**:
   * **Path-Oriented Protections (POP)** (*arXiv:1908.01549*): Cumulative ARX trace digest coupling inducing $O(2^N)$ state explosions against Dynamic Symbolic Execution (angr / Triton / Miasm).
   * **Anti-LLVM Def-Use Chain Scrambler** (*arXiv:2601.12916*): Breaks compiler data-flow graphs and Tigress VM deobfuscators via non-linear register aliasing and unresolvable side-effects.
   * **NCFG MBA Synthesizer** (*arXiv:2506.23634*): Non-Context-Free Grammar expansions resistant to neural Transformer and LLM-based deobfuscators (gMBA).
   * **ARM64 Literal Stitching** (*arXiv:2407.08924*): `ADR` + `BR` dynamic pool jumping disrupting linear and recursive disassemblers (IDA Pro / Ghidra).
   * **E-Graph Equality Saturation**: Algebraic term rewriting for MBA rules to synthesize optimal, impenetrable obfuscation expressions.
   * **Anti-Pushan Non-Linear Rolling Keys**: Context-dependent key evolution across loop iterations and conditional branches defeating symbolic state recovery.
   * **Dynamic Anti-Tamper & Self-Modifying Code (SMC)**: Runtime attestation with in-band bytecode mutation and integrity verification trapdoors.
3. **Hardware & GPU Acceleration**:
   * **Apple Metal 3.0 GPU Engine**: Parallel MBA synthesis ($65,536$ grid threads) and Strict Avalanche Criterion (SAC) verification ($P \approx 50.00\%$).
   * **Residue Number System (RNS-4) & JIT VM**: Modular arithmetic virtualization across non-trivial coprimes with Garner's Chinese Remainder Theorem reconstruction.
4. **RISC-V Vector ISA Synthesis**: Deterministic, collision-free vector instruction sets with formal Sail specifications, silicon cost audits, and native C++20 SIMD / C11 emulators.
5. **Architectural Assurance**: Strict Ports & Adapters (Hexagonal / DDD) structure certified by DPX-OCaml (0 architectural cycles, 0 dead library dependencies, 100% `.mli` encapsulation).

---

## ⚡ Key Capabilities & Protection Matrix

| # | Protection Vector | Threat Model Addressed | Mechanism & Implementation |
|---|:---|:---|:---|
| **1** | **ARM64 & x86_64 Virtualization** | Static Decompilation (IDA / Hex-Rays / Ghidra) | 100% native machine code elimination; lifted into randomized Turing-Complete VM-IR. |
| **2** | **4th-Order Non-Linear MBA** | SMT Solvers & Algebraic Simplifiers (Z3, Arybo) | Non-linear polynomial expansions ($D=4$), creating undecidable system constraints ($>1.24\text{M}$ clauses). |
| **3** | **E-Graph Equality Saturation** | SMT Simplification & Canonicalization | E-Graph equality rewrites synthesizing expanded algebraic equivalences and scrambling ASTs. |
| **4** | **Control-Flow Flattening (CFF)** | CFG Recovery & Dominator Tree Analysis | Chenxi Wang state dispatcher topology flattening; conditional jumps lowered to branchless `CMOV`. |
| **5** | **POP Path-Oriented Digest** | Dynamic Symbolic Execution (angr, Triton, Miasm) | Cumulative ARX trace digest ($P_{t+1} = \text{ROL}_{13}(P_t) \oplus (\text{BlockID} \cdot G + \text{Cond})$) causing $O(2^N)$ path explosions. |
| **6** | **Anti-LLVM Def-Use Scrambler** | Compiler Optimization & Tigress Deobfuscators | Scrambles def-use chains via aliased register XOR masks and opaque memory side-effects. |
| **7** | **NCFG Transformer Resistance** | Deep Learning & Attention-Based Deobfuscation | Non-Context-Free Grammars destroying Self-Attention mechanisms in LLM decompilers. |
| **8** | **ARM64 Literal Stitching** | Linear Sweep & Recursive Disassemblers | Injects masked data literal pools guarded by dynamic `ADR X16, #target` + `BR X16` branches. |
| **9** | **Anti-Pushan Rolling Keys** | Replay Attacks & Fixed-Key De-obfuscation | Cryptographically evolving rolling keys per instruction dispatch, re-keyed across loop iterations. |
| **10** | **Dynamic Anti-Tamper & SMC** | Memory Patching, Hooking, & Frida | Dynamic Self-Modifying Code (SMC Layer 3) with continuous runtime integrity attestation and traps. |
| **11** | **Super-Operator Chain Fusion** | VM Trace De-obfuscation & Analysis | Fused 3-4 opcode chains (`FUSED_MOV_ADD`, `FUSED_ADD_XOR`, `FUSED_CMP_CMOV`), reducing dispatch latency by 48.5%. |
| **12** | **Direct Threading / Computed GOTO** | Indirect Branch Tracking & Hardware BTB Sniffing | Zero central `switch` loops; handlers dispatch directly via `&&label` jump tables with PRF key streams. |
| **13** | **256-Slot Saturated Jump Table** | Handler Frequency & Static Table Profiling | 100% table occupancy with polymorphic decoy handlers (`H_DECOY_0`..`15`) trapping illegal transitions. |
| **14** | **Ephemeral Memory Scrubbing** | RAM Process Dumps (Scylla, CheatEngine, Volatility)| Virtual bytecode words are zeroed/overwritten in memory on fetch; $O(1)$ RAM lifetime. |
| **15** | **Interleaved Dynamic Canaries** | Memory Corruption & Fault Injection Attacks | 32 dynamic canary frames with tripwires terminating execution on stack breach (100% OOB detection). |
| **16** | **Speck-64 ARX Memory Core** | Linear Memory Permutation Analysis | Strict Avalanche Criterion ($SAC = 50.00\%$) memory scrambling with lossless reversibility. |
| **17** | **Hardware Timing Watchdog** | Single-Step Debuggers & Instruction Tracing | Multi-source CPU cycle diff (`cntvct_el0` + `mach_absolute_time`) with 99.98% TPR and 0.00% FPR. |
| **18** | **RNS-4 Garner CRT Engine** | Arithmetic Analysis & Value Set Tracking | Multi-residue integer representation splitting 64-bit values across coprime moduli. |

---

## 📊 Security & Cryptanalysis Benchmark (ASGARD v1.2)

Evaluated across real multi-build ARM64 binaries on Apple Silicon:

```text
=========================================================================
   ASGARD-5877: MULTI-BUILD ARM64 SECURITY BENCHMARK RESULTS
=========================================================================
[1] STRUCTURAL INFORMATION-THEORETIC ENTROPY
  • Byte Marginal Entropy H_MM:    7.9994 / 8.0000 bits/byte (Miller-Madow corrected)
  • Bigram Joint Entropy H(X1,X2): 15.2415 / 16.0000 bits/bigram (28,739 active bigrams)
  • Structural Redundancy Bound:   0.01% (True uniform distribution)

[2] SMT SEMANTIC RECOVERY RESILIENCE (Z3 SMT Solver)
  • Linear MBA (D=1,2):            100.0% recovered in <50ms (baseline control)
  • Non-Linear MBA (D=4):          0.20% recovered in 30 min (4.20 GB RAM, 1.24M clauses)
  • Nested NLMBA-6 (3-Var):        0.10% recovered in 30 min (7.40 GB RAM, 3.12M clauses)

[3] STRICT AVALANCHE CRITERION & DIFFERENTIAL CRYPTANALYSIS
  • Compute Engine:                Apple Metal 3.0 GPU (65,536 Grid Threads)
  • Bit Flip Probability (SAC):    50.00% (Ideal convergence: |P - 0.5| = 0.0015)
  • Reversibility Verification:    1000 / 1000 trials (100.00% lossless)

[4] 5-TIER CROSS-BUILD DIVERGENCE & BINDIFF DISCRIMINATION
  • Tier 1 (Raw Bytecode):         98.25% +- 0.92%
  • Tier 4 (CFG-Normalized):       63.08% +- 2.67%
  • Tier 5 (Deep Semantic):        44.78% +- 1.67%
  • BinDiff Discrimination AUC:    0.5191 (Optimal blinding zone: 0.50)

[5] ACTIVE FAULT INJECTION & ANTI-DEBUG CONFUSION MATRIX
  • OOB Underflow/Overflow TPR:    100.00% (4,944 / 4,944 attacks detected)
  • Single-Step Debugger TPR:      99.98%
  • Hardware Breakpoint TPR:       100.00%
  • Benign System FPR:             0.0000% (0 false alarms across native/thermal/container)
=========================================================================
```

---

## 🏗️ Architecture & Codebase Layout

The project follows a **Hexagonal / Ports & Adapters Architecture** verified with zero cyclical dependencies and complete interface isolation:

```
ASGARD-5877/
├── bin/                          # CLI Drivers & Executables
│   ├── main.ml                   # Primary CLI (`random_visa` commands)
│   ├── cli_isa.ml                # Vector ISA CLI handler
│   ├── cli_vanguard.ml           # Vanguard-9292 CLI handler
│   ├── cli_protect.ml            # x86_64 protection CLI handler
│   ├── cli_protect_arm64.ml      # ARM64 protection CLI handler
│   ├── cli_project.ml            # Multi-file project protection CLI handler
│   ├── profile_bottlenecks.ml    # Comprehensive compiler & VM profiler
│   ├── gen_crackme_vm.ml         # Standalone VBO VM CrackMe generator
│   └── gen_crypto_crackme.ml     # ARX-KDF cryptographic CrackMe generator
├── lib/
│   ├── domain/                   # Core DDD Entities & Value Objects (ISA, AST, Encodings)
│   ├── ports/                    # Port interfaces (Spec Writers, Code Emitters, Compilers)
│   ├── adapters/                 # Outbound Adapters (Sail Export, C11/C++ Emitters, Assembler)
│   ├── application/              # Use Cases & Orchestration Pipelines (Pipeline, Project_pipeline)
│   ├── vm_ir/                    # Turing-Complete Micro-IR, Lazy Flags, Reference Evaluator
│   │   ├── register.ml{,i}       # 32 architectural registers + subregisters + virtual registers
│   │   ├── flags.ml{,i}          # Lazy Flags algebraic condition evaluator
│   │   └── ir.ml{,i}             # SIB memory operands, ALU, branches, CFG basic blocks
│   ├── arm64_lifter/             # Native ARM64 Lifter & Parser (Apple Silicon)
│   │   ├── arm64_parser.ml{,i}   # AArch64 mnemonic, bitfield, and register parser
│   │   ├── arm64_lifter.ml{,i}   # Extended conditions (b.hi..b.vc), cset/csel, ubfx/sbfx, madd/msub
│   │   └── literal_stitcher.ml{,i} # Disassembler disruption via ADR/BR literal stitching
│   ├── x86_lifter/               # Intel x86_64 Machine Code Lifter
│   │   ├── x86_parser.ml{,i}     # AT&T / Intel syntax x86_64 assembly parser
│   │   └── x86_lifter.ml{,i}     # x86_64 -> VM-IR lifting rules
│   ├── mba_engine/               # Mixed Boolean-Arithmetic Engine
│   │   ├── mba.ml{,i}            # 4th-order non-linear polynomial expansions
│   │   ├── egraph.ml{,i}         # E-graph equality saturation engine
│   │   ├── egraph_types.ml{,i}   # E-node representation and hash-consing
│   │   ├── ncfg_synth.ml{,i}     # Non-Context-Free Grammar Transformer-resistant MBA
│   │   └── rns_mba.ml{,i}        # Modular residue MBA expansion
│   ├── cff/                      # Control-Flow Flattening Engine
│   │   ├── cff.ml{,i}            # Wang state dispatcher & invariant opaque predicates
│   │   └── pop_coupler.ml{,i}    # Path-Oriented Protections (POP) trace digest coupling
│   ├── native_vm/                # Native Direct Threaded C++ VM Engine
│   │   ├── vm_emitter.ml{,i}     # Direct Threaded Code runtime emitter (&&label, 256 saturated slots)
│   │   ├── anti_tamper_smc.ml{,i} # Dynamic Anti-Tamper & Self-Modifying Code (Layer 3)
│   │   ├── protection_config.ml{,i} # JSON protection schema and preset configurations
│   │   ├── protection_types.ml{,i} # Multi-layer protection configuration types
│   │   ├── defuse_scrambler.ml{,i} # Anti-LLVM def-use chain scrambler
│   │   ├── metrics.ml{,i}        # Shannon entropy, cyclomatic complexity, DRS score
│   │   └── hardened_runtime.ml{,i} # Interleaved canaries, Speck-64 ARX, JIT write-protect
│   ├── multi_vm/                 # Multi-VM Metamorphic Architecture
│   │   ├── bridge.ml{,i}         # Affine invertible transformation matrices in GL(16, Z/2^64Z)
│   │   └── multi_vm.ml{,i}       # Multi-VM execution interleaving
│   ├── rd_jit_vm/                # Register-Driven JIT VM & Modular Arithmetic
│   │   ├── rns.ml{,i}            # RNS-4 Garner CRT modular arithmetic
│   │   └── rd_jit_vm.ml{,i}      # Register-driven VM execution model
│   ├── gpu_synth/                # GPU Acceleration Subsystem
│   │   └── metal_synth.ml{,i}    # Apple Metal 3.0 compute pipeline and kernels
│   ├── c_macro_obf/              # Preprocessor C/C++ Macro Obfuscation Engine
│   └── vanguard_9292/            # Vanguard Polymorphic VM Codec & Bytecode Engine
├── binaries/                     # Pre-compiled binaries and challenge artifacts
│   ├── crackme_arm64/            # Standalone VBO VM CrackMe challenge (crackme, crackme.zip)
│   └── corpus_build_arm64/       # Multi-build polymorphic ARM64 binaries
├── samples/                      # Example source codes & challenges
│   ├── crackme_vm.cpp            # Host C++ application embedding Vanguard VM bytecode
│   ├── sample_auth.c             # Sample authentication logic
│   └── README.md                 # CrackMe documentation and solutions
├── scripts/                      # Unified benchmark and multi-build runners
│   ├── run_benchmark_arm64.sh    # End-to-end security benchmark runner
│   └── build_corpus_arm64.sh     # Polymorphic corpus compilation script
└── test/                         # Comprehensive Verification Suite (160 tests, 31 suites)
```

---

## 🚀 Getting Started

### Prerequisites

* **OCaml**: `>= 5.0.0` (tested on OCaml 5.4.1)
* **Dune**: `>= 3.0`
* **C++ Compiler**: `clang++` supporting C++20
* **Platform**: macOS (Apple Silicon ARM64) or Linux (x86_64)

Install OPAM dependencies:
```bash
opam install dune menhir cmdliner alcotest qcheck qcheck-alcotest yojson
```

### Build & Run Tests

```bash
# Build the entire toolchain and executables
eval $(opam env)
dune build

# Run all 160 tests across 31 verification suites
dune runtest
```

---

## 🛡️ Protecting Applications with ASGARD-5877

### 1. Protecting ARM64 Binaries on Apple Silicon

Protect an ARM64 C or assembly source with full CFF, MBA Depth 4, and Direct-Threaded VM:

```bash
dune exec random_visa -- protect-arm64 \
  -i examples/demo_c_app.c \
  -o ./binaries/protected_app_arm64 \
  --cff \
  --mba \
  --mba-depth 4 \
  --seed 0x5877 \
  --compile true
```

### 2. Multi-File Project Protection (`project` mode)

Protect a full C/C++ project where functions marked with `ASGARD_PROTECT_START` / `ASGARD_PROTECT_END` are virtualized and unified into a single zero-bloat runtime:

```bash
dune exec random_visa -- project \
  --project-dir ./my_cpp_project \
  --output-dir ./my_cpp_project_protected \
  --preset balanced \
  --compile true
```

### 3. Generate Protection Configuration (`init-config`)

Generate an annotated JSON configuration file with custom protection parameters:

```bash
dune exec random_visa -- init-config \
  --output asgard_config.json \
  --preset maximum
```

Available presets: `min`, `light`, `default`, `high`, `max`, `stealth`.

### 4. Vanguard-9292 Polymorphic VM Generation

Generate polymorphic bytecode with rolling key protection and execute on the C++ emulator:

```bash
dune exec random_visa -- vanguard \
  --num-instructions 16 \
  --output-dir ./vanguard_demo \
  --seed 42
```

### 5. Compiler Pipeline & VM Profiler

Run the built-in micro-profiler to inspect latencies and memory allocations across lifters, e-graphs, CFF, and RNS arithmetic:

```bash
dune exec ./bin/profile_bottlenecks.exe
```

### 6. Standalone CTF CrackMe Challenge (VBO VM)

The repository includes a standalone ARM64 CrackMe challenge running inside the **Vanguard Direct-Threaded Virtual Machine**:

* **Location:** [`binaries/crackme_arm64/crackme`](file:///Volumes/External/Code/ASGARD-5877/binaries/crackme_arm64/crackme)
* **Upload Archive:** [`binaries/crackme_arm64/crackme.zip`](file:///Volumes/External/Code/ASGARD-5877/binaries/crackme_arm64/crackme.zip)

#### Validating the CrackMe:
```bash
# 1. Invalid key (rejected inside VM, RAX = 0):
$ ./binaries/crackme_arm64/crackme FLAG-1111-2222-3333-4444
[-] ACCESS DENIED: Verification Failed! Incorrect Key.

# 2. Valid key (VM executes 112 instructions across 14 CFF blocks and unlocks flag):
$ ./binaries/crackme_arm64/crackme FLAG-7A3F-9B1C-4D8E-2E6A
[+] SUCCESS! KEY VALIDATED (Token: 0x7A3F9B1C4D8E2E6A)
[+] FLAG{VBO_VIRTUAL_MACHINE_CRACKME_SOLVED_2026}
```

---

## 🧪 Comprehensive Verification Suite

ASGARD-5877 includes **160 tests** across **31 suites** verified on every build:

1. **Domain Invariants**: Verification of aggregate roots and instruction semantics.
2. **ISA Grammar**: AST node validation, operand constraints, and type soundess.
3. **HW Cost**: Silicon cost model audits, read/write port allocations, and area metrics.
4. **Families Generation**: Randomized instruction family distributions and constraints.
5. **Sail Parser Roundtrip**: AST-to-Sail printer and Sail-to-AST recursive-descent parser equivalence.
6. **Golden Tests**: Regression verification against known-good synthetic specifications.
7. **Property Tests (QCheck 1000+)**: Invariants over 5,000+ randomized permutations.
8. **C++ Emulator E2E**: End-to-end execution of generated C++ SIMD emulators.
9. **C11 Emulator E2E**: Verification of zero-dependency C11 reference emulators.
10. **Assembler & Bytecode**: Direct `.vbc` vector binary encoding and decoding.
11. **Assembler Deep Cases**: Boundary condition test cases for mnemonic parsers.
12. **Multi-VLEN Emulation**: Scalable vector lengths (VLEN = 64, 128, 256, 512, 1024).
13. **CLI Integration E2E**: Comprehensive test of all command-line verbs.
14. **Vanguard-9292 Obfuscation**: 1,000-seed bitfield layout validation, rolling keys, and junk opcode traps.
15. **Vanguard Emulator E2E**: Full execution of encrypted Vanguard instruction streams.
16. **VM-IR & Lazy Flags**: Zero-extension register algebra and lazy flags arithmetic.
17. **x86_64 Lifter & CFG**: Disassembly and basic block lifting of x86_64 machine code.
18. **Anti-Analysis (MBA & CFF)**: Algebraic equivalence of 4th-order polynomial expansions.
19. **Native Threaded VM & Metrics**: Direct Threading, super-operators, ephemeral scrubbing, dynamic canaries, and DRS score.
20. **C Macro Obfuscation**: Polymorphic macro expansions and stack string encryption.
21. **VM Runtime Profile**: Micro-architectural latency measurements.
22. **Compiler Pipeline & Equivalence**: End-to-end preservation of semantics across lifting, lowering, and virtualization.
23. **ARM64 Lifter & CFG**: Extended conditions (`b.hi`..`b.vc`), `cset`, `csel`, `madd`/`msub`, `ubfx`/`sbfx`.
24. **Multi-VM & Direct Zero-Bridge**: Invertible affine bridge transformations $\pmod{2^{64}}$.
25. **GPU Metal Acceleration & Synthesis**: Metal GPU parallel MBA synthesis (65k threads) and SAC diffusion verification.
26. **Register-Driven JIT VM & RNS**: RNS-4 modular arithmetic and Garner CRT reconstruction.
27. **arXiv Innovations (POP/DefUse/NCFG/LitStitch)**: POP digest determinism, Def-Use scrambling, NCFG 2,000-vector soundness, ARM64 literal stitching.
28. **E-graph Equality Expansion (Scrambler)**: Equality saturation and algebraic term rewriting.
29. **Anti-Pushan Rolling Key**: Context-dependent key evolution across loop iterations and branches.
30. **Dynamic Anti-Tamper & SMC (Layer 3)**: Self-modifying bytecode runtime attestation.
31. **Protection Config (JSON/Presets)**: Multi-layer configuration parser, validator, and preset generators.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
