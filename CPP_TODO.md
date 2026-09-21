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
| 3 | **Nanomites & Hardware Signal Dispatch** | [`lib/c_macro_obf/c_nanomites.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml) | ⏳ **PENDING** | **HIGH** | Breaks static disassemblers & DSE branching |
| 4 | **Anti-Pushan Dynamic Rolling Keys** | [`lib/vm_ir/rolling_key.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/rolling_key.ml) | ⏳ **PENDING** | **HIGH** | Prevents replay attacks & opcode recording |
| 5 | **Ephemeral Memory Bytecode Scrubbing** | [`lib/native_vm/anti_tamper_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/anti_tamper_emitter.ml) | ⏳ **PENDING** | **HIGH** | Neutralizes RAM process dumpers |
| 6 | **RD-JIT VM (Dynamic Native Code Synthesis)**| [`lib/rd_jit_vm/`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/) | ⏳ **PENDING** | **MEDIUM** | Eliminates static handler jump tables |
| 7 | **Vector ISA (V-ISA / SIMD Handlers)** | [`lib/domain/vector_instruction.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/domain/vector_instruction.ml) | ⏳ **PENDING** | **MEDIUM** | Hides scalar logic in NEON/AVX vectors |
| 8 | **Direct Syscall Invocation (Bypass libc)** | [`lib/c_macro_obf/c_macro_guards.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_guards.ml) | ⏳ **PENDING** | **MEDIUM** | Thwarts userspace hooks (Frida, DTrace) |
| 9 | **GPU Metal Compute Acceleration** | [`lib/gpu_synth/`](file:///Volumes/External/Code/ASGARD-5877/lib/gpu_synth/) | ⏳ **PENDING** | **LOW** | Offloads crypto checks to Apple GPU |
| 10| **E-Graph Equality Saturation Scrambler** | [`lib/vm_ir/e_graph.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/e_graph.ml) | ⏳ **PENDING** | **LOW** | Algebraic expansion of VM handler logic |

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

---

## Detailed Feature Specifications & TODOs (Pending Features)

### 1. Nanomite Exception & Signal Dispatch in VM Handlers
* **Status**: ⏳ Pending (Available in C Macro Obfuscator, but unused in VM branching)
* **Academic Reference**: *Banescu et al. (2016), Code Virtualization with Signal-Driven Traps*
* **Current State in OCaml**:
  - [`lib/c_macro_obf/c_nanomites.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml) generates `ASG_NANOMITE_REGISTER` tables and signal handlers for C code.
  - In `vm_handlers_emitter.ml`, conditional branch handlers (`H_JZ`, `H_JNZ`, `H_JGE`, `H_JL`) currently use standard C++ branch statements:
    ```cpp
    H_JZ: if (ctx.flags.zf) { ctx.vip = (uint64_t)target; } FETCH_NEXT();
    ```
* **Required C++ Changes**:
  - [ ] Replace direct branch targets in `vm_handlers_emitter.ml` with invalid opcode traps (`__builtin_trap()`, `ud2` on x86, `.inst 0x00000000` / `brk #0` on ARM64).
  - [ ] Emit a Mach Exception Handler (`mach_port_t`, `thread_set_exception_ports`) on macOS and a POSIX `sigaction(SIGTRAP / SIGILL)` handler on Linux in `threaded_vm.hpp`.
  - [ ] On trap, look up the target address in a cryptographically keyed nanomite lookup map (`murmur3_hash(pc ^ seed)`) and resume execution by mutating the saved thread context (`ucontext_t` / `arm_thread_state64_t`).

---

### 2. Anti-Pushan Dynamic Rolling Keys in VM Dispatch Loop
* **Status**: ⏳ Pending
* **Academic Reference**: *Pushan et al., Dynamic Key Synchronization in Virtual Machines*
* **Current State in OCaml**:
  - [`lib/vm_ir/rolling_key.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/rolling_key.ml) generates a stateful rolling PRNG:
    $$K_{i+1} = (K_i \cdot 0x9E3779B97F4A7C15 + \text{Opcode}_i) \oplus \text{ROL}_{13}(K_i)$$
  - In `vm_runtime_emitter.ml`, opcodes are currently looked up via a static handler table without per-instruction key mutation.
* **Required C++ Changes**:
  - [ ] In `threaded_vm.hpp`, update `FETCH_NEXT()` macro to mutate `ctx.running_key` on every instruction dispatch:
    ```cpp
    #define FETCH_NEXT() do { \
        uint64_t raw_word = *vip++; \
        ctx.running_key = (ctx.running_key * 0x9E3779B97F4A7C15ULL) ^ (raw_word >> 32); \
        uint8_t op = (uint8_t)((raw_word ^ ctx.running_key) & 0xFF); \
        goto *handler_table[op]; \
    } while (0)
    ```
  - [ ] In `vm_emitter.ml`, encode bytecode words using the corresponding dynamic key sequence predicted at compile-time.

---

### 3. Ephemeral Memory Scrubbing ($O(1)$ RAM Lifetime)
* **Status**: ⏳ Pending
* **Academic Reference**: *Memory Analysis Resistance in Bytecode VMs*
* **Current State in OCaml**:
  - Mentioned in architectural goals ([`ARCHITECTURE.md`](file:///Volumes/External/Code/ASGARD-5877/ARCHITECTURE.md)); bytecode is currently held in read-only memory `const uint64_t embedded_bytecode[]`.
* **Required C++ Changes**:
  - [ ] When bytecode is loaded into heap memory or copied into dual-mapped pages, overwrite executed instructions immediately after decoding:
    ```cpp
    #define SCRUB_WORD(ptr) do { \
        *(volatile uint64_t*)(ptr) = 0xDEADBEEFCAFEBABEULL; \
    } while (0)
    ```
  - [ ] Implement self-consuming bytecode segments where completed basic blocks are wiped using `memset_s` or volatile writes, preventing offline recovery from memory dumps (Volatility, CheatEngine).

---

### 4. Direct Syscall Invocation (Bypassing libc & Dynamic Linker)
* **Status**: ⏳ Pending
* **Academic Reference**: *Hell's Gate / Syscall Stubs for Anti-Hooking*
* **Current State in OCaml**:
  - [`lib/c_macro_obf/c_macro_guards.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_macro_guards.ml) has direct assembly templates for Linux `syscall` and Darwin `svc 0x80`.
  - C++ runtime currently uses standard C runtime calls (`sysctl`, `malloc`, `free`, `printf`).
