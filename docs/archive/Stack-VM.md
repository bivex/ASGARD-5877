# Architectural Specification: Stack-VM Execution Engine for ASGARD-5877

This document defines the mathematical model, formal specification in **Z Notation**, transformation algorithms, intermediate representation (IR) specification, streaming encryption mechanism, and implementation roadmap for the **Stack Virtual Machine (Stack-VM)** within the ASGARD-5877 protection framework.

---

## 1. Concept and Objectives of Stack-VM in ASGARD-5877

The standard ASGARD-5877 architecture employs a high-performance **3-address register IR** (`Ir.Alu`, `Ir.Mem`, `Ir.Control`), optimized for compiler transformations, MBA obfuscation, and RD-JIT.

Integrating **Stack-VM** as an alternative or hybrid execution backend addresses the following security objectives:

1. **Dataflow Oblivion**:
   - In 3-address code, inter-register dependencies are explicit (def-use chains).
   - In a stack machine, operands pass implicitly across the evaluation stack top (`VSP`), destroying explicit register def-use associations in static decompilers (IDA Pro, Hex-Rays, Ghidra).
2. **Universal Logic Reduction**:
   - Elimination of discrete `AND`, `OR`, `XOR`, and `NOT` handlers through canonical reduction to Sheffer stroke (`NAND`) or Peirce arrow (`NOR`) universal logic gates.
3. **Rolling Cryptor Chaining**:
   - Every instruction byte or word is decrypted with a dynamic key dependent on execution history (stateful rolling key), preventing linear static disassembly of bytecode.
4. **Relative-Delta Threading**:
   - Absence of cleartext function pointer dispatch tables; execution transfers proceed via accumulated relative offsets relative to previous handler positions.

---

## 2. Formal Machine State

The virtual machine state is defined by the tuple:
$$\mathcal{S}_{\mathrm{SVM}} = \langle \mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}, \mathcal{M}_{\mathrm{stack}}, \mathcal{C}_{\mathrm{ctx}}, \mathcal{F}_{\mathrm{flags}} \rangle$$

where:
- **$\mathrm{VIP}$ (Virtual Instruction Pointer)**: Physical register indexing the current position in the encrypted bytecode stream.
- **$\mathrm{VSP}$ (Virtual Stack Pointer)**: Physical register pointing to the top of the computation stack in memory.
- **$\mathrm{VKEY}$ (Dynamic Decryption Key)**: Cryptor state register modified at each instruction fetch cycle.
- **$\mathrm{VDISP}$ (Handler Base / Dispatch Cursor)**: Base pointer for indirect transfers to the subsequent handler.
- **$\mathcal{M}_{\mathrm{stack}}$**: Execution stack memory (local computation frame).
- **$\mathcal{C}_{\mathrm{ctx}}$**: Context slot array (Context Frame), preserving target architecture general-purpose registers (x86_64 / AArch64 / RV64).
- **$\mathcal{F}_{\mathrm{flags}}$**: Condition flag register (or deferred flag state preserved on the evaluation stack).

### Stack Balance Invariant
For any linear basic block $B$:
$$\Delta \mathrm{VSP}(B) = \sum_{i \in B} \mathrm{pushWeight}(i) - \sum_{i \in B} \mathrm{popWeight}(i)$$
At basic block boundaries, the stack depth $\mathrm{depth}(\mathrm{VSP})$ must be deterministic to ensure correctness across control-flow merge points.

---

## 3. Formal Specification in Z Notation

The specification is formalized in the Schema Calculus, formatted in standard mathematical notation compatible with KaTeX / MathJax.

### 3.1 Basic Types, Sets, and Operators

$$[\mathrm{Addr}, \mathrm{Word}, \mathrm{Byte}, \mathrm{RegId}]$$

Derived types and global constants:
$$\mathrm{Val} == \mathrm{Word}, \quad \mathrm{Flags} == \mathrm{Word}, \quad \mathrm{Offset} == \mathbb{Z}$$
$$\mathrm{WordSize} == 8, \quad \mathrm{MaxStackDepth} : \mathbb{N}, \quad \mathrm{ActiveRegs} : \mathbb{P} ~ \mathrm{RegId}$$

