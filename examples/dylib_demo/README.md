# ASGARD-5877: Shared Dynamic Library (.dylib / .so) Example

This example demonstrates how to build and protect a **shared dynamic library** (`.dylib` on macOS/Darwin, `.so` on Linux/Android) using the **ASGARD-5877 Polymorphic Virtual Machine Engine** and the **C Obfuscation Macro SDK**.

It illustrates:
1. **How macros work inside a dynamic library** (demarcation, string encryption, and Mixed Boolean-Arithmetic).
2. **How the virtual machine executes inside a dynamic library** (Position-Independent Code, thread-local guest stacks, dynamic chunk canary verification, and rolling key cipher dispatch).
3. **How host applications (C++ and Swift) dynamically load (`dlopen`/`dlsym`) and execute the virtualized routines.**

---

## 1. Dynamic Library Security Architecture

```
+-------------------------------------------------------------------------------+
|                       Host Application (C++ or Swift)                         |
|   - dlopen("./libasgard_security.dylib", RTLD_NOW)                            |
|   - dlsym(handle, "asgard_verify_license")                                    |
|   - dlsym(handle, "asgard_derive_token")                                      |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼ Dynamic Symbol Dispatch (C-ABI)
+-------------------------------------------------------------------------------+
|                  libasgard_security.dylib (Export Surface)                    |
|   - asgard_verify_license(key, hwid)                                          |
|   - asgard_derive_token(session, nonce)                                       |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼ In-Place VM Trampoline
+-------------------------------------------------------------------------------+
|            ASGARD Polymorphic Virtual Machine Runtime (PIC)                   |
|   1. Dynamic Chunk Integrity: Canary validation (`__break(1u)` on tamper)    |
|   2. Key Derivation: Unmasks bytecode via `k_dyn = seed ^ (chunk_id * prime)`|
|   3. Memory Barrier: `__dmb(0xBu)` before execution                           |
|   4. Virtual Machine Call: `vanguard_threaded_vm::asgard_vm_call()`           |
|      - Thread-local guest stack allocation (1 MB isolated sandbox)            |
|      - Argument marshalling (`x0`..`x7` mapped to guest registers)            |
|      - Virtual Program Counter (VPC) state dispatcher loop                    |
|      - Instruction-by-instruction rolling key mutation (`__ROR8__`)           |
+-------------------------------------------------------------------------------+
```

---

## 2. How Macros Work Inside the Dynamic Library

### A. Demarcation Macros (`ASGARD_BEGIN_VIRTUALIZE` / `ASGARD_END`)
Defined in `asgard_obf.h`:
```c
#if defined(__arm64__) || defined(__aarch64__)
#define ASGARD_BEGIN_VIRTUALIZE(tag) \
    __asm__ volatile ("b 1f \n\t .ascii \"ASGARD_BEG_V____\" \n\t .balign 4 \n 1:\n\t" ::: "memory")
#define ASGARD_END() \
    __asm__ volatile ("b 1f \n\t .ascii \"ASGARD_END______\" \n\t .balign 4 \n 1:\n\t" ::: "memory")
#endif
```
- When Clang compiles the library, it preserves these markers inline in the emitted assembly.
- ASGARD's ARM64 lifter parses the markers, strips the native instructions between them, and translates them into encrypted bytecode chunks.
- The function body in the `.dylib` is reduced to an assembly stub invoking `asgard_vm_call()`.

### B. Mixed Boolean-Arithmetic Macros (`ASG_MBA_ADD`, `ASG_MBA_XOR`)
Used to expand algebraic relationships into non-linear boolean networks resisting SMT solvers:
```c
uint64_t hash = ASG_MBA_ADD((license_key ^ secret) * mult, salt);
```
Expands using Zhou / Eyrolles identities:
```c
#define ASG_MBA_ADD(a, b) (((a) ^ (b)) + 2 * ((a) & (b)))
```

### C. Stack String Encryption (`ASG_STR`)
String literals are encrypted at compile time and decrypted onto volatile stack buffers (`_alloca` / `__builtin_alloca`), disappearing upon function return:
```c
const char* msg = ASG_STR(((const uint8_t[]){ 0x76, 0x29, 0xCE, ... }), 14, 0x1337);
```
No cleartext strings land in the `.dylib`'s Mach-O `__cstring` section.

---

## 3. How the Virtual Machine Works Inside the `.dylib`

1. **Strict Position-Independent Code (PIC):**
   Shared libraries can be loaded at arbitrary virtual addresses by `dyld` (macOS) or `ld-linux` (Linux). The ASGARD VM runtime uses relative addressing and avoids fixed pointers, making it fully ASLR-compatible.
2. **Thread-Local Isolated Guest Stack:**
   Every execution allocates an isolated thread-local 1 MB memory area for guest operand evaluation, guaranteeing reentrancy and thread safety across multiple host threads calling the `.dylib`.