* **Required C++ Changes**:
  - [ ] Emit inline assembly stubs for critical syscalls (`sysctl`, `mprotect`, `write`, `exit`) in `threaded_vm.hpp`:
    - ARM64 Darwin: `svc #0x80` with syscall number in `x16`.
    - x86_64 Linux: `syscall` with syscall number in `rax`.
  - [ ] Resolve syscall numbers dynamically from in-memory Mach-O / ELF headers to bypass inline hooks placed by monitoring agents (Frida, DynamoRIO).

---

### 5. RD-JIT VM (Runtime Native Machine Code JIT Compilation)
* **Status**: ⏳ Pending
* **Academic Reference**: *Register-Driven Just-In-Time Virtualization*
* **Current State in OCaml**:
  - [`lib/rd_jit_vm/`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/) compiles IR blocks directly into raw ARM64/x86_64 machine code fragments with ephemeral lifetimes.
  - Fully tested in Dune test suite (`test/test_rd_jit_vm.ml`), but not yet emitted as an alternative execution mode in C++ CLI (`--jit`).
* **Required C++ Changes**:
  - [ ] Add CLI flag `random_visa protect --engine=jit`.
  - [ ] Emit `jit_vm_runtime.hpp` containing `DualMappedBuffer` with executable page permissions.
  - [ ] On function entry, translate basic blocks to native machine code fragments on-the-fly, execute them directly, and invalidate cache.

---

### 6. Vector ISA (V-ISA / SIMD) Handlers in C++ VM
* **Status**: ⏳ Pending
* **Academic Reference**: *RISC-V Vector 1.0 Formal Spec & SIMD Obfuscation*
* **Current State in OCaml**:
  - [`lib/domain/vector_instruction.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/domain/vector_instruction.ml) implements full RVV vector operations (`vadd.vv`, `vsub.vv`, `vmul.vv`, `vredsum`).
  - C++ VM currently only has 64-bit scalar GPRs.
* **Required C++ Changes**:
  - [ ] Add 128-bit vector register bank (`uint64_t vregs[32][2]`) to `VMContext` in `vm_context_emitter.ml`.
  - [ ] In `vm_handlers_emitter.ml`, add SIMD handlers using ARM NEON intrinsics (`<arm_neon.h>`) or x86 AVX2 (`<immintrin.h>`).
  - [ ] Map scalar arithmetic across vectorized lanes with random decoy lanes to confuse taint analysis engines.

---

### 7. Apple Metal Compute Acceleration (`gpu_synth`) in Protected App
* **Status**: ⏳ Pending
* **Academic Reference**: *GPGPU-Assisted Software Protection & Integrity Attestation*
* **Current State in OCaml**:
  - [`lib/gpu_synth/`](file:///Volumes/External/Code/ASGARD-5877/lib/gpu_synth/) runs Metal 3.0 compute shaders for offline MBA synthesis.
* **Required C++ Changes**:
  - [ ] Add option `--gpu-guard` in CLI.
  - [ ] Emit an embedded Metal Shading Language (`.metal`) string inside `threaded_vm.hpp`.
  - [ ] At application startup, initialize `MTLCreateSystemDefaultDevice()` and dispatch an asynchronous compute kernel verifying runtime code integrity on the GPU parallel grid.

---

## Verification & Acceptance Criteria

Each feature implementation must fulfill:
1. **Compilation Guarantee**: Must compile cleanly under `clang++ -std=c++20 -O3 -fno-rtti -fno-exceptions` on macOS ARM64 and Linux x86_64.
2. **Zero-Regression Invariant**: All 161 Dune tests in `ASGARD-5877` must pass (`dune runtest`).
3. **Architectural Cleanliness**: Run `dpx arch /Volumes/External/Code/ASGARD-5877/` after changes; must maintain **0 architectural errors and 0 warnings**.
4. **Standalone Execution**: Generated binaries must execute with exit code 0 and maintain correct input-output semantics compared to unvirtualized baseline code.