Axiomatic boolean logic and cryptor function signatures:

$$\begin{array}{l}
\mathrm{nor} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \\
\mathrm{nand} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \\
\mathrm{addWithFlags} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \times \mathrm{Flags} \\
\mathrm{subWithFlags} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \times \mathrm{Flags} \\
\mathrm{decryptByte} : \mathrm{Byte} \times \mathrm{Word} \to \mathrm{Byte} \\
\mathrm{deriveKey} : \mathrm{Word} \times \mathrm{Byte} \to \mathrm{Word} \\
\mathrm{readWordMem} : (\mathrm{Addr} \rightharpoonup \mathrm{Byte}) \times \mathrm{Addr} \to \mathrm{Val} \\
\mathrm{writeWordMem} : (\mathrm{Addr} \rightharpoonup \mathrm{Byte}) \times \mathrm{Addr} \times \mathrm{Val} \to (\mathrm{Addr} \rightharpoonup \mathrm{Byte})
\end{array}$$

---

### 3.2 Virtual Machine State Schema: $\mathrm{StackVMState}$

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{StackVMState} \\
\hline
\mathrm{vip} : \mathrm{Addr} \\
\mathrm{vsp} : \mathrm{Addr} \\
\mathrm{vkey} : \mathrm{Word} \\
\mathrm{vdisp} : \mathrm{Addr} \\
\mathrm{vstack} : \mathrm{seq} ~ \mathrm{Val} \\
\mathrm{vctx} : \mathrm{RegId} \rightharpoonup \mathrm{Val} \\
\mathrm{vmem} : \mathrm{Addr} \rightharpoonup \mathrm{Byte} \\
\mathrm{flags} : \mathrm{Flags} \\
\hline
|\mathrm{vstack}| \le \mathrm{MaxStackDepth} \\
\mathrm{vsp} \bmod \mathrm{WordSize} = 0 \\
\mathrm{dom}(\mathrm{vctx}) = \mathrm{ActiveRegs} \\
\hline
\end{array}$$

*Invariant Predicates:*
1. $|\mathrm{vstack}| \le \mathrm{MaxStackDepth}$ — The virtual stack is bounded to prevent unbounded memory growth.
2. $\mathrm{vsp} \bmod \mathrm{WordSize} = 0$ — The hardware stack pointer is strictly aligned to an 8-byte boundary.
3. $\mathrm{dom}(\mathrm{vctx}) = \mathrm{ActiveRegs}$ — All active architectural registers are mapped within the context frame.

---

### 3.3 Initial State Schema: $\mathrm{InitStackVMState}$

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{InitStackVMState} \\
\hline
\mathrm{StackVMState}' \\
\mathrm{entry?} : \mathrm{Addr} \\
\mathrm{initSp?} : \mathrm{Addr} \\
\mathrm{seedKey?} : \mathrm{Word} \\
\mathrm{baseDisp?} : \mathrm{Addr} \\
\mathrm{initCtx?} : \mathrm{RegId} \to \mathrm{Val} \\
\mathrm{initMem?} : \mathrm{Addr} \rightharpoonup \mathrm{Byte} \\
\hline
\mathrm{vip}' = \mathrm{entry?} \\
\mathrm{vsp}' = \mathrm{initSp?} \\
\mathrm{vkey}' = \mathrm{seedKey?} \\
\mathrm{vdisp}' = \mathrm{baseDisp?} \\
\mathrm{vstack}' = \langle \rangle \\
\mathrm{vctx}' = \mathrm{initCtx?} \\
\mathrm{vmem}' = \mathrm{initMem?} \\
\mathrm{flags}' = 0 \\
\hline
\end{array}$$

---