3. **Decoy Canaries & Anti-Tamper Traps:**
   Bytecode is partitioned into randomized chunks. Prior to execution, chunk integrity is verified:
   ```c
   if (c->canary != ((c->chunk_id * 0xdeadU + 0xcafeU) & 0xffffffffU)) {
       __break(1u); // Trap debugger / memory patcher
   }
   ```
4. **Automatic Constructor Assembly:**
   `__attribute__((constructor))` automatically initialises and verifies bytecode structures when the dynamic library is loaded by the OS via `dlopen()`.

---

## 4. Directory Layout

```
examples/dylib_demo/
├── README.md                      # Architecture documentation & audit guide
├── build_dylib.sh                 # Automated build script for dylib and clients
├── audit_idasql.sh                # Automated IDA Pro + idasql security audit
└── Sources/
    ├── Lib/
    │   ├── asgard_security.h      # Public C-ABI interface header
    │   ├── asgard_security.c      # Protected library implementation (macros + VM)
    │   └── asgard_obf.h           # ASGARD C/C++ obfuscation macro SDK
    └── Host/
        ├── host_runner.cpp        # C++ dynamic client (dlopen/dlsym)
        └── host_runner.swift      # Swift dynamic client (dlopen/dlsym)
```

---

## 5. Building and Running

### Build and Run Both Clients
```bash
./examples/dylib_demo/build_dylib.sh
```

**Observed Output:**
```text
==================================================================
🛡️  ASGARD-5877: Building Protected .dylib Shared Library
==================================================================
[*] Step 1/3: Virtualizing C Library Routines via ASGARD Engine...
=== ASGARD-5877 Stack-VM Protection Report ===
- Architecture: Threaded VM (Direct Threading + Rolling Key)
- Devirtualization Resistance Score (DRS): 93.7 / 100.0
- Shannon Entropy: 7.9964 / 8.0 (100.0%)
[*] Step 2/3: Compiling Position-Independent Shared Library (.dylib)...
✅ Dynamic Library Generated: build/libasgard_security.dylib
0000000000000ddc T _asgard_derive_token
0000000000000940 T _asgard_verify_license

[*] Step 3/3: Validating Dynamic Library from Host Clients...
[*] Compiling C++ Host Client...
[*] Launching C++ Host Client (Testing dlopen/dlsym on .dylib):
==================================================================
🛡️  C++ Host Client: Dynamic Loading of ASGARD .dylib Runtime
==================================================================
[*] Opening dynamic library via dlopen: build/libasgard_security.dylib
[+] Symbols successfully resolved:
    asgard_verify_license -> 0x102694940
    asgard_derive_token   -> 0x102694ddc

[*] 1. Invoking asgard_verify_license() across dylib boundary:
    Genuine Key (0x1337, Hash 0xC6BB7): ✅ ACCESS GRANTED
    Tampered Key:                               ✅ ACCESS DENIED (Rejected by VM)

[*] 2. Invoking asgard_derive_token() across dylib boundary:
    Session: 0x64, Nonce: 0x2A
    Computed Token: 0xB7575
    Expected Token: 0xB7575
    Verification:   ✅ 100% MATHEMATICAL MATCH
==================================================================

[*] Launching Swift Host Client (Testing dynamic binding from Swift):
==================================================================
🛡️  Swift Host Client: Dynamic Loading of ASGARD .dylib Runtime
==================================================================
[*] 1. Invoking asgard_verify_license() from Swift:
    Genuine Key (0x1337):  ✅ ACCESS GRANTED
    Tampered Key:              ✅ REJECTED BY VM

[*] 2. Invoking asgard_derive_token() from Swift:
    Actual Token:   0xB7575
    Expected Token: 0xB7575
    Match Status:   ✅ 100% MATHEMATICAL MATCH
==================================================================
```

---

## 6. Security Audit via `idasql`

Run the automated IDA Pro security audit:
```bash
./examples/dylib_demo/audit_idasql.sh
```

### Audit Findings in Hex-Rays Pseudocode:
Both exported functions (`_asgard_verify_license` and `_asgard_derive_token`) in the `.dylib` are stripped of their native instructions and reduced to chunk unmasking and VM dispatch:

```c
__int64 __fastcall asgard_verify_license(unsigned __int64 a1, unsigned __int64 a2, ...)
{
  if ( embedded_bytecode_asgard_verify_license_assembled )
    return vanguard_threaded_vm::asgard_vm_call(
             embedded_bytecode_asgard_verify_license,
             len, a1, a2);

  // Dynamic chunk unmasking & canary verification loop
  while ( 1 ) {
    if ( chunk->canary != 57005 * id + 51966 )
      __break(1u); // Anti-tamper trap

    // Unmask words via Fibonacci-prime stride
    k = (0x9E3779B97F4A7C15LL * id) ^ 0x5877A56A11223344LL;
    ...
  }
}
```

The original mathematical equations:
- `((license_key ^ 0x5877) * 42) + 0x1337 == hwid`
- `((session_id ^ 0x5877) * 31) + nonce + 0xCAFE`
**do not exist in the `.dylib` machine code or decompiled AST.**
