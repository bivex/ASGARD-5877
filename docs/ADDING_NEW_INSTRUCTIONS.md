# Adding New Instructions to the ASGARD-5877 VM Engine

Developer guide for adding native processor instructions (x86_64, ARM64, RISC-V) across all layers of the ASGARD-5877 virtualization pipeline.

---

## 1. Architectural Overview

The lifecycle of an instruction spans six distinct stages, from raw assembly parsing to direct-threaded execution in the hardened C++ runtime:

```
┌─────────────────────────────────────────┐
│ 1. Frontend Lifter                      │  lib/<arch>_lifter/
│    Assembly text -> Micro-IR            │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ 2. Micro-IR & Pipeline Passes           │  lib/vm_ir/
│    ir.mli, allocator, evaluator         │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ 3. Canonicalization                     │  lib/native_vm/vm_transform.ml
│    2-address forms, scratch registers   │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ 4. Bytecode Word Encoding               │  lib/native_vm/vm_emitter.ml
│    64-bit instruction word packaging    │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ 5. Runtime Handler                      │  lib/native_vm/vm_*_handlers.ml
│    C++20 Direct Threaded Code (&&label) │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ 6. Verification & Test Suite            │  test/
│    Reference VM Oracle + Native E2E     │
└─────────────────────────────────────────┘
```

---

## 2. Step-by-Step Implementation Guide

### Step 1: Micro-IR Definition (`lib/vm_ir/`)

1. **`lib/vm_ir/ir.mli` and `lib/vm_ir/ir.ml`**:
   - Add a new variant to `Ir.instr` (and any auxiliary opcode types if grouping instructions like `sha_op`, `atomic_op`, or `fp_conv_op`):

     ```ocaml
     (* lib/vm_ir/ir.mli *)
     type my_op = MyOp1 | MyOp2

     type instr =
       | ...
       | My_instr of {
           op : my_op;
           dst : Register.t;
           src : operand;
         }
     ```

2. **Exhaustive Pattern Matching Across IR Passes**:
   OCaml compiler warning 8 (partial-match) enforces that all transformation passes handle the new instruction:
   - `lib/vm_ir/register_allocator.ml` (`remap_instr`): remap all input and output registers so allocated context slots remain coherent across basic blocks.
   - `lib/vm_ir/superoperator.ml` (`of_instr` / `reads_flags` / `writes_flags`): track register dependencies and flag consumption to prevent illegal superoperator fusion across barrier boundaries.
   - `lib/vm_ir/subreg_write.ml`: handle sub-register truncation or zero-extension semantics for narrow writes (`B32`, `B16`, `B8`).
   - `lib/cff/cff.ml` (`is_reg_read_in_op`): track register reads for Control-Flow Flattening state dispatchers.

3. **Software Oracle in the Reference VM (`lib/vm_ir/vm_eval.ml`)**:
   - Implement the instruction's exact mathematical semantics in `eval_instr`.
   - For complex round algorithms (e.g. SHA-NI hashing, AES rounds), isolate the pure logic into a dedicated submodule (e.g. `lib/vm_ir/sha_ni.ml`).
   - *Requirement*: The Reference VM serves as the authoritative mathematical oracle for differential fuzzing and Stage-7 Equivalence Verification.

---

### Step 2: Frontend Lifter Integration (`lib/<arch>_lifter/`)

Implement mnemonic recognition and operand parsing in the corresponding architecture lifter:
- **x86-64**: `lib/x86_lifter/lifter.ml`
- **ARM64**: `lib/arm64_lifter/arm64_alu.ml`, `arm64_mem.ml`, `arm64_branch.ml`
- **RISC-V**: `lib/riscv_lifter/riscv_lifter.ml`

#### Lifter Rules:
1. **Implicit Registers**:
   If the instruction reads or writes implicit architectural registers (e.g. `SHA256RNDS2` implicitly reading `XMM0`, or `MUL` using `RDX:RAX`), expose them explicitly in the IR constructor (`src3 = Register.xmm0`).
2. **Zero Registers**:
   ARM64 zero registers (`xzr`/`wzr`) and RISC-V `x0` must discard writes without altering context state, and reads must return `0ULL`.
3. **Register Widths**:
   Always retain operand bit widths (`Register.get_width`). In x86_64 and ARM64, 32-bit writes strictly zero-extend into the upper 32 bits of the 64-bit parent register.

---

### Step 3: Canonicalization & Hazard Prevention (`lib/native_vm/vm_transform.ml`)

Before bytecode packaging, every basic block passes through `canonicalize_instr`.

Handle the instruction in `canonicalize_instr` if:
1. **Immediate operand exceeds word bitfield capacity**:
   For example, ARM64 `CCMP`/`CCMN` encodes only a 5-bit unsigned immediate (`0..31`). If the lifter emits `cmn w0, #100`, canonicalization must load the immediate into a temporary scratch register:
   ```ocaml
   | Ir.Ccmn { cond; src1 = Ir.Reg d; src2 = Ir.Imm imm; nzcv } when imm < 0L || imm > 31L ->
       let scratch = Register.with_width (pick_scratch_reg d d) (Register.get_width d) in
       [ Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm imm };
         Ir.Ccmn { cond; src1 = Ir.Reg d; src2 = Ir.Reg scratch; nzcv } ]
   ```
