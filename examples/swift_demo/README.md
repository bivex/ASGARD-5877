# ASGARD-5877: Swift Application Protection Example

This example demonstrates how to protect macOS and iOS Swift applications using the **ASGARD-5877 Polymorphic VM Protection Pipeline**.

---

## 1. The Challenge of Protecting Swift Applications

Swift compiles to native machine code via LLVM, but retains extensive runtime metadata in Mach-O binaries:
- **Exposed Symbol Table & Class Hierarchy:** Swift classes, methods, and closures emit reflection metadata (`__swift5_proto`, `__swift5_types`, `__swift5_fieldmd`) that decompilers (Hopper, IDA Pro, Ghidra) reconstruct with 100% fidelity.
- **Trivial Patch Points:** License validation logic written in pure Swift produces simple condition checks (`cbz`, `cbnz`, `tbz`, `tbnz`, `csel`) that reverse engineers bypass with a single nop or branch inversion (`b` / `nop`).
- **String & Constant Leakage:** Strings and cryptographic keys in Swift are stored as plaintext UTF-8 chunks or easily recoverable globals.

---

## 2. The ASGARD-5877 Solution

ASGARD-5877 virtualizes high-value security routines into a **custom, polymorphic virtual machine**:
1. **Instruction Set Virtualization:** The native ARM64 instructions are lifted into ASGARD VM-IR, which is then lowered into dynamic Stack-VM or Direct-Threaded VM bytecode.
2. **10-Phase Hardening Pipeline:**
   - **Superoperator Fusion:** Fuses common instruction combinations into monolithic opcodes.
   - **Bytecode Amplification:** Expands scalar logic through high-degree polynomials (Horner expansion) and bit-slice networks.
   - **Mixed Boolean-Arithmetic (MBA):** Synthesizes non-linear Zhou/Eyrolles identities that resist SMT solvers (Z3).
   - **Virtual Control Flow Flattening (CFF):** Eliminates native basic blocks; transitions route through an encrypted Virtual Program Counter (VPC) dispatcher.
   - **Spaghetti CFG Splitting:** Destructures linear execution paths into pseudo-random interconnected graph nodes.
   - **Ghost Stack Padding:** Injects entangled fake stack computations to defeat taint tracking and symbolic execution.
   - **State-Feedback Rolling Key:** Decrypts bytecode dynamically instruction-by-instruction based on runtime execution history.
   - **VSP Stack Whitening & Opcode Permutation:** Generates unique opcode tables and memory layouts per compilation.
3. **Swift Native C-ABI Bridge:** The Swift layer communicates with the virtual machine over the zero-overhead C ABI (`@_silgen_name` or Clang bridging header).

```
+-------------------------------------------------------------+
|                      Swift Application                      |
|       (UI / Business Logic / State Machine / Networking)    |
+-------------------------------------------------------------+
                              │
               @_silgen_name("asgard_verify_license")
                              ▼
+-------------------------------------------------------------+
|                     C++ Native Bridge                       |
|               asgard_verify_license(key, hash)              |
+-------------------------------------------------------------+
                              │
                 vanguard_threaded_vm::asgard_vm_call()
                              ▼
+-------------------------------------------------------------+
|              ASGARD-5877 Polymorphic Stack-VM              |
|  - Encrypted Dynamic Bytecode (Rolling Key Cipher)          |
|  - Virtual Program Counter (VPC) Dispatcher Loop            |
|  - Mixed Boolean-Arithmetic (MBA) Transformation Engine     |
|  - Ghost Stack Padding & Whitebox Entropy Feedback          |
+-------------------------------------------------------------+
```

---

## 3. Directory Layout

```
examples/swift_demo/
├── README.md                      # Architecture documentation & guide
├── build_swift.sh                 # End-to-end automated build & run script
└── Sources/
    ├── Core/
    │   └── license_core_arm64.s   # High-value ARM64 validation core
    ├── Bridge/
    │   ├── LicenseBridge.h        # C ABI export interface for Swift
    │   └── LicenseBridge.cpp      # Dispatches Swift calls to asgard_vm_call()
    └── App/
        └── main.swift             # High-level Swift application with LicenseGuard
```

---

## 4. Building and Running

### Prerequisites
- macOS on Apple Silicon (`arm64`)
- Swift 5.9+ / Swift 6 (`swiftc`)
- Clang with C++17 support (`clang++`)
- OCaml 4.14+ with Dune (to build ASGARD-5877)

### Automated Build
Run the build script from the repository root:

```bash
./examples/swift_demo/build_swift.sh
```

The script will:
1. Build `_build/default/bin/main.exe` (ASGARD compiler CLI).
2. Run `protect-arm64` on `Sources/Core/license_core_arm64.s` with `--engine=stack --cff --mba --mba-depth 4`.
3. Extract the encrypted polymorphic bytecode.
4. Compile the C++ VM bridge into `LicenseBridge.o`.
5. Compile `main.swift` via `swiftc -O` and link against the protected VM runtime.
6. Launch `./build/protected_swift_app`.

---

## 5. Reverse Engineering Analysis

When an analyst opens the protected Swift binary in a disassembler:

### In Unprotected Swift:
```text
_$s4main12LicenseGuardV6verify3key12expectedHashSbSb_tF:
    eor     x8, x0, #0x5877
    mov     w9, #42
    mul     x8, x8, x9
    add     x8, x8, #0x1337
    cmp     x8, x1
    cset    w0, eq          <--- Trivial patch: change to `mov w0, #1` or invert flag
    ret
```

### In ASGARD-Protected Swift:
1. `LicenseGuard.verify()` transfers control via a single indirect jump:
   ```arm64
   bl   _asgard_verify_license
   ```
2. `_asgard_verify_license` invokes the ASGARD VM dispatcher:
   ```arm64
   b    __ZN20vanguard_threaded_vm14asgard_vm_callEPKymy...
   ```
3. The original arithmetic, branching, and comparison instructions do not exist in the native text segment. Instead, IDA Pro / Hopper encounters:
   - A 45+ KB encrypted bytecode blob with near-maximum Shannon entropy (7.995 / 8.0).
   - An opaque VPC dispatcher with randomized opcode tables and rolling XOR keys.
   - Dead code traps and self-checking canaries that poison register states upon debugging or memory modification.
