# ASGARD-5877 Differential Fuzzing Guide

The Differential Fuzzer is an automated verification harness that validates **semantic equivalence** between the original native code and the code processed by the full ASGARD protection pipeline (C Macro Obfuscation + MBA + Control Flow Flattening + Native VM Virtualization).

---

## 1. Primary Goal: What Does the Fuzzer Look For?

The fundamental invariant of differential testing is:
$$\forall x: \quad f_{\text{native}}(x) \equiv f_{\text{protected\_vm}}(x)$$

The fuzzer feeds identical pseudorandom and mutated inputs $x$ into both implementations and flags any of the three critical failure states:

1. **Divergence (Value Mismatch)**: $f_{\text{native}}(x) \neq f_{\text{protected\_vm}}(x)$ — both implementations exit cleanly, but the VM produces an incorrect return value or state.
2. **Crash / Fault**: The native code executes cleanly, while the virtualized code crashes with `SIGSEGV`, `SIGBUS`, `SIGILL`, or enters an infinite loop.
3. **Compilation / Transformation Failure**: The obfuscator emits C++ source code that fails to compile under `clang++` or violates target language type constraints.

---

## 2. Specific Bug Classes Detected by the Fuzzer

### A. Register Preservation & Bit-Width Truncation
* **Scenario**: SIB indirect memory addressing of the form `[base + index * scale]`.
* **Root Cause Found**: During lowering of `movzx r9d, byte ptr [rsi + rax]`, the scratch address register inherited the 32-bit width of `r9d`. The 64-bit base address `rsi + rax` was truncated to 32 bits, causing an immediate segmentation fault (`SIGSEGV`).
* **Fix**: In `lib/native_vm/vm_transform.ml`, memory scratch registers are strictly enforced to `Register.B64`.

### B. Type Errors in MBA Obfuscation (Floating-Point Taint)
* **Scenario**: Source code performing floating-point addition: `double q2 = q + p.d;`.
* **Root Cause Found**: The arithmetic rewriter `c_arith_rewriter.ml` converted binary `+` into an integer MBA macro: `ASG_MBA_ADD(q, p.d)`. The macro used bitwise operators (`^`, `&`, `|`), which are invalid for floating-point types in C++.
* **Fix**: Introduced static FP-taint analysis (propagating float/double properties through literals, casts, structure definitions, and auto chains) to exclude floating-point types from integer MBA transformations.

### C. CPU Flags Clobbering in CFF and Opaque Predicates
* **Scenario**: A comparison instruction `cmp rax, rbx` sets CPU condition flags `ZF/CF/SF/OF`. The Control-Flow Flattening (CFF) dispatcher or opaque predicate inserts auxiliary arithmetic before a conditional branch (`jcc`).
* **Root Cause Found**: When the dispatcher overwrote flags during intermediate operations without saving them via `Get_flags` / `Set_flags`, conditional branches took the wrong path, causing semantic divergence (`DIVERGENCE FOUND: Golden != Protected`).

### D. Dynamic Decryption Key Desynchronization (Rolling Key Desync)
* **Scenario**: In-memory bytecode is encrypted with a positional dynamic key: `k_dyn = k_pos ^ ctx.running_key`. The key evolves with every `FETCH_NEXT()` invocation.
* **Root Cause Found**: In loops (back-edges) or conditional branches (`H_JCC`), failure to re-anchor the key to the target block's base offset (`reanchor_running_key`) caused the next loop iteration to decrypt instructions as pseudo-random junk.
* **Impact**: Invalid opcodes hit trap handlers (`H_DECOY_*`), poisoned register masks (`ctx.reg_mask`), and subsequent `LOAD/STORE` operations crashed on invalid addresses (`0x5877...`).

