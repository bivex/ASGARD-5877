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
        P1["Phase 1: Context Allocation & Shuffling"]
        P1b["Phase 1b (Pass 10): Algebraic Flag Materialization"]
        P9d["Phase 2-pre (Pass 9): Affine Domain Encoding"]
        P2["Phase 2: Superoperator Fusion & Multiplicity"]
        P3["Phase 2b: Horner Amplification & E-Graph MBA"]
        P4["Phase 3 (Pass 13): CFF with Hensel Implicit Predicates"]
        P5["Phase 4: Spaghetti CFG Splitting"]
        P6["Phase 5: Metamorphic Ghost Padding"]
        P7["Phase 5b: Variable-Size Avid Junk Operands"]
        P8["Phase 5c (Pass 14): Derangement Memory Entanglement"]
        P9t["Phase 5d: Stateful Transducer Coupling"]
        P10["Phase 5e (Pass 11): Bit-Permutation MBA & Cubic Knots"]
        P11["Phase 6: State-Feedback Rolling Key Stream"]
        P12["Phase 7: Stack Balance Verification & Repair"]
        P1 --> P1b --> P9d --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8 --> P9t --> P10 --> P11 --> P12
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

## 2. Complete Mathematical Model of the 18 Hardening Passes

Every pass is a semantics-preserving endomorphism over the Stack-IR program:
$$\mathcal{T}_i: \mathcal{P}_{\mathrm{IR}} \longrightarrow \mathcal{P}_{\mathrm{IR}}'$$
Operating over the abstract machine state:
$$\Sigma = \langle \mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VCTX}, \mathrm{VStack}, \mathrm{VMem}, \mathrm{VFlags} \rangle$$
Where $\mathrm{VStack} = [v_0, v_1, \dots, v_{k-1}]$ (stack top $v_0$), and $\mathrm{VCTX}[i] \in \mathbb{Z}_{2^{64}}$.

---

### Phase 1: IR Lowering & Context Shuffling (`ir_to_stack.ml`, `context_allocator.ml`)
* **Mapping**: Bijective assignment of architectural registers $R_{\mathrm{arch}}$ to flat context slots:
  $$\pi: R_{\mathrm{arch}} \longleftrightarrow [0, C-1], \quad \mathrm{ctx}[\pi(r)] := \mathrm{Val}(r)$$
* **Stack Transition**: Translates 3-operand GPR instructions into zero-address stack operations:
  $$r_d \leftarrow r_1 \odot r_2 \implies [\text{PushReg } \pi(r_1); \ \text{PushReg } \pi(r_2); \ \odot; \ \text{PopReg } \pi(r_d)]$$
---

### Phase 1b (Pass 10): Branchless Bit-Blasted Flag Materialization (`stack_algebraic_flags_pass.ml`, `stack_handlers_emitter.ml`)
* **Formula**: Eliminates native host `RFLAGS`/`NZCV` execution dependencies by materializing condition codes entirely through branchless algebraic bit-vector expressions in $\mathbb{Z}_{2^{64}}$:
  * **Zero Flag**:
    $$\mathrm{ZF}(r) = \big( (r - 1) \land \neg r \big) \gg 63$$
  * **Sign Flag**:
    $$\mathrm{SF}(r) = r \gg 63$$
  * **Carry / Borrow Flag**:
    $$\mathrm{CF}_{\mathrm{add}}(x, y, r) = \big( (x \land y) \lor ((x \lor y) \land \neg r) \big) \gg 63$$
    $$\mathrm{CF}_{\mathrm{sub}}(x, y, r) = \big( (\neg x \land y) \lor ((\neg x \lor y) \land r) \big) \gg 63$$
  * **Signed Overflow Flag**:
    $$\mathrm{OF}_{\mathrm{add}}(x, y, r) = \big( \neg(x \oplus y) \land (x \oplus r) \big) \gg 63$$
    $$\mathrm{OF}_{\mathrm{sub}}(x, y, r) = \big( (x \oplus y) \land (x \oplus r) \big) \gg 63$$
* **Impact**: Replaces C++ conditional branches (`res == 0`, `res < 0`) in VM handlers with 100% branchless bitwise evaluations, unwinding `Flag-Dead Precondition` constraints across basic blocks.

---

