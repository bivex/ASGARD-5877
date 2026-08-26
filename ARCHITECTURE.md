# Random Vector ISA (vISA) Architecture & Technical Specification

This document defines the formal architectural contract of the **Random Vector ISA Synthesizer** implemented in OCaml, its encoding taxonomy, element width invariants, and the boundaries between the architectural specification and current generator implementation limits.

---

## 1. Encoding Taxonomy & Bitfield Layout

All synthesized instructions target the canonical 32-bit RISC-V Vector Extension (`OP-V`, opcode `0x57 = 0b1010111`) space:

```
 31        26 25 24        20 19           15 14    12 11       7 6          0
┌────────────┬──┬────────────┬───────────────┬────────┬──────────┬────────────┐
│   funct6   │vm│    vs2     │  vs1/rs1/imm  │ funct3 │    vd    │ 0x57 (OP-V)│
└────────────┴──┴────────────┴───────────────┴────────┴──────────┴────────────┘
```

### 1.1 `funct6` Allocation: Single-Family Monopoly Invariant
* **Invariant**: Each `Instruction_family.t` is assigned a **strictly exclusive, dedicated `funct6` code** in `0..63`.
* Different instruction families **never share** a `funct6` code, even if their `funct3` spaces do not overlap.
* Allocation order is frequency-weighted: families with higher statistical weight in the profile receive the lowest available `funct6` codes (`0, 1, 2, ...`), maximizing decoder switch density.
* Verified by property-based testing over 1,000+ random seeds (`per_funct6_single_family_and_unique_funct3`).

### 1.2 `funct3` Mapping: Logical Operand Roles
The 3-bit `funct3` field encodes the **logical operand addressing mode** within the family's dedicated `funct6`:

| Format | Suffix | `funct3` | RVV Canonical Name | Semantics |
|---|:---:|:---:|:---:|---|
| `OP_VV` | `_vv` | `0b000` (0) | `OPIVV` | Vector-Vector: `vd[i] = vs2[i] op vs1[i]` |
| `OP_VX` | `_vx` | `0b100` (4) | `OPIVX` | Vector-Scalar: `vd[i] = vs2[i] op x[rs1]` |
| `OP_VI` | `_vi` | `0b011` (3) | `OPIVI` | Vector-Immediate: `vd[i] = vs2[i] op simm5` |
| `OP_MVV` | `_m` | `0b010` (2) | `OPMVV` | Unary / Mask / Math: `vd[i] = op(vs2[i])` |
| `OP_RED` | `_vs` | `0b001` (1) | `OPRED` | Vector Reduction: `vd[0] = fold(vs2)` |
| `OP_WIDENING` | `_vv` | `0b000` (0) | `OPWVV` | Widening Vector-Vector: `2*SEW = SEW op SEW` |

> **Crucial Distinction**: `OP_WIDENING` uses the standard vector-vector `funct3 = 0b000 (OPIVV)` bit pattern. It is disambiguated from standard `OP_VV` arithmetic by the **exclusive `funct6`** allocated to widening families (`vwadd`, `vwsub`, `vwmul`).

---

## 2. Element Sizing (SEW), Saturating, and Widening

### 2.1 Formal Architectural Contract
1. **Dynamic / Configurable SEW**:
   - Supported Standard Element Widths: `SEW ∈ {8, 16, 32, 64}` bits (`Types.Sew.t`).
   - Maximum Element Width `ELEN` (default 64 bits).
   - Vector Register Length `VLEN` (default 128 bits, configurable 64..1024).
2. **Saturating Arithmetic Semantics**:
   - Results MUST be clamped to the signed integer range defined by the active element width:
     $$\text{Clamp}(\text{val}) = \left[\,-2^{\text{SEW}-1},\; 2^{\text{SEW}-1} - 1\,\right]$$
     - $\text{SEW}=8$: $[-128, 127]$
     - $\text{SEW}=16$: $[-32768, 32767]$
     - $\text{SEW}=32$: $[-2147483648, 2147483647]$
     - $\text{SEW}=64$: $[-2^{63}, 2^{63}-1]$
3. **Widening Arithmetic Semantics**:
   - Computes operands of width $\text{SEW}$ and produces a destination element of double width:
     $$\text{Destination Width} = 2 \times \text{SEW}$$
   - **Hardware Feasibility Invariant**: Widening is valid if and only if $2 \times \text{SEW} \le \text{ELEN}$.

### 2.2 Current Generator Implementation Scope (MVP Technical Debt Record)
To prevent drift between architectural documentation and source code, the following implementation boundaries are formally noted:

