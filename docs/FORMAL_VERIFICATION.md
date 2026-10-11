# Formal Verification & F* Proof Workflow

This document explains the formal verification architecture of **ASGARD-5877**, how Mixed Boolean-Arithmetic (MBA) rewrite rules are mathematically proven in **F\* 2026.08.23** with **Z3 5.0.0**, and how verified code is extracted into clean OCaml.

---

## 1. Overview & Verification Objectives

In binary virtualization and obfuscation, compiler bugs can alter the runtime semantics of protected functions, causing silent corruption or crashes. 

To provide **mathematical certainty** that transformations preserve original program semantics, ASGARD-5877 uses **F\*** (a functional programming language with dependent types and refinement types from Microsoft Research / Inria) integrated with the **Z3 SMT solver**.

```
┌────────────────────────────────────────────────────────┐
│            F* Source (fstar/Mba_Verified.fst)          │
│  - Bit-extensionality lemmas (FStar.UInt.nth_lemma)    │
│  - Two's complement algebraic cancellation lemmas      │
│  - Refinement types (forall env. eval e' == eval e)    │
│  - Structural induction across 9 AST constructors      │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼ (fstar.exe check + Z3 Proofs)
┌────────────────────────────────────────────────────────┐
│             Automated SMT Solver (Z3 5.0.0)            │
│  - Discharges 100% of proof obligations in < 0.5s      │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼ (fstar.exe --codegen OCaml)
┌────────────────────────────────────────────────────────┐
│          Extracted OCaml (fstar/Mba_Verified.ml)       │
│  - Proof erasure: all lemmas and ghost types stripped │
│  - Pure, high-performance OCaml AST rewriter          │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼ (Native Integration)
┌────────────────────────────────────────────────────────┐
│     Native VM Protector Library (lib/mba_engine/)      │
│  - rewrite_verified & rewrite_demorgan                 │
│  - 31 verified E-graph equality saturation rules       │
│  - Verified opaque polynomial zero invariants          │
└────────────────────────────────────────────────────────┘
```

---

## 2. Formally Proven MBA Identities (`fstar/Mba_Verified.fst`)

All MBA identities are verified over 64-bit modular arithmetic (`uint_t 64`) using bit-extensionality:

$$\forall a, b \in \mathbb{U}_{64}, \quad (\forall i \in [0, 63], \; \text{bit}_i(LHS) = \text{bit}_i(RHS)) \implies LHS = RHS$$

### 2.1 Core Boolean Identities

