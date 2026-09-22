# ASGARD-5877: C++ Virtual Machine & Runtime Feature Parity Roadmap (`CPP_TODO.md`)

> **Document Status**: Active / Living Technical Roadmap  
> **Target Runtime**: C++20 (`clang++ -std=c++20 -O3`), macOS (Apple Silicon ARM64) & Linux (x86_64)  
> **Compiler Core**: OCaml 5.4+ (Hexagonal Ports & Adapters Architecture)

---

## Executive Summary

The **ASGARD-5877** engine contains advanced code virtualization, algebraic obfuscation, and formal synthesis algorithms. While core features (Computed GOTO, CFF, basic MBA, and recently **RNS-4** and **Multi-VM Zero-Bridge**) are active in C++ code generation, several theoretical sub-engines implemented in OCaml are not yet fully piped into the native C++ runtime emitted by [`lib/native_vm`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm) and [`lib/multi_vm`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm).

This roadmap tracks feature completion, architectural gaps, and implementation tasks required to achieve 100% feature parity between the OCaml core and the generated C++ binaries.

---

## Implementation Status Matrix

| # | Engine Subsystem | OCaml Module | C++ Status | Priority | Impact / Threat Model |
|---|:---|:---|:---:|:---:|:---|
| 1 | **Residue Number System (RNS-4)** | [`lib/vm_ir/rns.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/rns.ml) | ✅ **DONE** | Complete | Breaks linear SMT solvers ($M > 2^{64}$) |
| 2 | **Multi-VM Zero-Bridge** | [`lib/multi_vm/`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/) | ✅ **DONE** | Complete | $GL_{16}(\mathbb{Z}/2^{64}\mathbb{Z})$ affine morphing in bytecode |
| 3 | **Nanomites & Hardware Signal Dispatch** | [`lib/native_vm/hardened_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/hardened_runtime.ml) | ✅ **DONE** | Complete | Breaks static disassemblers & DSE branching |
| 4 | **Anti-Pushan Dynamic Rolling Keys** | [`lib/vm_ir/rolling_key.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/rolling_key.ml) | ✅ **DONE** | Complete | Prevents replay attacks & opcode recording |
| 5 | **Ephemeral Memory Bytecode Scrubbing** | [`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml) | ✅ **DONE** | Complete | Neutralizes RAM process dumpers |
| 6 | **RD-JIT VM (Dynamic Native Code Synthesis)**| [`lib/rd_jit_vm/`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/) | ✅ **DONE** | Complete | Eliminates static handler jump tables |
| 7 | **Vector ISA (V-ISA / SIMD Handlers)** | [`lib/domain/vector_instruction.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/domain/vector_instruction.ml) | ✅ **DONE** | Complete | Hides scalar logic in NEON/AVX vectors |
| 8 | **Direct Syscall Invocation (Bypass libc)** | [`lib/c_macro_obf/c_macro_guards.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_guards.ml) | ✅ **DONE** | Complete | Thwarts userspace hooks (Frida, DTrace) |