### Phase 2-pre (Pass 9): End-to-End Affine Ring Domain Encoding (`stack_domain_enc_pass.ml`)
* **Formula**: Encodes program values into individual affine quotient rings $\mathbb{Z}_{2^{64}}$ via Lagrange-Rivest bijections:
  $$\mathcal{E}_i(x) = (\alpha_i \cdot x + \beta_i) \pmod{2^{64}}, \quad \alpha_i \equiv 1 \pmod 2$$
  $$\mathcal{D}_i(y) = \alpha_i^{-1} \cdot (y - \beta_i) \pmod{2^{64}}, \quad \alpha_i \cdot \alpha_i^{-1} \equiv 1 \pmod{2^{64}}$$
* **Homomorphic Operations**:
  * **Homomorphic Addition**:
    $$\hat{z} = (C_1 \cdot \hat{x} + C_2 \cdot \hat{y} + C_0) \pmod{2^{64}}$$
    where $C_1 = \alpha_3 \alpha_1^{-1}$, $C_2 = \alpha_3 \alpha_2^{-1}$, $C_0 = \beta_3 - C_1 \beta_1 - C_2 \beta_2 \pmod{2^{64}}$.
  * **Homomorphic Multiplication**:
    $$\hat{z} = (M_{xy} \cdot \hat{x} \cdot \hat{y} + M_x \cdot \hat{x} + M_y \cdot \hat{y} + M_0) \pmod{2^{64}}$$
* **Impact**: Eliminates plaintext constant signatures (AES S-Boxes, API hashes) from the instruction stream; prevents Term Slicing and GVN across differing domain encodings.

---

### Phase 2a: Superoperator Fusion (`stack_superop_pass.ml`)
* **Formula**: Fuses adjacent constant/register load and ALU instruction pairs into atomic handlers:
  $$[\text{PushImm } c; \ \text{Add}] \xrightarrow{\mathcal{T}_{\mathrm{fuse}}} [\text{AddImm } c], \quad \Delta_{\mathrm{net}} = 0$$
  $$[\text{PushReg } s; \ \text{Add}] \xrightarrow{\mathcal{T}_{\mathrm{fuse}}} [\text{AddReg } s], \quad \Delta_{\mathrm{net}} = 0$$
* **Impact**: Eliminates intermediate stack pops and pushes, reducing dispatch transitions by 40–60%.

---

### Phase 2a-mult: Handler Multiplicity (`stack_multiplicity_pass.ml`)
* **Formula**: Breaks 1:1 opcode-to-semantics mapping via non-linear Boolean basis decompositions:
  * **MBA Addition**:
    $$x + y \equiv - \big( \text{Nor}(x, y) + \text{Nand}(x, y) + 2 \big) \pmod{2^{64}}$$
  * **MBA Subtraction**:
    $$x - y \equiv (x \land \neg y) - (\neg x \land y) \pmod{2^{64}}$$
  * **Flag-Dead Precondition**: MBA expansions alter arithmetic flags (`CF`, `OF`, `AF`); they are strictly gated by `Stack_flag_liveness` to execute only when condition codes are dead.
  * **Stack Permutation Desugaring**:
    $$\text{Swap} \implies [s_1 \leftarrow \text{pop}(); \ s_2 \leftarrow \text{pop}(); \ \text{push}(s_1); \ \text{push}(s_2)]$$

---

### Phase 2: Horner Polynomial Amplification (`bytecode_amplifier.ml`)
* **Formula**: Amplifies linear computations through degree-$d$ Horner polynomial forms and carry-chain bit-slicing:
  $$P(x) = c_0 + x \cdot \big(c_1 + x \cdot (c_2 + \dots + x \cdot c_d) \dots \big) \pmod{2^{64}}$$
* **Web-Knots**: Injects def-use chords using Boolean zero identities:
  $$\text{Zero}(r) = \text{Nor}\big(r, \text{Nor}(r, r)\big) \equiv 0 \implies x + \text{Zero}(r) \equiv x$$

---

### Phase 2b: MBA Constant Synthesis (`stack_mba_pass.ml`)
* **Formula**: Eliminates literal constants `PushImm c`. Synthesizes $c$ through an E-Graph saturation engine:
  $$c \equiv \big( (a \oplus b) + 2(a \land b) \big) \pmod{2^{64}} \quad \text{where } a, b \in_R \mathbb{Z}_{2^{64}}, \ a + b = c$$
  $$c \equiv \text{Nor}(\neg c, 0) \equiv \text{Nand}(\neg c, \neg c)$$
* **Register-Anchored Synthesis**: Defeats constant folding by binding $c$ to live context registers:
  $$c \equiv (r + \text{mask}) - r + (c - \text{mask}) \pmod{2^{64}}$$

