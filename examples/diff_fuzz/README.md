# ASGARD-5877 Differential Fuzzing

Full divergence coverage between native reference code and the ASGARD VM across two complementary harnesses sharing a common core (`proj_src/`).

For in-depth background on target bug classes, verification methodology, and fuzzer internals, see the [Differential Fuzzing Guide](../../docs/DIFFERENTIAL_FUZZING_GUIDE.md).

```
                    ┌──────────────────────────────────────────┐
                    │  proj_src/compute_core.cpp  (kernels)    │
                    │  proj_src/main_driver.cpp   (--fuzz main)│
                    └───────────────┬──────────────────────────┘
              ┌─────────────────────┴──────────────────────┐
     native clang++ (golden)                    random_visa project
     markers = inert no-ops                     macro-obf + CFF + MBA + VM
              │                                              │
   ┌──────────┴──────────┐                       ┌───────────┴───────────┐
   │ Option 2: Python    │                       │ Option 1: libFuzzer   │
   │ run_diff_project.py │                       │ run_libfuzzer.sh      │
   │ process-streaming   │                       │ in-process, coverage- │
   │ ~10^4 test vectors  │                       │ guided, ~10^5-10^6 ops│
   └─────────────────────┘                       └───────────────────────┘
```

## Workloads Under Test

`asgard_fuzz_compute` (ULTRA): Evaluates branch conditions, switch tables, integer arithmetic (add, sub, mul, xor, and, or, not, variable bitwise rotations, unsigned div/mod, arithmetic shifts), double-precision floating-point operations (mul, add, comparisons), conversions (`cvttsd2si`, `cvtsd2ss` double-to-float bit reinterpretations), and loops with data-dependent iteration bounds and internal branching.

`asgard_fuzz_mix` (VIRTUALIZE): A streaming hash over caller-supplied memory buffers, stressing memory loads outside the marked stack frame, loop back-edges, and internal loop control flow (stress-testing CFF flattening).

Boundary values exercised include: `INT32_MIN` / `INT32_MAX`, bit shifts by 0, 31, 32, 63, and 64, walking bit masks, `±0.0`, subnormals (`5e-324`), extreme magnitudes (`1e300` / `DBL_MAX` testing `cvttsd2si` saturation to `0x8000000000000000`), as well as empty and 64-byte binary payloads.

## Option 1: libFuzzer (In-Process, Coverage-Guided)

```bash
./examples/diff_fuzz/run_libfuzzer.sh                          # 60-second smoke campaign
ASG_FUZZ_SECONDS=600 ./examples/diff_fuzz/run_libfuzzer.sh      # 10-minute run
ASG_FUZZ_RUNS=5000000 ./examples/diff_fuzz/run_libfuzzer.sh     # 5 million iterations
ASG_FUZZ_ALLOW_NAN=1 ./examples/diff_fuzz/run_libfuzzer.sh      # Enable NaN/Inf parity testing
ASG_FUZZ_NO_CFF=1 ASG_FUZZ_NO_MBA=1 ./examples/diff_fuzz/run_libfuzzer.sh  # Isolate pure VM lift
```

Builds a unified binary combining three translation units: the golden native core (compiled with symbol renaming via `-D`), the virtualized translation unit (`vm_out/.asgard_build/compute_core_virtualized.cpp`), and the `LLVMFuzzerTestOneInput` harness. When divergence is detected, the driver emits a diagnostic input dump and invokes `__builtin_trap()`, prompting libFuzzer to save a repro crash artifact to `artifacts/`:

```bash
./build/diff_fuzzer -minimize_crash=1 -runs=100000 ./artifacts/crash-*
```

The dictionary `diff_fuzz.dict` (curated boundary constants, masks, and bit patterns from past fuzzing campaigns) is automatically passed via `-dict` to bias mutations toward edge conditions. The seed corpus in `corpus/` is populated automatically on startup.

## Option 2: Python Differential Runner (Full Pipeline)

```bash
python3 examples/diff_fuzz/run_diff_project.py -n 10000
python3 examples/diff_fuzz/run_diff_project.py -n 50000 --seed 5877 --keep-going
python3 examples/diff_fuzz/run_diff_project.py --skip-build     # Reuse previously compiled binaries
```

Builds `vm_out/app_native` (golden) and `vm_out/protected_proj` (`random_visa project -d proj_src --cff --mba`), streams test payloads through both processes in `--fuzz` mode, and prints tabular diagnostic dumps with XOR discrepancy bitmasks upon divergence.

## Makefile Targets

```bash
make diff-fuzz-libfuzzer    # Option 1: libFuzzer execution
make diff-fuzz-project      # Option 2: Python runner (N=10,000)
```

## Invariants and Constraints

- **Floating-Point Parity**: Both native golden and virtualized routines evaluate floating-point math against x86 baseline semantics: add and mul operations are kept isolated, and golden routines compile with `-ffp-contract=off` (preventing Apple Silicon / ARM64 hardware FMA contraction from triggering false-positive rounding mismatches).
- **Out-of-Range Casts**: `static_cast<int64_t>(double)` on out-of-range values is undefined behavior in abstract C++, but maps to deterministic `cvttsd2si` hardware saturation on both sides. NaN and Inf are filtered unless `ASG_FUZZ_ALLOW_NAN=1` is specified.
- **Engine Support**: `random_visa project` exercises the threaded VM engine. For Stack-VM or RD-JIT validation, use `examples/cpp_types_demo/diff_fuzz.py`.
- **Source Layout**: Functions under protection must be located directly in the compiled source file (scanned by the AST trampoline adapter), making `compute_core.cpp` the canonical source for both harnesses.

## File Directory Structure

```text
fuzz_types.h                Shared TestPayload struct definition (40-byte POD)
proj_src/compute_core.cpp   Marked computation kernels (canonical source)
proj_src/main_driver.cpp    Streaming protocol harness (--fuzz interface)
fuzz_driver.cpp             LLVMFuzzerTestOneInput driver with divergence reporter
run_libfuzzer.sh            Option 1 runner: compilation and libFuzzer harness
diff_fuzz.dict              Boundary dictionary loaded via libFuzzer -dict flag
run_diff_project.py         Option 2 runner: end-to-end Python pipeline runner
corpus/                     Seed corpus directory (generated automatically)
vm_out/, build/, artifacts/ Ephemeral build and crash reproduction artifacts
```
