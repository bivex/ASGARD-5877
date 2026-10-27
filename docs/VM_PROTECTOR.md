# ASGARD-5877: Virtual Machine Code Protector (VM-Protector)

This document provides the formal mathematical foundation and complete architectural specification of the **ASGARD-5877 Virtual Machine Code Protector**, implemented in pure OCaml 5 with C++20 Direct Threaded Code runtime generation.

---

## 1. Top-Level Mathematical Model of the Virtualization Pipeline

The protector is formalized as an end-to-end semantics-preserving functor $\mathcal{P}$ from native machine code $\mathcal{M}_{\mathrm{native}}$ across target architectures (x86_64, ARM64, RV64) to a decentralized, encrypted, multi-layered virtual execution system $\mathcal{M}_{\mathrm{virtual}}$:

$$\mathcal{P} = \mathcal{R} \circ \mathcal{E} \circ \left( \prod_{i=N}^{1} \mathcal{T}_i \right) \circ \mathcal{L}$$

```mermaid
flowchart TD
    Src["Native Source / Assembly<br/>(ARM64 / x86_64 / RV64)"] --> Lift["1. Multi-Arch Lifter (L)<br/>Lowering to Micro-IR"]
    Lift --> IR["Turing-Complete Stack-IR<br/>Program (Blocks, Context Slots)"]
    
    subgraph Passes [2. Hardening Pipeline]
        direction TB
        P1["Phase 1: Context Allocation & Epoch Shuffling"]
        P2["Phase 2: Superoperator Fusion & Multiplicity"]
        P3["Phase 2b: Horner Amplification & E-Graph MBA"]
        P4["Phase 3: CFF with Metamorphic VPC Dispatchers"]
        P5["Phase 4: Spaghetti CFG Splitting"]
        P6["Phase 5: Metamorphic Ghost Padding (Scratch Ring)"]
        P7["Phase 5b: Variable-Size Avid Junk Operands"]
        P8["Phase 5c: Memory-Address Entanglement"]
        P9["Phase 5d: Stateful Transducer Coupling"]
        P10["Phase 5e: Non-Linear PolyMBA Knots"]
        P11["Phase 6: State-Feedback Rolling Key Stream"]
        P12["Phase 7: Stack Balance Verification & Repair"]
        P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8 --> P9 --> P10 --> P11 --> P12
    end
    
    IR --> P1
    P12 --> Enc["3. Compact Polymorphic Encoder (E)<br/>Unique Opcode & Field Permutations"]
    Enc --> RT["4. Pipelined Stage Dispatch Runtime (R)<br/>Decoupled Epilogues & Affine Blinding"]
    RT --> Bin["Protected Binary (protected_app)<br/>Zero-Native Trampoline & Watermark"]
```

### 1.1 Abstract Machine State Space

The virtual machine state is defined as an 8-tuple:

$$\Sigma_{\text{VM}} = \langle \text{VIP}, \text{VSP}, \text{VKEY}, \text{VCTX}, \text{VStack}, \text{VMem}, \text{VFlags}, \text{Halted} \rangle$$

Where:
* $\text{VIP} \in \mathbb{N}$: Virtual Instruction Pointer (offset in ciphertext stream).
* $\text{VSP} \in \mathbb{Z}_{2^{64}}$: Virtual Stack Pointer referencing thread-local `host_stack`.
* $\text{VKEY} \in \mathbb{Z}_{2^{64}}$: Dynamic rolling cryptographic key state.
* $\text{VCTX}: [0 \dots C-1] \to \mathbb{Z}_{2^{64}}$: Array of $C$ 64-bit virtual registers/scratch slots.
* $\text{VStack} \in (\mathbb{Z}_{2^{64}})^*$: Operational LIFO evaluation stack ($\text{depth} \le 4096$).
* $\text{VMem}: \mathbb{Z}_{2^{64}} \to \mathbb{Z}_{2^8}$: Byte-addressable host/guest memory space.
* $\text{VFlags} \in \mathcal{F}$: Deferred lazy algebraic condition code state.
* $\text{Halted} \in \{0, 1\}$: Process termination and security abort flag.