### 3.4 Instruction Fetch and Streaming Decryption: $\mathrm{FetchByte}$

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{FetchByte} \\
\hline
\Delta \mathrm{StackVMState} \\
\mathrm{plain!} : \mathrm{Byte} \\
\hline
\mathrm{vip} \in \mathrm{dom}(\mathrm{vmem}) \\
\mathrm{plain!} = \mathrm{decryptByte}(\mathrm{vmem}(\mathrm{vip}), \mathrm{vkey}) \\
\mathrm{vip}' = \mathrm{vip} + 1 \\
\mathrm{vkey}' = \mathrm{deriveKey}(\mathrm{vkey}, \mathrm{plain!}) \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{vstack}' = \mathrm{vstack} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

---

### 3.5 Operational Schemas ($\Delta \mathrm{StackVMState}$)

#### Operation $\mathrm{PushImm}$ (Push Immediate Operand):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{PushImm} \\
\hline
\Delta \mathrm{StackVMState} \\
\mathrm{imm?} : \mathrm{Val} \\
\hline
|\mathrm{vstack}| < \mathrm{MaxStackDepth} \\
\mathrm{vstack}' = \langle \mathrm{imm?} \rangle \mathbin{\frown} \mathrm{vstack} \\
\mathrm{vsp}' = \mathrm{vsp} - \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{PushReg}$ (Read Register from Context Frame):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{PushReg} \\
\hline
\Delta \mathrm{StackVMState} \\
r? : \mathrm{RegId} \\
\hline
r? \in \mathrm{dom}(\mathrm{vctx}) \\
|\mathrm{vstack}| < \mathrm{MaxStackDepth} \\
\mathrm{vstack}' = \langle \mathrm{vctx}(r?) \rangle \mathbin{\frown} \mathrm{vstack} \\
\mathrm{vsp}' = \mathrm{vsp} - \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{PopReg}$ (Pop Value to Context Slot):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{PopReg} \\
\hline
\Delta \mathrm{StackVMState} \\
r? : \mathrm{RegId} \\
\hline
r? \in \mathrm{dom}(\mathrm{vctx}) \\
\mathrm{vstack} \ne \langle \rangle \\
\mathrm{vctx}' = \mathrm{vctx} \oplus \{ r? \mapsto \mathrm{head}(\mathrm{vstack}) \} \\
\mathrm{vstack}' = \mathrm{tail}(\mathrm{vstack}) \\
\mathrm{vsp}' = \mathrm{vsp} + \mathrm{WordSize} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecNor}$ (Universal Peirce Arrow):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecNor} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathbf{let} ~ a = \mathrm{vstack}(1) \land b = \mathrm{vstack}(2) \bullet \\
\quad \mathrm{vstack}' = \langle \mathrm{nor}(a, b) \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \\
\mathrm{vsp}' = \mathrm{vsp} + \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecAdd}$ (Addition with Flag Generation):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecAdd} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathbf{let} ~ a = \mathrm{vstack}(1) \land b = \mathrm{vstack}(2) \bullet \\
\quad \mathbf{let} ~ (res, newFlags) = \mathrm{addWithFlags}(a, b) \bullet \\
\quad\quad \mathrm{vstack}' = \langle res \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \land \\
\quad\quad \mathrm{flags}' = newFlags \\
\mathrm{vsp}' = \mathrm{vsp} + \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecDup}$ (Duplicate Stack Top):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecDup} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
\mathrm{vstack} \ne \langle \rangle \\
|\mathrm{vstack}| < \mathrm{MaxStackDepth} \\
\mathrm{vstack}' = \langle \mathrm{head}(\mathrm{vstack}) \rangle \mathbin{\frown} \mathrm{vstack} \\
\mathrm{vsp}' = \mathrm{vsp} - \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecSwap}$ (Swap Two Top Stack Elements):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecSwap} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathrm{vstack}' = \langle \mathrm{vstack}(2), \mathrm{vstack}(1) \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecReadMem}$ (Indirect Read from Physical Memory):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecReadMem} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
\mathrm{vstack} \ne \langle \rangle \\
\mathbf{let} ~ addr = \mathrm{head}(\mathrm{vstack}) \bullet \\
\quad addr \in \mathrm{dom}(\mathrm{vmem}) \land \\
\quad \mathrm{vstack}' = \langle \mathrm{readWordMem}(\mathrm{vmem}, addr) \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{vstack}) \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecWriteMem}$ (Write from Stack to Physical Memory):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecWriteMem} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathbf{let} ~ addr = \mathrm{vstack}(1) \land val = \mathrm{vstack}(2) \bullet \\
\quad \mathrm{vmem}' = \mathrm{writeWordMem}(\mathrm{vmem}, addr, val) \\
\mathrm{vstack}' = \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \\
\mathrm{vsp}' = \mathrm{vsp} + (2 \cdot \mathrm{WordSize}) \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Operation $\mathrm{ExecDispatchRel}$ (Relative Dispatch Cursor Adjustment):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecDispatchRel} \\
\hline
\Delta \mathrm{StackVMState} \\
\delta? : \mathrm{Offset} \\
\hline
\mathrm{vdisp}' = \mathrm{vdisp} + \delta? \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vstack}' = \mathrm{vstack} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

