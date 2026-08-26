# Virtual Machine Code Protector (VM-Protector) Architecture

This document provides a comprehensive mathematical and technical specification of the industrial-grade **Virtual Machine Code Protector (ASGARD-5877)** implemented in pure OCaml 5 with C++20 Direct Threaded Code runtime emission.

---

## 1. Executive Summary & Design Principles

The ASGARD-5877 VM-Protector virtualizes arbitrary x86_64 machine code functions by lifting native instructions into an expressive Turing-complete Micro-IR, hardening the program through non-linear mathematical and topological transformations, and compiling the result into a randomized, encrypted, direct-threaded virtual machine bytecode executed by a custom C++ runtime.

```
┌───────────────────────────────┐
│     x86_64 Machine Code       │ (demo_hash.s / object file)
└───────────────┬───────────────┘
                │
                ▼ (1. Intel Syntax Parser & Lifter)
┌───────────────────────────────┐
│  Turing-Complete VM-IR & CFG  │ (SIB lowering, RMW decomposition, Lazy Flags)
└───────────────┬───────────────┘
                │
                ▼ (2. Anti-Analysis Layer)
┌───────────────────────────────┬───────────────────────────────┐
│  Mixed Boolean-Arithmetic     │  Control-Flow Flattening      │
│  (F* / Z3 Verified Identities)│  (Wang's Algorithm, CMOV, OP) │
└───────────────┴───────────────┴───────────────────────────────┘
                │
                ▼ (3. Native Code Generation & Encryption)
┌───────────────────────────────┬───────────────────────────────┐
│  Direct Threaded C++ Runtime  │  Positional Rolling PRF Key   │
│  (Computed GOTO: &&label)     │  (k = PRF(seed, offset))      │
└───────────────┴───────────────┴───────────────────────────────┘
                │
                ▼ (4. Hardness Audit)
┌───────────────────────────────┐
│ Devirtualization Resistance   │ (Shannon Entropy, Cyclomatic M, Decoy Density)
│ Score (DRS Index: 0 .. 100)   │
└───────────────────────────────┘
```

### Core Invariants
1. **Semantic Preservation**: $\forall \sigma \in \Sigma, \quad \text{Eval}_{\text{VM}}(\text{Protect}(P), \sigma) \equiv \text{Eval}_{\text{x86}}(P, \sigma)$.
2. **Zero Central Dispatch**: Elimination of centralized `switch(op)` dispatch loops to defeat heuristic pattern-matching in disassemblers (IDA Pro / Ghidra).
3. **Decoy Trap Dominance**: $>90\%$ of the 8-bit opcode space is populated by lethal trap handlers (`&&H_DECOY`) that immediately terminate execution upon control-flow tampering.
4. **Position-Dependent Bytecode Encryption**: Deterministic, jump-safe pseudorandom permutation of every bytecode word using Knuth's 64-bit golden ratio constant and Xorshift32.

---

## 2. Phase 1: Micro-IR & Lazy Flags Engine (`lib/vm_ir/`)

### 2.1 Register File Architecture
The virtual register file models 16 64-bit General-Purpose Registers (GPRs) and 7 dedicated Virtual Registers (VREGs):

* **GPRs**: `RAX`, `RCX`, `RDX`, `RBX`, `RSP`, `RBP`, `RSI`, `RDI`, `R8`–`R15`.
  * Sub-register access (`EAX`, `AX`, `AL`) adheres to x86_64 semantics: 32-bit writes **strictly zero-extend** into the upper 32 bits of the 64-bit parent register.
* **VREGs**:
  * `VIP`: Virtual Instruction Pointer (bytecode program counter).
  * `VSP`: Virtual Stack Pointer.
  * `VKEY`: Dynamic rolling key / PRF context.
  * `VTMP0`–`VTMP3`: High-speed scratch registers for SIB address arithmetic, RMW lowering, and MBA stack operations.

### 2.2 SIB Memory Addressing
Complex x86 memory references are modeled via explicit `mem_ref` records:
$$\text{Effective Address} = \text{Base} + (\text{Index} \times \text{Scale}) + \text{Displacement}$$
where $\text{Scale} \in \{1, 2, 4, 8\}$, $\text{Displacement} \in [-2^{63}, 2^{63}-1]$.