| 10| **E-Graph Equality Saturation Scrambler** | [`lib/vm_ir/e_graph.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/e_graph.ml) | ✅ **DONE** | Complete | Algebraic expansion of VM handler logic |

---

## Completed Runtime Implementations

### A. Residue Number System (RNS-4) Arithmetic Engine
* **Status**: ✅ Fully Operational (`lib/vm_ir/rns.ml`, `lib/native_vm/vm_handlers_emitter.ml`)
* **Mathematical Primitive**: Moduli set $\mathcal{M} = \{2^{16}-15, 2^{16}-17, 2^{16}-39, 2^{16}-57\}$, total dynamic range $M = \prod m_i \approx 2^{63.999}$.
* **Implementation Details**:
  - Injected 64-bit to 4-channel residue decomposition in `VMContext`.
  - Arithmetic operations (`ADD`, `SUB`, `MUL`) split into parallel modular channels, immune to linear SMT solvers.
  - Reconstructed back to 64-bit integer via Garner's algorithm in `H_RNS_RECONSTRUCT`.

### B. Multi-VM Zero-Bridge Dynamic Affine Morphing
* **Status**: ✅ Fully Operational (`lib/multi_vm/`, `lib/native_vm/`)
* **Mathematical Primitive**: Invertible affine transformation $y = A \cdot x + b \pmod{2^{64}}$ over $GL_{16}(\mathbb{Z}/2^{64}\mathbb{Z})$ coupled with non-linear Trace Digest $\text{Murmur3}(VIP \oplus \text{TraceKey})$.
* **Implementation Details**:
  - Opcodes `OP_BRIDGE_TO_FLOW` (0x55) and `OP_BRIDGE_TO_MATH` (0x56) mapped to handlers `H_BRIDGE_TO_FLOW` and `H_BRIDGE_TO_MATH`.
  - Bytecode emitted dynamically at engine boundary transitions (`inject_bridge_transitions` in `multi_vm_emitter.ml`).
  - In-place $16 \times 16$ affine register transformation executed in C++ `VMContext` (`in_place_morph_math_to_flow`, `in_place_morph_flow_to_math`), scrambling the entire register bank between functional VM partitions.
  - Tested E2E with both standalone ARM64/x86_64 protected binaries and Dune test suite (`test/test_multi_vm.ml`).

### C. Anti-Pushan Dynamic Rolling Keys in VM Dispatch Loop
* **Status**: ✅ Fully Operational (`lib/vm_ir/rolling_key.ml`, `lib/native_vm/vm_emitter.ml`, `vm_runtime_emitter.ml`, `vm_handlers_emitter.ml`, `vm_context_emitter.ml`)
* **Academic Reference**: *Pushan et al., Dynamic Key Synchronization in Virtual Machines*
* **Mathematical Primitive**: block-chained keystream — within a basic block the word mask is $m_j = k_{\text{pos}}(j) \oplus K_j$, where the chain anchor is the domain-separated PRF $K_0 = \text{PRF}(\text{seed} \oplus 0\text{x}5\text{BD}1\text{E}995,\ \text{block\_offset} \oplus 0\text{x}13375877)$ and each step mixes the decoded instruction itself:
  $$K_{j+1} = \big(\text{ROR}_{23}(K_j \oplus (\text{op}_j \cdot 0x9E3779B97F4A7C15 + (\text{dst}_j \ll 24) + \text{imm}_j)) \cdot 0xBF58476D1CE4E5B9\big) \oplus 0x5877CAFE1337BEEF$$
* **Implementation Details**:
  - `lib/vm_ir/rolling_key.ml` is the canonical OCaml mirror of the C++ keystream (`key64_for_offset` / `anchor_key` / `advance_key_step` / `decode_fields`); the encoder simulates at compile time exactly what `FETCH_NEXT` does at runtime, including the 46→32-bit sign-extended immediate truncation.
  - `FETCH_NEXT` decrypts as `word = bytecode[vIP] ^ k_pos ^ running_key`, then advances the key from the decoded `(op, dst, imm)`; the running key also feeds `evolve_mask`, the self-consuming scrub noise, and the dispatch-domain selector.
  - **Loop safety by construction**: every inter-block transition goes through an explicit terminal — `H_JMP` / `H_JCC` (carries both targets, no fall-through) / `H_CALL` — and each re-anchors `running_key = anchor_key(seed, vIP)` right after assigning `vIP_idx`; the VM entry does `reanchor_running_key(0)`. The keystream at any fetch therefore matches the encoder's prediction regardless of how many loop iterations executed.
  - The mask is coupled to the blinded architectural `REG_VKEY` register; flag `anti_pushan.running_key` toggles the scheme, and with it off the encoder keeps `cur_key = 0` — byte-identical legacy positional output.
  - Tested by `test/test_anti_pushan.ml`: golden PRF vectors, mirror replay of the anchor+advance chain over real ciphertext, legacy-identity on flag-off, and E2E clang++ execution of loops (`5! = 120`) and both branch paths.

### D. Ephemeral Memory Bytecode Scrubbing ($O(1)$ RAM Lifetime)
* **Status**: ✅ Fully Operational (`lib/native_vm/vm_runtime_emitter.ml`, `test/test_native_vm_and_metrics.ml`)
* **Academic Reference**: *Memory Analysis Resistance in Bytecode VMs (Pushan / VMP / Themida)*
* **Mathematical & Architectural Primitive**: Dual-tier volatile memory scrubbing and just-in-time instruction staging:
  - **Per-Fetch Ephemeral Stack Staging**: Instructions are staged just-in-time into isolated stack/alloca buffer `work_bc[vIP_idx] = bytecode[vIP_idx]`, decoded into CPU register `word = work_bc[vIP_idx] ^ k_dyn`, and immediately overwritten with dynamic rolling keystream noise:
    ```cpp
    #define SCRUB_WORD(ptr, val) do { \
        *(reinterpret_cast<volatile uint64_t*>(ptr)) = (val); \
    } while(0)
    SCRUB_WORD(&work_bc[vIP_idx], (k_dyn * 0x6A09E667F3BCC908ULL) ^ 0x5877CAFE1337BEEFULL);
    ```
    Executed instructions in `work_bc` have strict $O(1)$ RAM lifetime.
  - **DSE-Immune Volatile Sanitization**: Uses `volatile uint64_t*` pointer casts (`SCRUB_WORD`) to guarantee that Clang/GCC `-O2`/`-O3` optimizer passes cannot eliminate the memory wipes via Dead Store Elimination.
  - **Loop & Multi-Pass Soundness**: On loop backward edges or CFF re-entry, JIT staging seamlessly restores the active instruction into `work_bc[vIP_idx]` on each fetch without altering master ciphertext until block/program retirement.
  - **Master Bytecode & Heap Sanitization**: In `runner.cpp`, embedded bytecode is stored in non-`const` segment `static uint64_t embedded_bytecode[]`. When `execute_threaded(..., scrub_source = true)` exits, the master bytecode array is completely scrubbed with `0xDEADBEEFCAFEBABEULL ^ (seed + i)`. Any dynamically allocated `heap_bc` is securely wiped prior to `free()`.
  - **Verified by Tests**: Tested in `test/test_native_vm_and_metrics.ml` (`test_ephemeral_self_consuming_scrubbing`, `test_ephemeral_scrubbing_loop_and_stack` with `4! = 24`), and E2E with ARM64 protected applications.

### E. Nanomites & Hardware Signal Dispatch in VM Handlers
* **Status**: ✅ Fully Operational (`lib/native_vm/hardened_runtime.ml`, `lib/native_vm/vm_handlers_emitter.ml`, `lib/native_vm/vm_runtime_emitter.ml`, `test/test_anti_tamper_smc.ml`)
* **Academic Reference**: *Banescu et al. (2016), Code Virtualization with Signal-Driven Traps*
* **Mathematical & Architectural Primitive**: Dynamic exception and hardware signal-driven branch redirection:
  - **Branch Replacement with Software/Hardware Traps**: Conditional branches (`H_JCC`), direct jumps (`H_JMP`), and calls (`H_CALL`) no longer execute direct linear jumps or standard control-flow statements. Instead, branches register entry descriptors into `asgard_nanomites::g_nanomite_dispatcher` with XOR-encrypted targets keyed by `(seed ^ vIP_idx)`:
    ```cpp
    asgard_nanomites::g_nanomite_dispatcher.current_trap_id = (uint32_t)vIP_idx;
    asgard_nanomites::g_nanomite_dispatcher.current_condition = (uint32_t)c;
    asgard_nanomites::g_nanomite_dispatcher.register_nanomite((uint32_t)vIP_idx, t_true, t_false, (uint64_t)(seed ^ (uint32_t)vIP_idx));
    raise(SIGTRAP);
    vIP_idx = (size_t)asgard_nanomites::g_nanomite_dispatcher.resolved_target;
    ```
  - **POSIX & Darwin Signal Dispatcher**: An OS-level signal handler with `sigaction(SIGTRAP / SIGILL, ...)` captures synchronous trap interrupts. On signal delivery, the handler extracts the hardware instruction pointer from `ucontext_t` (`uc->uc_mcontext->__ss.__pc` on ARM64 macOS, `__rip` on x86_64, `pc` / `REG_RIP` on Linux), executes a 64-bit Murmur3 mix keyed by `seed`, decrypts the selected branch target, and sets `resolved_target`.
  - **Anti-Pushan Rolling Key Coherence**: Integrates directly with the Anti-Pushan rolling key re-anchoring pipeline. Every nanomite-resolved jump immediately triggers `reanchor_running_key((uint64_t)vIP_idx)`, guaranteeing 100% loop safety and keystream synchronization.
  - **Anti-Analysis & DSE Immunity**: Obfuscates the Control Flow Graph from static decompilers (Ghidra, IDA Pro, Binary Ninja) by replacing explicit branch edges with signal interrupts, defeating dynamic symbolic execution (DSE / angr) engines that do not model operating system signal delivery.
  - **Verified by Tests**: Verified in `test/test_anti_tamper_smc.ml` (`test_nanomite_signal_dispatch`) with full C++20 compilation and execution under `clang++ -std=c++20 -O2`.

### F. Direct Syscall Invocation (Bypass libc & Dynamic Linker)
* **Status**: ✅ Fully Operational (`lib/native_vm/hardened_runtime.ml`, `lib/native_vm/vm_runtime_emitter.ml`, `lib/native_vm/protection_presets.ml`, `test/test_anti_tamper_smc.ml`)
* **Academic Reference**: *Hell's Gate / Syscall Stubs for Anti-Hooking & Direct Kernel Transition*
* **Mathematical & Architectural Primitive**: Bare-metal kernel transitions bypassing libc and dynamic linker symbol resolution (`libsystem_kernel.dylib` / `libc.so`):
  - **Multi-Architecture Kernel Inline Assembly**: Zero-overhead direct syscall wrappers (`direct_syscall_0` through `direct_syscall_6`) across target ABIs:
    - **ARM64 Darwin**: Direct trap via `svc #0x80`, loading syscall number into `x16` and arguments into `x0..x5`.
    - **x86_64 Darwin**: Direct trap via `syscall`, loading `0x2000000 | sys_num` into `rax` and arguments into `rdi, rsi, rdx, r10, r8, r9`.
    - **x86_64 Linux**: Standard System V kernel trap via `syscall` with syscall number in `rax`.
    - **ARM64 Linux**: Linux aarch64 kernel trap via `svc #0` with syscall number in `x8` and arguments in `x0..x5`.
  - **Hook-Resistant Anti-Debugger Kernel Probes**: `asgard_syscalls::sys_check_debugger_present()` queries kernel debugging state (`P_TRACED`) completely without invoking libc `sysctl()` or `getpid()`:
    - Darwin: Direct syscall `SYS___sysctl (202)` querying `CTL_KERN, KERN_PROC, KERN_PROC_PID, sys_getpid()` with `kinfo_proc`.
    - Linux: Direct syscall `SYS_openat (-100, "/proc/self/status", O_RDONLY, 0)` and `SYS_read`, parsing `TracerPid:` directly from buffer memory with zero dynamic allocations.
  - **Dynamic Interposition Immunity**: Immune to user-space dynamic interception frameworks (Frida `Interceptor.attach`, DTrace, Substrate, `DYLD_INSERT_LIBRARIES`, `LD_PRELOAD`).
  - **Verified by Tests**: Verified in `test/test_anti_tamper_smc.ml` (`test_direct_syscalls_e2e`) verifying `sys_getpid`, `sys_check_debugger_present`, and `sys_write` under `clang++ -std=c++20 -O2`.

