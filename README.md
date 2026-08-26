# Random Vector ISA (vISA) & VM-Protector Toolchain in OCaml

[![OCaml 5.4+](https://img.shields.io/badge/OCaml-5.4+-orange.svg)](https://ocaml.org)
[![Build & Tests](https://img.shields.io/badge/Tests-91%20passing%20(5000%2B%20QCheck)-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/Architecture-Hexagonal%20%2F%20DDD-blue.svg)]()
[![Target Spec](https://img.shields.io/badge/ISA-RISC--V%20Vector%201.0%20%2B%20x86__64-red.svg)](https://github.com/riscv/riscv-v-spec)

A high-assurance, dual-purpose **RISC-V Vector ISA (vISA) synthesizer** and **industrial-grade Virtual Machine Code Protector (VM-Protector)** written in pure **OCaml 5**.

Designed for CPU architects, formal verification teams, and reverse-engineering / binary defense researchers who need:
1. Deterministic, collision-free vector instruction sets with formal Sail specs and native emulators.
2. Hardened **code virtualization** that translates real x86_64 machine code into a randomized, encrypted virtual architecture with Control-Flow Flattening (CFF), Mixed Boolean-Arithmetic (MBA), and a C++ Direct Threaded Code runtime (Computed GOTO).

---

## ⚡ Key Capabilities

### 1. Hardened x86_64 VM-Protector (`random_visa protect`)
* **x86_64 $\to$ Turing-Complete VM-IR Lifter**:
  * Full Intel syntax parsing supporting 16 64-bit GPRs, 32-bit zero-extension, and SIB memory addressing `[base + index*scale + disp]`.
  * Lowers complex memory Read-Modify-Write instructions (`add [rsp - 8], 10`) into atomic VM-IR sequences.
  * Resolves conditional branch fallthrough targets automatically into an explicit Control Flow Graph (CFG).
* **Lazy Flags Evaluation Engine**:
  * Real VM-protector style (QEMU/Bochs): computes CF, ZF, SF, OF, PF, AF algebraically on demand from `CC_OP_ADD`, `CC_OP_SUB`, etc., thwarting symbolic execution engines.
* **Mixed Boolean-Arithmetic (MBA) Engine**:
  * Transforms arithmetic operations (`+`, `-`, `^`, `&`, `|`) into undecidable non-linear polynomial expansions (Zhou / Eyrolles identities) with stack-oriented lowering.
* **Control-Flow Flattening (CFF) & Opaque Predicates**:
  * Destroys CFG topology using Chenxi Wang's flattening algorithm. Replaces conditional jumps with branchless `CMOV` state selectors and centralized state dispatchers.
  * Injects number-theoretic invariant opaque predicates ($x(x + 1) \pmod 2 == 0$) to induce path explosion in SMT solvers (angr / Triton).
* **Direct Threaded Code C++ Runtime (Computed GOTO)**:
  * Eliminates central `switch` loops. Handlers jump directly to the next handler using GCC/Clang `goto *dispatch_table[op]`.
  * Per-offset rolling XOR key stream (`xorshift32` + golden ratio PRF) ensuring every byte is positionally encrypted and jump-safe.
  * Decoy / Junk traps taking up >90% of opcode space: jumping to an unmapped handler traps and halts the VM.
* **Devirtualization Resistance Scoring (DRS)**:
  * Computes Shannon bytecode entropy, cyclomatic complexity, flattening depth, and decoy density, outputting a composite 0–100 hardness score.

### 2. RISC-V Vector ISA Synthesis & Formal Toolchain
* **Deterministic Randomized ISA Synthesis**: Generates compliant 32-bit RISC-V Vector instruction sets across 28 instruction families (Integer Arithmetic, Saturating DSP, Widening Double-Precision, Mask Logic, and Reductions).
* **Guaranteed Zero Encoding Collisions**:
  * Enforces an exclusive **1-family = 1-`funct6` monopoly invariant**, preventing opcode packing collisions.
* **Formal Sail Export & Round-Trip Parser**:
  * Emits formal Sail definitions with first-class `mapping clause encdec` bitfields. Menhir LR(1) parser with 100% round-trip fidelity.
* **Dual Native CPU Emulators (C++20 SIMD & C11 Bare-Metal)**.
* **Vector Assembler & Bytecode Toolchain**:
  * Assembles human-readable assembly (`.s` / `.asm`) into binary Vector ByteCode (`.vbc`).
  * `.vbc` format includes a 16-byte magic header (`\x7fVBC`), version, VLEN, ELEN, and instruction count.
  * Disassembles raw bytecode back into exact assembly text.
* **Unified Command-Line Interface (`random_visa`)**: Built with `cmdliner` with POSIX-compliant man-pages and subcommands.

---

## 🏗️ Architecture & Codebase Layout

The project strictly follows **Hexagonal (Ports & Adapters) Architecture** and **Domain-Driven Design (DDD)**. The domain core is completely pure and contains zero side effects, file I/O, or mutable state.

```
ASGARD-5877/
├── bin/                          # Presentation Layer: CLI Driver
│   ├── dune
│   └── main.ml                   # Cmdliner interface: generate, parse, assemble, disassemble, cost
├── lib/
│   ├── domain/                   # Pure Domain Core (Zero side-effects, immutable)
│   │   ├── types.ml{,i}          # Sew, Lmul, Instruction_format, Binary_op (19), Unary_op (6)
│   │   ├── errors.ml             # Typed domain error variants
│   │   ├── instruction_class.ml  # Arith, Saturating, Widening, Compare taxonomy
│   │   ├── instruction_family.ml # Family Value Object with weight/formats validation
│   │   ├── vector_config.ml      # VLEN, ELEN, default SEW, and hardware constraints
│   │   ├── vector_instruction.ml # 32-bit RISC-V V-ISA bitfield encoding/decoding
│   │   ├── vector_isa_spec.ml    # Aggregate Root: construction-time collision invariants
│   │   ├── isa_grammar.ml        # 28-family catalog & deterministic frequency sampling
│   │   ├── sail_ast.ml           # AST representation of formal Sail specifications
│   │   └── hw_cost.ml            # Silicon area, port requirements, and feasibility model
│   ├── ports/                    # Port Signatures (Module types)
│   │   └── ports.ml{,i}          # Sail_spec_writer, Sail_parser, Cpp/C11_emitter, Compiler, Assembler
│   ├── application/              # Application Use Cases & Orchestrators
│   │   ├── pipeline.ml           # End-to-end flow: synthesis -> Sail -> emulator -> native test
│   │   ├── synthesize_isa.ml     # Pure ISA generation use-case
│   │   ├── export_sail.ml        # Formal Sail export use-case
│   │   ├── import_sail.ml        # Formal Sail parsing use-case
│   │   └── generate_emulator.ml  # C++20 and C11 emission orchestrator
│   └── adapters/                 # Infrastructure Adapters (implementing Ports)
│       ├── sail_export/          # Outbound: Formal Sail specification generator
│       ├── sail_parser/          # Inbound: Menhir parser + ocamllex lexer
│       ├── cpp_emitter/          # Outbound: C++20 SIMD vector emulator generator
│       ├── c11_emitter/          # Outbound: Pure C11 bare-metal emulator generator
│       ├── compiler_adapter/     # Outbound: Subprocess wrapper for clang++ / clang
│       └── assembler/            # Inbound/Outbound: Vector assembly & .vbc binary compiler
├── test/                         # Comprehensive Verification Suite (Alcotest + QCheck)
└── ARCHITECTURE.md               # Formal architectural specification & encoding contract
```

---

## 🚀 Getting Started

### Prerequisites

* **OCaml**: `>= 5.0.0` (tested on OCaml 5.4.1)
* **OPAM**: Package manager
* **Dune**: `>= 3.0`
* **C++ Compiler**: `clang++` with C++20 support (or `g++`)
* **C Compiler**: `clang` or `gcc` with C11 support

Install dependencies via OPAM:
```bash
opam install dune menhir cmdliner alcotest qcheck qcheck-alcotest
```

### Build & Run Tests

```bash
# Build the entire project and CLI executable
dune build

# Run all 62 test cases (including 3,000 QCheck property test seeds)
dune test
```

---

## 💻 CLI Usage Guide

The unified CLI tool `random_visa` is built at `_build/default/bin/main.exe` and can be invoked via `dune exec -- random_visa <command>`.

### 1. Synthesize ISA & Generate Native C++ Emulator
Synthesizes an ISA with 16 instructions, generates Sail formal specification, emits C++20 emulator, compiles with `clang++ -O2`, and executes automated self-tests:

```bash
dune exec -- random_visa generate \
  --name "Custom_RVV_ISA" \
  --num-instructions 16 \
  --profile "rvv-like" \
  --seed 42 \
  --output-dir ./my_chip \
  --compile-and-test
```

### 2. Parse Formal Sail Specification
Parses an existing `.sail` file into the domain model and displays all extracted instruction bitfields:

```bash
dune exec -- random_visa parse -i ./my_chip/custom_rvv_isa.sail
```

### 3. Evaluate Silicon Hardware Feasibility
Calculates required register file read/write ports, decoder switch footprint, and audits hardware safety:

```bash
dune exec -- random_visa cost -s ./my_chip/custom_rvv_isa.sail
```

**Example Report Output:**
```text
=== Hardware Cost Model Report ===
  Verdict:               OK
  Regfile Read Ports:    3
  Regfile Write Ports:   1
  Max Element/Group:     4 bytes
  VLEN:                  16 bytes (128 bits)
  ELEN:                  64 bits
  Widening Dst Width:    0 bits
  Decoder Entries:       16
  Distinct funct6 codes: 6
==================================
```

### 4. Assemble Vector Assembly into Bytecode (`.vbc`)
Compiles human-readable vector assembly code into `.vbc` binary bytecode:

```bash
# Create assembly program
cat << 'EOF' > program.s
main:
    vadd_vv v3, v2, v1
    vsll_vi v4, v2, 2
    vand_vv v5, v3, v4
    vsub_vx v6, v5, x1
EOF

# Assemble against the Sail specification
dune exec -- random_visa assemble -s ./my_chip/custom_rvv_isa.sail -i program.s -o program.vbc
```

### 5. Disassemble Bytecode
Disassembles `.vbc` bytecode back into verified human-readable assembly text:

```bash
dune exec -- random_visa disassemble -s ./my_chip/custom_rvv_isa.sail -i program.vbc
```

### 6. Execute Bytecode on the Generated Native Emulator
Run the assembled program directly inside the emitted C++20 emulator:

```bash
# Extract raw instruction words (skip 16-byte VBC header)
tail -c +17 program.vbc > program.bin

# Run on the native emulator
./my_chip/visa_test_runner --bin program.bin
```

---

## 🔬 Instruction Set Architecture Details

The generated instructions use the 32-bit RISC-V Vector encoding space (`0x57` / `OP-V`):

```
 31        26 25 24        20 19           15 14    12 11       7 6          0
┌────────────┬──┬────────────┬───────────────┬────────┬──────────┬────────────┐
│   funct6   │vm│    vs2     │  vs1/rs1/imm  │ funct3 │    vd    │ 0x57 (OP-V)│
└────────────┴──┴────────────┴───────────────┴────────┴──────────┴────────────┘
```

* **`funct6`** (6 bits): Exclusively allocated to an instruction family (`vadd`, `vsub`, `vmul`, etc.).
* **`funct3`** (3 bits): Enforces the logical operand format:
  * `0b000` (`OPIVV`): Vector-Vector (`vd = vs2 op vs1`)
  * `0b100` (`OPIVX`): Vector-Scalar (`vd = vs2 op x[rs1]`)
  * `0b011` (`OPIVI`): Vector-Immediate (`vd = vs2 op simm5`)
  * `0b010` (`OPMVV`): Vector-Unary & Mask math (`vd = op(vs2)`)
  * `0b001` (`OPRED`): Vector-Reduction (`vd[0] = fold(vs2)`)
* **`vm`** (1 bit): Mask control (`1` = unmasked, `0` = masked execution predication via register `v0`).
* **`vd, vs2, vs1`** (5 bits each): Vector register indices `v0`–`v31`.

For formal semantics, element clamping rules, and technical debt documentation, consult [ARCHITECTURE.md](file:///Volumes/External/Code/ASGARD-5877/ARCHITECTURE.md).

---

## 🧪 Test Coverage & Invariant Verification

The test suite contains **62 tests** covering all layers of the architecture:

| Test Module | Tests | Verified Invariants |
|---|:---:|---|
| **Domain Invariants** | 7 | Bitfield masks, SEW/LMUL validation, all 25 arithmetic/bitwise ops |
| **ISA Grammar** | 11 | Catalog completeness (28 families), profile weights, priors |
| **Hardware Cost** | 6 | Sizing of read/write ports, decoder entries, $ELEN$ limits |
| **Families Generation** | 9 | Shared family variants, weight priority ordering |
| **Sail Parser Roundtrip** | 4 | Menhir LR(1) and ocamllex fixed-point parser round-trip |
| **Golden Determinism** | 2 | Seed 42 golden regression, byte-for-byte PRNG stability |
| **QCheck Property Tests** | 3 | **3,000 random seeds**: zero collisions, Sail round-trip identity, per-`funct6` family exclusivity |
| **C++ Emulator E2E** | 1 | Native Clang++ compilation and self-test harness verification |
| **C11 Emulator E2E** | 2 | Fail-fast check on widening, native Clang C11 execution |
| **Assembler & Bytecode** | 5 | Instruction formats (`.vv`, `.vx`, `.vi`, `.m`), `.vbc` header check |
| **Assembler Deep Cases** | 5 | Hex/negative immediates, label parsing, invalid register handling |
| **Multi-VLEN Emulation** | 4 | Emulator compilation and execution across $VLEN \in \{64, 128, 256, 512\}$ |
| **CLI Integration E2E** | 3 | End-to-end integration of all subcommands |

Run tests:
```bash
dune test
```

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