### 2.3 Algebraic Lazy Flags Evaluation (`Flags.ml`)
Instead of computing CPU condition codes on every ALU instruction (which introduces heavy register pressure and reveals condition flags to symbolic execution engines), the engine uses lazy algebraic deferred evaluation:

$$\text{cc\_op} \in \{\text{CC\_OP\_RAW}, \text{CC\_OP\_ADD}, \text{CC\_OP\_ADC}, \text{CC\_OP\_SUB}, \text{CC\_OP\_SBB}, \text{CC\_OP\_LOGIC}, \text{CC\_OP\_INC}, \text{CC\_OP\_DEC}\}$$

When an instruction requires a conditional evaluation (e.g. `Jcc`, `Cmov`, `Setcc`), flags are reconstructed algebraically on demand:

* **Carry Flag (CF)**:
  $$\text{CF}_{\text{SUB}}(s_1, s_2) = (s_1 < s_2), \qquad \text{CF}_{\text{ADD}}(s_1, s_2, \text{res}) = (\text{res} < s_1)$$
* **Zero Flag (ZF)**: $\text{ZF} = (\text{res} = 0)$.
* **Sign Flag (SF)**: $\text{SF} = (\text{res} < 0) \equiv (\text{res} \gg 63 = 1)$.
* **Overflow Flag (OF)**:
  $$\text{OF}_{\text{ADD}} = ((s_1 \oplus \sim s_2) \land (s_1 \oplus \text{res})) \gg 63 \neq 0$$
  $$\text{OF}_{\text{SUB}} = ((s_1 \oplus s_2) \land (s_1 \oplus \text{res})) \gg 63 \neq 0$$
* **Parity Flag (PF)**: Precomputed via 256-entry lookup table over $\text{res} \pmod{256}$.

---

## 3. Phase 2: x86_64 Lifter & CFG Construction (`lib/x86_lifter/`)

### 3.1 Intel Syntax Parser (`X86_parser.ml`)
Parses full Intel syntax x86_64 assembly, including:
* All 16 GPRs and their 32-bit (`eax`), 16-bit (`ax`), and 8-bit (`al`) aliases.
* SIB memory operands: `[rsp - 8]`, `[rdi + rsi*4 + 0x10]`, `[rax + 16]`.
* Size directives: `qword ptr`, `dword ptr`, `word ptr`, `byte ptr`.
* Immediates in decimal, hex (`0x1337`), and negative forms.

### 3.2 Read-Modify-Write (RMW) Decomposition
Instructions performing in-place memory modifications are automatically lowered to atomic sequences:
```
// Original x86_64
add qword ptr [rsp - 8], 10

// Lowered VM-IR sequence
mov vtmp0, [rsp - 8]
alu add, vtmp0, vtmp0, 10
mov [rsp - 8], vtmp0
```

### 3.3 Control-Flow Graph Partitioning & Fallthrough Resolution
The lifter identifies basic block boundaries on:
1. Entry point of the function.
2. Targets of conditional/unconditional jumps (`.Llabel`).
3. Instructions immediately following branches (`jcc`, `jmp`, `call`, `ret`).

For conditional branches (`jcc .Ltarget`), the implicit hardware fallthrough is explicitly converted into an explicit false edge:
$$\text{Jcc} \implies \{\text{target\_true} = \text{Block}(\text{target}), \quad \text{target\_false} = \text{Block}(\text{fallthrough})\}$$

---

## 4. Phase 3: Anti-Analysis Layer (MBA & CFF)

### 4.1 Formally Verified Mixed Boolean-Arithmetic (MBA) Engine (`lib/mba_engine/`)
The MBA engine replaces linear ALU instructions with non-linear polynomial expressions. Every identity is **formally proven in F\* 2026.08.23 and verified by Z3 5.0.0** (`fstar/Mba_Verified.fst`):

$$\begin{aligned}
a \oplus b &\equiv (a \lor b) \oplus (a \land b) \\
a \land b &\equiv (a \lor b) \oplus (a \oplus b) \\
a \lor b &\equiv (a \oplus b) \oplus (a \land b) \\
\sim a &\equiv a \oplus \text{0xFFFFFFFFFFFFFFFF} \\
a + b &\equiv (a \oplus b) + 2(a \land b) \equiv (a \lor b) + (a \land b) \\
a - b &\equiv (a \oplus b) - 2(\sim a \land b) \equiv 2(a \land \sim b) - (a \oplus b)
\end{aligned}$$