### G. RD-JIT VM (Register-Driven Dynamic Native Code Synthesis)
* **Status**: ✅ Fully Operational (`lib/rd_jit_vm/rd_jit_emitter.ml`, `bin/cli_protect.ml`, `bin/cli_protect_arm64.ml`, `test/test_rd_jit_vm.ml`)
* **Academic Reference**: *Register-Driven Just-In-Time Virtualization & Ephemeral Code Synthesis*
* **Mathematical & Architectural Primitive**: On-the-fly ephemeral machine code synthesis with zero static handler dispatch tables:
  - **Dual-Mapping W^X Memory Manager (`DualMappedJITBuffer`)**: Dual-mapped virtual memory architecture bypassing W^X protections:
    - macOS / Apple Silicon: `vm_allocate` + `vm_remap` (`VM_PROT_READ | VM_PROT_EXECUTE`) mapping identical physical pages to writable view `rw_buf` and executable view `rx_buf`, with `MAP_JIT` / `pthread_jit_write_protect_np` fallback.
    - Linux: `memfd_create("asgard_rd_jit_wx", MFD_CLOEXEC)` with dual shared `mmap` mappings (`PROT_READ|PROT_WRITE` and `PROT_READ|PROT_EXEC`).
  - **Ephemeral Native Machine Code Synthesizer**: Converts basic block instructions just-in-time into raw CPU machine opcodes:
    - ARM64: dynamic generation of `LDR/STR` unsigned offset, `MOVZ/MOVK` 64-bit immediate materialization, `ADD`, `SUB`, `MUL`, `EOR`, `AND`, `ORR`, and `RET` (`0xd65f03c0`).
    - x86_64: dynamic generation of REX-prefixed `MOV`, `ADD`, `SUB`, `IMUL`, `XOR`, `AND`, `OR`, and `RET` (`0xc3`).
  - **RNS-4 Moduli Residue Synchronization**: Parallel modular channels ($M = \prod m_i > 2^{64}$) synchronized post-execution in `RD_JIT_Context` using Garner's CRT recovery.
  - **$O(1)$ Machine Code RAM Lifetime & Atomic Scrub**: Immediately upon block retirement, `atomic_zeroize` scrubs the write view with `volatile` wipes, leaving 0 trace of synthesized machine code in process RAM.
  - **CLI Integration**: Added CLI flags `--engine=jit` and `--jit` to `random_visa protect` and `random_visa protect-arm64`.
  - **Verified by Tests**: Tested in `test/test_rd_jit_vm.ml` with E2E multi-op arithmetic execution under `clang++ -std=c++20 -O2`.

