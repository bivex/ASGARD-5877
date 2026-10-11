# Running and Debugging ASGARD-5877 on Windows ARM64 via Parallels Desktop from macOS

This guide explains how to cross-virtualize, compile, execute, and debug ASGARD-5877 protected binaries on a Windows 11 ARM64 guest inside Parallels Desktop directly from a macOS host terminal.

---

## 1. Architectural Topology

```
+-----------------------------------------------------------------------------------+
| macOS Host (Apple Silicon ARM64)                                                  |
|                                                                                   |
|  - OCaml 5.4+ Toolchain: _build/default/bin/main.exe                              |
|  - Workspace: /Volumes/External/Code/ASGARD-5877                                  |
|  - Control Plane: prlctl CLI / Parallels MCP                                      |
+-----------------------------------------+-----------------------------------------+
                                          |
                      Shared Folder Mount | (\\Mac\asgard <-> W:\)
                                          v
+-----------------------------------------------------------------------------------+
| Windows 11 Pro ARM64 VM (Parallels Desktop)                                       |
|                                                                                   |
|  - Shared Drive: W:\                                                              |
|  - Compiler: MSVC cl.exe (Visual Studio 2026 Developer Prompt ARM64)              |
|  - Debugger: CDB ARM64 (C:\Program Files (x86)\Windows Kits\10\Debuggers\arm64\cdb)|
|  - Runtime: Native Windows ARM64 PE Executables                                   |
+-----------------------------------------------------------------------------------+
```

---

## 2. Prerequisites & Setup

### 2.1 Parallels VM Setup
1. A running Windows 11 ARM64 VM in Parallels Desktop.
2. Find the VM UUID or name using `prlctl`:
   ```bash
   prlctl list -a
   ```
   Example output:
   ```
   UUID                                    STATUS       IP_ADDR   NAME
   {d53f9ec7-88af-4baf-831a-08a68d4dbb9a}  running      -         Windows 11 Pro (Debugger)
   ```

### 2.2 Shared Folder Mapping
Map the repository directory to drive `W:\` in the Windows VM:
```bash
prlctl exec "d53f9ec7-88af-4baf-831a-08a68d4dbb9a" --current-user cmd.exe /c \
  "net use W: \\\\Mac\\asgard /persistent:yes"
```
*(Or configure "Shared Folders" in Parallels VM settings: Options -> Sharing -> Custom Folders).*

### 2.3 Guest Toolchain Requirements
Inside the Windows 11 ARM64 VM:
- **Visual Studio 2022/2026** with C++ ARM64 build tools (`cl.exe` ARM64 native).
- **Windows SDK** Debugging Tools for Windows (`cdb.exe` ARM64).

---

## 3. Workflow: Generate, Compile, and Run

### Step 1: Generate Protected C++ Source on macOS
Run the ASGARD virtualization toolchain on the macOS host:
```bash
eval $(opam env)
_build/default/bin/main.exe protect-arm64 \
  -i examples/real_corpus/openssl_sha256.c \
  -o _build/real_corpus_bench/openssl/asgard_out \
  --flatten --mba
```
This produces:
- `_build/real_corpus_bench/openssl/asgard_out/app_virtualized.cpp`: Complete C++20 virtualized wrapper with embedded encrypted bytecode chunks.
- `_build/real_corpus_bench/openssl/asgard_out/threaded_vm.hpp`: Multi-architecture threaded runtime header (MSVC / GCC / Clang compatible).
- `_build/real_corpus_bench/openssl/asgard_out/asgard_obf.h`: C Macro obfuscation macros.

### Step 2: Compile with MSVC `cl.exe` from macOS
Execute `vcvarsall.bat arm64` followed by MSVC compilation in the VM using `prlctl exec`:

```bash
prlctl exec "d53f9ec7-88af-4baf-831a-08a68d4dbb9a" --current-user cmd.exe /c \
  "call \"C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat\" arm64 && \
   cd /d W:\_build\real_corpus_bench\openssl\asgard_out && \
   cl /std:c++20 /O2 app_virtualized.cpp /Fe:app.exe"
```

> [!NOTE]
> ASGARD includes standard C++20 `<bit>` and `<atomic>` shims plus computed GOTO switch fallbacks under `_MSC_VER`, compiling cleanly with **0 errors and 0 warnings**.

### Step 3: Run the Protected Binary in Windows ARM64
Execute the generated binary inside the VM:

```bash
prlctl exec "d53f9ec7-88af-4baf-831a-08a68d4dbb9a" --current-user cmd.exe /c \
  "cd /d W:\_build\real_corpus_bench\openssl\asgard_out && app.exe 10"
```

Expected output:
```
[DEBUG] Verification pass state: d7a8fbb3 07d78094 69ca9abc b0082e4f 8d5651e4 6d3cdb76 2d02d0bf 37c9e592
[BENCHMARK] Suite: OpenSSL Cryptographic Core
[BENCHMARK] Target: SHA-256 FIPS 180-4 Block Transform
[BENCHMARK] Iterations: 10
[BENCHMARK] Elapsed: 1247990 us
[BENCHMARK] Digest: 21C25835769B6919A340A4595B1B1BDA
[BENCHMARK] Verification: PASS
```

To capture the exact numeric exit code (`%ERRORLEVEL%`) under `cmd.exe`:
```bash
prlctl exec "d53f9ec7-88af-4baf-831a-08a68d4dbb9a" --current-user cmd.exe /v:on /c \
  "cd /d W:\_build\real_corpus_bench\openssl\asgard_out && app.exe 10 & echo ERRORLEVEL: !errorlevel!"
