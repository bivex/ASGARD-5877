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
│  - Refinement types (forall env. eval e' == eval e)    │
│  - Structural induction on AST depth                   │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼ (fstar.exe check + Z3 Proofs)
┌────────────────────────────────────────────────────────┐
│             Automated SMT Solver (Z3 5.0.0)            │
│  - Discharges all 64-bit algebraic proof obligations   │
│  - Verification time: < 0.5 seconds                   │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼ (fstar.exe --codegen OCaml)
┌────────────────────────────────────────────────────────┐
│          Extracted OCaml (fstar/Mba_Verified.ml)       │
│  - Proof erasure: all lemmas and ghost types stripped │
│  - Pure, high-performance OCaml AST rewriter          │
└───────────────────────────┬────────────────────────────┘
                            │
                            ▼ (Dune Build)
┌────────────────────────────────────────────────────────┐
│     Native VM Protector Library (lib/mba_engine/)      │
└────────────────────────────────────────────────────────┘
```

---

## 2. Formally Proven MBA Identities (`fstar/Mba_Verified.fst`)

All MBA identities are verified over 64-bit modular arithmetic (`uint_t 64`) using bit-extensionality:

$$\forall a, b \in \mathbb{U}_{64}, \quad (\forall i \in [0, 63], \; \text{bit}_i(LHS) = \text{bit}_i(RHS)) \implies LHS = RHS$$

### 2.1 The Four F\* Core Theorems

1. **XOR via OR and AND (`mba_xor_eq`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \oplus b \equiv (a \lor b) \oplus (a \land b)$$
   *F\* Definition*:
   ```fstar
   val mba_xor_eq : a:u64 -> b:u64 ->
     Lemma (logxor #w a b == logxor #w (logor #w a b) (logand #w a b))
   ```

2. **AND via OR and XOR (`mba_and_eq`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \land b \equiv (a \lor b) \oplus (a \oplus b)$$
   *F\* Definition*:
   ```fstar
   val mba_and_eq : a:u64 -> b:u64 ->
     Lemma (logand #w a b == logxor #w (logor #w a b) (logxor #w a b))
   ```

3. **OR via XOR and AND (`mba_or_eq`)**:
   $$\forall a, b \in \mathbb{U}_{64}, \quad a \lor b \equiv (a \oplus b) \oplus (a \land b)$$
   *F\* Definition*:
   ```fstar
   val mba_or_eq : a:u64 -> b:u64 ->
     Lemma (logor #w a b == logxor #w (logxor #w a b) (logand #w a b))
   ```

4. **Bitwise NOT via XOR (`mba_not_eq`)**:
   $$\forall a \in \mathbb{U}_{64}, \quad \sim a \equiv a \oplus \text{0xFFFFFFFFFFFFFFFF}$$
   *F\* Definition*:
   ```fstar
   val mba_not_eq : a:u64 ->
     Lemma (lognot #w a == logxor #w a (ones w))
   ```

---

## 3. Structural Induction Theorem: Soundness of Rewrite

The main theorem proven in F\* establishes that applying the rewrite rules to any AST expression $e$ at arbitrary recursion depth $d$ preserves evaluation under all variable assignments $\text{env}$:

```fstar
val rewrite_sound : depth:nat -> e:expr ->
  Lemma (forall (env:env_t). eval env (rewrite depth e) == eval env e)
```

### Proof Strategy
* **Base case ($d = 0$)**: $\text{rewrite}(0, e) = e \implies \text{eval}(env, e) = \text{eval}(env, e)$ (trivial).
* **Inductive step ($d = k + 1$)**: For each binary constructor (`Xor`, `And`, `Or`, `Not`), we invoke the induction hypothesis on child nodes and apply the corresponding verified algebraic lemma. Z3 closes the proof obligation automatically.

---

## 4. How to Run the Formal Proofs

### Prerequisites
* `fstar.exe` (installed at `/opt/homebrew/bin/fstar.exe`)
* `z3` (installed at `/opt/homebrew/bin/z3`)

### Verification Command
To verify the complete formal specification:
```bash
cd fstar
fstar.exe \
  --include "/opt/homebrew/opt/fstar/fstar/lib/fstar" \
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
# Step 1: Check and generate .checked cache
fstar.exe \
  --include "/opt/homebrew/opt/fstar/fstar/lib/fstar" \
  --cache_checked_modules \
  --cache_dir . \
  Mba_Verified.fst

# Step 2: Codegen clean OCaml
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
