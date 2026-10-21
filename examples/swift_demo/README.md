# ASGARD-5877: Pure Swift Zero-Bridge Protection & idasql Audit

This project demonstrates the **Zero-Bridge Swift Protection Pipeline** for macOS and iOS (Apple Silicon ARM64), verified via automated **`idasql`** security audits.

---

## 1. Why Zero-Bridge?

In legacy obfuscation setups, protecting Swift code required:
1. Writing separate C/C++ or assembly files (`.c`, `.cpp`, `.s`).
2. Creating manual C-bridge headers (`.h`) and glue wrappers.
3. Marshalling arguments manually and declaring `@_silgen_name`.
4. Leaving secondary Swift methods and string literals exposed in cleartext.

With ASGARD-5877's **Zero-Bridge Pipeline**:
- The developer writes **100% pure Swift**.
- Sensitive routines are marked via `@_cdecl` / Swift Macro.
- String literals are encrypted in-place via compile-time XOR macros (`asg_str`).
- The build pipeline compiles Swift to ARM64 assembly, extracts the designated routines, virtualizes them into dynamic Stack-VM bytecode, and replaces the native function bodies with an opaque branch to the auto-synthesized VM dispatcher.
- Zero manual C/C++ glue code required.

---

## 2. Architecture & Data Flow

```
+-------------------------------------------------------------------+
|               Pure Swift Application (Sources/App/main.swift)     |
|   - In-place string encryption (asg_str)                          |
|   - Pure Swift validation logic (verify_license)                  |
+-------------------------------------------------------------------+
                                  │
                                  ▼
+-------------------------------------------------------------------+
| 1. Swift Frontend Compiler (`swiftc -emit-assembly`)              |
|    - Emits raw ARM64 machine instructions                         |
+-------------------------------------------------------------------+
                                  │
                                  ▼
+-------------------------------------------------------------------+
| 2. ASGARD Stack-VM Virtualization (`protect-arm64 --engine=stack`)|
|    - Lifts ARM64 instructions into VM-IR                          |
|    - Ten-phase polymorphic obfuscation:                           |
|        * Superoperator Fusion & Bytecode Amplification (Horner)   |
|        * Mixed Boolean-Arithmetic (MBA) Constant Synthesis        |
|        * Virtual CFG Flattening & Spaghetti Block Splitting       |
|        * Ghost Stack Padding & State-Feedback Rolling Key Cipher  |
|    - Emits encrypted bytecode and auto-synthesizes VM dispatcher  |
+-------------------------------------------------------------------+
                                  │
                                  ▼
+-------------------------------------------------------------------+
| 3. In-Place Assembly Trampoline Patching                          |
|    - Replaces both C-ABI and Swift-mangled entrypoints with `b`   |
|      into `_asgard_vm_entry_verify_license`                       |
+-------------------------------------------------------------------+
                                  │
                                  ▼
+-------------------------------------------------------------------+
| 4. Native Linking (`swiftc -O`)                                   |
|    - Produces hardened standalone Mach-O binary                   |
+-------------------------------------------------------------------+
```

---

## 3. Directory Layout

```
examples/swift_demo/
├── README.md                      # Architecture documentation & audit report
├── build_swift.sh                 # Zero-bridge automated build & link pipeline
├── audit_idasql.sh                # Automated IDA Pro + idasql security audit
└── Sources/
    └── App/
        └── main.swift             # Pure Swift application with string encryption
```

---

## 4. Building and Auditing

### Prerequisites
- macOS on Apple Silicon (`arm64`)
- Swift 5.9+ / Swift 6 (`swiftc`)
- Clang with C++17 support (`clang++`)
- IDA Pro 9.x (`idat`) and `idasql` CLI utility

### 1. Build Protected Binary
```bash
./examples/swift_demo/build_swift.sh
```

Output:
```text
==================================================================
🛡️  ASGARD-5877: Pure Swift Zero-Bridge Protection Pipeline
==================================================================
[*] Step 1/6: Compiling pure Swift to ARM64 assembly via swiftc...
[*] Step 2/6: Extracting target Swift function (_verify_license)...
[*] Step 3/6: Virtualizing ARM64 logic into ASGARD Stack-VM Bytecode...
=== ASGARD-5877 Stack-VM Protection Report ===
- Architecture: Stack-VM Execution Engine (Universal Logic + Rolling Key)
- Devirtualization Resistance Score (DRS): 96.96 / 100.0
- Shannon Entropy: 7.9764 / 8.0 (99.7%)
- Bytecode Size: 8469 bytes (1059 words)
[*] Step 4/6: Synthesizing automated VM entrypoint dispatcher...
[*] Step 5/6: Patching Swift ARM64 assembly with opaque VM trampoline...
[*] Step 6/6: Linking protected Swift Mach-O binary...
==================================================================
✅ Build Successful: examples/swift_demo/build/protected_swift_app
==================================================================

[*] Executing Protected Swift Application:
------------------------------------------------------------------
================================================================
🛡️  ASGARD-5877: Pure Swift Protection Engine (Zero Bridge)
================================================================
[*] 1. Validating Authentic License Key (0x1337):
    Status: ✅ ACCESS GRANTED (Evaluated in Stack-VM)

[*] 2. Validating Tampered License Key (0xDEADBEEF):
    Status: ✅ ACCESS DENIED (Tamper rejected by VM)

[*] 3. Validating Forged Expected Signature (0xCAFEBABE):
    Status: ✅ ACCESS DENIED (Signature mismatch detected)
================================================================
```

### 2. Run Automated idasql Security Audit
```bash
./examples/swift_demo/audit_idasql.sh
```

---

## 5. Reverse Engineering Audit via idasql

### A. Data-Hiding Verification (`strings` virtual table)
```sql
SELECT count(*) FROM strings 
WHERE content LIKE '%ACCESS%' OR content LIKE '%GRANTED%' OR content LIKE '%DENIED%';
```
**Observed Result:** `0 row(s)` — all sensitive strings are encrypted in volatile stack memory.

### B. Swift Entrypoint Decompilation (`pseudocode` virtual table)
Hex-Rays decompiles both the C-ABI export and the internal Swift-mangled symbol to trivial thunks:

```c
// attributes: thunk
__int64 verify_license()
{
  return asgard_vm_entry_verify_license();
}

// attributes: thunk
Swift::UInt64 __swiftcall verify_license(_:_:)(Swift::UInt64 a1, Swift::UInt64 a2)
{
  return asgard_vm_entry_verify_license(a1, a2);
}
```

The original mathematical verification logic:
`((key ^ 0x5877) * 42) + 0x1337 == expected`
**does not exist anywhere in the native text segment.**

### C. Stack-VM Dispatcher Decompilation
Hex-Rays decompilation of the virtual machine dispatcher (`asgard_vm_entry_verify_license` and `sub_...`):
- Hardware timing probes via `CNTVCT_EL0` and `mach_absolute_time()` to detect emulators.
- Dynamic inspection of loaded dylibs (`_dyld_image_count()`) searching for hooking frameworks (`frida`, `substrate`).
- Rolling XOR key mutation: `*v15 = __ROR8__(*v15, 61) + (v23 ^ 0x5A)`.
- Control-flow breakdown: `JUMPOUT(...)` disrupting Hex-Rays c-tree AST recovery.