```

---

## 4. Debugging with Windows Debugger (CDB / WinDbg)

When diagnosing crashes (`0xC0000005`), anti-tamper trips, or VM exceptions, use the command-line debugger `cdb.exe` non-interactively from macOS.

### 4.1 Locating `cdb.exe`
The ARM64 debugger is installed by the Windows SDK at:
```
C:\Program Files (x86)\Windows Kits\10\Debuggers\arm64\cdb.exe
```

### 4.2 Handling Nanomite Breakpoints (`brk #0xF000` / `0x80000003`)

ASGARD uses hardware breakpoint instructions (`brk #0xF000` on ARM64) for **Nanomite Vectored Control-Flow Obfuscation**. In normal execution, these are caught and dispatched by ASGARD's Vectored Exception Handler (`nanomite_vectored_handler`).

However, Windows Debuggers (CDB/WinDbg) intercept all `STATUS_BREAKPOINT` (`0x80000003`) events as first-chance exceptions before VEH handlers run.

> [!IMPORTANT]
> To instruct CDB to pass breakpoints to ASGARD's VEH handler, use `sxd bpe` (*Set Exception Disabled for Breakpoint Exceptions*):

```bash
prlctl exec "d53f9ec7-88af-4baf-831a-08a68d4dbb9a" --current-user cmd.exe /c \
  "\"C:\Program Files (x86)\Windows Kits\10\Debuggers\arm64\cdb.exe\" \
   -g -G -c \"sxd bpe; g; r; k; u @pc-16 L10; q\" \
   W:\_build\real_corpus_bench\openssl\asgard_out\app.exe 1"
```

CDB command breakdown:
- `-g`: Ignore initial breakpoint at process startup.
- `-G`: Ignore final breakpoint on process exit.
- `-c "<commands>"`: Run debugger commands upon startup:
  - `sxd bpe`: Disable first-chance break on `STATUS_BREAKPOINT`, routing it to VEH.
  - `g`: Continue execution.
  - `r`: Print ARM64 registers (`x0`..`x28`, `fp`, `lr`, `sp`, `pc`).
  - `k`: Print call stack backtrace.
  - `u @pc-16 L10`: Disassemble instructions around the crash program counter.
  - `q`: Quit debugger.

---

## 5. Diagnosing ASGARD Anti-Tamper Tripwires

ASGARD does not use simple `abort()` calls when tampering is detected; instead, it performs **silent context poisoning** by XORing the VM register blinding mask (`ctx.reg_mask ^= penalty`).

When poisoned, all memory pointers loaded by the VM are corrupted, resulting in an immediate Access Violation (`0xC0000005`) on the next memory store or load.

### Identifying Tripwires from Registers in CDB:

| Corrupted Register Pattern | Triggering Anti-Tamper Subsystem | Root Cause & Resolution |
|:---|:---|:---|
| `0x5877BAADC0DEDEAD` | PE Section Integrity Drift Scanner | Section hash changed dynamically. Ensure only `(Characteristics & IMAGE_SCN_MEM_EXECUTE) && !(Characteristics & IMAGE_SCN_MEM_WRITE)` (`.text`) is hashed, excluding mutable `.data`. |
| `0xFEEDFACE5877CAFE` | Hypervisor / Jitter Watchdog | Cycle diff (`_ReadStatusReg(ARM64_CNTVCT)`) exceeded jitter threshold (> 30,000 cycles). Occurs under extreme hypervisor scheduling spikes. |
| `0xDEADBEEF5A5A1337` | Anti-Emulation Slow-Path | Secondary clock differential (`QueryPerformanceCounter`) detected clock freeze or abnormal drift. |
| `0xCAFEBABE13375877` | Anti-Debugging Probe | `IsDebuggerPresent()` or PEB `BeingDebugged` returned true. Expected behavior when attached to a debugger. |
| `0xDEADBEEF5A5A5A5A` | Poly-Hash Bytecode Integrity Guard | Dynamic bytecode modified in memory or mismatched rolling poly-hash. |

---

## 6. Process Locking & Cleanup

If a background debugger session or failed executable locks `app.exe`, MSVC will fail with:
```
LINK : fatal error LNK1104: cannot open file 'app.exe'
LINK : fatal error LNK1105: cannot close file 'app.exe'; error code 1224
```

Kill any hanging instances from macOS using:
```bash
prlctl exec "d53f9ec7-88af-4baf-831a-08a68d4dbb9a" --current-user cmd.exe /c \
  "taskkill /f /im cdb.exe & taskkill /f /im app.exe & taskkill /f /im runner.exe & exit 0"
```

---

## 7. Automated Helper Script

For automated execution, use [`scripts/run_windows_vm_bench.sh`](file:///Volumes/External/Code/ASGARD-5877/scripts/run_windows_vm_bench.sh):

```bash
# Run OpenSSL SHA-256 benchmark with 10 iterations on Windows ARM64
./scripts/run_windows_vm_bench.sh openssl_sha256.c openssl 10

# Run SQLite Varint/PageHash benchmark
./scripts/run_windows_vm_bench.sh sqlite3_varint_hash.c sqlite3 50

# Run GNU Coreutils CRC-32 benchmark
./scripts/run_windows_vm_bench.sh coreutils_crc32.c coreutils 50
```