### 1.2 Fundamental Soundness Invariants

$$\forall P \in \mathcal{M}_{\mathrm{native}}, \quad \forall \sigma \in \Sigma_{\mathrm{native}}: \quad \llbracket \mathcal{P}(P) \rrbracket(\sigma) \equiv \llbracket P \rrbracket(\sigma)$$

1. **Stack Neutrality**: $\forall B \in \text{Blocks}, \quad \Delta_{\mathrm{net}}(\text{VStack}) = 0$ on all intra-block exits.
2. **Flag Equivalence**: For any conditional consumer $\mathcal{C} \in \{\text{JccRel}, \text{Setcc}, \text{Cmov}\}$, the materialized condition codes $\text{Flags}(\Sigma)$ match the hardware CPU flags of the unvirtualized baseline.
3. **Dead-Slot Chaff Isolation**: Chaff/blinding operations operate on dedicated context slots $[C_{\mathrm{live}} \dots C_{\mathrm{live}} + 2^k - 1]$, strictly isolated from guest architectural state.
4. **Linear Memory Bounding**: Memory-entanglement operations access strictly within the thread-local frame $[\text{SP} - 128 \dots \text{SP} - 16]$, preserving caller stack frames and thread safety.

---

## 2. Mathematical Formalization of Hardening Passes

### Phase 1: IR Lowering & Context Allocator Epochs (`lib/stack_vm/`)
Native registers $R_{\mathrm{arch}}$ are mapped onto context slots through an injective permutation $\pi_{\mathrm{epoch}}: R_{\mathrm{arch}} \to [0 \dots C-1]$:
$$\text{ctx}[\pi_{\mathrm{epoch}}(r)] = \text{val}(r)$$
During compilation, `standard_registers` assigns dedicated slots for architecture GPRs (RAX..R15 / X0..X30), VM internals (`VIP`, `VSP`, `VKEY`), and temporary scratch channels (`vtmp0`..`vtmp3`).

### Phase 2a: Superoperator Fusion & Multiplicity (`stack_multiplicity_pass.ml`)
Replaces 1:1 opcode patterns with polymorphic clone trees and metamorphic expansions:
* **MBA Add Expansion**:
  $$x + y \equiv - (\text{Nor}(x, y) + \text{Nand}(x, y) + 2) \pmod{2^{64}}$$
* **MBA Sub Expansion**:
  $$x - y \equiv (x \land \neg y) - (\neg x \land y) \pmod{2^{64}}$$
* **Stack Permutations**: Structural desugaring of `Swap`, `Dup`, `Rot` via scratch context registers, defeating opcode frequency profiling.

### Phase 2: Horner Polynomial Amplification (`bytecode_amplifier.ml`)
Amplifies linear computations through degree-$d$ Horner polynomial forms and carry-chain bit-slicing:
$$P(x) = c_0 + x \cdot (c_1 + x \cdot (c_2 + \dots + x \cdot c_d) \dots) \pmod{2^{64}}$$
Injects def-use web knots using algebraic zero identities:
$$\text{Zero}(r) = ((r + \text{salt}) - r - \text{salt}) \equiv 0$$

### Phase 2b: E-Graph Equality Saturation & Constant Synthesis (`stack_mba_pass.ml`)
Eliminates plaintext immediate constants `PushImm v`. Constants are synthesized via an E-Graph saturation engine (`lib/mba_engine/`):
$$v = \mathcal{E}_{\text{MBA}}(c) \in \text{Lang}(\text{Nor}, \text{Nand}, \text{Add}, \text{Sub}, \text{Mul})$$
Extracts alternation-heavy AST expressions mixing Boolean lattices and modular arithmetic.