#### Stack-Oriented Lowering
To prevent register spilling and keep scratch register usage constant ($O(1)$), the MBA AST is evaluated on the virtual stack:
* Leaf variables and constants are pushed to `VSP`.
* Binary operations pop operands into `VTMP0` / `VTMP1`, compute the result, and push back.

### 4.2 Control-Flow Flattening (CFF) & Opaque Predicates (`lib/cff/`)
Based on Chenxi Wang's control-flow flattening algorithm:

1. **State Machine Dispatcher**:
   * Each basic block $B_i$ is assigned a unique randomized 32-bit state identifier $S_i \in [0, 2^{32}-1]$.
   * All explicit jump instructions (`jmp`, `jcc`) are removed from basic blocks.
   * Basic blocks terminate by updating the state variable `vtmp3` and jumping to the central state dispatcher.
2. **Branchless State Selection (`CMOV`)**:
   Conditional branches are converted into constant-time state selections:
   $$\text{vtmp3} \leftarrow \text{Cmov}(cond, S_{\text{true}}, S_{\text{false}})$$
3. **Number-Theoretic Invariant Opaque Predicates**:
   To defeat static symbolic execution engines (e.g. angr, Triton), invariant mathematical truths are injected into dead branches:
   $$\forall x \in \mathbb{Z}, \quad x(x + 1) \equiv 0 \pmod 2$$
   $$\forall x \in \mathbb{Z}, \quad x^2 + x + 7 \not\equiv 0 \pmod 2$$

---

## 5. Phase 4: Direct Threaded Code C++ Runtime (`lib/native_vm/`)

### 5.1 Elimination of Central `switch` (Computed GOTO)
Conventional interpreters use a `while(true) { switch(*ip++) { ... } }` loop, which decompilers trivially collapse into a single switch node. ASGARD-5877 eliminates this by generating **Direct Threaded Code**:

```cpp
static const void* const dispatch_table[256] = {
    &&H_MOV, &&H_ADD, &&H_SUB, &&H_CMP, &&H_JMP, &&H_CMOV, &&H_RET,
    // ... 235 decoy slots pointing to &&H_DECOY ...
};

#define FETCH_NEXT() do { \
    if (vIP >= vIP_end) goto EXIT_VM; \
    size_t off = static_cast<size_t>(vIP - bytecode); \
    uint32_t k = key_for_offset(seed, off); \
    uint64_t word = *vIP++ ^ static_cast<uint64_t>(k); \
    goto *dispatch_table[word & 0xFF]; \
} while(0)
```

Each instruction handler directly computes the address of the next handler and jumps directly via `goto *dispatch_table[op]`.

### 5.2 Positional Rolling PRF Key Stream
To ensure compatibility with loops, backwards jumps, and CFF dispatchers without losing keystream synchronization, every bytecode word is encrypted with a position-dependent pseudorandom function:

$$k(\text{seed}, \text{offset}) = \text{xorshift32}\left(\text{seed} \oplus (\text{offset} \cdot \text{0x9E3779B97F4A7C15})\right)$$

* **Determinism**: Jumps to any valid instruction offset immediately decrypt the correct instruction word.
* **Integrity**: Patching a single byte in memory or single-stepping desynchronizes the PRF, triggering an illegal opcode jump into `&&H_DECOY`.

### 5.3 Decoy Trap Density (>91.8%)
Out of 256 possible 8-bit opcodes:
* **21 slots** map to functional VM handlers.
* **235 slots** map to `&&H_DECOY`.
* Any out-of-order execution, fuzzing attempt, or corrupted state immediately traps and halts the process.

---

## 6. Phase 5: Devirtualization Resistance Scoring (DRS)

The `Metrics` module evaluates the defensive strength of the virtualized binary across four orthogonal dimensions:

| Metric | Mathematical Definition | Target Range | Weight |
|---|---|:---:|:---:|
| **Shannon Bytecode Entropy ($H$)** | $H = -\sum_{i=0}^{255} p_i \log_2(p_i)$ | $4.5 - 8.0$ bits/byte | 25 pts |
| **Cyclomatic Complexity ($M$)** | $M = E - V + 2P$ | $2 - 20+$ | 25 pts |
| **Decoy Trap Ratio ($D$)** | $D = \frac{N_{\text{decoy}}}{256}$ | $> 90\%$ | 25 pts |
| **Flattening Depth ($F$)** | Number of flattened dispatcher states | $4 - 16+$ blocks | 25 pts |