---

### Phase 3: Virtual CFG Flattening & Hensel Lifting (Pass 13, `stack_cff_pass.ml`)
* **Formula**: Transforms basic blocks into state machine transitions routed through virtual program counter $\mathrm{vpc}$:
  $$B_i \implies [\dots; \ \mathrm{vpc} \leftarrow \mathrm{Token}_{i+1}; \ \text{JmpRel Dispatcher}]$$
* **Hensel Lifting Implicit Predicate Synthesis (Pass 13)**:
  Completely erases target constants $\mathrm{Token}_k$ from machine code. The dispatcher tests equality via a flat cubic polynomial:
  $$H_k(\mathrm{vpc}) = \gamma_0 + \mathrm{vpc} \cdot \big(\gamma_1 + \mathrm{vpc} \cdot (\gamma_2 + \gamma_3 \cdot \mathrm{vpc})\big) \equiv 0 \pmod{2^{64}} \iff \mathrm{vpc} == \mathrm{Token}_k$$
  Where:
  $$\gamma_0 = \big(-a_1 \tau + 2 c_2 \tau^2 - 4 c_3 \tau^3\big) \bmod 2^{64}, \quad \gamma_1 = \big(a_1 - 4 c_2 \tau + 12 c_3 \tau^2\big) \bmod 2^{64}$$
  $$\gamma_2 = \big(2 c_2 - 12 c_3 \tau\big) \bmod 2^{64}, \quad \gamma_3 = 4 c_3 \bmod 2^{64}$$
  By Hensel's lemma, odd derivative $H_k'(\tau) \equiv a_1 \equiv 1 \pmod 2$ guarantees $\mathrm{Token}_k$ is the **strictly unique root** modulo $2^{64}$.
  Disassemblers and symbolic execution cannot grep or solve linear equality on tokens, as $\mathrm{Token}_k$ is nowhere present in the binary.
---

### Phase 4: Deterministic Spaghetti Block Splitting (`stack_spaghetti_pass.ml`)
* **Formula**: Splits block $B$ into fragments $B^{(1)}, B^{(2)}$ linked by non-linear polynomial zero branches:
  $$\mathrm{Guard}(r_1, r_2, r_3) = (r_1 \cdot r_2 + r_3) - (r_1 \cdot r_2 + r_3) \equiv 0$$
  $$\text{Terminator}: [\text{Cmp } \mathrm{Guard}, 0; \ \text{JccRel }(B^{(2)}, \text{E}); \ \text{JmpRel }(B_{\mathrm{decoy}})]$$
* **Impact**: Defeats topological block re-assembly and decompiler CFG-mergers.

---

### Phase 5: Metamorphic Ghost Stack Padding (`stack_ghost_pass.ml`)
* **Formula**: Injects parasite computations cyclically chained across a 4-slot scratch ring:
  $$s_{(i+1) \bmod 4} \leftarrow \big( s_{i \bmod 4} \odot r_{\mathrm{live}} \big) \oplus \text{Const}, \quad \odot \in \{\text{Add}, \text{Sub}, \text{Nor}\}$$
* **Stack Delta Invariant**:
  $$\Delta_{\mathrm{net}} = \sum_{op \in \text{Cluster}} \mathrm{delta}(op) = 0$$
* **Flag Preservation**: Enclosed in $[\text{PushFlags}; \ \text{Cluster}; \ \text{PopFlags}]$ when downstream flags are live.

---

### Phase 5b: Variable-Size Avid Junk Operands (`stack_avid_pass.ml`)
* **Formula**: Destroys static instruction length alignment through variable pseudo-immediates:
  $$\mathrm{Anchor}_{k+1} \leftarrow (\mathrm{Anchor}_k \cdot C_{\mathrm{gold}} + \mathrm{PseudoImm}) \pmod{2^{64}}$$
* **Stack Roundtrip**:
  $$[\text{PushImm } \text{imm}; \ \text{PushReg } \mathrm{Anchor}; \ \text{Swap}; \ \text{PopReg } \mathrm{Anchor}; \ \text{PopReg Scratch}]$$

---

