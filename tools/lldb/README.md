# ASGARD-5877 LLDB Bytecode Debugger Plugin

Comprehensive LLDB extension plugin designed for inspecting, debugging, disassembling, and stepping through virtual bytecode generated and executed by the ASGARD protection engines:

1. **Native Threaded VM (`vanguard_threaded_vm`)**:
   - Dynamic affine register permutation ($\pi \in S_{32}$, $phys = (i \cdot A + B) \bmod 32$)
   - Per-slot canary masks and global register mask unmasking
   - Anti-Pushan positional PRF and in-block rolling keystream derivation
   - Virtual architectural GPRs (RAX..R15), flags (CF, ZF, SF, OF, PF, ARM64_C), and security state
   - Circular x87 FPU stack ST(0)..ST(7)
   - Cryptographic register mutation (`asg-set-reg`)

2. **Stack VM (`stack_vm_t`)**:
   - Blinded VSP stack encryption with dynamic slot whitening (`asg_vsp_mask`)
   - 40 polymorphic opcode specifications and Costas-6 randomized field layouts
   - SipHash-1-2 per-block key derivation and Murmur3 fmix64 rolling steps
   - Virtual context slots (`ctx[0..63]`), flags, and execution status

---

## Installation & Setup

In LLDB:
```lldb
(lldb) command script import /path/to/ASGARD-5877/tools/lldb/asgard_lldb.py
```

To auto-load on every LLDB launch, add the command to `~/.lldbinit`:
```sh
echo "command script import $(pwd)/tools/lldb/asgard_lldb.py" >> ~/.lldbinit
```

---

## Command Reference

| Command | Aliases | Description |
|---|---|---|
| `asg-help` | | Print the debugger command manual and syntax |
| `asg-status` | | Inspect active VM engine, context pointer, vIP, and security status |
| `asg-regs` | `asg-r` | Dump unmasked architectural registers, flags, and keys |
| `asg-stack` | `asg-vsp` | Dump unmasked virtual stack entries (TOS and frames) |
| `asg-fpu` | | Dump virtual x87 FPU stack ST(0..7) and status word |
| `asg-disas` | `asg-d` | Disassemble virtual instructions at current or specified vIP |
| `asg-step` | `asg-s` | Single-step forward by ONE virtual bytecode instruction |
| `asg-next` | `asg-n` | Step over virtual call or to next bytecode instruction |
| `asg-break` | `asg-b` | Set a virtual breakpoint at bytecode index: `asg-break <vIP>` |
| `asg-trace` | | Step $N$ virtual instructions, printing instruction and register diffs |
| `asg-set-reg` | | Modify a virtual register with cryptographic re-encryption |
| `asg-export` | | Export VM context, registers, and disassembly to JSON |

---

## Examples

### 1. Inspecting Virtual Registers
```lldb
(lldb) asg-regs
╔═══════════════════════════════════════════════════════════════════════════════╗
║ ASGARD Virtual Registers (VMContext @ 0x00016FDFF320)                         ║
╠═══════════════════════════════════════════════════════════════════════════════╣
  RAX    0x0000000000000037 (55          )   RCX    0x0000000000000000 (0           )
  RDX    0x0000000000000000 (0           )   RBX    0x0000000000000000 (0           )
  RSP    0x000000016FDFF6B0 (6171915952  )   RBP    0x000000016FDFF700 (6171916032  )
  RSI    0x0000000100003F40 (4294983488  )   RDI    0x0000000000000001 (1           )
  ...
─────────────────────────────────────────────────────────────────────────────────
  FLAGS:  CF=0  ZF=0  SF=0  OF=0  PF=1  ARM64_C=0
  STATUS: Canaries: OK | Trapped: False | Instructions: 4
  KEYS:   running_key=0x5877CAFE1337BEEF  data_key=0xA5A5A5A51337BEEF
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### 2. Disassembling Virtual Bytecode
```lldb
(lldb) asg-disas
[+] Native VM Disassembly (vIP: 0, seed: 0x5877A564):
-> [0000]  MOV_RI         rax, 0xa
   [0001]  ADD_RI         rax, 0x14
   [0002]  IMUL_RI        rax, 0x2
   [0003]  SUB_RI         rax, 0x5
   [0004]  RET
```

### 3. Virtual Stepping and Tracing
```lldb
(lldb) asg-step
[STEP] Stepped to vIP [0001] (Instruction #1) | Changes: RAX: 0x0 -> 0xA
-> [0001]  ADD_RI         rax, 0x14

(lldb) asg-trace 3
[+] Starting ASGARD Virtual Trace (3 steps)...
[STEP] Stepped to vIP [0002] (Instruction #2) | Changes: RAX: 0xA -> 0x1E
[STEP] Stepped to vIP [0003] (Instruction #3) | Changes: RAX: 0x1E -> 0x3C
[STEP] Stepped to vIP [0004] (Instruction #4) | Changes: RAX: 0x3C -> 0x37
```

### 4. Setting Virtual Breakpoints
```lldb
(lldb) asg-break 3
[+] Virtual Breakpoint #1 set at vIP == 3
(lldb) continue
Process stopped at virtual breakpoint vIP = 3.
```

### 5. Patching Virtual Registers Live
```lldb
(lldb) asg-set-reg rax 0x1337
[+] Successfully wrote RAX = 0x0000000000001337 (phys 14: gpr=0x..., mask=0x...)
```