---

### 3.6 Stack Conservation Theorem

Let basic block $B$ be defined as the sequential composition of operations:
$$\mathcal{T}_B = \mathcal{O}_1 \mathbin{\mathbf{;}} \mathcal{O}_2 \mathbin{\mathbf{;}} \dots \mathbin{\mathbf{;}} \mathcal{O}_n$$

$$\begin{array}{l}
\mathbf{Theorem} ~ (\mathrm{StackConservation}) \bullet \\
\forall s : \mathrm{StackVMState} \bullet \\
\quad (\Delta \mathrm{VSP}(B) = 0 \land s \in \mathrm{dom}(\mathcal{T}_B)) \implies \\
\quad\quad |\mathcal{T}_B(s).\mathrm{vstack}| = |s.\mathrm{vstack}| \land \mathcal{T}_B(s).\mathrm{vsp} = s.\mathrm{vsp}
\end{array}$$

*Corollary:* When basic block balance $\Delta \mathrm{VSP}(B) = 0$, branch and loop transitions are guaranteed to neither leak nor overflow the virtual stack.

---

## 4. Stack-ISA Instruction Set

| Opcode | Mnemonic | Stack Effect | Description |
| :--- | :--- | :--- | :--- |
| `0x01` | `PUSH_IMM` | $(\epsilon \to v)$ | Decrypt immediate $imm$ from bytecode and push to VSP |
| `0x02` | `PUSH_REG` | $(\epsilon \to \mathcal{C}[idx])$ | Read context register slot to VSP |
| `0x03` | `POP_REG` | $(v \to \epsilon)$ | Pop top value to context slot $\mathcal{C}[idx]$ |
| `0x04` | `READ_MEM` | $(addr \to value)$ | Read value from physical memory at stack address |
| `0x05` | `WRITE_MEM` | $(addr, value \to \epsilon)$ | Write value to physical memory |
| `0x06` | `ADD` | $(a, b \to a + b, flags)$ | Binary integer addition with flag generation |
| `0x07` | `SUB` | $(a, b \to a - b, flags)$ | Binary integer subtraction |
| `0x08` | `NOR` | $(a, b \to \neg(a \lor b), flags)$ | Canonical Peirce arrow universal gate |
| `0x09` | `NAND` | $(a, b \to \neg(a \land b), flags)$ | Alternative Sheffer stroke universal gate |
| `0x0A` | `SHL` / `SHR` | $(val, count \to res, flags)$ | Logical bitwise shifts |
| `0x0B` | `DUP` | $(a \to a, a)$ | Duplicate stack top element |
| `0x0C` | `SWAP` | $(a, b \to b, a)$ | Swap two topmost stack elements |
| `0x0D` | `POP_FLAGS` | $(flags \to \epsilon)$ | Restore hardware flags from stack |
| `0x0E` | `PUSH_FLAGS`| $(\epsilon \to flags)$ | Push current hardware flags to stack |
| `0x0F` | `JMP_REL` | $(\epsilon \to \epsilon)$ | Adjust VIP by relative signed offset |
| `0x10` | `JCC_REL` | $(cond \to \epsilon)$ | Conditional relative jump based on stack top |
| `0x11` | `VM_EXIT` | $(\epsilon \to \epsilon)$ | Restore native context and return to caller |