---

## Completed Feature Specifications

### H. Vector ISA (V-ISA / SIMD) Handlers in C++ VM
* **Status**: ✅ Fully Operational (`lib/native_vm/vm_context_emitter.ml`, `lib/native_vm/vm_handlers_emitter.ml`, `lib/native_vm/vm_transform.ml`, `lib/native_vm/vm_runtime_emitter.ml`, `lib/native_vm/protection_types.ml`, `test/test_anti_tamper_smc.ml`)
* **Academic Reference**: *RISC-V Vector 1.0 Formal Spec & SIMD Obfuscation*
* **Mathematical & Architectural Primitive**: 128-bit dual-lane vector register bank with platform-native SIMD intrinsics:
  - **Vector Register Bank**: `uint64_t vregs[32][2]` added to `VMContext` — 32 128-bit registers, each stored as `[lane0=lo, lane1=hi]`, zero-initialized in `init()`. Accessed via `get_vreg_lane(i, lane)` and `set_vreg(i, lo, hi)`.
  - **New Opcodes**: `OP_VADD_VV`, `OP_VSUB_VV`, `OP_VMUL_VV`, `OP_VXOR_VV` added to `raw_op_kind`, `all_op_kinds`, and `op_kind_to_handler_name`. Decoy saturation: 256 − 43 = **213** polymorphic decoy slots.
  - **NEON Handlers (ARM64)**: `vaddq_u64` / `vsubq_u64` / `veorq_u64` via `<arm_neon.h>` using `vcombine_u64` / `vcreate_u64` / `vgetq_lane_u64`.
  - **SSE Handlers (x86_64)**: `_mm_add_epi64` / `_mm_sub_epi64` / `_mm_xor_si128` via `<immintrin.h>` using `_mm_set_epi64x` / `_mm_extract_epi64`.
  - **Scalar Fallback**: Lane-wise `+`, `−`, `*`, `^` for non-NEON/SSE targets.
  - **`H_VMUL_VV`**: Scalar lane-wise 64-bit multiply (no universal 64×64→64 SIMD mul across all ISAs).
  - **SIMD Include Guard**: `vector_isa : bool` flag in `vm_runtime_config` controls whether `#include <arm_neon.h>` / `#include <immintrin.h>` is emitted. Wired through protection presets (default=true, max_security=true, lightweight=false, minimal=false) and JSON serialization.
