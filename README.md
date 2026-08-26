# Random Vector ISA (vISA) Toolchain in OCaml

[![OCaml 5.4+](https://img.shields.io/badge/OCaml-5.4+-orange.svg)](https://ocaml.org)
[![Build & Tests](https://img.shields.io/badge/Tests-62%20passing%20(3000%2B%20QCheck)-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/Architecture-Hexagonal%20%2F%20DDD-blue.svg)]()
[![Target Spec](https://img.shields.io/badge/ISA-RISC--V%20Vector%201.0-red.svg)](https://github.com/riscv/riscv-v-spec)

A high-assurance, randomized **RISC-V Vector ISA (vISA)** synthesizer, formal **Sail** specification exporter, bi-directional parser, hardware cost analyzer, and multi-backend CPU emulator generator written in pure **OCaml 5**.

Designed for CPU architects, compiler engineers (LLVM, GCC), and formal verification teams who need to generate diverse, mathematically consistent, and collision-free vector instruction sets with verifiable silicon feasibility and ready-to-run native CPU emulators.

---

## ⚡ Key Capabilities

* **Deterministic Randomized ISA Synthesis**: Generates compliant 32-bit RISC-V Vector instruction sets across 28 instruction families (Integer Arithmetic, Saturating DSP, Widening Double-Precision, Mask Logic, and Reductions).
* **Guaranteed Zero Encoding Collisions**:
  * Enforces an exclusive **1-family = 1-`funct6` monopoly invariant**, preventing opcode packing collisions.
  * Aggregate root (`Vector_isa_spec`) verifies collision-freedom and unique mnemonics at object construction time.
* **Formal Sail Export & Round-Trip Parser**:
  * Emits formal Sail definitions with first-class `mapping clause encdec` bitfields.
  * Includes a conflict-free LR(1) **Menhir** parser and **ocamllex** lexer capable of parsing `.sail` specifications back into the domain AST with 100% round-trip fidelity.
* **Hardware Feasibility & Silicon Cost Model (`Hw_cost`)**:
  * Evaluates register file read/write port sizing (2–3 read ports, 1 write port).
  * Audits ALU bandwidth and warns if widening destination exceeds $ELEN$ or if vector groups exceed $VLEN$.
* **Dual Native CPU Emulators**:
  * **C++20 Emulator**: Emits clean, multi-file C++20 projects (`isa_state.hpp`, `decoder.hpp`, `instructions.cpp`, `main.cpp`) with SIMD-vectorized execution, masked execution via `v0.t`, and CLI runners supporting `--bin` and `--hex`.
  * **C11 Bare-Metal Emulator**: Generates zero-dependency C11 source suitable for embedded microcontrollers, featuring fail-fast compile-time checks on unsupported features.
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
