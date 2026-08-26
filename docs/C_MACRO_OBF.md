# C/C++ Macro-Based Source Code Obfuscator

This document details the **C/C++ Preprocessor Macro Obfuscation Engine (`lib/c_macro_obf/`)** and `random_visa c-obf` CLI tool in ASGARD-5877.

---

## 1. Overview & Architecture

While bytecode virtualization protects compiled functions, many proprietary algorithms, licensing checks, cryptography keys, and string tables must be compiled natively. 

The **C Macro Obfuscator** provides compile-time and source-level protection by transforming standard C/C++ sources into hardened code leveraging:
1. **Dynamic Stack-Allocated String Encryption** (`__builtin_alloca` / Compound Literals).
2. **Mixed Boolean-Arithmetic (MBA) Preprocessor Macros** (Zhou / Eyrolles Identities).
3. **Compile-Time Constant Blinding**.
4. **Number-Theoretic Invariant Opaque Predicates**.
5. **Macro-based Control-Flow Flattening (CFF) DSL**.

```
┌────────────────────────────┐
│      Original C Source     │ (main.c: strings, math, constants)
└──────────────┬─────────────┘
               │
               ▼ (random_visa c-obf)
┌──────────────┴─────────────┬──────────────────────────────┐
│  Obfuscated Source (.c)    │  Polymorphic Header (.h)     │
│  - Replaces "..." with     │  - asgard_obf.h              │
│    ASG_STR(...)            │  - Stack decryptor           │
│  - Blinded constants       │  - MBA macro expansions      │
│  - Opaque predicates       │  - Opaque predicate macros   │
└──────────────┬─────────────┴──────────────────────────────┘
               │
               ▼ (Standard GCC / Clang / MSVC)
┌────────────────────────────┐
│   Hardened Native Binary   │ (Zero plaintext strings, non-linear math)
└────────────────────────────┘
```

---

## 2. Protection Primitives

### 2.1 Stack-Allocated String Encryption (`ASG_STR`)
Instead of storing plaintext strings in `.rdata` / `.rodata` where `strings` or IDA Pro immediately locates them:
* Strings are stored as XOR-encrypted array literals with a randomized rolling keystream.
* Upon execution, memory is allocated **strictly on the stack** (`__builtin_alloca`), decrypted in a single unrolled pass, used, and automatically deallocated when the stack frame returns:

```c
// Original:
const char* key = "SECRET_LICENSE_KEY";

// Obfuscated:
const char* key = ASG_STR(((const uint8_t[]){ 0x31, 0x7F, 0x8F, 0x39, ... }), 18, 0x39D2F867U);
```

### 2.2 Mixed Boolean-Arithmetic (MBA) Macros
Replaces linear arithmetic with non-linear bitwise polynomials:
* Addition: `#define ASG_MBA_ADD(a, b) (((a) ^ (b)) + 2 * ((a) & (b)))`
* Subtraction: `#define ASG_MBA_SUB(a, b) (((a) ^ (b)) - 2 * ((~(a)) & (b)))`
* XOR: `#define ASG_MBA_XOR(a, b) (((a) | (b)) - ((a) & (b)))`
* AND: `#define ASG_MBA_AND(a, b) (((a) + (b)) - ((a) | (b)))`
* OR: `#define ASG_MBA_OR(a, b) (((a) ^ (b)) + ((a) & (b)))`

### 2.3 Constant Blinding
Splits 64-bit integer literals into algebraic identities:
$$\text{val} = ((c_1 \oplus k_1) + k_2) - k_2$$
`#define ASG_BLIND_I64(c1, k1, k2) ((int64_t)((((uint64_t)(c1) ^ (uint64_t)(k1)) + (uint64_t)(k2)) - (uint64_t)(k2)))`

### 2.4 Invariant Opaque Predicates
Number-theoretic truths injected into conditionals:
* `ASG_OPAQUE_TRUE(x)`: `((((uint64_t)(x)) * (((uint64_t)(x)) + 1ULL)) % 2ULL) == 0ULL`
* `ASG_OPAQUE_FALSE(x)`: `((((uint64_t)(x)) * (((uint64_t)(x)) + 1ULL)) % 2ULL) != 0ULL`

### 2.5 Control-Flow Flattening (CFF) Macro DSL
Allows developers to manually flatten state machines without compiler plugins:
```c
ASG_CFF_BEGIN(state, 1);
    ASG_CFF_STATE(1)
        do_step_1();
        ASG_CFF_NEXT(state, 2);
    ASG_CFF_STATE(2)
        do_step_2();
        ASG_CFF_EXIT(state);
ASG_CFF_END();
```

---

## 3. CLI Usage Guide (`random_visa c-obf`)

```bash
# Obfuscate a C source file and generate companion header
random_visa c-obf \
  -i examples/demo_c_app.c \
  -o ./protected_c/main.c \
  --header ./protected_c/asgard_obf.h \
  --seed 42 \
  --compile true
```
