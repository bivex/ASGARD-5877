# tools/vm_fuzz_harness — Coverage-Guided Structure-Aware Stack-VM Fuzzer

Attacks the layer **underneath** the crypto barrier: VM handler semantics.
The tamper fuzzer proved ciphertext garbage is trapped by authentication;
this harness encrypts *fuzzer-chosen plaintext* under the real key schedule
(SipHash-1-2 entry key + fmix64 rolling stream), so `stack_vm_run` decrypts
it into **valid instruction streams** and dispatches real handlers.

## What it catches that ciphertext fuzzing cannot

- `h_div` / `h_idiv` by zero and `INT64_MIN` edge cases
- stack underflow in `h_add`/`h_sub`/`h_pop_reg` on crafted op sequences
- ctx slot OOB in `h_push_reg`/`h_pop_reg` with extreme `i16` operands
- shift handlers (`h_shl`/`h_shr`/`h_sar`) with counts > 63
- `JccRel`/`CMOV` flag-state desynchronization
- VSP whitening push/pop mask asymmetries

## Invariants (violation = VM bug → abort)

- `vm.vsp_idx <= 4096` (VSP pool bounds) after every run

## Build & Run

```bash
bash tools/vm_fuzz_harness/build.sh

# Coverage-guided (requires LLVM toolchain with libFuzzer, e.g. brew install llvm):
./tools/vm_fuzz_harness/vm_fuzz -max_len=512 -runs=100000

# Standalone random-mutation stress (works with plain Apple clang):
./tools/vm_fuzz_harness/vm_fuzz_standalone <iters> <max_len> <seed>
```

Seed key: `ASGARD_FUZZ_SEED` env (default `0x2ED2232624AED846`, the pinned
license-check build seed; must match the runtime header's key tables).

Verified on this machine: standalone 200,000 runs (max_len 1024) in 0.16 s
(~1.2M exec/s), 0 invariant violations, 0 crashes.
