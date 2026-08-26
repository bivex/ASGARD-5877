# Random Vector ISA (vISA) & Industrial VM-Protector Toolchain in OCaml

[![OCaml 5.4+](https://img.shields.io/badge/OCaml-5.4+-orange.svg)](https://ocaml.org)
[![Build & Tests](https://img.shields.io/badge/Tests-95%20passing%20(5000%2B%20QCheck)-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/Architecture-Hexagonal%20%2F%20DDD-blue.svg)]()
[![Target Spec](https://img.shields.io/badge/ISA-RISC--V%20Vector%201.0%20%2B%20x86__64-red.svg)](https://github.com/riscv/riscv-v-spec)

A high-assurance, multi-purpose toolchain written in pure **OCaml 5**:
1. **RISC-V Vector ISA Synthesis**: Deterministic, collision-free vector instruction sets with formal Sail specifications, silicon cost audits, and native CPU emulators (C++20 SIMD & C11 bare-metal).
2. **Hardened Code Virtualization (VM-Protector)**: Translation of real x86_64 machine code into a randomized, encrypted virtual architecture with Mixed Boolean-Arithmetic (MBA), Control-Flow Flattening (CFF) with opaque predicates, a C++ Direct Threaded Code runtime (Computed GOTO), positional rolling XOR stream encryption, and decoy junk traps.
3. **C/C++ Preprocessor Macro Obfuscation (`c-obf`)**: Source-level hardening with stack-allocated string encryption (`__builtin_alloca`), constant blinding, MBA macros, and macro-based Control-Flow Flattening.

---

## ⚡ Key Capabilities

### 1. Hardened x86_64 VM-Protector (`random_visa protect`)
* **x86_64 $\to$ Turing-Complete VM-IR Lifter**:
  * Full Intel syntax parsing supporting all 16 64-bit GPRs, 32-bit zero-extension (`eax` zeroing upper bits of `rax`), sub-registers (`ax`, `al`), and SIB memory addressing `[base + index*scale + disp]`.
  * Automatically lowers complex memory Read-Modify-Write instructions (`add [rsp - 8], 10`) into atomic VM-IR sequences using scratch registers.
  * Resolves conditional branch fallthrough targets automatically into an explicit Control Flow Graph (CFG).
* **Lazy Flags Evaluation Engine**:
  * Real VM-protector style (QEMU/Bochs): computes CF, ZF, SF, OF, PF, AF algebraically on demand from `CC_OP_ADD`, `CC_OP_SUB`, etc., thwarting symbolic execution engines (angr / Triton).
* **Mixed Boolean-Arithmetic (MBA) Engine**:
  * Transforms arithmetic operations (`+`, `-`, `^`, `&`, `|`) into undecidable non-linear polynomial expansions (Zhou / Eyrolles identities formally proven in F* 2026.08.23 + Z3 5.0.0).
* **Control-Flow Flattening (CFF) & Opaque Predicates**:
  * Destroys CFG topology using Chenxi Wang's flattening algorithm. Replaces conditional jumps with branchless `CMOV` state selectors and centralized state dispatchers.
  * Injects number-theoretic invariant opaque predicates ($x(x + 1) \pmod 2 == 0$) to induce path explosion in SMT solvers.
* **Direct Threaded Code C++ Runtime (Computed GOTO)**:
  * Eliminates central `switch` loops. Handlers jump directly to the next handler using GCC/Clang `goto *dispatch_table[op]`.
  * Jump-safe positional rolling XOR key stream ($k = \text{PRF}(\text{seed}, \text{offset})$) ensuring every instruction word is positionally encrypted and loop-safe.
  * Decoy / Junk traps taking up >90% of opcode space: jumping to an unmapped handler traps and halts the VM.

### 2. C/C++ Source-Level Macro Obfuscator (`random_visa c-obf`)
* **Stack-Allocated String Encryption (`ASG_STR`)**: Replaces plaintext strings with XOR-encrypted compound literals decrypted on stack via `__builtin_alloca` with zero runtime memory leaks.
* **Multi-Layer MBA Macros**: `#define ASG_MBA_ADD(a, b)`, `ASG_MBA_SUB`, `ASG_MBA_XOR`, `ASG_MBA_AND`, `ASG_MBA_OR`.
* **Constant Blinding**: Rewrites integer literals into blinded identities: `((c1 ^ k1) + k2) - k2`.
* **CFF Preprocessor DSL**: State machine macros (`ASG_CFF_BEGIN`, `ASG_CFF_STATE`, `ASG_CFF_NEXT`, `ASG_CFF_EXIT`).

### 3. RISC-V Vector ISA Synthesis & Formal Toolchain
* **Deterministic Randomized ISA Synthesis**: Generates compliant 32-bit RISC-V Vector instruction sets across 28 instruction families (Integer Arithmetic, Saturating DSP, Widening Double-Precision, Mask Logic, and Reductions).
* **Guaranteed Zero Encoding Collisions**:
  * Enforces an exclusive **1-family = 1-`funct6` monopoly invariant**, preventing opcode packing collisions.
* **Formal Sail Export & Round-Trip Parser**:
  * Emits formal Sail definitions with first-class `mapping clause encdec` bitfields. Menhir LR(1) parser with 100% round-trip fidelity.
* **Hardware Feasibility & Silicon Cost Model (`Hw_cost`)**:
  * Evaluates register file read/write port sizing (2–3 read ports, 1 write port), audits ALU bandwidth, and checks $ELEN$/$VLEN$ limits.
* **Dual Native CPU Emulators (C++20 SIMD & C11 Bare-Metal)**.

* **Vector Assembler & Bytecode Toolchain**:
  * Assembles human-readable assembly (`.s` / `.asm`) into binary Vector ByteCode (`.vbc`).

---

## 🏗️ Architecture & Codebase Layout

The project strictly follows **Hexagonal (Ports & Adapters) Architecture** and **Domain-Driven Design (DDD)**.

```
ASGARD-5877/
├── bin/                          # Presentation Layer: CLI Driver
│   ├── dune
│   └── main.ml                   # Cmdliner interface: generate, parse, assemble, cost, vanguard, protect
├── lib/
│   ├── domain/                   # Pure RISC-V Vector Domain Core (Immutable)
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
│   ├── application/              # Synthesis & pipeline orchestrators
│   ├── adapters/                 # Sail, C++20, C11, Compiler, and Assembler adapters
│   ├── vm_ir/                    # Turing-Complete Micro-IR, Lazy Flags, Reference Evaluator
│   │   ├── register.ml{,i}       # 16 GPRs + sub-registers (eax/ax/al) + virtual regs
│   │   ├── flags.ml{,i}          # Lazy Flags Engine (CF, ZF, SF, OF, PF on demand)
│   │   ├── ir.ml{,i}             # SIB memory operands, ALU, branches, CFG basic blocks
│   │   └── vm_eval.ml{,i}        # Pure functional reference interpreter
│   ├── x86_lifter/               # Real x86_64 Machine Code Lifter
│   │   ├── x86_parser.ml{,i}     # Intel syntax parser (SIB, immediates, labels)
│   │   └── lifter.ml{,i}         # CFG constructor, fallthrough patcher, RMW memory lowerer
│   ├── mba_engine/               # Mixed Boolean-Arithmetic (MBA) Engine
│   │   └── mba.ml{,i}            # Zhou/Eyrolles non-linear expansion & stack lowering
│   ├── cff/                      # Control-Flow Flattening & Opaque Predicates
│   │   └── cff.ml{,i}            # Chenxi Wang CFG flattener, CMOV state select, invariant predicates
│   ├── vanguard_9292/            # Polymorphic Bytecode Encoding & Rolling Key Scheme
│   └── native_vm/                # Native Threaded Code C++ VM & Hardness Metrics
│       ├── metrics.ml{,i}        # Shannon entropy, cyclomatic complexity, DRS score
│       └── vm_emitter.ml{,i}     # C++ Direct Threaded Code runtime emitter (&&label)
├── examples/                     # Example x86_64 and RISC-V assembly programs
│   └── demo_hash.s               # Sample arithmetic & branch hashing algorithm
└── test/                         # Comprehensive Verification Suite (91 Alcotest suites + QCheck)
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

# Run all 91 test suites (including 5,000+ QCheck property test seeds)
dune test
```

---

## 🛡️ VM-Protector Guide (`random_visa protect`)

The `protect` command lifts real x86_64 assembly, applies MBA and Control-Flow Flattening, encrypts bytecode with positional rolling keys, and emits a native C++ runner using **Direct Threaded Code (Computed GOTO)**.

### Example: Protecting an x86_64 Algorithm

Given [`examples/demo_hash.s`](file:///Volumes/External/Code/ASGARD-5877/examples/demo_hash.s):
```asm
; Complex x86_64 algorithm: Hash & arithmetic check
demo_func:
    mov rax, 1337
    add rax, 42
    imul rax, 3
    cmp rax, 1000
    jge .Lhigh
    add rax, 50
    ret
.Lhigh:
    sub rax, 100
    ret
```

Run the protector with Control-Flow Flattening (`--cff`) and Mixed Boolean-Arithmetic (`--mba`):
```bash
dune exec -- random_visa protect \
  -i examples/demo_hash.s \
  --cff \
  --mba \
  -o ./protected_out
```

### Output & Devirtualization Resistance Report

```text
================ DEVIRTUALIZATION RESISTANCE REPORT ================
  Shannon Bytecode Entropy:        4.938 / 8.000 bits/byte
  CFG Cyclomatic Complexity:       2
  Control Flow Flattening Depth:   8 blocks
  Decoy / Junk Trap Density:       91.8%
  MBA Transformation Node Count:   30 nodes
--------------------------------------------------------------------
  TOTAL RESISTANCE SCORE (DRS):    64.2 / 100.0 [ STRONG OBFUSCATION ]
====================================================================

Generated Threaded VM Header: ./protected_out/threaded_vm.hpp
Generated Protected Bytecode: ./protected_out/protected.vanguard (176 bytes)

[1/2] Compiling Native Direct Threaded VM with clang++ -O2...
[2/2] Launching Protected Binary in Threaded VM:
--------------------------------------------------------
[VM] Execution SUCCESS! Verified 21 instructions. RAX: 4037
--------------------------------------------------------
```

### Internal Protection Layers

1. **Direct Threaded Code (No `switch`)**:
   ```cpp
   // Handlers jump directly to the next handler address
   #define FETCH_NEXT() do { \
       if (vIP >= vIP_end) goto EXIT_VM; \
       size_t off = static_cast<size_t>(vIP - bytecode); \
       uint32_t k = key_for_offset(seed, off); \
       word = *vIP++ ^ static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(k))); \
       goto *dispatch_table[word & 0xFF]; \
   } while(0)
   ```
2. **Positional Rolling Key Stream**: Every bytecode word is encrypted with $k = \text{PRF}(\text{seed}, \text{offset})$. Any tampering, disassembly attempt, or single-stepping desynchronizes the state.
3. **Decoy Junk Traps**: 235 out of 256 opcode slots point to `&&H_DECOY`, which immediately aborts execution on invalid control flow.

---

## 💻 RISC-V Vector ISA Toolchain Guide

### 1. Synthesize ISA & Generate Native C++ Emulator
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
```bash
dune exec -- random_visa parse -i ./my_chip/custom_rvv_isa.sail
```

### 3. Evaluate Silicon Hardware Feasibility
```bash
dune exec -- random_visa cost -s ./my_chip/custom_rvv_isa.sail
```

### 4. Assemble Vector Assembly into Bytecode (`.vbc`)
```bash
dune exec -- random_visa assemble -s ./my_chip/custom_rvv_isa.sail -i program.s -o program.vbc
```

### 5. Disassemble Bytecode
```bash
dune exec -- random_visa disassemble -s ./my_chip/custom_rvv_isa.sail -i program.vbc
```

---

## 🔒 Hardened C/C++ Protection Guide

### 1. VMProtect-Style Marker Delimiters (1-Click Protection)

Protect any critical algorithm directly in your C or C++ codebase using marker delimiters from `asgard_obf.h`:

```c
#include <stdio.h>
#include <stdint.h>
#include "asgard_obf.h"

int64_t verify_license(int64_t hwid, int64_t user_serial) {
    int64_t is_valid = 0;

    // 🔒 ASGARD VIRTUALIZATION REGION (Direct Threaded VM + CFF + MBA)
    ASGARD_BEGIN_ULTRA("LicenseValidation");

    int64_t secret_mult = 0x5877;
    int64_t secret_bias = 0x1337;
    int64_t expected_key = ((hwid ^ secret_mult) * 42) + secret_bias;

    if (user_serial == expected_key) {
        is_valid = 1;
    } else {
        is_valid = 0;
    }

    ASGARD_END();
    // 🔓 END OF VIRTUALIZED REGION

    return is_valid;
}
```

Protect and compile the source file in **1 single command**:
```bash
./random_visa protect -i examples/app.c -o ./binaries/app_dist --cff --mba --compile true
```

* **Auto-Detection**: Scans and virtualizes marked slices into Turing-complete VM-IR with CFF and MBA.
* **Stack String Encryption**: Replaces strings with stack-decrypted literals (`ASG_STR`).
* **Zero C++ Stdlib Bloat**: Strips all RTTI, exception handling, and iostream bloat so IDA Pro sees only `_main`.

---

### 2. Multi-File Project Builder (`random_visa project`)

For real-world production projects containing multiple source files across directories:

```bash
# Build an entire multi-file project with scattered markers in one command
./random_visa project -d examples/multi_file_project/src -o ./bin/secure_app --cff --mba -s 42
```

#### Makefile Integration:
```makefile
ASGARD = ../../random_visa

all:
	$(ASGARD) project -d src -o ./bin/secure_app --cff --mba -s 42
```

#### CMake Integration (`CMakeLists.txt`):
```cmake
add_custom_target(asgard_protect ALL
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/random_visa project -d ${CMAKE_CURRENT_SOURCE_DIR}/src -o ${CMAKE_CURRENT_BINARY_DIR}/secure_app --cff --mba
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building Hardened Binary via ASGARD-5877 VM Protector..."
)
```

---

### 3. Source-Level Macro Obfuscation (`random_visa c-obf`)

Obfuscate any standard C/C++ source code with stack string encryption, constant blinding, and MBA expansions:

```bash
# Obfuscate C source and generate companion header
./random_visa c-obf \
  -i examples/demo_c_app.c \
  -o ./protected_c/main.c \
  --header ./protected_c/asgard_obf.h \
  --seed 42 \
  --compile true
```


---

## 🧪 Test Coverage & Invariant Verification

The project includes **95 test suites** covering domain invariants, parsers, property tests, native runtimes, and macro obfuscation:

| Subsystem | Suites | Verified Invariants |
|---|:---:|---|
| **Domain Invariants** | 7 | Bitfield masks, SEW/LMUL validation, all 25 arithmetic/bitwise ops |
| **ISA Grammar** | 11 | Catalog completeness (28 families), profile weights, priors |
| **Hardware Cost** | 6 | Sizing of read/write ports, decoder entries, $ELEN$ limits |
| **Families Generation** | 9 | Shared family variants, weight priority ordering |
| **Sail Parser Roundtrip** | 4 | Menhir LR(1) and ocamllex fixed-point parser round-trip |
| **Golden Determinism** | 2 | Seed 42 golden regression, byte-for-byte PRNG stability |
| **QCheck Property Tests** | 3 | **3,000 random seeds**: zero collisions, Sail round-trip identity, per-`funct6` exclusivity |
| **C++ & C11 Emulators** | 3 | Native Clang++ C++20 and Clang C11 compilation and execution |
| **Assembler & Bytecode** | 10 | `.vv`, `.vx`, `.vi`, `.m` formats, hex/negative immediates, deep cases |
| **Multi-VLEN Emulation** | 4 | Verification across $VLEN \in \{64, 128, 256, 512\}$ |
| **CLI Integration E2E** | 3 | End-to-end testing of CLI commands |
| **Vanguard-9292 Obfuscation** | 6 | Field layout randomization, rolling keys, junk opcode detection |
| **Vanguard Emulator E2E** | 1 | Native emulator integration with decoy trap traps |
| **VM-IR & Lazy Flags** | 7 | GPR sub-registers (zero-extension), lazy flags algebra (1,000 seeds), Fibonacci function |
| **x86_64 Lifter & CFG** | 6 | SIB addressing, linear math, abs branch, factorial loop, memory RMW, array sum |
| **Anti-Analysis (MBA & CFF)**| 6 | MBA algebraic soundness (1,000 seeds), stack lowering, CFF Fibonacci/Factorial/Abs |
| **Native Threaded VM & Metrics**| 3 | Shannon entropy, Direct Threaded Code (Computed GOTO), CFF execution, decoy traps |
| **C Macro Obfuscation** | 4 | Standalone header generation, stack string encryption, constant blinding, Clang E2E |


Run all tests:
```bash
dune test
```

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