### Phase 3: Virtual CFG Flattening (CFF) with Metamorphic Dispatchers (`stack_cff_pass.ml`)
Transforms the basic block call graph into an irreducible state machine routed through a virtual program counter (`vpc`):
$$\text{Target} = \text{Dispatcher}(\text{vpc})$$
To defeat dynamic `vpc` write-hooking, dispatcher comparisons are diversified into 6 metamorphic shapes:
$$\text{Shape}_1: \text{Cmp}(\text{vpc}, \text{token})$$
$$\text{Shape}_2: \text{Sub}(\text{vpc}, \text{token}) == 0$$
$$\text{Shape}_3: \text{Sub}(\text{vpc} - \text{vpc}, \text{token} - \text{token}) == 0$$
$$\text{Shape}_4: \text{JccRel}(\text{fall}, \text{NE}); \ \text{JmpRel}(\text{target})$$

### Phase 4: Deterministic Spaghetti Block Splitting (`stack_spaghetti_pass.ml`)
Partitions linear basic blocks into fragmented segments linked by non-linear polynomial zero branches:
$$\text{Condition}: ((r_1 \cdot r_2 + r_3) - (r_1 \cdot r_2 + r_3)) == 0 \implies \text{JccRel}(\text{target}, \text{E})$$
Embeds decoy backward loop edges, defeating topological block re-assembly in IDA Pro and Ghidra.

### Phase 5: Ghost Stack Padding & 4-Slot Def-Use Scratch Ring (`stack_ghost_pass.ml`)
Injects semantically neutral instruction clusters maintaining a cyclic def-use chain across a 4-slot ring:
$$s_{(i+1) \bmod 4} \leftarrow \mathcal{F}(s_{i \bmod 4}, r_{\mathrm{live}})$$
* **Class A**: Context moves (`SetRegImm`, `PushReg`, `PopReg`).
* **Class B**: Multi-step ALU chains (`AddRegImm`, `Nor`, `Add`) when flags are dead.
* **Class C/D**: Live-stack zero knots wrapped in flag-restoring sandwiches (`PushFlags ... PopFlags`).

### Phase 5b: Variable-Size Avid Junk Operands (`stack_avid_pass.ml`)
Injects variable-length junk clusters bound to live context anchor slots:
$$\text{Anchor}_{k+1} \leftarrow \text{Anchor}_k \oplus \text{PseudoImm}$$
Prevents static instruction length alignment and heuristic linear sweep disassembly.

---

## 3. Advanced Defense Mechanisms: Breaking Next-Gen Deobfuscators

```
                                  Threat & Defense Model
┌───────────────────────────────┬──────────────────────────────────┬───────────────────────────────────────────┐
│ Attack Vector                 │ Attacker Mechanism               │ ASGARD-5877 Countermeasure                │
├───────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Boolean Differential Calculus │ ∂Sink / ∂s == 0                  │ Phase 5c: Memory-Address Entanglement     │
│                               │ Prunes cancelling variables      │ ∂TargetAddr / ∂s != 0 (Physical RAM Sink) │
├───────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Black-Box Inductive Synthesis │ Pure function sampling           │ Phase 5d: Stateful Transducer Coupling    │
│ (Syntia, QSynth, MCTS)        │ f(x, y) -> z formula search      │ Transducer LCG: 0% I/O reproducibility    │
├───────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Equality Saturation           │ Simultaneous rule expansion      │ Phase 5e: Non-Linear PolyMBA Knots        │
│ (E-Graphs, SaMBA, Cobra, egg) │ Linear MBA factorization         │ Degree >= 2 cross-terms & dynamic shifts  │
├───────────────────────────────┼──────────────────────────────────┼───────────────────────────────────────────┤
│ Backward Program Slicing      │ I/O sink backward reachability   │ Phase 5c & 8: Decoupled Memory & Chaff    │
│ (LLVM / IDA Hex-Rays)         │ Dead code elimination            │ Sinks retain full transitive closure      │
└───────────────────────────────┴──────────────────────────────────┴───────────────────────────────────────────┘
```

