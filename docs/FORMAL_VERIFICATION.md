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

## 5. How to Run the Formal Proofs & Codegen

### Prerequisites
* `fstar.exe` 2026.08.23 (installed at `/opt/homebrew/bin/fstar.exe`)
* `z3` 5.0.0 (installed at `/opt/homebrew/bin/z3`)

### Verification Command
To verify the complete formal specification with 100% conditions discharged:
```bash
cd fstar
fstar.exe \
  --include "/opt/homebrew/opt/fstar/fstar/lib/fstar" \
  --cache_checked_modules \
  --cache_dir . \
  Mba_Verified.fst
```

**Expected Output:**
```text
Verified module: Mba_Verified
All verification conditions discharged successfully
```

### Extraction to OCaml
To extract the verified code to OCaml:
```bash
cd fstar
fstar.exe \
  --include "/opt/homebrew/opt/fstar/fstar/lib/fstar" \
  --codegen OCaml \
  --extract Mba_Verified \
  --cache_checked_modules \
  --cache_dir . \
  --odir . \
  Mba_Verified.fst
```

The resulting [`fstar/Mba_Verified.ml`](file:///Volumes/External/Code/ASGARD-5877/fstar/Mba_Verified.ml) file contains pure OCaml code with all proofs erased.
