# Random Vector ISA (vISA) & Industrial VM-Protector Toolchain in OCaml

[![OCaml 5.4+](https://img.shields.io/badge/OCaml-5.4+-orange.svg)](https://ocaml.org)
[![Build & Tests](https://img.shields.io/badge/Tests-102%20passing%20(5000%2B%20QCheck)-brightgreen.svg)]()
[![Architecture](https://img.shields.io/badge/Architecture-Hexagonal%20%2F%20DDD-blue.svg)]()
[![Target Spec](https://img.shields.io/badge/ISA-RISC--V%20Vector%201.0%20%2B%20x86__64-red.svg)](https://github.com/riscv/riscv-v-spec)

A high-assurance, multi-purpose toolchain written in pure **OCaml 5**:
1. **RISC-V Vector ISA Synthesis**: Deterministic, collision-free vector instruction sets with formal Sail specifications, silicon cost audits, and native CPU emulators (C++20 SIMD & C11 bare-metal).
2. **Hardened Code Virtualization (VM-Protector)**: Translation of real x86_64 machine code into a randomized, encrypted virtual architecture with Mixed Boolean-Arithmetic (MBA), Control-Flow Flattening (CFF), Super-Operators, Direct Threaded Code runtime (Computed GOTO), Ephemeral Self-Consuming Bytecode, Dead Taint Siphoning, and Hardware Breakpoint / Nanomite probes.
3. **C/C++ Preprocessor Macro Obfuscation (`c-obf`)**: Source-level hardening with stack-allocated volatile string encryption, API hashing, constant blinding, MBA macros, Exception-based signal jumping, and Nanomite dispatching.


---

## ⚡ Key Capabilities & Protection Matrix

ASGARD-5877 implements **14+ state-of-the-art protection layers**, combining theoretical compiler transformations with hardware-assisted anti-reverse engineering techniques:

| # | Protection Vector | Threat Model Addressed | Mechanism & Implementation |
|---|:---|:---|:---|
| **1** | **Custom ISA Virtualization** | Static Decompilation (IDA / Hex-Rays / Ghidra) | 100% native x86_64 machine code elimination; lifted into randomized Turing-Complete VM-IR. |
| **2** | **Multi-Layer Non-Linear MBA** | Algebraic Simplifiers / Theorem Provers (Z3, SMT) | Zhou / Eyrolles polynomial expansions ($d \ge 2$), transforming linear ALU into undecidable systems. |
| **3** | **Control-Flow Flattening (CFF)** | CFG Recovery & Graph Dominator Analysis | Chenxi Wang dispatcher topology flattening; conditional jumps lowered to branchless `CMOV`. |
| **4** | **Super-Operators / Instruction Fusion** | Virtual Instruction Trace De-obfuscation | Todd Proebsting fusion patterns (`FUSED_MOV_ADD`, `FUSED_ADD_IMUL`, `FUSED_CMP_CMOV`) collapsing opcodes. |
| **5** | **Direct Threading / Computed GOTO** | Indirect Branch Tracking & Hardware BTB Sniffing | Zero central `switch` loops; handlers dispatch directly via `&&label` jump tables with PRF key stream. |
| **6** | **Randomized Register Permutation** | DFG (Data Flow Graph) Data-Dependency Analysis | Bijective permutation $\pi \in S_{32}$ of architectural registers + XOR `reg_mask` blinding. |
| **7** | **Ephemeral Self-Consuming Bytecode** | Process Memory Dumps (Scylla, CheatEngine, Volatility)| Bytecode memory is continuously overwritten with noise on every fetch; epilogue wipes RAM buffer. |
| **8** | **Dynamic Junk Bytecode & Taint Siphoning** | Symbolic Execution Engines (angr, Triton, Miasm) | Dead registers (`VTMP2`) with phantom non-linear DFG paths to explode solver constraint search. |
| **9** | **Virtual Stack Scrambling** | Shadow Stack / Memory Call-Stack Probing | Non-linear affine index permutation ($f(sp) = (sp \cdot 37 + 13) \pmod{256}$) + slot-level dynamic encryption. |
| **10** | **Bytecode & Section HMAC Integrity** | Breakpoint Injection (0xCC / `int3`) & NOP Patching | Rolling 64-bit polynomial HMAC checksum verified at runtime; mismatch poisons VM context. |
| **11** | **Active Anti-Debugging & HW Breakpoints** | Dynamic Debugging (LLDB, x64dbg, CheatEngine) | Mach thread state (`DR0..DR7`), `sysctl(KERN_PROC_PID, P_TRACED)`, `/proc/self/status` `TracerPid`. |
| **12** | **Opaque Signal / Exception Dispatching** | Static/Dynamic Control Flow Disassembly | Deliberate `SIGILL` / `SIGFPE` / `VEH` triggers with `ucontext_t` (`RIP`/`PC`) hijacking. |
| **13** | **Multithreaded Nanomites** | Dynamic Single-Stepping & Debugger Attachment | Replaces conditional branches with `SIGTRAP` breakpoints resolved via encrypted tables. |
| **14** | **Anti-ConstExpr Volatile String Barriers** | Compile-Time Optimizer String De-obfuscation | Volatile pointers + inline `__asm__ volatile("" : "+r" : : "memory")` preventing Clang `-O3` constant folding. |
| **15** | **Compile-Time API Hashing (IAT Erasure)**| Import Address Table (IAT) Inspection | 32-bit polynomial API name hashing (`ASG_API_CALL`) resolving functions directly from memory headers. |
| **16** | **Hardware Timing Watchdog** | Instruction Tracing & Step-by-Step Analysis | CPU cycle counter validation (`rdtsc` / ARM `cntvct_el0`) detecting trace slowdowns. |


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

The project includes **102 test suites** covering domain invariants, formal parsers, property tests, native virtual runtimes, anti-analysis guards, and macro obfuscation:

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
| **x86_64 Lifter & CFG** | 7 | SIB addressing, linear math, abs branch, factorial loop, memory RMW, array sum, marker extraction |
| **Anti-Analysis (MBA & CFF)**| 6 | MBA algebraic soundness (1,000 seeds), stack lowering, CFF Fibonacci/Factorial/Abs |
| **Native Threaded VM & Metrics**| 7 | Shannon entropy, Computed GOTO, Super-operators, Ephemeral memory scrubbing, Dynamic junk bytecode, HMAC integrity, Affine stack scrambling |
| **C Macro Obfuscation** | 6 | Standalone header generation, volatile stack string encryption, constant blinding, Clang E2E, Signal-based dispatching, Nanomite trap-and-trace |

Run all tests:
```bash
dune test
```


---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