---

## 5. Compilation and Transformation Algorithms

### Algorithm 1: Lowering 3-Address IR to Stack-VM

Lowers a 3-address instruction `dst = op(src1, src2)` into stack instructions:

```text
Function LowerToStack(Instr):
  1. Input: Instr(dst, op, src1, src2)
  2. If src2 is Constant(c):
       Emit(PUSH_IMM, c)
     Else:
       Emit(PUSH_REG, ContextSlot(src2))

  3. If src1 is Constant(c):
       Emit(PUSH_IMM, c)
     Else:
       Emit(PUSH_REG, ContextSlot(src1))

  4. If op in {Add, Sub, Mul}:
       Emit(TranslateAluOp(op))
     Else if op in {And, Or, Xor, Not}:
       EmitUniversalLogic(op)

  5. If Instr produces a result:
       Emit(POP_REG, ContextSlot(dst))
     If Instr updates condition flags:
       Emit(POP_FLAGS)
```

---

### Algorithm 2: Logic Decomposition to Universal NOR / NAND Basis

All boolean logic reduces strictly to `NOR` ($\downarrow$):

1. **Inversion $\mathrm{NOT}(x)$:**
   $$\neg x \equiv x \downarrow x$$
   *Stack template:*
   ```text
   DUP
   NOR
   ```

2. **Disjunction $\mathrm{OR}(x, y)$:**
   $$x \lor y \equiv (x \downarrow y) \downarrow (x \downarrow y)$$
   *Stack template:*
   ```text
   NOR
   DUP
   NOR
   ```

3. **Conjunction $\mathrm{AND}(x, y)$:**
   $$x \land y \equiv (\neg x) \downarrow (\neg y) \equiv (x \downarrow x) \downarrow (y \downarrow y)$$
   *Stack template:*
   ```text
   SWAP
   DUP
   NOR        ; NOT(y)
   SWAP
   DUP
   NOR        ; NOT(x)
   NOR        ; NOT(x) NOR NOT(y) == x AND y
   ```

4. **Exclusive OR $\mathrm{XOR}(x, y)$:**
   Set-theoretic identity:
   $$x \oplus y \equiv (x \lor y) \land \neg(x \land y)$$
   
   Canonically expressed in Peirce basis ($\downarrow$) via superposition:
   $$x \oplus y = ((x \downarrow x) \downarrow (y \downarrow y)) \downarrow (x \downarrow y)$$
   
   *Correctness Proof:*
   - Left sub-expression: $(x \downarrow x) \downarrow (y \downarrow y) = (\neg x) \downarrow (\neg y) = \neg(\neg x \lor \neg y) = x \land y$.
   - Right sub-expression: $x \downarrow y = \neg(x \lor y)$.
   - Their composition via $\mathrm{NOR}$:
     $$\neg \Big( (x \land y) \lor \neg(x \lor y) \Big) = \neg (x \odot y) = x \oplus y$$

   *5-Gate Decomposition:*
   $$\begin{aligned}
   g_1 &= x \downarrow y \\
   g_2 &= x \downarrow g_1 \\
   g_3 &= y \downarrow g_1 \\
   g_4 &= g_2 \downarrow g_3 \\
   x \oplus y &= g_4 \downarrow g_4
   \end{aligned}$$

   *Compiler Stack Template:*
   ```text
   ; 1. Compute (x AND y) on stack
   PUSH_REG src2       ; y
   DUP
   NOR                 ; NOT(y)
   PUSH_REG src1       ; x
   DUP
   NOR                 ; NOT(x)
   NOR                 ; (x AND y)

   ; 2. Compute (x NOR y) on stack
   PUSH_REG src2       ; y
   PUSH_REG src1       ; x
   NOR                 ; (x NOR y)

   ; 3. Final reduction
   NOR                 ; (x AND y) NOR (x NOR y) == x XOR y
   ```

*Protection Effect:* Decompilers observe zero `and`/`or`/`xor` opcodes. All operations invoke the identical `NOR` handler with varying stack permutations.