### E. False Positives in Anti-Tamper & Anti-Debug (Scheduler Preemption)
* **Scenario**: Timing checks in `evaluate_emulation_differential` and introspective SMC probes via `execute_introspective_smc_probe`.
* **Root Cause Found**: Under heavy fuzzing load, OS thread preemption caused 64-nop timing measurements (`cntvct_el0`) to spike from 10 ns to 4 ms. The runtime falsely identified this as debugger single-stepping and poisoned registers with penalty constants (`0x5877AABBCCDDEEFFULL`).
* **Fix**: Transitioned to multi-trial measurements (taking the minimum of 5 runs to eliminate context-switch outliers) and measured paired timers (`cntvct` and `mach_absolute_time`) over identical intervals.

### F. Subtle Architectural Edge Cases
* Shift counts of 0, 31, 32, 63, and 64 bits (undefined behavior in C++ versus x86/ARM hardware counter masking `& 31` / `& 63`).
* Float-to-integer conversion saturation in `cvttsd2si`: converting NaN, Inf, or out-of-bounds doubles to `int64_t` must produce the exact architecture-defined result (`0x8000000000000000ULL`).
* Division by zero and signed edge cases around `INT32_MIN` (-2147483648).

---

## 3. Architecture: How Differential Fuzzing Operates

ASGARD provides two complementary fuzzing harnesses:

```
                    ┌──────────────────────────────────────────┐
                    │  proj_src/compute_core.cpp  (kernel)     │
                    │  proj_src/main_driver.cpp   (--fuzz main)│
                    └───────────────┬──────────────────────────┘
              ┌─────────────────────┴──────────────────────┐
     native clang++ (golden)                    random_visa project
     markers = inert no-ops                     macro-obf + CFF + MBA + VM
              │                                              │
   ┌──────────┴──────────┐                       ┌───────────┴───────────┐
   │ Option 2: Python    │                       │ Option 1: libFuzzer   │
   │ run_diff_project.py │                       │ run_libfuzzer.sh      │
   │ Out-of-process      │                       │ In-process            │
   │ Full CLI validation │                       │ Coverage-guided       │
   │ Speed: ~100-500/s   │                       │ Speed: 5000-8000/s    │
   └─────────────────────┘                       └───────────────────────┘
```

### Option 1: libFuzzer (`run_libfuzzer.sh`)
* **Mechanism**: Compiles both golden and protected implementations into a **single unified process**. Inputs are generated and mutated by LLVM's libFuzzer engine.
* **Coverage-Guided**: LLVM instruments basic blocks. When a mutation triggers a new control-flow branch (in the native core or inside the VM interpreter loop), the input is preserved in `corpus/`.
* **High Throughput**: 5,000 to 8,000 executions per second (millions of trials in under 5 minutes).
* **Automated Minimization**: Divergences or faults invoke `__builtin_trap()`, prompting libFuzzer to persist the minimal crash reproduction input to `artifacts/crash-*`.

### Option 2: Python Project Runner (`run_diff_project.py`)
* **Mechanism**: Compiles two distinct binaries (`app_native` and `protected_proj`) via the `random_visa project` command-line interface.
* **Full Pipeline Verification**: Validates not only instruction virtualization, but also Makefile generation, header dependencies, symbol stripping, and linking.
* **Granular Diagnostics**: On divergence, prints a structured payload dump, comparing golden versus VM values along with an XOR bitmask of differences.

---

## 4. Usage Instructions

### Quick libFuzzer Run (60 seconds):
```bash
./examples/diff_fuzz/run_libfuzzer.sh
```

### Extended Overnight Fuzzing Campaign:
```bash
# By duration (e.g. 10 minutes)
ASG_FUZZ_SECONDS=600 ./examples/diff_fuzz/run_libfuzzer.sh

# Or by iteration count (e.g. 5 million executions)
ASG_FUZZ_RUNS=5000000 ./examples/diff_fuzz/run_libfuzzer.sh
```

### Reproducing a Specific Crash Artifact:
```bash
./examples/diff_fuzz/build/diff_fuzzer ./examples/diff_fuzz/artifacts/crash-<hash>
```

### Running via Makefile:
```bash
make diff-fuzz-libfuzzer    # Option 1: libFuzzer in-process
make diff-fuzz-project      # Option 2: Python runner (10,000 vectors)
```