### Phase 5c: Non-Aliasing Feistel / Derangement Memory Entanglement (Pass 14, `stack_mem_webbing_pass.ml`)
* **Derangement Memory Invariant & LLVM Store-to-Load Forwarding Defeat**:
  Computes two provably distinct 8-byte aligned addresses strictly within a single 64-byte L1D cache line $[\mathrm{Base} \dots \mathrm{Base} + 56]$:
  $$\mathrm{Base} = (\mathrm{SP} - 128) \land \sim\!\text{0x3F}$$
  $$a_{\mathrm{real}} = \mathrm{Base} + (s \land \text{0x38})$$
  $$a_{\mathrm{decoy}} = \mathrm{Base} + 8 \cdot \Big( \big( K_{\mathrm{perm}} \gg (3 \cdot ((s \gg 3) \land 7)) \big) \land 7 \Big)$$
  Where $K_{\mathrm{perm}} = \texttt{0x1F58D1}$ is a derangement permutation in $\mathbb{F}_{2^3}$ ($\forall u \in [0..7]: \pi(u) \ne u$).
  * Store 1 (live value): $\mathrm{Memory}[a_{\mathrm{real}}] \leftarrow s \quad (\text{WriteMem 8})$
  * Store 2 (interleaving decoy): $\mathrm{Memory}[a_{\mathrm{decoy}}] \leftarrow (s + \text{0x58771337CAFE}) \quad (\text{WriteMem 8})$
  * Load (real read): $s' \leftarrow \mathrm{Memory}[a_{\mathrm{real}}] \quad (\text{ReadMem 8})$
  * Self-verifying recovery: $s \leftarrow s + (s - s') \equiv s \pmod{2^{64}}$
* **Anti-Forwarding Invariant**: Because Store 2 writes a distinct value to $a_{\mathrm{decoy}}$ strictly between Store 1 and Load 1 via a dynamic variable shift, LLVM `BasicAA` and `SCEVAA` cannot prove disjointness and return `MayAlias`, physically prohibiting store-to-load forwarding.
* **Cache & ABI Safety**: Negative offset $(\mathrm{SP} - 128)$ strictly allocates in private host memory; mask `0x38` bounds the entire cluster within 56 bytes of a single 64-byte L1D line.
---

### Phase 5d: Stateful Transducer Coupling (`stack_transducer_pass.ml`)
* **Formula**: Converts pure ALU operations into stateful transducers to break inductive synthesis (Syntia / QSynth):
  $$S_{k+1} = (S_k \cdot C_{\mathrm{mul}} + C_{\mathrm{add}}) \pmod{2^{64}}$$
  Where $C_{\mathrm{mul}} \equiv 5 \pmod 8$, $C_{\mathrm{add}} \equiv 1 \pmod 2$ ($\gcd(C_{\mathrm{add}}, 2^{64}) = 1$, strictly satisfying the Hull-Dobell theorem for maximal period $2^{64}$).
  * **Add**: $[B, A] \implies (B - S) + (A + S) \equiv A + B \pmod{2^{64}}$
  * **Sub**: $[B, A] \implies (A + S) - (B + S) \equiv A - B \pmod{2^{64}}$
* **Flag-Dead Precondition**: To prevent distortion of condition codes (`CF`, `OF`, `AF`), transducer transformations are **strictly restricted** to instructions where downstream flags are dead ($\text{live}(\text{Flags}) == \text{false}$ via `Stack_flag_liveness`).
* **Zero I/O Reproducibility**:
  $$\forall \langle A, B \rangle: \quad \mathrm{Out}_1(A, B, S_1) \ne \mathrm{Out}_2(A, B, S_2) \quad \text{for } S_1 \ne S_2$$

---

### Phase 5e: Non-Linear PolyMBA & Bit-Permutation Knots (Pass 11, `stack_polymba_pass.ml`)
* **Formula**: Forces e-node explosion in E-Graphs (SaMBA, Cobra, egg) and breaks linear MBA coordinate projections (SiMBA, GAMBA):
  * **Degree $\ge 3$ Cubic Rivest Permutation Knot**:
    $$\mathrm{Knot}_{\mathrm{cubic}}(s) = ((s + 1)^3) - (s^3 + 3s^2 + 3s + 1) \equiv 0 \pmod{2^{64}}$$
    Expands into 8 multinomial terms in equality saturation, saturating SMT rewrite budgets.
  * **Asymmetric Distributive Shift Knot**:
    $$\mathrm{Knot}_{\mathrm{shift}}^*(s) = \big( (s \cdot 5 + 3) \ll (s \land 15) \big) - \Big( \big( (s \ll (s \land 15)) \cdot 5 \big) + \big( 3 \ll (s \land 15) \big) \Big) \equiv 0 \pmod{2^{64}}$$
  * **Non-Associative Bit-Permutation MBA Knot (Pass 11)**:
    $$\mathrm{Knot}_{\mathrm{perm}}(s) = s - \Big( \mathrm{swap}_{32}\big( \mathrm{swap}_{32}(s) \oplus C \big) \oplus C \Big) \equiv 0 \pmod{2^{64}}$$
    Where $\mathrm{swap}_{32}(x) = (x \ll 32) \lor (x \gg 32)$ and $C = \texttt{0x5555555555555555}$. Because bit-permutations do not commute with coordinate-wise bit projections, linear MBA solvers fail with matrix rank divergence.

---

### Phase 5f: Chinese Remainder Theorem (CRT) Split-Path Execution (Pass 12, `stack_crt_pass.ml`)
* **Formula**: Splits arithmetic operations across pairwise coprime non-power-of-2 moduli:
  $$m_1 = 2^{22} = 4\,194\,304, \quad m_2 = 2^{21} - 1 = 2\,097\,151, \quad m_3 = 2^{21} - 3 = 2\,097\,149$$
  Dynamic range $M = m_1 \cdot m_2 \cdot m_3 = \texttt{0xFFFFE00000C00000} \approx 2^{64}$.
* **Garner Mixed-Radix Reconstruction (Zero 64-Bit Overflow)**:
  $$x_1 = z_1 \bmod m_1$$
  $$x_2 = \big((z_2 - (x_1 \bmod m_2) + m_2) \cdot (m_1^{-1} \bmod m_2)\big) \bmod m_2$$
  $$t_3 = \big((z_3 - (x_1 \bmod m_3) + m_3) \cdot (m_1^{-1} \bmod m_3)\big) \bmod m_3$$
  $$x_3 = \big((t_3 - (x_2 \bmod m_3) + m_3) \cdot (m_2^{-1} \bmod m_3)\big) \bmod m_3$$
  $$x = x_1 + m_1 \cdot (x_2 + m_2 \cdot x_3) \pmod M$$
  Intermediates stay strictly $< 2^{42}$, guaranteeing exact 64-bit integer execution without overflow while forcing SMT solvers into division timeouts in the `QF_BV` logic.
---

### Phase 6: State-Feedback Rolling Key Stream (`stack_feedback_pass.ml`)
* **Formula**: Cryptographically couples bytecode decryption key $\mathrm{VKEY}$ to dynamic register state:
  $$\mathrm{VKEY}_{k+1} = \mathrm{VKEY}_k \oplus \mathrm{Hash}_{\mathrm{splitmix64}}(\mathrm{VCTX}[\mathrm{slot}_k])$$
  $$\mathrm{Hash}(v) = \mathrm{fold64}(v \times C_{\mathrm{golden}} \oplus (v \gg 32))$$
* **Integrity**: Any runtime context tampering or register hooking desynchronizes the keystream, causing illegal opcode faults.

---

### Phase 7: Formal Stack Balance & Type Verification (`stack_balance_pass.ml`)
* **Formal Verification Invariant**: Statically verifies that every basic block enters and exits with an empty operational evaluation stack:
  $$\forall B_i \in \text{Blocks}: \quad \Delta_{\mathrm{exit}}(B_i) = \sum_{op \in B_i} \mathrm{delta}(op) \equiv 0 \quad \land \quad \min_{t} \mathrm{depth}(t) \ge 0$$
* **Compiler Safety**: Emits a fatal compiler error if any hardening pass violates stack neutrality or introduces an underflow branch.

---

### Phase 8: Pipelined Stage Dispatch Architecture (`stack_runtime.ml`, `pipelined_dispatch_pass.ml`)
* **Formula**: Completely eliminates centralized interpreter dispatch loops via decoupled 3-stage handler epilogues:
  $$\text{Stage 1 (Pre-Fetch)}: \quad \mathrm{op}_{k+1} = \mathrm{Bytecode}[\mathrm{VIP}] \oplus (\mathrm{VKEY}_k \land \text{0xFF}), \quad \mathrm{VIP} \leftarrow \mathrm{VIP} + 1$$
  $$\mathrm{VKEY}_{k+1} = \mathrm{StepKey}(\mathrm{VKEY}_k, \mathrm{op}_{k+1})$$
  $$\text{Stage 2 (Chaffing)}: \quad \mathrm{slot}_{\mathrm{chaff}} = C_{\mathrm{base}} + \left( \frac{(\mathrm{op}_{k+1} \cdot C_{\mathrm{golden}}) \oplus \mathrm{Salt}}{2^{56}} \land \mathrm{Mask} \right)$$
  $$\mathrm{VCTX}[\mathrm{slot}_{\mathrm{chaff}}] \leftarrow \mathrm{VCTX}[\mathrm{slot}_{\mathrm{chaff}}] \oplus (\mathrm{VKEY}_{k+1} + \mathrm{op}_{k+1})$$
  $$\text{Stage 3 (Decoupled Jump)}: \quad K_{\mathrm{slot}}(\mathrm{op}) = (\mathrm{op} \cdot C_{\mathrm{table}}) \oplus \mathrm{Salt}_{\mathrm{affine}} \oplus \mathrm{addr\_key}$$
  $$\mathrm{Target} = \mathrm{DispatchTable}[\mathrm{op}_{k+1}] \oplus K_{\mathrm{slot}}(\mathrm{op}_{k+1}) \equiv \& \&\text{lbl\_op}$$
  $$\text{Jump}: \quad \text{goto } *\mathrm{Target} \quad \big(\text{or inline asm: } \text{br X11} \ / \ \text{jmp *RAX}\big)$$
* **Dynamic Table Blinding**: $\mathrm{DispatchTable}[i] = (\& \&\text{lbl\_op}_i) \oplus K_{\mathrm{slot}}(i)$. Because $\mathrm{addr\_key}$ is computed at startup by $\text{derive\_addr\_key}()$ from the runtime ASLR layout of all handlers in memory, static offline extraction of the 256 handler entrypoints from $\mathrm{.rodata}$ yields complete garbage without process execution.
## 5. Empirical Verification & Attack Resilience Profile

Empirically measured via `examples/deobf_probe/run_probe.sh` over protected production binaries:

### 5.1 Multi-Tier Deobfuscation Benchmark Results

| Attack Tier | Attacker Threat Model | Tooling Emulated | Evaluated Program Operations | SMT / Attack Reductions | Resilience Verdict |
|:---:|:---|:---|:---:|:---:|:---:|
| **Tier 1** | Local Peephole & Dead-Slot DCE | Hex-Rays / LLVM Opt | 235,397 ops | 40 ops (**0.02%**) | **99.98% RESILIENT** |
| **Tier 2** | Semantic SMT Zero-Knot Inverses | Z3 / D810 / Triton | 235,397 ops | 139 ops (**0.06%**) | **99.94% RESILIENT** |
| **Tier 3** | Constant Folding & Superops | Abstract Interpretation | 235,397 ops | **0 ops (0.00%)** | **100.0% RESILIENT** |
| **Tier 4** | Lifter & Backward Program Slicing | LLVM IR Backward Slicer | 235,397 ops | 8,096 kept ops | **Complete Def-Use Closure (+1.7x)** |
| **Tier 5** | Boolean Differential Calculus | $\frac{\partial \mathrm{Sink}}{\partial s} \ne 0$ Analysis | 1,255 Memory Sinks | **1,179 non-zero derivatives (93.9%)** | **100% Non-Detachable RAM Sinks** |
| **Tier 6** | Black-Box Inductive Synthesis | Syntia / QSynth / MCTS | 8,531 Expression Clusters | **0 / 8,531 synthesized (0.0%)** | **100.0% [TIER 3+ RESILIENT]** |

### 5.2 Dispatch Topology & Graph Invariants
- **Basic Blocks**: 322 blocks, 638 CFG edges.
- **Max In-Degree**: 12.1% (block 260).
- **CFG Verdict**: `DISPERSED - no dominant hub` (centralized dispatcher successfully eliminated).
- **Shannon Bytecode Entropy**: $7.9998$ / $8.0000$ bits/byte (indistinguishable from high-grade AES-CTR ciphertext).
- **DRS Security Score**: **97.00 / 100.00** [Maximum Hardening].

---

## 6. Zero-Native Caller Assimilation & Trampolines (`lib/adapters/`)

To prevent reverse engineers from placing breakpoints at function boundaries:
1. **Zero-Native Dispatch**: The original function body is excised and replaced with a 56-byte inline assembly trampoline.
2. **Fragmented Storage**: Bytecode is partitioned into encrypted chunks with SplitMix64 ECC verification.
3. **Decoy Manifold**: Dual dummy bytecode streams are embedded to confuse automated disassemblers.
4. **Watermarking**: 48-bit cryptographically verifiable client payload embedded with repetition ECC into executable segments.
