# Architectural Specification: Pipelined Stage Dispatch for ASGARD-5877

## 1. Overview & Threat Model

Classical process virtualizers (e.g., legacy VMProtect, standard Themida interpreters) employ an atomic, centralized interpretation cycle:
```c
while (!vm->halted) {
    uint8_t op = fetch_byte(vm, bytecode, &vip);
    dispatch(op);
}
```
Even when implemented via GCC computed gotos (`goto *dispatch_table[op]`), this centralized loop presents significant vulnerabilities against automated symbolic execution and dynamic analysis tools (Triton, D810, QBDL):

1. **Dispatcher Identification by Graph Topology**: The central dispatcher forms a dominant hub in the Control Flow Graph (CFG) with in-degree equal to the number of handlers ($N \ge 38$) and out-degree equal to the opcode table size ($256$). This structure is trivially identified by static graph-matching algorithms.
2. **Atomic Taint Sinks**: Symbolic deobfuscators easily track the virtual instruction pointer (`VIP`) and virtual key register (`VKEY`) because both are updated atomically in the prologue of every dispatch transition.
3. **Hardware Breakpoint Pinpointing**: Placing hardware read/execute breakpoints on the dispatch table or `fetch_byte` allows analysts to step from virtual instruction to virtual instruction without reverse engineering individual handlers.

**Pipelined Stage Dispatch (Stage Relocation & Decoupled Execution)** destroys this centralized topology by decomposing the instruction execution lifecycle into split, decoupled pipeline stages with interleaved non-linear state permutations.

---

## 2. Pipeline Stage Decomposition

Under **Pipelined Stage Dispatch**, the execution of virtual instruction $I_{k}$ and the fetching/decoding of $I_{k+1}$ are overlapped and distributed across three discrete stages:

```
[Handler(I_k)] ──> [Stage 1: Pre-Fetch] ──> [Stage 2: Permutation/Integrity] ──> [Stage 3: Decoupled Dispatch] ──> [Handler(I_{k+1})]
```

### Stage 1: Epilogue Pre-Fetch
Instead of fetching the next opcode in a shared central dispatcher, each handler performs the byte-fetch and rolling key update of the *subsequent* opcode in its epilogue before transferring control:
$$\mathrm{op}_{k+1} = \mathrm{bytecode}[\mathrm{VIP}] \oplus (\mathrm{VKEY}_k \land \mathtt{0xFF})$$
$$\mathrm{VKEY}_{k+1} = \mathrm{step\_key}(\mathrm{VKEY}_k, \mathrm{op}_{k+1})$$
$$\mathrm{VIP} \leftarrow \mathrm{VIP} + 1$$

### Stage 2: Inter-Stage Arithmetic Chaffing & State Blinding
Between reading $\mathrm{op}_{k+1}$ and resolving its entry address, a pseudo-random integrity check or chaotic state permutation is computed over the runtime context:
$$K_{\mathrm{slot}} = (\mathrm{op}_{k+1} \times C_{\mathrm{golden}}) \oplus \mathrm{Salt}_{\mathrm{dispatch}}$$
$$\mathrm{VCTX}[\mathrm{hash}(\mathrm{op}_{k+1}) \pmod{16}] \mathrel{\text{^=}} \mathrm{VKEY}_{k+1} + \mathrm{op}_{k+1}$$
This breaks memory-read taint continuity: symbolic execution engines cannot propagate a linear symbol directly from the bytecode buffer into the program counter.

### Stage 3: Decoupled Computed Jump
Control is transferred to the next handler using blinded function pointers or direct indirect branches:
$$\mathrm{Target} = \mathrm{DispatchTable}[\mathrm{op}_{k+1}] \oplus K_{\mathrm{slot}}$$
$$\mathbf{goto} *(\mathrm{Target})$$

---

## 3. Mathematical & Cryptographic Invariants