---

### Algorithm 3: Streaming Bytecode Decryption (Rolling-Key Decryption)

Bytecode is protected via an adaptive stream cipher where each fetch cycle updates the decryption key.

```text
Fetch-Decode Cycle:
  1. raw_byte = Memory[VIP]
  2. VIP = VIP + 1
  3. plain_byte = raw_byte XOR VKEY
  4. VKEY = RotL(VKEY, 3) + plain_byte XOR 0x5A
  5. Return plain_byte
```

#### Inter-Block Key Reconciliation
When control-flow paths converge at a join point $B_{\mathrm{join}}$ ($B_1 \to B_{\mathrm{join}}$ and $B_2 \to B_{\mathrm{join}}$), the final keystream states $\mathrm{VKEY}(B_1)$ and $\mathrm{VKEY}(B_2)$ may diverge.
- **Resolution**: A transition handler (`KEY_ADJUST`) is inserted on edge $B_2 \to B_{\mathrm{join}}$:
  $$\mathrm{VKEY}_{\mathrm{target}} = \mathrm{VKEY}_{\mathrm{current}} \oplus \Delta_{\mathrm{block}}$$

---

### Algorithm 4: Relative-Delta Dispatching

Instead of an exposed jump table, handlers terminate with relative offset dispatch sequences:

```x86asm
; Handler epilogue
; VIP points to next encrypted delta byte
movzx eax, byte ptr [VIP]
add   VIP, 1
xor   eax, VKEY               ; Decrypt delta
add   VKEY, eax               ; Update keystream
add   VDISP, eax              ; VDISP = VDISP + delta
jmp   VDISP                   ; Jump to next polymorphic handler
```

- Zero handler pointer arrays exist in the compiled binary.
- Handlers are distributed pseudo-randomly across the text segment with interleaved junk padding.
- Reconstructing the VM control-flow graph through static signature matching is neutralized.

---

## 6. Polymorphic Runtime Synthesizer

On every module compilation:

1. **Random Register Assignment**:
   Architecture registers are mapped randomly to non-overlapping hardware registers:
   - x86-64: $\{\mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}\} \subset \{\mathrm{RAX}, \mathrm{RBX}, \mathrm{RCX}, \mathrm{RDX}, \mathrm{RSI}, \mathrm{RDI}, \mathrm{R8}..\mathrm{R15}\}$
   - AArch64: $\{\mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}\} \subset \{\mathrm{X19}..\mathrm{X28}\}$
   - RV64: $\{\mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}\} \subset \{\mathrm{s1}..\mathrm{s11}\}$
2. **Context Slot Permutation**:
   The offset of native register $R_k$ in context array $\mathcal{C}[R_k]$ is governed by random permutation $\pi \in S_N$.
3. **Handler Mutation**:
   Handlers are injected with equivalent syntactic variants:
   - Replacement of `add a, b` with `sub a, -b` or LEA sequences.
   - Insertion of dead-code-resistant opaque predicates.

---

## 7. Implementation Roadmap (Phases 1 to 7)

### Phase 1: Intermediate Representation and Lowering (Stack-IR)
- [x] **1.1 Stack-IR Type Definition in OCaml**:
  Module `lib/stack_vm/stack_ir.ml` / `stack_ir.mli`:
  - Type `stack_op = PushImm of int64 | PushReg of int | PopReg of int | ReadMem of int | WriteMem of int | Nor | Nand | Add | Sub | Mul | Div | Shl | Shr | Dup | Swap | JmpRel of int | JccRel of int * condition | KeyAdjust of int64 | Exit`
  - Stack weight calculations: `push_weight`, `pop_weight`, `delta_vsp`.
  - Serializer, deserializer, and debug pretty-printer (`to_string`, `print_program`).
- [x] **1.2 Lowering Pass `lib/stack_vm/ir_to_stack.ml` and Context Allocator**:
  - Implemented `lib/stack_vm/context_allocator.ml` / `context_allocator.mli` with randomized register slot permutations (GPR + VREG).
  - Translated 3-address `Ir.t` to `Stack_ir.program` (`lower_block`, `lower_program`).
  - Verified with property-based unit tests.

