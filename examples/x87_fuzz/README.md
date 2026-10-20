# ASGARD-5877 x87 FPU Differential Fuzzer

Differential fuzzing framework for legacy x87 FPU instructions, comparing native hardware execution against ASGARD's virtualized Direct-Threaded VM (`vanguard_threaded_vm`) and a high-precision IEEE-754 shadow oracle.

```
                   ┌──────────────────────────────────────────┐
                   │    X87Generator (Constraint-Based)       │
                   │  - Stack Ring Tracker (st(0)..st(7))     │
                   │  - Float/Int Edge & Special Vector Pool  │
                   └──────────────────┬───────────────────────┘
                                      │
                         Emits valid x87 assembly (.s)
                                      │
               ┌──────────────────────┼──────────────────────┐
               ▼                      ▼                      ▼
      Hardware Reference      ASGARD VM Pipeline       Python Oracle
     (Rosetta x86-64 /       (random_visa protect    (IEEE-754 Shadow
      Native Intel x86)      --engine=threaded)       Stack Model)
               │                      │                      │
               ▼                      ▼                      ▼
         FSW + RAX + st()       FSW + RAX + st()       FSW + RAX + st()
               │                      │                      │
               └──────────────────────┼──────────────────────┘
                                      ▼
                        Differential Verification
                        (Exact FSW & Epsilon Floats)
```

## Features & Instruction Coverage

- **Stack Operations & Movement**:
  - `fld`, `fst`, `fstp` (memory qword/dword, `st(i)`)
  - `fild`, `fist`, `fistp` (memory integer conversions)
- **Built-in Constants**:
  - `fld1` (+1.0), `fldz` (+0.0), `fldpi` (π), `fldl2e` (log2(e)), `fldl2t` (log2(10)), `fldlg2` (log10(2)), `fldln2` (ln(2))
- **Binary Arithmetic**:
  - `fadd`, `faddp`, `fsub`, `fsubp`, `fsubr`, `fsubrp`
  - `fmul`, `fmulp`, `fdiv`, `fdivp`, `fdivr`, `fdivrp`
- **Unary & Math**:
  - `fchs` (negate), `fabs` (absolute value), `fsqrt` (square root)
- **Transcendentals**:
  - `fsin` (sine), `fcos` (cosine), `f2xm1` (2^x - 1), `fyl2x` (y * log2(x))
- **Comparisons & Condition Codes**:
  - `fcomi`, `fcomip` (updates EFLAGS CF, ZF, PF)
  - `fcom`, `fcomp`, `fcompp` (updates FSW condition codes C0..C3)
- **Status Word**:
  - `fstsw ax`, `fnstsw ax` (captures stack TOP and exception flags)

## Usage

### 1. Full Differential Campaign (Hardware vs ASGARD VM)

```bash
# 50 test cases with differential verification
python3 examples/x87_fuzz/fuzz_x87.py -n 50 --mode=diff

# Deterministic campaign with specific seed and continuing on divergence
python3 examples/x87_fuzz/fuzz_x87.py -n 100 --seed 58779292 --mode=diff --keep-going
```

### 2. High-Speed Oracle Campaign (10,000+ tests/sec)

Stress-tests generator constraints, state permutations, and IEEE-754 properties without compiler overhead:

```bash
python3 examples/x87_fuzz/fuzz_x87.py -n 10000 --mode=oracle --seed 42
```

### 3. Hardware-Only Campaign (Rosetta x86-64)

Validates test cases on actual hardware or Rosetta translation:

```bash
python3 examples/x87_fuzz/fuzz_x87.py -n 50 --mode=rosetta
```

### 4. VM-Only Execution

Validates ASGARD virtualization pipeline and C++ threaded VM bytecode:

```bash
python3 examples/x87_fuzz/fuzz_x87.py -n 25 --mode=vm
```

## Reproduction & Triage

When a divergence or error is detected, the fuzzer automatically preserves the exact assembly file in `examples/x87_fuzz/artifacts/`:

```bash
# Inspect the failing case
cat examples/x87_fuzz/artifacts/case_7_58779292.s

# Replay through random_visa
dune exec -- random_visa protect -i examples/x87_fuzz/artifacts/case_7_58779292.s -o /tmp/repro --engine=threaded
```