### Phase 5c: Memory-Address Entanglement (`stack_mem_webbing_pass.ml`)
**Mathematical Principle**: Eliminates the vulnerability where algebraic chords $((x + s) - s)$ have zero derivative with respect to $s$.
$$\text{offset}(s) = (s \land \text{0x78}) + 16 \in [16 \dots 128]$$
$$\text{addr} = \text{SP} - \text{offset}(s)$$
$$\text{Memory}[\text{addr}] \leftarrow s \quad (\text{WriteMem 8})$$
$$s' \leftarrow \text{Memory}[\text{addr}] \quad (\text{ReadMem 8})$$
$$s \leftarrow s + (s - s') \equiv s$$

* **Non-Zero Derivative**:
  $$\frac{\partial \text{TargetAddr}}{\partial s} \ne 0$$
  Flipping any bit of $s$ physically modifies which memory address in RAM is targeted. Symbolic simplifiers cannot cancel $s$ without risking memory corruption.
* **Sink Status**: `WriteMem` is an observable external sink, forcing backward slicers to keep all instructions computing $s$.

### Phase 5d: Stateful Transducer Coupling (`stack_transducer_pass.ml`)
**Mathematical Principle**: Destroys black-box I/O reproducibility for inductive synthesizers (Syntia / QSynth) by converting pure ALU operations into stateful transducers.
$$S_{k+1} = (S_k \cdot C_{\mathrm{mul}} + C_{\mathrm{add}}) \pmod{2^{64}}$$
Where $C_{\mathrm{mul}} = \text{0x58771337CAFEBEED}$ ($C_{\mathrm{mul}} \equiv 5 \pmod 8$), $C_{\mathrm{add}} = \text{0x9E3779B97F4A7C15}$ (Hull-Dobell maximal period over $\mathbb{Z}_{2^{64}}$).

ALU operations are split across the evolving state $S$:
* **`Add` ($A + B$)**:
  $$[B, A] \implies (B - S) + (A + S) \equiv A + B \pmod{2^{64}}$$
* **`Sub` ($A - B$)**:
  $$[B, A] \implies (A + S) - (B + S) \equiv A - B \pmod{2^{64}}$$
**Synthesizer Defeat**: Re-running a basic block with identical inputs $\langle A, B \rangle$ produces different internal values because $S$ mutates continuously ($0\%$ I/O reproducibility).

### Phase 5e: Non-Linear PolyMBA Pass (`stack_polymba_pass.ml`)
**Mathematical Principle**: Forces combinatorial explosion (OOM) in E-graphs and SMT QF_BV solvers:
1. **Degree-2 Quadratic Cross-Term Knot**:
   $$((s + 1)^2) - (s^2 + 2s + 1) \equiv 0 \pmod{2^{64}}$$
   Distributing $(s+1)(s+1)$ produces cross-terms that explode the e-node class space $O(d^k)$.
2. **Dynamic Variable-Shift Knot**:
   $$\left( (s \cdot 5 + 3) \ll (s \land 15) \right) - \left( (s \cdot 5 + 3) \ll (s \land 15) \right) \equiv 0 \pmod{2^{64}}$$
   Because $(s \land 15)$ is a dynamic runtime variable, no static first-order rewrite rule exists. Solvers must case-split across all 16 shift states.

---

## 4. Phase 8: Pipelined Stage Dispatch Architecture (`stack_runtime.ml`)

Conventional virtual machines execute an atomic centralized interpreter cycle:
$$\text{while (!halted)} \ \{ \ \text{op} = \text{fetch}(); \ \text{goto} *T[\text{op}]; \ \}$$
This creates a dominant hub in the CFG ($\text{in-degree} \ge 256$), trivially identified by graph-matching algorithms.

ASGARD-5877 implements **Pipelined Stage Dispatch**, completely decoupling the dispatch logic across all 256 handlers:

```
[Handler I_k Epilogue]
    │
    ├─► Stage 1: ASG_PIPELINED_PREFETCH
    │       op_{k+1} = bytecode[VIP] ^ (VKEY & 0xFF)
    │       step_key(&VKEY, op_{k+1})
    │       VIP++
    │
    ├─► Stage 2: Constant-Time Context Chaffing
    │       slot = chaff_base + hash(op_{k+1})
    │       VCTX[slot] ^= VKEY + op_{k+1}
    │
    └─► Stage 3: ASG_PIPELINED_DISPATCH
            k_slot = (op_{k+1} * C_golden) ^ Salt
            Target = dispatch_table[op_{k+1}] ^ k_slot
            goto *Target   (or inline asm: br X11 / jmp *RAX)
```

1. **Stage 1 (Pre-Fetch)**: Opcode $I_{k+1}$ is fetched and decrypted inside the epilogue of handler $I_k$.
2. **Stage 2 (Chaffing)**: Destroys taint continuity from bytecode buffer into PC via non-linear XOR diffusion into dead context slots.
3. **Stage 3 (Decoupled Jump)**: Direct indirect branch to pre-blinded table entry unmasked branchlessly in constant time. No centralized re-entry label exists.

---

## 5. Empirical Verification & Attack Resilience Profile

Empirically measured via `examples/deobf_probe/run_probe.sh` over protected production binaries:

### 5.1 Multi-Tier Deobfuscation Benchmark Results

| Attack Tier | Attacker Threat Model | Tooling Emulated | Evaluated Program Operations | SMT / Attack Reductions | Resilience Verdict |
|:---:|:---|:---|:---:|:---:|:---:|
| **Tier 1** | Local Peephole & Dead-Slot DCE | Hex-Rays / LLVM Opt | 195,770 ops | 47 ops (**0.02%**) | **99.98% RESILIENT** |
| **Tier 2** | Semantic SMT Zero-Knot Inverses | Z3 / D810 / Triton | 195,770 ops | 139 ops (**0.07%**) | **99.93% RESILIENT** |
| **Tier 3** | Constant Folding & Superops | Abstract Interpretation | 195,770 ops | **0 ops (0.00%)** | **100.0% RESILIENT** |
| **Tier 4** | Lifter & Backward Program Slicing | LLVM IR Backward Slicer | 195,770 ops | 4,998 kept ops | **Complete Def-Use Closure** |
| **Tier 5** | Boolean Differential Calculus | $\frac{\partial \text{Sink}}{\partial s} = 0$ Analysis | 634 Memory Sinks | **392 non-zero derivatives** | **100% Non-Detachable RAM Sinks** |
| **Tier 6** | Black-Box Inductive Synthesis | Syntia / QSynth / MCTS | 8,515 Expression Clusters | **0 / 8,515 synthesized (0.0%)** | **100.0% [TIER 3+ RESILIENT]** |

### 5.2 Dispatch Topology & Graph Invariants
- **Basic Blocks**: 322 blocks, 638 CFG edges.
- **Max In-Degree**: 12.1% (block 260).
- **CFG Verdict**: `DISPERSED - no dominant hub` (centralized dispatcher successfully eliminated).
- **Shannon Bytecode Entropy**: $7.9997$ / $8.0000$ bits/byte (indistinguishable from high-grade AES-CTR ciphertext).
- **DRS Security Score**: **97.00 / 100.00** [Maximum Hardening].

---

## 6. Zero-Native Caller Assimilation & Trampolines (`lib/adapters/`)

To prevent reverse engineers from placing breakpoints at function boundaries:
1. **Zero-Native Dispatch**: The original function body is excised and replaced with a 56-byte inline assembly trampoline.
2. **Fragmented Storage**: Bytecode is partitioned into encrypted chunks with SplitMix64 ECC verification.
3. **Decoy Manifold**: Dual dummy bytecode streams are embedded to confuse automated disassemblers.
4. **Watermarking**: 48-bit cryptographically verifiable client payload embedded with repetition ECC into executable segments.
