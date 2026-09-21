# IDA Pro Analysis Guide — ASGARD-5877 Multi-VM Zero-Bridge

This directory contains pre-compiled binaries for side-by-side inspection in **IDA Pro / Hex-Rays / Ghidra / Binary Ninja**.

---

## 1. Binaries Available for IDA Pro

| Binary | Architecture | Protection Level | Purpose |
|:---|:---:|:---:|:---|
| [`unprotected_license_checker`](file:///Volumes/External/Code/ASGARD-5877/examples/ida_demo/unprotected_license_checker) | **ARM64** | None (Clean `-O2`) | Baseline to see original decompiled logic |
| [`unprotected_license_checker_x86_64`](file:///Volumes/External/Code/ASGARD-5877/examples/ida_demo/unprotected_license_checker_x86_64) | **x86_64** | None (Clean `-O2`) | Baseline for x86_64 IDA environments |
| [`protected_runner`](file:///Volumes/External/Code/ASGARD-5877/examples/ida_demo/protected_runner) | **ARM64** | **Max Security** | Multi-VM + Zero-Bridge + CFF + MBA + RNS-4 |
| [`protected_runner_x86_64`](file:///Volumes/External/Code/ASGARD-5877/examples/ida_demo/protected_runner_x86_64) | **x86_64** | **Max Security** | Multi-VM + Zero-Bridge for x86_64 IDA |

---

## 2. What to Inspect in IDA Pro

### Step 1: Open the Unprotected Baseline
- Load `unprotected_license_checker` into IDA Pro.
- Navigate to symbol `check_license_core` and press **F5** (Decompile).
- **Result**: You will immediately see the clean arithmetic formula:
  ```c
  return (((key ^ 0x5877) * 42) + 0x1337) == expected;
  ```
  The CFG consists of only 2 basic blocks and direct linear jumps.

---

### Step 2: Open the Protected Runner (`protected_runner` or `protected_runner_x86_64`)
- Load `protected_runner` into IDA Pro.
- Open the Functions window (`Shift+F3`) and navigate to `main` or `asgard_vm_execute`.
- Press **Space** for Graph View, or **F5** for Hex-Rays Decompiler.

#### What you will observe:
1. **Control-Flow Graph Flattening (CFF) & Computed GOTO**:
   - The CFG is completely flattened into an indirect branch dispatch (`BR Xn` on ARM64 or `jmp [rax*8 + offset]` on x86_64).
   - Decompiler outputs a massive switch/indirect jump structure with no recognizable high-level loops or conditional branches.
2. **Multi-VM Zero-Bridge Dispatch**:
   - Inspect handlers `H_BRIDGE_TO_FLOW` and `H_BRIDGE_TO_MATH`.
   - You will see the in-place $GL_{16}(\mathbb{Z}/2^{64}\mathbb{Z})$ affine matrix multiplication unrolled across 16 registers, scrambling the register state between execution engines.
3. **Absence of Linear Constants**:
   - Search for `0x5877` or `0x1337` (`Alt+I` in IDA).
   - **Found: 0 occurrences**. The constants were absorbed into MBA polynomials and RNS residue channels.
4. **Bytecode Section (`protected.vanguard`)**:
   - Shannon entropy is **7.991 / 8.000 bits/byte** (virtually indistinguishable from AES-encrypted data or random noise).