* **Sail Formal AST**:
  - `Vector_instruction.synthesize_sail_function` dynamically accepts `~sew:config.default_sew` and emits Sail function bodies with `src_bits = SEW` and `dst_bits = 2*SEW` (e.g. 8→16, 16→32, 32→64).
* **C++20 & C11 Emulators**:
  - In the current MVP generator, native C++ and C11 emitter backends instantiate arithmetic arrays using fixed `int32_t` (`SEW = 32`) and widening results using `int64_t` (`2*SEW = 64`).
  - The C11 bare-metal emitter fails fast with `Unsupported_backend_feature` if widening instructions are present.
* **Roadmap Item `TODO(dynamic-sew-vtype)`**:
  - Full dynamic switching of SEW at runtime via the `vsetvli` instruction and `vtype` CSR across all four element widths (8/16/32/64).

---

## 3. Hardware Cost Model (`Hw_cost`)

The hardware cost model evaluates silicon feasibility before code generation:

1. **Register File Ports**:
   - **Read Ports**:
     - Formats `OP_VV`, `OP_RED`, `OP_WIDENING` require 2 read ports (`vs2`, `vs1`).
     - Masked execution (`vm=0`) requires 1 additional read port (`v0`).
     - Total peak read ports: **3**.
   - **Write Ports**:
     - Instructions retire 1 vector register destination (`vd`).
     - Total peak write ports: **1**.
2. **Decoder Footprint**:
   - Number of distinct entries in the primary instruction table.
   - Number of distinct active `funct6` codes.
3. **Silicon Invariant Checks**:
   - Warns if $2 \times \text{SEW} > \text{ELEN}$ (widening beyond ALU width).
   - Warns if $\text{SEW} \times \text{LMUL} > \text{VLEN}$ (vector group exceeds register size).

---

## 4. Verification Guarantees

The OCaml implementation enforces these contracts through:
1. **Construction-Time Invariants**: `Vector_isa_spec.add_instruction` returns `Error (Encoding_collision ...)` on duplicate `(funct6, funct3, opcode)` or duplicate mnemonics.
2. **Deterministic PRNG**: Injected `Random.State.t` guarantees byte-for-byte identical generation across runs.
3. **QCheck Property Tests**:
   - 1,000 seeds: Zero encoding collisions.
   - 1,000 seeds: Formal Sail export $\to$ Menhir parse round-trip identity.
   - 1,000 seeds: Per-`funct6` single-family monopoly and unique `funct3` allocation.

---

## 5. Dual Architecture: Virtual Machine Code Protector (VM-Protector)

In addition to RISC-V Vector ISA synthesis, ASGARD-5877 includes an industrial **VMProtect / Themida-style code virtualization engine**:

* **x86_64 $\to$ VM-IR Lifter (`lib/x86_lifter/`, `lib/vm_ir/`)**: Intel syntax parser with full SIB addressing `[base + index*scale + disp]`, 32-bit zero-extension semantics, and algebraic Lazy Flags reconstruction (CF, ZF, SF, OF, PF, AF).
* **F\* Formally Verified MBA Engine (`lib/mba_engine/`, `fstar/`)**: Mixed Boolean-Arithmetic polynomial expansions verified against SMT solver Z3 5.0.0.
* **Control-Flow Flattening (`lib/cff/`)**: Chenxi Wang CFG flattening with branchless `CMOV` state transition selectors and number-theoretic opaque predicates ($x(x+1) \pmod 2 == 0$).
* **Direct Threaded Code C++ Runtime (`lib/native_vm/`)**: GCC/Clang computed goto (`goto *dispatch_table[op]`), positional rolling PRF key stream ($k = \text{PRF}(\text{seed}, \text{offset})$), and $>91.8\%$ decoy traps.
* **Devirtualization Resistance Scoring (`Metrics.ml`)**: Automated evaluation of Shannon bytecode entropy ($H \in [0, 8]$), cyclomatic complexity, flattening depth, and decoy density (DRS score 0–100).

### Detailed Documentation Index
* [VM Protector Architecture & Specification](file:///Volumes/External/Code/ASGARD-5877/docs/VM_PROTECTOR.md)
* [Formal Verification & F* Proof Workflow](file:///Volumes/External/Code/ASGARD-5877/docs/FORMAL_VERIFICATION.md)
* [Devirtualization Resistance & Entropy Model](file:///Volumes/External/Code/ASGARD-5877/docs/ENTROPY_MODEL.md)