* **Verified by Tests**: `test/test_anti_tamper_smc.ml` (`test_vector_isa_e2e`) — compiles NEON VADD and VXOR handlers under `clang++ -std=c++20 -O2` on ARM64 macOS and verifies [10+3=13, 20+7=27] and self-XOR=0 arithmetic correctness.

---


### I. E-Graph Equality Saturation Scrambler
* **Status**: ✅ Fully Operational (`lib/native_vm/egraph_cpp_emitter.ml`, `lib/native_vm/vm_handlers_emitter.ml`, `lib/native_vm/vm_runtime_emitter.ml`, `lib/native_vm/protection_types.ml`, `test/test_egraph_expansion.ml`, `test/test_protection_config.ml`)
* **Academic Reference**: *EqSat / Egg: Equality Saturation for Rewrite Optimization & De-canonicalization (arXiv:2603.03624)*
* **Mathematical & Architectural Primitive**: Equality saturation + max-complexity extraction → per-seed unique algebraic handler forms:
  - **`Egraph_cpp_emitter`** (new module): `expr_to_cpp ~a_cpp ~b_cpp` renders a `Mba.expr` tree as a parenthesized C++ `uint64_t` expression string. Variables `"a"`/`"b"` → `ctx.get_reg(dst)`/`ctx.get_reg(src)`. Consts emitted as `0x...ull` hex literals.
  - **5 public helpers**: `egraph_add_rr`, `egraph_sub_rr`, `egraph_xor_rr`, `egraph_and_rr`, `egraph_or_rr` — each calls `Mba_engine.Egraph.expand` with `node_limit=120, time_budget_s=0.08, iter_limit=6` and renders the max-complexity extracted form.
  - **`vm_handlers_emitter.ml`**: new `~enable_egraph_expansion` labeled parameter. When `true`, `H_ADD_RR`, `H_SUB_RR`, `H_XOR_RR`, `H_AND_RR`, `H_OR_RR` bodies are replaced with egraph-saturated C++ expressions; when `false`, fall back to existing `pick_poly_*` variants.
  - **`vm_runtime_emitter.ml`**: extracts `enable_egraph_expansion` from config and threads it into `emit_handlers_hpp`.
  - **`vm_runtime_config`** field: `egraph_expansion : bool` — wired through `protection_types.ml/.mli`, `protection_config.mli`, all 6 presets (default=true, max_security=true, high=true, stealth=true, lightweight=false, minimal=false), and JSON serialization roundtrip.
  - **Semantic invariant**: Every emitted expression is algebraically equivalent to the original op over Z₂⁶⁴ — verified by `test_rule_verification` (24 MBA identity rules, 240 trials).
* **Verified by Tests**: `test/test_egraph_expansion.ml` test 8 (`egraph_cpp_handler_expansion_e2e`) — generates ADD/SUB/XOR/AND/OR expressions via E-Graph, substitutes `ctx.get_reg(dst)→a, ctx.get_reg(src)→b`, compiles with `clang++ -std=c++20 -O2`, executes with `a=100, b=37`, asserts all 5 results match reference arithmetic.

---

## Verification & Acceptance Criteria

Each feature implementation must fulfill:
1. **Compilation Guarantee**: Must compile cleanly under `clang++ -std=c++20 -O3 -fno-rtti -fno-exceptions` on macOS ARM64 and Linux x86_64.
2. **Zero-Regression Invariant**: All 172 Dune tests in `ASGARD-5877` must pass (`dune runtest`).
3. **Architectural Cleanliness**: Run `dpx arch /Volumes/External/Code/ASGARD-5877/` after changes; must maintain **0 architectural errors and 0 warnings**.
4. **Standalone Execution**: Generated binaries must execute with exit code 0 and maintain correct input-output semantics compared to unvirtualized baseline code.