2. **Memory operands requiring register-only form**:
   If the opcode format only admits register operands, lower memory accesses (`Ir.Mem`) into scratch loads via `pick_scratch_reg`.
3. **Addressing Hazard (`dst = src1 OP dst`)**:
   For non-commutative operations, save the old `dst` value into a scratch register to prevent clobbering input operands during operand setup.

---

### Step 4: Opcode Registration & Bytecode Packaging (`lib/native_vm/`)

1. **`lib/native_vm/vm_transform.mli` and `lib/native_vm/vm_transform.ml`**:
   - Register the opcode in the `opcode` variant:
     ```ocaml
     | OP_MY_OP
     ```
   - Map the opcode to its handler label string:
     ```ocaml
     | OP_MY_OP -> "H_MY_OP"
     ```
   - Append `OP_MY_OP` to `all_opcodes`.

2. **Bytecode Emission (`lib/native_vm/vm_emitter.ml`)**:
   In `compile_and_package_multi`, add an emission rule:
   ```ocaml
   | Ir.My_instr { op; dst; src } ->
       encode_raw_word ~extra_bits:(Int64.of_int (my_op_code op))
         (get_opcode OP_MY_OP) (get_reg_idx dst) (get_reg_idx src) imm
   ```

#### 64-Bit Native VM Instruction Word Layout:
* Bits `0..7`: Opcode (8 bits).
* Bits `8..12`: Destination register index `dst` (5 bits).
* Bits `13..17`: Source register index `src` (5 bits).
* Bits `18..56`: Immediate / packed secondary operands (39 bits).
* Bits `57..63`: `extra_bits` (dialect tags, width codes, sub-opcodes).

---

### Step 5: Direct-Threaded C++ Runtime Handler (`lib/native_vm/vm_*_handlers.ml`)

Implement the runtime handler in the appropriate category module:
- `vm_alu_handlers.ml` — Arithmetic, logic, bit manipulations, flags.
- `vm_mem_handlers.ml` — Memory loads/stores, SIMD vector registers, atomics, system calls.
- `vm_control_handlers.ml` — Branches, calls, returns, dispatcher bridges.

#### Core Principle: Cross-Platform Portability
> Handlers must be written in **portable C++20**, avoiding host-locked intrinsics (e.g. `__builtin_ia32_*` or ARM NEON intrinsics).
>
> This guarantees that a protected binary virtualizing x86-64 code can execute cleanly on Apple Silicon (ARM64), and vice versa.

Handler Template:
```cpp
H_MY_OP: {
    const uint64_t a = ctx.get_reg(dst);
    const uint64_t b = ctx.get_reg(src);
    const uint64_t res = (a ^ b); // execution logic
    ctx.set_reg(dst, res);
    
    // Flag computation if applicable:
    ctx.zf = (res == 0);
    ctx.sf = (static_cast<int64_t>(res) < 0);
    
    // Advance virtual instruction pointer to next handler:
    NEXT_INSTR;
}
```

*For emission via typed AST, use `emit_handler_ast` or string buffers via `Buffer.add_string`.*

---

### Step 6: Stack-VM Engine Lowering (`lib/stack_vm/ir_to_stack.ml`)

If the instruction is supported by the universal logic Stack-VM:
- Map `Ir.instr -> stack_op list` in `lib/stack_vm/ir_to_stack.ml`.
- If unsupported (e.g. 128-bit SIMD or SHA-NI extensions), terminate execution explicitly:
  ```ocaml
  | Vec_sha _ -> [Exit]
  ```

---

## 3. Verification & Testing

Under `AGENTS.md`, every code modification must be verified against target test suites before committing.

### 1. Lifter Unit & Reference VM Test
Add a test case in `test/test_<arch>_lifter.ml`:
- Provide an assembly snippet.
- Lift using `Lifter.lift_function`.
- Set up initial state with `make_state ()`.
- Evaluate using `run_func state func`.
- Assert register values and flags against the hardware specification (Intel SDM / ARM ARM).

### 2. End-to-End Native Execution Test
Add an E2E test in `test/test_native_semantics.ml`:
- Package bytecode with `Vm_emitter.compile_and_package`.
- Compile and execute the direct-threaded C++ runtime via `run_custom_vm`.
- Check exit codes and register file outputs.

### 3. Targeted Suite Execution
```bash
# Build test runner
dune build test/run_tests.exe

# Run individual test by index
_build/default/test/run_tests.exe test "x86_64 Lifter & CFG" 33

# Run targeted suite
_build/default/test/run_tests.exe test "x86_64 Lifter & CFG"
```

---

## 4. Pre-Commit Checklist

- [ ] New `Ir.instr` variant declared; `.mli` interfaces updated.
- [ ] Pattern matching covered across all passes in `lib/vm_ir/` (zero compiler warnings).
- [ ] Reference VM (`vm_eval.ml`) implements correct mathematical semantics.
- [ ] Opcode registered in `vm_transform.ml` and included in `all_opcodes`.
- [ ] Canonicalization handles oversized immediates and register hazards.
- [ ] C++ handler written in portable C++ without platform-locked intrinsics.
- [ ] Unit and E2E tests added and passing.
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`.
- [ ] Conventional Commit format applied (`feat(x86): ...`, `feat(arm64): ...`).
