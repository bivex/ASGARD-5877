# ASGARD-5877: Android Kotlin + Protected .so JNI Example

This example demonstrates how to build and protect an **Android NDK shared library** (`libasgard_security.so`, ARM64 ELF) called from **Kotlin** via JNI, verified live on a running Android emulator (`emulator-5554`) and audited via **`idasql`** (IDA Pro).

---

## 1. Android NDK Protection Architecture

```
+-------------------------------------------------------------------------------+
|                       Android App / Service (Kotlin)                          |
|                       com.asgard.security.AsgardSecurity                      |
|                                                                               |
|   - System.load("/data/local/tmp/libasgard_security.so")                      |
|   - external fun verifyLicense(licenseKey: Long, hwid: Long): Long            |
|   - external fun deriveToken(sessionId: Long, nonce: Long): Long              |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼ Java Native Interface (JNI)
+-------------------------------------------------------------------------------+
|                 libasgard_security.so (ELF 64-bit arm64-v8a)                  |
|                                                                               |
|   JNIEXPORT jlong JNICALL                                                     |
|   Java_com_asgard_security_AsgardSecurity_verifyLicense(...)                  |
|   Java_com_asgard_security_AsgardSecurity_deriveToken(...)                    |
+-------------------------------------------------------------------------------+
                                        │
                                        ▼ In-Place VM Trampoline
+-------------------------------------------------------------------------------+
|            ASGARD Polymorphic Virtual Machine Runtime (PIC / ELF)             |
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

## 2. Directory Layout

```
examples/android_demo/
├── README.md                      # Architecture documentation & audit guide
├── build_and_run_android.sh       # Automated build, deploy, and execution script
├── audit_idasql.sh                # Automated IDA Pro + idasql security audit
└── Sources/
    ├── Jni/
    │   ├── asgard_security_jni.c  # JNI implementation with ASGARD markers + MBA
    │   ├── asgard_obf.h           # ASGARD C/C++ macro obfuscation SDK
    │   └── jni.h                  # Standalone JNI types header
    └── Kotlin/
        ├── AsgardSecurity.kt      # Kotlin external JNI declarations
        └── Main.kt                # Kotlin test runner for Android ART runtime
```

---

## 3. Building and Running on Android Emulator

### Prerequisites
- Active Android Emulator or physical device connected via `adb` (`emulator-5554`, `arm64-v8a`).
- Android SDK with `d8` (`35.0.0`) and `platform-tools` (`adb`).
- Android NDK (`r28+`) with `aarch64-linux-android-clang++`.
- Kotlin compiler (`kotlinc`).

### One-Command Build, Deploy, and Run
```bash
./examples/android_demo/build_and_run_android.sh
```

**Observed Output:**
```text
==================================================================
🤖  ASGARD-5877: Android NDK (.so) + Kotlin Protection Pipeline
==================================================================
[+] Android NDK Compiler: android-sdk/ndk/28.2.13676358/.../aarch64-linux-android-clang++
[+] Connected Device:    emulator-5554 (arm64-v8a)

[*] Step 1/4: Virtualizing JNI Functions via ASGARD Engine...
=== ASGARD-5877 Protection Report ===
- Architecture: Threaded VM (Direct Threading + Rolling Key)
- Devirtualization Resistance Score (DRS): 93.7 / 100.0
- Shannon Entropy: 7.9964 / 8.0 (100.0%)

[*] Step 2/4: Compiling libasgard_security.so via Android NDK (arm64-v8a)...
[+] Android Shared Library Generated: build/libasgard_security.so
libasgard_security.so: ELF 64-bit LSB shared object, ARM aarch64, dynamically linked

[*] Step 3/4: Compiling Kotlin Client & Generating Dalvik Executable (D8)...
[+] Generated Dalvik DEX: build/classes.dex

[*] Step 4/4: Deploying and Running on Android Emulator (emulator-5554)...
libasgard_security.so: 1 file pushed.
classes.dex: 1 file pushed.
------------------------------------------------------------------
[*] Executing Kotlin Application via app_process on Android:
------------------------------------------------------------------
================================================================
🤖  ASGARD-5877: Android Kotlin + Protected .so Library
================================================================
[*] Target Architecture: Linux / Android arm64-v8a
[*] Native Library:      libasgard_security.so (ELF 64-bit)
[*] Loading native runtime via System.load()...

[+] Native library successfully loaded and bound to JNI.

[*] Test 1: AsgardSecurity.verifyLicense() via JNI:
    Genuine Key (0x1337):  ✅ ACCESS GRANTED (Verified by VM)
    Tampered Key (0xDEADBEEF): ✅ ACCESS DENIED (Rejected by VM)

[*] Test 2: AsgardSecurity.deriveToken() via JNI:
    Session ID:     0x64, Nonce: 0x2A
    Computed Token: 0xB7575
    Expected Token: 0xB7575
    Match Status:   ✅ 100% MATHEMATICAL MATCH
------------------------------------------------------------------
✅ Android Emulator Verification PASSED.
==================================================================
```

---

## 4. Security Audit via `idasql` (IDA Pro)

Run the automated IDA Pro security audit on `libasgard_security.so`:
```bash
./examples/android_demo/audit_idasql.sh
```

### Audit Findings in Hex-Rays Pseudocode:
Both exported JNI functions in `libasgard_security.so` are completely stripped of their native instructions and reduced to chunk unmasking and VM dispatch:

```c
__int64 __fastcall Java_com_asgard_security_AsgardSecurity_verifyLicense(
        JNIEnv *env,
        jobject thiz,
        unsigned __int64 license_key,
        unsigned __int64 hwid)
{
  if ( embedded_bytecode_asgard_verify_license_assembled )
    return vanguard_threaded_vm::asgard_vm_call(
             embedded_bytecode_asgard_verify_license,
             len, license_key, hwid);

  // Dynamic chunk unmasking & canary verification loop
  while ( 1 ) {
    if ( chunk->canary != 57005 * id + 51966 )
      __break(1u); // Anti-tamper trap

    k = (0x9E3779B97F4A7C15LL * id) ^ 0x5877A56A11223344LL;
    ...
  }
}
```

The original mathematical equations:
- `((license_key ^ 0x5877) * 42) + 0x1337 == hwid`
- `((session_id ^ 0x5877) * 31) + nonce + 0xCAFE`
**do not exist in the Android ELF .so machine code or decompiled AST.**
