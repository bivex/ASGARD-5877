# deobf_probe — Multi-Tier Deobfuscation & Topology Probe

Offline attack harness evaluating bytecode resilience and dispatch dispersion of protected builds, with no knowledge of internal pass seeds:

1. **Multi-Tier Deobfuscation Engine (`peephole_eval.py`)**:
   Models automated symbolic, SMT, and pattern deobfuscators (D810, Triton, angr, QBDL) across 3 reduction tiers:
   * **Tier 1 (Structural & Dead-Slot DCE)**: Universal stack identities (`Swap³`, `Dup·Swap²`, `Rot⁴`, `PushReg r; Dup; PopReg r`), plus $O(\log n)$ dead-slot analysis over per-slot interval event trees (soundly eliminating unread scratch writes across $10^7$ ops).
   * **Tier 2 (Semantic ALU Inverses, XOR & Zero-Knots)**: Algebraic ALU identities (two's complement negation, double negation, 5-NOR XOR circuit folding, canonical Nor-Nor knots, neutral identity cancellations).
   * **Tier 3 (Constant Folding, Ring Inverses & Superoperator Desugaring)**: Pure-constant binary operation folding over arbitrary-depth trees (`Add`, `Sub`, `Mul`, `Nor`, `Nand`), ring twist modular inverse detection ($k \cdot k^{-1} \equiv 1 \pmod{2^{64}}$), compound immediate superoperators (`AddImmImm`, `SubImmImm`, `PushImm_AddImm`), and polynomial zero branch deobfuscation ($(r_1 \cdot r_2 + r_3) - (r_1 \cdot r_2 + r_3) \equiv 0$).
2. **Dispatch Topology (`dispatch_topology.py`)**:
   * **Bytecode layer**: rebuilds basic block CFG from phase dumps, measuring CFF hub concentration and dispatcher in-degree.
   * **Machine-code layer**: disassembles `stack_vm_run` in the native binary, verifying true indirect branch dispersion (in-degree = 1 per branch site) and ensuring compilers (Clang/GCC) have not tail-merged distinct handler epilogues into a centralized trampoline.

`run_probe.sh SEED` protects `examples/license_check.c` twice (full config vs baseline), executes the protected binary under valid and invalid license keys, and measures the resilience across all intermediate and final phases.

---

## Findings & Resilience Evolution (2026-10-27)

### 1. Final Program Resilience: 0.0% Junk Recovery (16.5M Operations)
* **Baseline expansion**: +1,652× (10,086 lowered ops $\to$ **16,537,106 final ops**).
* **Junk recovered by attack**: **0 ops (0.0%)** across all 3 tiers combined.
* **Attack Breakdown on final phase `7-balance_(final)`**:
  * Tier 1 (Structural & Dead-Slot DCE): **0 reductions**
  * Tier 2 (Semantic ALU, XOR & Knots): **0 reductions**
  * Tier 3 (Constant Folding, Ring Twists & Superops): **0 reductions**

### 2. Intermediate Pipeline Hardening

| Phase | Description | Initial Removal | Post-Hardening Status | Hardening Mechanism |
|---|---|---|---|---|
| **`2-amplified`** | Bytecode Amplification | 66,736 ops (61.4%) | **0 ops (0.0%)** | Register-anchored Horner polynomial steps (`?anchor`), flag-neutral `Swap` permutations in ring twists |
| **`2a-multiplicity`** | Opcode Metamorphism | 11,542 ops (54.0%) | **0 ops (0.0%)** | Desugared `Swap`/`Dup`/`Rot` via scratch context registers, register-anchored split sums |
| **`2a-post-superop`** | Post-Superop Fusion | 41,869 ops (51.0%) | **0 ops (0.0%)** | Register-interleaved carry cascades, elimination of hardcoded mod-inverse pairs |
| **`2b-mba`** | MBA Constant Synthesis | 103,836 ops (71.8%) | **0 ops (0.0%)** | Def-use register-anchored constant leaves in E-graph trees (`lower_mba_to_stack ?anchor`), live-register L6 splits |
| **`3-cff`** | Virtual CFG Flattening | 107,174 ops (71.1%) | **844 ops (0.2%)** | Register-anchored polynomial zero branches (`vpc_slot`), streamlined direct `Cmp` |
| **`4-spaghetti`** | Spaghetti Block Splitting | 108,014 ops (71.1%) | **1,002 ops (0.2%)** | Runtime context-anchored polynomial zero jumps (`(r*r2+r3)-(r*r2+r3)==0`) |
| **`5-ghost`** | Ghost Stack Padding | 154,039 ops (18.7%) | **0 ops (0.0%)** | Purged dead unread `GhostImmStore`, register-anchored zero differences ($x + ((r+k)-r-k) == x$) |
| **`5b-avid`** | Avid Junk Operands | 13,230 ops | **0 ops (0.0%)** | Complete def-use anchor webbing, register-anchored subtraction deltas |
| **`6-feedback`** | Rolling Key Feedback | 0 ops | **0 ops (0.0%)** | 100% cryptographic bytecode coupling to live register execution |
| **`7-balance`** | Final Balance Pass | 284,026 ops (26.3%) | **0 ops (0.0%)** | Elimination of naked `AddImmImm`/`SubImmImm`, zero-reduction final program |

### 3. Machine Code & Dispatch Hardening
* **No Handler Pointer Leaks in `.rodata`**: The compiler's static 2,048-byte `raw_dispatch_table` pointer array in `__TEXT,__const` was eliminated. Dispatch table entries are initialized via direct per-slot XOR-masked assignments at runtime (`adrp/add` + `eor` + `str`), leaving **0 code pointers in read-only data**.
* **True Epilogue Dispersion**: Per-handler inline indirect branches (`asm volatile("br %0")` on AArch64 / `"jmp *%0"` on x86-64) with distinct compile-time slot masks prevent Clang/GCC from tail-merging epilogues into a shared trampoline. Confirmed via `dispatch_topology.py`: **257 distinct indirect branches, each with in-degree 1**.
* **Encrypted Anti-Debug Probes**: Stack-constructed XOR character arrays for `"/proc/self/status"` and `"TracerPid:"`, paired with dynamic polynomial derivation `(p_flag * 0x5877A55A1337ULL) | 1ULL`, eliminating static string searches and penalty signatures.

---

## Usage

```sh
bash examples/deobf_probe/run_probe.sh 1337

# Or evaluate existing phase dumps:
python3 examples/deobf_probe/peephole_eval.py /tmp/asg_probe/dumpA

# Inspect binary dispatch topology:
python3 examples/deobf_probe/dispatch_topology.py \
  --phase-json "/tmp/asg_probe/dumpA/phase_7-balance_(final).json" \
  --binary protected_arm64_out/protected_app
```

Dependencies: Python 3 stdlib only; `nm` + `otool`/`llvm-objdump` for machine code analysis; `bin/main.exe` for VM protection.