### Invariant 1: Keystream Synchronicity
The rolling keystream must advance strictly by the number of consumed bytes. For any instruction $I_k$ with operand length $L_k$:
$$\Delta \mathrm{VIP} = 1 + L_k$$
The key state $\mathrm{VKEY}$ undergoes $1 + L_k$ successive applications of $\mathrm{step\_key}$:
$$\mathrm{VKEY}_{t+1} = \mathrm{feedback\_hash}\left(\mathrm{ROTL}_{64}(\mathrm{VKEY}_t, 3) + (p \oplus \mathtt{0x5A})\right)$$
Because pre-fetch moves the opcode fetch of $I_{k+1}$ to the tail of $I_k$, the initial program entry stub must execute the *priming pre-fetch* of $I_0$ prior to entering the handler matrix.

### Invariant 2: Zero Stack & Flag Corruption
The intermediate chaffing calculations in Stage 2 must operate exclusively on:
- Scratch context registers marked dead in the current epoch, OR
- Arithmetic operations that preserve processor condition flags (`CF, ZF, SF, OF, PF`), preventing corruption of deferred flag consumers (`JccRel`, `Setcc`, `Cmov`).

### Invariant 3: Constant-Time Dispatch Slot Unmasking
Dispatch table entries $\mathrm{DispatchTable}[i]$ are stored pre-blinded with affine masking over $\mathbb{Z}_{2^{64}}$:
$$\mathrm{Mask}(i) = (i \times \lfloor 2^{64} / \sqrt[3]{3} \rfloor) \oplus \mathtt{0x5877CAFE1337BEEF}$$
Unmasking is computed with branchless single-cycle ALU instructions (`mul`, `xor`), eliminating cache and timing side-channels.

---

## 4. CFG Impact & Deobfuscator Resistance

| Metric | Centralized Switch Dispatch | Centralized Computed Goto | Pipelined Stage Dispatch |
| :--- | :---: | :---: | :---: |
| **CFG Hubs** | 1 monolithic switch node | 1 shared dispatch block | **0 (Complete dispersion)** |
| **In-Degree per Handler** | 1 (from central loop) | 1 (from central loop) | **$N$ (Fully connected mesh)** |
| **Cyclomatic Complexity** | $O(N)$ concentrated | $O(N)$ concentrated | **$O(N^2)$ distributed** |
| **D810/angr Graph Recovery** | Trivial (pattern match) | High (pattern match) | **Impractical (combinatorial explosion)** |
| **Static Disassembler Linear Sweep** | Desynchronized after first block | Desynchronized after first block | **Desynchronized at every handler boundary** |

---

## 5. Integration with Existing ASGARD-5877 Passes

1. **Stack_avid_pass (Phase 5b)**:
   Avid junk operands lengthen individual instruction spans dynamically based on $\mathrm{VKEY}$. Pipelined Stage Dispatch integrates with avid skipping by allowing handlers to consume variable-length operands before invoking the epilogue pre-fetch.
2. **Stack_multiplicity_pass (Phase 2a-mult)**:
   Because handlers are polymorphic clones with varied internal sequences, the pre-fetch logic is embedded across distinct clones with differing register permutations, preventing static clustering of epilogue sequences.
3. **Tech-2603 (Anti-VPC Tracking)**:
   Pipelined stage dispatch routes virtual control flow without materializing linear $\mathrm{VIP}$ values into guest registers, complementing the non-linear affine transformation of virtual block addresses.

---

## 6. Verification & Test Plan

1. **Unit Verification (`test_cpp_codegen.ml`)**:
   Verify that generated C++ AST contains decoupled `ASG_PIPELINED_PREFETCH` and `ASG_PIPELINED_DISPATCH` primitives without centralized re-entry labels.
2. **End-to-End Execution (`test_stack_vm.ml`)**:
   Execute the full compiler pipeline on `examples/license_check.c` with `pipelined_dispatch = true`. Verify:
   - Valid license key (`ASGARD-5877-GOLD`) outputs `ACCESS GRANTED` and exit code `0`.
   - Invalid key outputs `ACCESS DENIED` and exit code `1`.
   - Tampered bytecode fails authentication before reaching the pipelined execution stage.