### Phase 2: Optimization and Obfuscation Passes
- [x] **2.1 Universal Logic Reduction Pass (`lib/stack_vm/stack_logic_pass.ml`)**:
  - Substituted NOR/NAND expansions for boolean operations (`NOT`, `AND`, `OR`, `XOR`).
  - Verified 5-gate XOR decomposition in Peirce basis without truth-table degradation.
  - Configurable basis selection: `NorBasis`, `NandBasis`, `MixedBasis`.
- [x] **2.2 Stack Balance Verification Pass**:
  - Module `lib/stack_vm/stack_balance_pass.ml` / `stack_balance_pass.mli`:
  - Static stack depth analyzer `analyze_stack_balance`.
  - Invariant assertion $\Delta \mathrm{VSP} = 0$ on block exit edges.
  - Automated remediation `repair_stack_balance` inserting garbage scrubs or alignment padding.

### Phase 3: Bytecode Generation and Cryptor
- [x] **3.1 Rolling-Key Encoder (`lib/stack_vm/stack_encoder.ml`)**:
  - Implemented rolling-key generator (`step_key`, 64-bit circular rotate and XOR constants).
  - Bidirectional encoding and decoding (`encode_program`, `decode_program`).
  - Inter-block key reconciliation (`reconcile_keys` injecting `KeyAdjust`).
- [x] **3.2 Bytecode Serialization**:
  - Packed variable-length opcodes and 64-bit arguments into contiguous byte arrays.
- [x] **3.3 Reference Stack Evaluator (`lib/stack_vm/stack_eval.ml`)**:
  - Interpreter `eval_program` executing `Stack_ir.program`.
  - Interpreter `eval_encrypted` with in-flight stream decryption during execution.

### Phase 4: Target Runtime Synthesizer
- [x] **4.1 Multi-Platform Runtime Generator (`lib/stack_vm/stack_runtime.ml`)**:
  - Emitted entry stubs `vm_enter` (context preservation, state initialization).
  - Emitted handlers `PUSH_IMM`, `PUSH_REG`, `POP_REG`, `READ_MEM`, `WRITE_MEM`, `NOR`, `NAND`, `ADD`, `SUB`, `DUP`, `SWAP`, `KEY_ADJUST`.
  - Emitted relative dispatchers for x86-64, AArch64, and RV64.
  - Emitted standalone portable C runtime (`emit_c_runtime`).

### Phase 5: Framework Integration
- [x] **5.1 Multi-Tier Engine Selector**:
  - CLI switch `--engine=stack` / `--engine=threaded` (`cli_protect.ml`, `cli_protect_arm64.ml`).
  - Automated packaging into `stack_vm_runtime.hpp` with invocation trampolines.
- [x] **5.2 Test Verification**:
  - Test suite `test/test_stack_vm.ml` with 8 comprehensive suites (Stack IR, Context Allocator, Logic Pass, IR Lowering, Stack Balance, Rolling Key, Multi-Target Runtime, Stack VM Extensions).
  - Fully integrated into `test/run_tests.ml`.
- [x] **5.3 Decompiler Resilience Auditing via `idasql`**:
  - SQL verification pipeline against IDA Pro databases (see [`idasql.md`](idasql.md)).
  - Verified 0 string leaks, elimination of function symbols, and disrupted Hex-Rays pseudocode.
  - Confirmed CFG fragmentation with `JUMPOUT(...)` directives neutralizing Hex-Rays data-flow analysis.
  - Constant table converted to FNV-1a hashing with lazy XOR decryption, removing `_strcmp` and `_strlen` imports.
  - Fail-closed guards protecting against stack underflow/overflow and context bounds violations.

### Phase 6: Anti-VMPredator Address Binding
- [x] **6.1 Address-Bound Bytecode**:
  - Protection against generic memory dumpers and symbolic devirtualizers (VMPredator, NoVmp).
  - In C++ runtime (`stack_vm_runtime.hpp`), all 29 handlers are standalone functions whose addresses populate `g_stack_handler_table`.
  - `derive_addr_key()` computes a 64-bit hash of inter-handler address deltas (`addr[i] - addr[i-1]`), invariant under ASLR and PIE module base shifts, yielding address key $D$.