### Composite Score Formula
$$\text{DRS} = \min\left(25, \frac{H}{8.0} \times 25\right) + \min\left(25, \frac{M}{10} \times 25\right) + \min\left(25, \frac{D}{0.95} \times 25\right) + \min\left(25, \frac{F}{8} \times 25\right)$$

* **0.0 – 39.9**: Weak Obfuscation (vulnerable to standard IDA / Ghidra decompilation).
* **40.0 – 69.9**: Strong Obfuscation (defeats symbolic execution, requires custom devirtualizer).
* **70.0 – 100.0**: Maximum Hardening (full CFF + recursive MBA + positional PRF encryption).

---

## 7. Marker-Based Region Protection (VMProtect-Style SDK)

Instead of virtualizing entire monolithic binaries, developers place fine-grained marker delimiters around sensitive licensing, cryptographic, and anti-tamper logic:

```c
#include "asgard_obf.h"

int64_t verify_license(int64_t hwid, int64_t user_serial) {
    int64_t is_valid = 0;

    // 🔒 VIRTUALIZED IN DIRECT THREADED VM WITH CFF + MBA
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

### Supported Marker Tiers
* `ASGARD_BEGIN_VIRTUALIZE("Tag")`: Pure bytecode virtualization with rolling key PRF.
* `ASGARD_BEGIN_MUTATION("Tag")`: MBA mutation and polymorphic arithmetic rewriting.
* `ASGARD_BEGIN_ULTRA("Tag")`: Full Virtualization + Control-Flow Flattening (CFF) + Recursive MBA.
* `ASGARD_END()`: Region delimiter.

---

## 8. Zero-Bloat Runtime & Anti-Analysis Metadata Stripping

To prevent reverse engineers from identifying the VM runtime via standard library artifacts, the C++ runtime was re-engineered for **zero standard library overhead**:

1. **Elimination of C++ `std::vector` & `std::iostream`**:
   * Fixed 512-word stack array inside `VMContext` (`uint64_t stack[512]`).
   * Pure C runtime functions (`printf`, `fopen`, `fread`, `fclose`) with zero dynamic heap allocations.
2. **Hidden Visibility & Inlining**:
   * All VM handlers and `execute_threaded` are marked `__attribute__((always_inline, visibility("hidden")))`.
   * Function names never enter the Mach-O/ELF export or symbol tables.
3. **Hardened Linker Flags**:
   * `-fno-rtti -fno-exceptions -fno-unwind-tables -fvisibility=hidden -Wl,-dead_strip -Wl,-x && strip -x`.
4. **Hex-Rays / IDA Pro Output**:
   * Symbol table contains **only `_main`** and standard OS syscall stubs (`_printf`).
   * No `std::length_error`, `___cxa_throw`, `typeinfo`, or plaintext trap strings exist in the binary.

---

## 9. Production Multi-File Project Builder (`random_visa project`)

For production codebases with multiple source files (`.c`, `.cpp`, `.s`) across directories:

```bash
./random_visa project -d ./src -o ./bin/secure_app --cff --mba -s 42
```

### Pipeline Workflow
```
[src/license.c] ───► [c_macro_obf] ───► [clang -S] ───► [extract markers] ───► [compile obj] ──┐
[src/crypto.c]  ───► [c_macro_obf] ───► [clang -S] ───► [extract markers] ───► [compile obj] ──┼─► [clang Link & Strip] ──► ./bin/secure_app
[src/auth.c]    ───► [c_macro_obf] ───► [clang -S] ───► [extract markers] ───► [compile obj] ──┤
[src/main.c]    ───► [c_macro_obf] ───► [clang -S] ───► [extract markers] ───► [compile obj] ──┘
```

---

## 10. CMake & Makefile Integration

### Makefile
```makefile
ASGARD = ./random_visa

all:
	$(ASGARD) project -d src -o ./bin/secure_app --cff --mba -s 42
```

### CMake (`CMakeLists.txt`)
```cmake
cmake_minimum_required(VERSION 3.15)
project(MySecureApp C)

add_custom_target(asgard_protect ALL
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/random_visa project -d ${CMAKE_CURRENT_SOURCE_DIR}/src -o ${CMAKE_CURRENT_BINARY_DIR}/secure_app --cff --mba
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building Hardened Multi-File Binary via ASGARD-5877..."
)
```