1. **XOR via OR and AND (`mba_xor_eq`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \oplus b \equiv (a \lor b) \oplus (a \land b)$$

2. **AND via OR and XOR (`mba_and_eq`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \land b \equiv (a \lor b) \oplus (a \oplus b)$$

3. **OR via XOR and AND (`mba_or_eq`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \lor b \equiv (a \oplus b) \oplus (a \land b)$$

4. **Bitwise NOT via XOR (`mba_not_eq`)**:
   $$\forall a \in \mathbb{U}_{64}, \quad \sim a \equiv a \oplus \text{0xFFFFFFFFFFFFFFFF}$$

### 2.2 De Morgan Laws & Involutions

5. **De Morgan AND (`mba_and_demorgan`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \land b \equiv \sim(\sim a \lor \sim b)$$

6. **De Morgan OR (`mba_or_demorgan`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \lor b \equiv \sim(\sim a \land \sim b)$$

7. **XOR Bitwise Involution (`mba_xor_not`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \oplus b \equiv \sim a \oplus \sim b$$

8. **Double Negation / Involutive NOT (`mba_double_not`)**:
   $$\forall a \in \mathbb{U}_{64}, \quad \sim(\sim a) \equiv a$$

9. **NOT-XOR Distribution (`mba_not_xor`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad \sim(a \oplus b) \equiv \sim a \oplus b$$

10. **Complement Annihilation (`mba_and_not_self`, `mba_or_not_self`)**:
    $$a \land \sim a \equiv 0, \quad a \lor \sim a \equiv \text{0xFFFFFFFFFFFFFFFF}$$

### 2.3 Two's Complement Arithmetic Bridges

These theorems bridge modular arithmetic modulo $2^{64}$ and bitwise operations:

11. **Arithmetic NOT (`mba_not_arith`)**:
    $$\forall a \in \mathbb{U}_{64}, \quad \sim a \equiv -a - 1 \pmod{2^{64}}$$

12. **Arithmetic Negation (`mba_neg_eq`)**:
    $$\forall a \in \mathbb{U}_{64}, \quad -a \equiv \sim a + 1 \pmod{2^{64}}$$

13. **Double Arithmetic Negation (`mba_double_neg`)**:
    $$\forall a \in \mathbb{U}_{64}, \quad -(-a) \equiv a \pmod{2^{64}}$$

14. **Subtraction via Bitwise NOT (`mba_sub_via_not`)**:
    $$\forall a, b \in \mathbb{U}_{64}, \quad a - b \equiv a + (\sim b + 1) \pmod{2^{64}}$$

15. **Identity & Nilpotence (`mba_sub_self`, `mba_add_zero`, `mba_sub_zero`)**:
    $$a - a \equiv 0, \quad a + 0 \equiv a, \quad a - 0 \equiv a \pmod{2^{64}}$$

---

## 3. Structural Induction Theorems: Soundness of Rewriters

F\* verifies two complete recursive AST rewriters via structural induction across all 9 expression constructors (`Var`, `Const`, `Add`, `Sub`, `Neg`, `Xor`, `And`, `Or`, `Not`):

### 3.1 Main MBA Rewriter Soundness (`rewrite_sound`)

```fstar
val rewrite_sound : depth:nat -> e:expr ->
  Lemma (forall (env:env_t). eval env (rewrite depth e) == eval env e)
```

**Inductive invariant**:
* At depth 0: identity transformation.
* At depth $k+1$:
  - `Neg a` is replaced by `Add (Not (r a)) (Const 1)` (proven by `mba_neg_eq`).
  - `Sub a b` is replaced by `Add (r a) (Add (Not (r b)) (Const 1))` (proven by `mba_sub_via_not`).
  - `Xor a b` is replaced by `Xor (Or (r a) (r b)) (And (r a) (r b))` (proven by `mba_xor_eq`).
  - `And a b` is replaced by `Xor (Or (r a) (r b)) (Xor (r a) (r b))` (proven by `mba_and_eq`).
  - `Or a b` is replaced by `Xor (Xor (r a) (r b)) (And (r a) (r b))` (proven by `mba_or_eq`).
  - `Not a` is replaced by `Xor (r a) (Const (ones 64))` (proven by `mba_not_eq`).
  - `Add a b` preserves evaluation trivially by induction on children.

### 3.2 De Morgan Rewriter Soundness (`rewrite_demorgan_sound`)

```fstar
val rewrite_demorgan_sound : depth:nat -> e:expr ->
  Lemma (forall (env:env_t). eval env (rewrite_demorgan depth e) == eval env e)
```

Proves that recursive De Morgan dualization ($a \land b \mapsto \sim(\sim a \lor \sim b)$, $a \lor b \mapsto \sim(\sim a \land \sim b)$, $a \oplus b \mapsto \sim a \oplus \sim b$) preserves exact 64-bit runtime semantics under any environment.

---

## 4. OCaml Integration in `lib/mba_engine/`

The formally verified proofs directly back the obfuscation pipeline in ASGARD-5877:

1. **`Mba.rewrite_verified`**: Deterministic rewriter mirroring `Mba_Verified.rewrite` from F\*.
2. **`Mba.rewrite_demorgan`**: De Morgan normalizer mirroring `Mba_Verified.rewrite_demorgan` from F\*.
3. **Opaque Polynomial Zero Invariants**:
   - `zero_inv1 a b`: $((a \lor b) + (a \land b)) - (a + b) \equiv 0$
   - `zero_inv2 a b`: $(a \oplus b) - ((a \lor b) - (a \land b)) \equiv 0$
   - `zero_inv3 a b`: $((a \land b) + (a \land \sim b)) - a \equiv 0$
   - `zero_inv4 a b`: $((a \oplus b) + 2(a \land b)) - (a + b) \equiv 0$
   - `zero_inv_demorgan_and a b`: $(a \land b) - \sim(\sim a \lor \sim b) \equiv 0$
   - `zero_inv_demorgan_or a b`: $(a \lor b) - \sim(\sim a \land \sim b) \equiv 0$
   - `zero_inv_sub_not a b`: $(a - b) - (a + (\sim b + 1)) \equiv 0$
4. **E-graph Equality Saturation (`egraph_rules.ml`)**:
   Contains 31 verified rewriting rules + 4 degree-5 non-linear invariants (total 35 rules), all validated against randomized inputs and edge vectors over $\mathbb{Z}_{2^{64}}$.

---

## 5. Formally Verified Lazy Flags & Branch Conditions (`fstar/Flags_Verified.fst`)

In binary virtualization, CPU flags (Carry, Zero, Sign, Overflow) determine all conditional branch decisions (`jcc`). ASGARD-5877 calculates flags lazily using optimized 64-bit bitwise expressions.

Module [`fstar/Flags_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Flags_Verified.fst) formally proves that these lazy expressions are **100% equivalent** to architectural x86_64 / ARM64 hardware specifications under all $2^{64} \times 2^{64}$ inputs.

### 5.1 Arithmetic Flags Theorems

1. **Carry Flag on ADD (`theorem_cf_add`)**:
   $$a + b \ge 2^{64} \iff \text{add\_mod}(a, b) < a$$
   *Proves*: Unsigned addition overflow is identically detected by comparing the modular sum to the first operand.

2. **Borrow Flag on SUB (`theorem_cf_sub`)**:
   $$a < b \iff \text{lazy\_cf\_sub}(a, b)$$

3. **Zero Flag (`theorem_zf`) & Sign Flag (`theorem_sf`)**:
   $$\text{compute\_zf}(res) \iff res = 0, \quad \text{compute\_sf}(res) \iff \text{to\_signed}(res) < 0$$
   *Proves*: MSB extraction (`msb res`) rigorously tests negative numbers under two's complement.

4. **Overflow Flag on ADD (`theorem_of_add`)**:
   $$\text{hw\_of\_add}(a, b) \iff \text{msb}(((a \oplus dst) \land (b \oplus dst)))$$
   *Proves*: Signed addition overflow ($(a > 0 \land b > 0 \land dst < 0) \lor (a < 0 \land b < 0 \land dst \ge 0)$) exactly matches the single-cycle bitwise formula used in the VM.

5. **Overflow Flag on SUB (`theorem_of_sub`)**:
   $$\text{hw\_of\_sub}(a, b) \iff \text{msb}(((a \oplus b) \land (a \oplus dst)))$$
   *Proves*: Signed subtraction overflow is identically detected.

### 5.2 Branch Condition Code (Jcc) Theorems

ASGARD-5877 formally proves the fundamental equivalence theorems of computer architecture:

| Condition | Flag Formula | Architectural Meaning | Formally Proven Theorem |
|---|---|---|---|
| **L** (Less / JL) | $SF \neq OF$ | $\text{to\_signed}(a) < \text{to\_signed}(b)$ | `theorem_cond_l` |
| **GE** (Greater or Equal / JGE) | $SF = OF$ | $\text{to\_signed}(a) \ge \text{to\_signed}(b)$ | `theorem_cond_ge` |
| **LE** (Less or Equal / JLE) | $ZF \lor (SF \neq OF)$ | $\text{to\_signed}(a) \le \text{to\_signed}(b)$ | `theorem_cond_le` |
| **G** (Greater / JG) | $\neg ZF \land (SF = OF)$ | $\text{to\_signed}(a) > \text{to\_signed}(b)$ | `theorem_cond_g` |
| **B** (Below / JB / Carry) | $CF$ | $a <_{unsigned} b$ | `theorem_cond_b` |
| **AE** (Above or Equal / JAE) | $\neg CF$ | $a \ge_{unsigned} b$ | `theorem_cond_ae` |
| **BE** (Below or Equal / JBE) | $CF \lor ZF$ | $a \le_{unsigned} b$ | `theorem_cond_be` |
| **A** (Above / JA) | $\neg CF \land \neg ZF$ | $a >_{unsigned} b$ | `theorem_cond_a` |

---

## 6. Formally Verified Residue Number System & CRT (`fstar/Rns_Verified.fst`)

ASGARD-5877 uses a 4-channel Residue Number System (RNS-4) to split 64-bit integer calculations into carry-free parallel modular channels ($m_1, m_2, m_3, m_4$), obscuring arithmetic dataflow against symbolic deobfuscation and SMT synthesis attacks.

Reconstruction of the original integer uses the **Garner Mixed-Radix Conversion algorithm** (a constructive Chinese Remainder Theorem implementation).

Module [`fstar/Rns_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Rns_Verified.fst) formally proves:

### 6.1 Moduli and Dynamic Range
* $m_1 = 65537$ ($2^{16} + 1$, Fermat prime)
* $m_2 = 65521$ (largest prime $< 2^{16}$)
* $m_3 = 65519$ (second largest prime $< 2^{16}$)
* $m_4 = 65497$ (third largest prime $< 2^{16}$)
* **Dynamic Range (`theorem_dynamic_range`)**:
  $$M = \prod_{i=1}^4 m_i = 18427046975179708711 > 2^{63} - 1$$
  *Proves*: Range covers all non-negative 63-bit integers without overflow.

### 6.2 Precomputed Bézout Inverses (`theorem_inverses`)
F* rigorously proves all 6 mixed-radix inverses:
* $(m_1 \cdot 61426) \equiv 1 \pmod{m_2}$
* $(m_1 \cdot 3640) \equiv 1 \pmod{m_3}$
* $(m_1 \cdot 11462) \equiv 1 \pmod{m_4}$
* $(m_2 \cdot 32760) \equiv 1 \pmod{m_3}$
* $(m_2 \cdot 62768) \equiv 1 \pmod{m_4}$
* $(m_3 \cdot 20840) \equiv 1 \pmod{m_4}$

### 6.3 Garner Mixed-Radix Reconstruction
Reconstruction evaluates the Horner polynomial:
$$X = v_1 + m_1 (v_2 + m_2 (v_3 + m_3 v_4))$$

Proven theorems:
1. **Range Bound (`theorem_garner_range`)**: $\forall r, \; \text{decode}(r) < M$.
2. **Channel 1 Congruence (`theorem_garner_m1`)**: $\text{decode}(r) \equiv r_1 \pmod{m_1}$.
3. **Channel 2 Congruence (`theorem_garner_m2`)**: $\text{decode}(r) \equiv r_2 \pmod{m_2}$.
4. **Channel Additive Homomorphism (`theorem_rns_add_homomorphism`)**: Parallel addition across moduli preserves $(a + b) \pmod{m_i}$ on all 4 channels.

---

## 7. Formally Verified Stack-VM Balance & Underflow Freedom (`fstar/Stack_Balance_Verified.fst`)

In bytecode virtualization, basic blocks execute stack pushes and pops. Any stack imbalance across join points or negative stack underflow leads to fatal VM crashes (unmapped host stack reads or register context corruption).

Module [`fstar/Stack_Balance_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Stack_Balance_Verified.fst) formally models all 37 Stack-VM opcodes, their push/pop weights, and proves the correctness of the balance analysis and repair pass.

### 7.1 Core Stack Delta Algebra
* **Delta Homomorphism (`lemma_sum_delta_append`)**:
  $$\forall L_1, L_2, \quad \Delta(L_1 \mathbin{+\!+} L_2) = \Delta(L_1) + \Delta(L_2)$$
* **Repetition Homomorphism (`lemma_sum_delta_repeat`)**:
  $$\forall n, op, \quad \Delta(\text{repeat } n \; op) = n \cdot \delta(op)$$
* **Non-destructive Splitting (`lemma_split_append`)**:
  Separating basic blocks at the first terminator into $(\text{prefix}, \text{suffix})$ preserves exact instruction sequence.

### 7.2 Theorems of Balance & Safety
1. **Total Balance Repair Soundness (`theorem_repair_balanced`)**:
   $$\forall ops, reg, \quad \Delta(\text{repair\_ops}(ops, reg)) \equiv 0$$
   *Proves*: For any arbitrary block with excess values ($d > 0$), inserting $d$ `PopReg`s before terminators, or for blocks with stack deficiency ($d < 0$), prepending $-d$ `PushImm`s, mathematically guarantees zero net stack drift.

2. **CFG Path Stack Invariance (`theorem_path_balance`)**:
   For any execution path $P = [B_1, B_2, \dots, B_k]$ composed of repaired blocks:
   $$\Delta_{\text{total}}(P) = \sum_{i=1}^k \Delta(B_i) = 0$$
   *Proves*: Arbitrary branch, loop, and jump executions never accumulate phantom stack drift across CFG join points.

3. **Dynamic Execution Semantics (`theorem_eval_depth_delta`)**:
   If dynamic execution from depth $cur$ completes safely without underflow:
   $$\text{eval\_depth}(cur, ops) = \text{Some } final\_d \implies final\_d = cur + \Delta(ops)$$

4. **Underflow Freedom Invariant (`theorem_min_req_safe`)**:
   Given inductive minimum required depth $\text{min\_req}(ops)$:
   $$cur \ge \text{min\_req}(ops) \implies \text{eval\_depth}(cur, ops) \neq \text{None}$$
   *Proves*: The stack never encounters underflow at any intermediate execution step.

5. **Padded Trace Safety (`theorem_padded_never_underflows`)**:
   Prepending $\text{min\_req}(ops)$ `PushImm` instructions guarantees that starting from an empty stack ($depth = 0$), execution always completes without underflow:
   $$\text{eval\_depth}(0, \text{repeat } (\text{min\_req } ops) \; (\text{PushImm } 0) \mathbin{+\!+} ops) \neq \text{None}$$

---

## 8. Formally Verified Instruction Codec & Total Parser Safety (`fstar/Codec_Verified.fst`)

Vanguard-9292 uses randomized bitfield layout permutation and rolling key XOR stream encryption for all instruction words. A critical vulnerability in binary interpreters is parser panics / out-of-bounds crashes when encountering corrupted bytes, junk opcodes, or adversarial payloads.

Module [`fstar/Codec_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Codec_Verified.fst) formally specifies bitfield slices and rolling key encryption, proving roundtrip fidelity and total parser safety.

### 8.1 Disjoint Slice Packing & Extraction
* **Prefix / Suffix / Nested Invariants (`lemma_slice_prefix`, `lemma_slice_suffix`, `lemma_slice_nested`)**:
  Formally establishes non-interference across bitfield concatenation:
  $$\text{slice}(\text{append } s_1 \; s_2, 0, |s_1|) = s_1$$
  $$\text{slice}(\text{append } s_1 \; s_2, |s_1| + i, |s_1| + j) = \text{slice}(s_2, i, j)$$

### 8.2 Theorems of Codec Fidelity & Security
1. **Unencrypted Packing Roundtrip (`theorem_pack_unpack_roundtrip`)**:
   $$\forall i \in \text{v\_instr}, \quad \text{unpack}(\text{pack}(i)) \equiv i$$
   *Proves*: Bitfield packing of Opcode (8b), Dst (8b), Src1 (8b), Src2 (8b), Imm (16b), Mask (8b), Junk (8b) into 64-bit words has zero bit crosstalk and recovers all fields identically.

2. **Rolling Key Involution (`theorem_key_involution`)**:
   $$\forall W, K \in \mathbb{B}^{64}, \quad (W \oplus K) \oplus K = W$$

3. **End-to-End Encrypted Codec Roundtrip (`theorem_codec_roundtrip`)**:
   $$\forall i, K, \quad \text{decode}(\text{encode}(i, K), K) \equiv i$$
   *Proves*: Any instruction encrypted with a rolling key is decoded back to the exact original instruction without loss.

4. **Parser Total Safety / Crash Freedom (`theorem_parser_total_safety`)**:
   For ANY 64-bit word $W \in \mathbb{B}^{64}$ and arbitrary stream key $K$:
   $$\text{parse\_word}(W, K, \text{is\_junk}, \text{is\_valid}) \text{ is total and never panics}$$
   *Proves*: Decoder terminates unconditionally on any arbitrary input (including malformed fuzzing vectors) and partitions all words into structured `Parse_Success`, `Parse_Junk`, or `Parse_Invalid`.

---

## 9. Formally Verified Degree-5 Null-Polynomials over $\mathbb{Z}_{2^{64}}$ (`fstar/Poly_Verified.fst`)

ASGARD-5877 uses degree-5 opaque polynomial zero invariants in Control Flow Flattening (CFF) and dead-code generator passes to create branch conditions that are algebraically impossible to evaluate to non-zero, defeating symbolic execution solvers and heuristic deobfuscators.

Module [`fstar/Poly_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Poly_Verified.fst) formally proves:

### 9.1 Divisibility by $2^3 = 8$
* **Parity Division Step (`lemma_consecutive_even`, `lemma_even_step2_div8`, `lemma_odd_step2_div8`)**:
  - If $x$ is even: $x = 2k \implies x(x-2) = 4k(k-1)$. Since $k(k-1)$ is even, $x(x-2) = 8m \implies x(x-2) \equiv 0 \pmod 8$.
  - If $x$ is odd: $x-1 = 2k \implies (x-1)(x-3) = 4k(k-1) = 8m \implies (x-1)(x-3) \equiv 0 \pmod 8$.
* **Consecutive Factor Theorem (`theorem_poly5_divisible_by_8`)**:
  $$\forall x \in \mathbb{Z}, \quad x(x - 1)(x - 2)(x - 3)(x - 4) \equiv 0 \pmod 8$$
* **Symmetric Factor Theorem (`theorem_poly5_sym_divisible_by_8`)**:
  $$\forall x \in \mathbb{Z}, \quad (x - 2)(x - 1)x(x + 1)(x + 2) \equiv 0 \pmod 8$$

### 9.2 Opaque Annihilation Modulo $2^{64}$
1. **Canonical Degree-5 Null Invariant (`theorem_zero_inv5_poly`)**:
   $$\forall x \in \mathbb{Z}, \quad 2^{61} \cdot x(x - 1)(x - 2)(x - 3)(x - 4) \equiv 0 \pmod{2^{64}}$$
   *Proof*: Since $P(x) = 8k = 2^3 k$, then $2^{61} \cdot P(x) = 2^{61} \cdot 2^3 k = 2^{64} k \equiv 0 \pmod{2^{64}}$.

2. **Symmetric Centered Degree-5 Invariant (`theorem_zero_inv5_sym_poly`)**:
   $$\forall x \in \mathbb{Z}, \quad 2^{61} \cdot (x - 2)(x - 1)x(x + 1)(x + 2) \equiv 0 \pmod{2^{64}}$$

3. **Non-linear Cross-term Annihilation (`theorem_zero_inv5_nl`)**:
   $$\forall E \in \mathbb{Z}, \quad \text{zero\_factor} \equiv 0 \pmod{2^{64}} \implies (\text{zero\_factor} \cdot E) \equiv 0 \pmod{2^{64}}$$

---

## 10. Formally Verified Anti-Pushan Rolling Keys & Cryptographic Bijectivity (`fstar/Rolling_Key_Verified.fst`)

In ASGARD-5877, instruction execution history dynamically mutates a 64-bit running cryptographic key via the `advance_key_step` state evolution primitive. To ensure that the keystream space never collapses, degrades into fixed points, or loses entropy across execution depth, the transition mapping must be mathematically bijective (one-to-one and onto).

Module [`fstar/Rolling_Key_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Rolling_Key_Verified.fst) formally proves:

### 10.1 Modular Inverse & Cyclic Rotations
* **Bézout Multiplier Inverse (`theorem_multiplier_inverse`, `lemma_mul_inverse_cancel`)**:
  For $M = \text{0xBF58476D1CE4E5B9}$ (odd, coprime to $2^{64}$), there exists an exact modular inverse $M^{-1} = \text{0x96DE1B173F119089}$ such that:
  $$(M \cdot M^{-1}) \equiv 1 \pmod{2^{64}}$$
  $$(X \cdot M \cdot M^{-1}) \equiv X \pmod{2^{64}}$$
* **Cyclic Rotation Cancellation (`lemma_rot_cancel`)**:
  $$\forall x \in \mathbb{U}_{64}, \quad \text{rol23}(\text{ror23}(x)) \equiv x$$

### 10.2 Bijectivity & Collision Freedom
1. **Roundtrip Invertibility Theorem (`theorem_key_step_invertible`)**:
   $$\forall k, \Delta \in \mathbb{U}_{64}, \quad \text{invert\_key\_step}(\text{advance\_key\_step}(k, \Delta), \Delta) \equiv k$$
   *Proves*: With known execution transition $\Delta$, the state evolution is unconditionally reversible and exact.

2. **Strict Injective / Collision-Free Guarantee (`theorem_key_step_injective`)**:
   $$\forall k_1, k_2, \Delta \in \mathbb{U}_{64}, \quad k_1 \neq k_2 \implies \text{advance\_key\_step}(k_1, \Delta) \neq \text{advance\_key\_step}(k_2, \Delta)$$
   *Proves*: Different execution keys cannot collide into the same state after any step. The key space cardinality $|S| = 2^{64}$ is perfectly preserved.

3. **Odd Multiplier Coprimality (`theorem_odd_multiplier`)**:
   $$\forall \text{mixed} \in \mathbb{U}_{64}, \quad (\text{ensure\_odd}(\text{mixed})) \equiv 1 \pmod 2 \implies \gcd(\text{ensure\_odd}(\text{mixed}), 2^{64}) = 1$$
   *Proves*: Linear congruential polynomial generators in `poly_multiplier_of_seed` are guaranteed permutations over $\mathbb{Z}_{2^{64}}$.

---

## 11. Formally Verified Control Flow Flattening (CFF) & Opaque Predicates (`fstar/Cff_Verified.fst`)

In control flow obfuscation, ASGARD-5877 flattens control flow graphs into centralized dispatcher state ladders and inserts opaque predicates to defeat symbolic execution and decompiler CFG recovery.
A critical soundness requirement is that the dispatcher must faithfully preserve original CFG edge semantics and that opaque predicate traps must never be triggered on valid execution paths.

Module [`fstar/Cff_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Cff_Verified.fst) formally proves:

### 11.1 Opaque Parity Invariant
* **Parity Annihilation (`theorem_opaque_parity_is_zero`)**:
  $$\forall x \in \mathbb{U}_{64}, \quad (x \mathbin{\&} (x + 1)) \mathbin{\&} 1 \equiv 0$$
  *Proof*: For any 64-bit integer $x$, the least significant bit $\text{lsb}(x) \neq \text{lsb}(x + 1)$. Therefore $x \mathbin{\&} (x + 1)$ has a 0 in bit 0, and further masking with 1 yields strictly 0.
  *Soundness Guarantee*: In `Cff.inject_opaque_predicate`, the conditional branch `jne trap_block` is mathematically unreachable; execution unconditionally proceeds along the valid target edge.

### 11.2 Dispatcher Soundness & Step Bisimulation
1. **Dispatcher Target Soundness (`theorem_dispatch_finds_target`)**:
   $$\forall \text{ladder}, \text{entry}, \quad (\text{distinct\_states}(\text{ladder}) \land \text{entry} \in \text{ladder}) \implies \text{dispatch}(\text{ladder}, \text{entry}.\text{state}) = \text{Some } \text{entry}.\text{target}$$
   *Proves*: If all state keys in the ladder are distinct, looking up any valid entry's key yields its exact target block without misdirection.

2. **Trap Freedom on Reachable States (`theorem_dispatch_reachable_not_none`)**:
   $$\forall \text{ladder}, \text{entry}, \quad (\text{distinct\_states}(\text{ladder}) \land \text{entry} \in \text{ladder}) \implies \text{dispatch}(\text{ladder}, \text{entry}.\text{state}) \neq \text{None}$$
   *Proves*: The dispatcher never falls through to the terminal trap block on any valid CFG transition.

3. **CFG Step Bisimulation / Congruence (`theorem_cff_step_congruence`)**:
   For any CFG with direct edge $B_{\text{cur}} \to B_{\text{next}}$, state mapping $\sigma(B_{\text{next}}) = s$, and ladder containing $(s, B_{\text{next}})$:
   $$\text{cff\_step}(\text{edges}, \text{ladder}, \sigma, B_{\text{cur}}) = \text{direct\_step}(\text{edges}, B_{\text{cur}})$$
   *Proves*: Flattening through the dispatcher state machine preserves exact execution trace semantics.

---

## 12. Formally Verified Instruction Lifter & Simulation Equivalence (`fstar/Lifter_Verified.fst`)

The instruction lifter frontend translates architectural x86_64 instructions into VM-IR instructions. Any semantic discrepancy or register clobbering across lowering corrupts application logic.

Module [`fstar/Lifter_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Lifter_Verified.fst) formally specifies the architectural x86_64 operational semantics, the VM-IR execution semantics, and proves strict forward simulation:

### 12.1 Primitive ALU & Unary Equivalence
* **ALU Equivalence (`theorem_lift_alu_equiv`)**:
  $$\forall op \in \{\text{Add}, \text{Sub}, \text{Xor}, \text{And}, \text{Or}, \text{Shl}, \text{Shr}, \text{Rol}, \text{Ror}\}, \quad \text{step}_{\text{vm}}^*(\text{lift}(\text{Arch\_Alu } op \; dst \; src), \sigma) \sim_{\text{arch}} \text{step}_{\text{arch}}(\text{Arch\_Alu } op \; dst \; src, \sigma)$$
* **Unary Equivalence (`theorem_lift_unary_equiv`)**:
  $$\forall op \in \{\text{Inc}, \text{Dec}, \text{Not}, \text{Neg}\}, \quad \text{step}_{\text{vm}}^*(\text{lift}(\text{Arch\_Unary } op \; dst), \sigma) \sim_{\text{arch}} \text{step}_{\text{arch}}(\text{Arch\_Unary } op \; dst, \sigma)$$
* **Flag Predicates (`theorem_lift_cmp_equiv`, `theorem_lift_test_equiv`)**:
  Formally proves that VM-IR comparison and test lowering compute exact arithmetic borrow (`cf`), zero (`zf`), sign (`sf`), and signed overflow (`of`).
* **Conditional Movement (`theorem_lift_cmov_equiv`)**:
  Lowering `Cmov cc dst src` conditionally updates `dst` if and only if the architectural condition code evaluates to true on current flags.

### 12.2 Composite Lowering Soundness
1. **Exchange Invariance (`theorem_lift_xchg_equiv`)**:
   Lowering `xchg r1, r2` via `VTMP0` scratch register swaps values with zero loss:
   $$\sigma' = \text{step}_{\text{vm}}^*(\text{lift}(\text{Arch\_Xchg } r_1 \; r_2), \sigma) \implies \sigma'(r_1) = \sigma(r_2) \land \sigma'(r_2) = \sigma(r_1)$$

2. **Atomic Fetch-and-Add (`theorem_lift_xadd_equiv`)**:
   Lowering `xadd dst, src` correctly handles both distinct registers ($dst \neq src$) and aliased self-addition ($dst = src$):
   $$\sigma'(dst) = \sigma(dst) + \sigma(src) \land (dst \neq src \implies \sigma'(src) = \sigma(dst))$$

3. **Bitwise AND-NOT (`theorem_lift_andn_equiv`)**:
   Lowering BMI instruction `andn dst, s1, s2` via temporary inversion in `VTMP1` guarantees:
   $$\sigma'(dst) = (\sim \sigma(s_1)) \mathbin{\&} \text{eval}(s_2, \sigma)$$

### 12.3 Complete Simulation Soundness
* **Lifter Simulation Theorem (`theorem_lifter_soundness`)**:
  For ANY valid architectural instruction $I_{\text{arch}}$, the lifted sequence $L(I_{\text{arch}})$ preserves exact architectural machine state modulo internal VM temporary registers:
  $$\forall \sigma, \quad \text{step}_{\text{vm}}^*(L(I_{\text{arch}}), \sigma) \sim_{\text{arch}} \text{step}_{\text{arch}}(I_{\text{arch}}, \sigma)$$

---

## 13. Formally Verified Multi-VM Invertible Affine Bridge (`fstar/Bridge_Verified.fst`)

In ASGARD-5877, complex functions are partitioned across heterogeneous virtual machines (Native-VM and Stack-VM). Crossing VM boundaries requires morphing register context through an invertible affine transformation masked by a cumulative execution trace digest:
$$V_{\text{dst}} = (M_{\text{fwd}} \cdot V_{\text{src}}) \oplus \text{TraceDigest}$$

Module [`fstar/Bridge_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Bridge_Verified.fst) formally proves:

### 13.1 Quadratic Newton-Raphson Inversion
* **Hensel Lifting Error Contraction (`lemma_nr_formula`)**:
  $$\forall y \in \mathbb{U}_{64}, \quad 1 - y(2 - y) \equiv (1 - y)^2 \pmod{2^{64}}$$
  *Proves*: Each iteration of $x_{k+1} = x_k(2 - a x_k)$ doubles the precision of the modular inverse.
* **Constant Multiplier Inversion (`theorem_mod_inv_odd_constant`)**:
  Formally proves $a \cdot \text{mod\_inv\_64}(a) \equiv 1 \pmod{2^{64}}$ for the core constants (SplitMix64 and the Golden Ratio constant $\phi = \text{0x9E3779B97F4A7C15}$).

### 13.2 Trace Digest & Affine Morphing Bijectivity
1. **Trace Digest Invertibility (`theorem_trace_digest_invertible`)**:
   $$\forall \text{prev}, \text{op}, \text{vip}, \quad \text{invert\_trace\_digest}(\text{update\_trace\_digest}(\text{prev}, \text{op}, \text{vip}), \text{op}, \text{vip}) \equiv \text{prev}$$
   *Proves*: The execution digest evolution $K_{t+1} = \text{ROL13}(K_t) \oplus (\text{Op} + \text{VIP} \cdot \phi)$ is strictly bijective and reversible given block metadata.

2. **Channel Masking Involution (`theorem_apply_mask_involution`)**:
   $$\forall V \in \mathbb{U}_{64}^4, D \in \mathbb{U}_{64}, \quad \text{apply\_mask}(\text{apply\_mask}(V, D), D) \equiv V$$

3. **End-to-End Affine Bridge Roundtrip (`theorem_affine_bridge_roundtrip`)**:
   For any invertible matrix pair $(M_{\text{fwd}}, M_{\text{inv}})$ where $M_{\text{inv}} M_{\text{fwd}} = I$:
   $$\forall V, D, \quad \text{inverse\_morph}(M_{\text{inv}}, \text{forward\_morph}(M_{\text{fwd}}, V, D), D) \equiv V$$
   *Proves*: State transferred across VMs via the affine bridge suffers zero distortion or data loss.

---

## 14. Formally Verified Stack-VM Superoperator Fusion Pass (`fstar/Superop_Verified.fst`)

In Stack-VM virtualization, Phase 2a fuses recurring multi-dispatch bytecode sequences into specialized superoperators (`AddImmImm`, `SubImmImm`, `AddRegImm`, `SetRegImm`, `AddImm`, `SubImm`).

Module [`fstar/Superop_Verified.fst`](file:///Volumes/External/Code/ASGARD-5877/fstar/Superop_Verified.fst) formally proves:

### 14.1 Stack Delta Invariance
* **Delta Preservation Theorems (`theorem_delta_add_imm_imm` .. `theorem_delta_sub_imm`)**:
  - $\Delta([\text{PushImm } a; \text{PushImm } b; \text{Add}]) = \Delta([\text{AddImmImm}(a, b)]) = +1$
  - $\Delta([\text{PushImm } a; \text{PushImm } b; \text{Sub}]) = \Delta([\text{SubImmImm}(a, b)]) = +1$
  - $\Delta([\text{PushReg } r; \text{PushImm } c; \text{Add}]) = \Delta([\text{AddRegImm}(r, c)]) = +1$
  - $\Delta([\text{PushImm } c; \text{PopReg } r]) = \Delta([\text{SetRegImm}(r, c)]) = 0$
  - $\Delta([\text{PushImm } c; \text{Add}]) = \Delta([\text{AddImm } c]) = 0$
  - $\Delta([\text{PushImm } c; \text{Sub}]) = \Delta([\text{SubImm } c]) = 0$

### 14.2 Trace Equivalence & Flag Preservation
* **Soundness Theorems (`theorem_eval_equiv_add_imm_imm` .. `theorem_eval_equiv_sub_imm`)**:
  For all 6 fused patterns, the fused superoperator produces the exact same stack state, register file, and CPU condition flags (`cf`, `zf`, `sf`, `of`) as the original sequence:
  $$\forall \sigma, \quad \text{eval\_trace}(\sigma, \text{fused}) \equiv \text{eval\_trace}(\sigma, \text{unfused})$$

---

## 15. How to Run the Formal Proofs & Codegen

### Prerequisites
* `fstar.exe` 2026.08.23 (installed at `/opt/homebrew/bin/fstar.exe`)
* `z3` 5.0.0 (installed at `/opt/homebrew/bin/z3`)

### Verification Commands
To verify the complete formal specifications with 100% conditions discharged:
```bash
cd fstar

# Verify all 10 modules sequentially
for f in \
  Mba_Verified.fst \
  Flags_Verified.fst \
  Rns_Verified.fst \
  Stack_Balance_Verified.fst \
  Codec_Verified.fst \
  Poly_Verified.fst \
  Rolling_Key_Verified.fst \
  Cff_Verified.fst \
  Lifter_Verified.fst \
  Bridge_Verified.fst \
  Superop_Verified.fst; do
  fstar.exe \
    --include "/opt/homebrew/opt/fstar/fstar/lib/fstar" \
    --cache_checked_modules \
    --cache_dir . \
    "$f"
done
```

**Expected Output:**
```text
Verified module: Mba_Verified
All verification conditions discharged successfully
Verified module: Flags_Verified
All verification conditions discharged successfully
Verified module: Rns_Verified
All verification conditions discharged successfully
Verified module: Stack_Balance_Verified
All verification conditions discharged successfully
Verified module: Codec_Verified
All verification conditions discharged successfully
Verified module: Poly_Verified
All verification conditions discharged successfully
Verified module: Rolling_Key_Verified
All verification conditions discharged successfully
Verified module: Cff_Verified
All verification conditions discharged successfully
Verified module: Lifter_Verified
All verification conditions discharged successfully
Verified module: Bridge_Verified
All verification conditions discharged successfully
Verified module: Superop_Verified
All verification conditions discharged successfully
```

### Extraction to OCaml
To extract the verified code to OCaml:
```bash
cd fstar
for f in \
  Mba_Verified \
  Flags_Verified \
  Rns_Verified \
  Stack_Balance_Verified \
  Codec_Verified \
  Poly_Verified \
  Rolling_Key_Verified \
  Cff_Verified \
  Lifter_Verified \
  Bridge_Verified \
  Superop_Verified; do
  fstar.exe \
    --include "/opt/homebrew/opt/fstar/fstar/lib/fstar" \
    --codegen OCaml \
    --extract "$f" \
    --cache_checked_modules \
    --cache_dir . \
    --odir . \
    "$f.fst"
done
```

The resulting `.ml` files in [`fstar/`](file:///Volumes/External/Code/ASGARD-5877/fstar/) contain pure OCaml code with all proofs erased.