- [x] **6.2 Key Literal Masking (`Stack_encoder`)**:
  - Field `addr_mask` in `encrypted_bytecode`. Key literals (`seed_key`, `block_keys`) are pre-XORed with mask $D$ (`Stack_encoder.apply_addr_mask`).
  - Ciphertext bytes remain unchanged; only header and join-point key literals are shifted.
  - Runtime folds the mask back: `vm.addr_key = derive_addr_key(); vm.vkey ^= vm.addr_key;`, with `h_jmp_rel` and `h_jcc_rel` folding `vm.addr_key` during block reconciliation.
- [x] **6.3 Two-Stage Probe Compilation**:
  - Micro-probe `Stack_runtime.emit_probe_cpp` compiled under identical flags (`-O3`, dead-strip, RTTI/EH disabled) as `addr_probe.cpp`.
  - Pipeline executes `addr_probe`, captures `ADDR_KEY`, calculates $D$, and rewrites `stack_vm_runtime.hpp` via `rebind_address`.
  - Fallback mode with mask 0 if compilation fails.
- [x] **6.4 Verification**:
  - `test_addr_mask_unit`: verifies ciphertext bitwise invariance and reversibility of `apply_addr_mask`.
  - `test_addr_mask_wrong_key`: verifies failure and devirtualization interruption under invalid key $D'$.
  - `test_address_bound_c_runtime_probe_and_run`: E2E probe compilation, key resolution, header rebinding, and native runner execution against reference interpreter.

### Phase 7: Payload Integrity Authentication and Guest Memory Policy
- [x] **7.1 Keyed Payload Integrity Tag (`Stack_encoder.payload_tag`)**:
  - Added `payload_tag` and `tag_keys` (two MAC key halves under identifiers 0 and 1, masked via `mask64`).
  - Tag computed as CBC-MAC over ciphertext: `asg_siphash12` (mirroring `Stack_encoder.siphash_block`, SipHash-1-2) in CBC mode, absorbing domain separation and length parameters prior to 64-bit words.
  - MAC keys are domain-separated from block keys and from each other via PRF derivations (`Stack_encoder.payload_tag_keys`). Tag is computed from effective (unmasked) seed, rendering it invariant under `apply_addr_mask`.
  - Runtime verifies tag in `asg_payload_auth_ok` **prior to the initial fetch** (`stack_vm_run`). On mismatch, the VM halts fail-closed without decoding a single byte, using constant-time comparison.
  - Authentication failure contract: zeroized context, reset `vsp_idx`, and uniform exit status identical to key rejection.
- [x] **7.2 Instruction Fetch Bounds Enforcement (`fetch_byte`)**:
  - Bound field `bc_size` in `stack_vm_t`; `stack_vm_run` validates `vip < bc_size` before every byte read, halting out-of-bounds execution.
- [x] **7.3 Guest Memory Access Policy (`asg_mem_access_ok`)**:
  - `READ_MEM` / `WRITE_MEM` access policies enforce width $\in \{1, 2, 4, 8\}$, non-null address, natural alignment, canonical 64-bit pointers (sign-extended bits 63:48), and upper bound overflow checks.
  - Mirrored in OCaml reference evaluator `Stack_eval.mem_access_ok`.

---

## Security Invariants and Constraints

1. **Tamper-Evidence vs. Secret Isolation**: The MAC key derives from the embedded seed; therefore, the payload tag provides tamper-evidence and enforcement, but does not substitute for hardware-rooted or remote key distribution.
2. **Decompiler Disruption**: Local validation logic remains susceptible to symbolic execution if unvirtualized; obfuscation must be combined with symbol stripping and dead-code elimination.
3. **Source Distribution**: Handlers `h_push_imm` through `h_test` reside in generated C++ translation units. Production security relies on compilation with full optimizations (`-O3`), inlining, and dead-stripping.
