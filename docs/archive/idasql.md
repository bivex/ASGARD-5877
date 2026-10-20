# Guide to Auditing ASGARD-5877 Virtualized Binaries via idasql

This document describes the methodology for using `idasql` to perform automated analysis, security audits, resilience verification, and runtime debugging on binary executables protected by the ASGARD-5877 virtual machines (including Stack-VM and Register-VM).

---

## 1. Purpose and Audit Objectives

When protecting binaries via code virtualization (Stack-VM / Register-VM) and C-macro obfuscation (`asgard_obf.h`), the protection must be objectively verified against industry-standard reverse engineering tools (IDA Pro, Hex-Rays Decompiler).

The `idasql` tool provides a declarative SQLite interface to the internal IDA Pro database (`.i64` / `.idb`). This enables automated testing of:
- String encryption and symbol stripping;
- Hex-Rays decompiled pseudocode resilience;
- Inspection of low-level virtual machine state structures and memory alignment;
- Detection of subtle runtime flaws and edge cases in emitted VM C++ source code.

### Verified Protection Properties

1. **Data Hiding**: Absence of cleartext internal strings, validation messages, cryptographic keys, and marker signatures in the `strings` table.
2. **Symbol Elimination**: Complete removal of target function names and bodies from `funcs` and `names` tables.
3. **Decompiler Resilience**: Disruption of business logic and data-flow graphs in Hex-Rays (`pseudocode` table).
4. **Bytecode Security**: Verification of dynamic rolling-key bytecode encryption and absence of static instruction-operand chains.
5. **Fail-Closed Runtime Safety**: Bound checks on the operand stack pointer (`vsp`), context slot validation, and elimination of spurious system imports.

---

## 2. Prerequisites

1. **IDA Pro 9.x / 8.x** with batch console mode support:
   - macOS: `/Applications/IDA Professional 9.2.app/Contents/MacOS/idat`
   - Linux: `/opt/idapro/idat64`
2. **`idasql` CLI utility**:
   - SDK binary location: `idasql`
3. **Protected Binary** compiled by ASGARD-5877:
   - For example: `_build/clean_test_stack/protected_app`

---

## 3. Binary Compilation Modes

### 3.1 Production Mode (Black-Box Audit)
By default, binaries are compiled with maximum optimizations and aggressive symbol and debug section stripping (`strip -x`, `-Wl,-dead_strip`, `-Wl,-x`):

```bash
./_build/default/bin/main.exe protect-arm64 -i app.c -o _build/out --engine=stack
```

### 3.2 Debug Mode with DWARF Preservation (White-Box Audit)
For in-depth analysis of virtual machine internals, struct layouts, and runtime debugging, the toolchain supports the environment variable `ASGARD_DEBUG_SYMBOLS=1`.

When set:
- DWARF debug information is retained (`-g -O1 -Wno-format-security`);
- Symbol stripping is disabled;
- C++ structure layouts (`local_types`, `types_members`), argument names, and mangled symbols are preserved in the IDA database.

```bash
ASGARD_DEBUG_SYMBOLS=1 ./_build/default/bin/main.exe protect-arm64 -i app.c -o _build/out --engine=stack
```

---

## 4. Audit Pipeline

### Step 1: Batch Database Generation

Run IDA Pro in headless batch mode:

```bash
# macOS
"/Applications/IDA Professional 9.2.app/Contents/MacOS/idat" -A -B path/to/protected_app

# Linux
idat64 -A -B path/to/protected_app
```

Flags:
- `-A`: Autonomous mode, suppresses modal dialogues.
- `-B`: Batch mode, generates `.i64` database and `.asm` listing.

This creates `protected_app.i64` in the target directory.

### Step 2: Querying with `idasql`

#### Single Query Execution:
```bash
idasql -s protected_app.i64 -q "SELECT name, size FROM funcs;"
```

#### Interactive REPL:
```bash
idasql -s protected_app.i64 -i
```

#### SQL Script File Execution:
```bash
idasql -s protected_app.i64 -f audit_queries.sql
```

---

## 5. `idasql` Schema Overview

The `idasql` tool exposes over 40 virtual tables. The primary tables for virtualized binary auditing include:

| Table | Description | Key Columns |
| :--- | :--- | :--- |
| `strings` | String literals discovered by IDA | `address`, `length`, `type_name`, `content` |
| `funcs` | Recognized function entry points | `address`, `name`, `size`, `prototype`, `flags` |
| `names` | Symbols, labels, and segment identifiers | `address`, `name` |
| `pseudocode` | Decompiled C pseudocode (Hex-Rays) | `func_addr`, `line_num`, `line` |
| `local_types` | Registered type definitions and structures | `ordinal`, `name`, `is_struct`, `is_enum` |
| `types_members` | Structure field offsets, sizes, and types | `type_name`, `member_name`, `offset`, `size`, `member_type` |
| `xrefs` | Code and data cross-references | `from_ea`, `to_ea`, `type`, `type_name` |
| `segments` | Binary section map | `name`, `start_ea`, `end_ea`, `bitness` |

---

## 6. Protection Validation Query Suite

### 6.1 String Literal Hiding Verification

**Goal**: Verify that sensitive strings are encrypted and do not appear in cleartext.

```sql
SELECT printf('0x%X', address) AS addr, length, content
FROM strings
WHERE content LIKE '%license%'
   OR content LIKE '%valid%'
   OR content LIKE '%serial%'
   OR content LIKE '%secret%'
   OR content LIKE '%Testing%';
```

- **Expected Result**: `0 row(s)`.
- **Finding Interpretation**: Leaked strings indicate missing `ASG_STR` macro wrappers or disabled macro obfuscation.

### 6.2 Protected Function Symbol Elimination

**Goal**: Confirm that the target function is fully virtualized, with original symbol names and bodies removed.

```sql
SELECT printf('0x%X', address) AS addr, name, size
FROM funcs
WHERE name LIKE '%verify%'
   OR name LIKE '%license%'
   OR name LIKE '%serial%';
```

- **Expected Result**: `0 row(s)`.
- **Finding Interpretation**: The original native body is removed. Execution flows through a trampoline directly into the VM dispatcher.

### 6.3 Residual Function Inventory

**Goal**: Audit all functions visible to static disassembly.

```sql
SELECT printf('0x%X', address) AS addr, name, size
FROM funcs
ORDER BY size DESC;
```

A production virtualized build should only contain:
1. Dynamic linker stubs (`_printf`, etc.).
2. Entry point / `main` (`start`).
3. Virtual machine dispatch loop (`sub_...` or `asgard_vm_call`).

### 6.4 Verification of Marker Symbol Elimination

```sql
SELECT printf('0x%X', address) AS addr, name
FROM names
WHERE name LIKE '%ASGARD%'
   OR name LIKE '%Vanguard%'
   OR name LIKE '%Ultra%';
```

- **Expected Result**: `0 row(s)`. Demarcation delimiters (`ASGARD_BEGIN_ULTRA`, `ASGARD_END`) must leave zero symbol traces in binary metadata.

### 6.5 Low-Level Memory Layout Audit (`types_members`)

When built with `ASGARD_DEBUG_SYMBOLS=1`, inspect the VM state struct:

```sql
SELECT member_name, offset, size, member_type
FROM types_members
WHERE type_name LIKE '%stack_vm%'
ORDER BY member_index;
```

**Reference layout for `asgard_stack_vm::stack_vm_t`:**
```text
+-------------+--------+-------+----------------+
| member_name | offset | size  | member_type    | 
+-------------+--------+-------+----------------+
| vsp         | 0      | 32768 | uint64_t[4096] | 
| vsp_idx     | 32768  | 4     | int            | 
| ctx         | 32776  | 512   | uint64_t[64]   | 
| vkey        | 33288  | 8     | uint64_t       | 
| zf          | 33296  | 1     | uint8_t        | 
| sf          | 33297  | 1     | uint8_t        | 
| cf          | 33298  | 1     | uint8_t        | 
| of          | 33299  | 1     | uint8_t        | 
| halted      | 33300  | 4     | int            | 
+-------------+--------+-------+----------------+
```

Validation criteria:
- Computation stack `vsp` occupies exactly 32 KB (4096 8-byte slots);
- Register context `ctx` is aligned to an 8-byte boundary (offset 32776);
- Dynamic rolling key `vkey` immediately follows the context array;
- Condition flags `zf`, `sf`, `cf`, `of` are packed into individual byte slots.

### 6.6 Hex-Rays Decompiler Audit (`pseudocode`)

> [!IMPORTANT]
> Always filter `pseudocode` queries with `WHERE func_addr = <addr>` to prevent triggering decompilation of every function in the binary.

#### Analysis of Virtualized Function Call Site:
```sql
SELECT line_num, line
FROM pseudocode
WHERE func_addr = (SELECT address FROM funcs WHERE name = 'start' OR name = 'main')
ORDER BY line_num;
```

- **Validation Criteria**: Pseudocode displays stack-based string deobfuscation loops (XOR loops) and an opaque invocation:
  ```c
  v2 = sub_100000580(arg1, arg2);
  ```
  The decompiler cannot link caller arguments to internal verification logic.

#### Analysis of VM Dispatcher Internals:
```sql
SELECT line_num, line
FROM pseudocode
WHERE func_addr = (SELECT address FROM funcs WHERE size > 2000 LIMIT 1)
  AND (line LIKE '%RotL%' OR line LIKE '%ROR8%' OR line LIKE '%switch%')
ORDER BY line_num;
```

- **Validation Criteria**: The decompiler only recovers bytecode decryption logic (`__ROR8__`, rolling-key mutation, and opcode dispatch). Protected instructions remain encrypted in ciphertext arrays and are not decompiled.

#### Detection of Control-Flow Disruptions (`JUMPOUT`):
```sql
SELECT line_num, line
FROM pseudocode
WHERE func_addr = (SELECT address FROM funcs WHERE size > 2000 LIMIT 1)
  AND line LIKE '%JUMPOUT%'
ORDER BY line_num;
```

- **Validation Criteria**: Presence of `JUMPOUT(...)` confirms that Hex-Rays failed to structure control-flow transitions (CFG breakdown) due to Control-Flow Flattening, spaghetti dispatch, or fail-closed trap jumps. Data-flow analysis across these points is halted.

---

## 7. Practical Case Studies: Bug Detection and Fixes via idasql

During Stack-VM audits using `idasql`, several runtime defects were identified and resolved in the emitted C++ code:

### Case 1: Spurious `dlsym(RTLD_DEFAULT, "")` Calls and Extraneous Imports
- **Symptom in `pseudocode`**:
  ```c
  v76 = dlsym((void *)0xFFFFFFFFFFFFFFFELL, "");
  if (!v76) {
      snprintf(alt, 256, "_%s", "");
      v76 = dlsym(..., alt);
  }
  ```
- **Cause**: When a protected function used no external APIs, `g_external_symbols` was emitted as `{ "" }`. The `CALL_EXTERN` / `RESOLVE_SYM` handlers invoked `dlsym` on an empty string, polluting the import table with `_dlsym` and `_snprintf`.
- **Fix**: In [`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml), added the guard `if (sym_name && sym_name[0] != '\0')`. Extraneous imports were completely eliminated (`funcs` count dropped from 7 to 5).

### Case 2: Stack Underflow / Overflow and Memory Safety (Fail-Closed)
- **Symptom in `pseudocode`**: Stack access `vm->vsp[vm->vsp_idx++]` and `vm->vsp[--vm->vsp_idx]` lacked boundary checks. Malformed or mutated bytecode could corrupt `ctx` and condition flags.
- **Fix**: Introduced strict fail-closed boundary guards:
  ```cpp
  /* PUSH: Overflow guard */
  if (vm->vsp_idx < 4096) vm->vsp[vm->vsp_idx++] = val;

  /* POP: Underflow guard */
  if (vm->vsp_idx > 0) vm->ctx[idx] = vm->vsp[--vm->vsp_idx];

  /* BINARY OPS (ADD, SUB, NOR, CMP, ...): Require 2 operands */
  if (vm->vsp_idx >= 2) {
      uint64_t b = vm->vsp[--vm->vsp_idx];
      uint64_t a = vm->vsp[--vm->vsp_idx];
      ...
  }
  ```

### Case 3: Register Context Slot Bounds Checking
- **Symptom**: The register slot `idx` in `PUSH_REG` / `POP_REG` / `CMOV` was read as `int16_t` without upper bound enforcement.
- **Fix**: Added dynamic validation `idx >= 0 && idx < max_ctx`, where `max_ctx = sizeof(vm->ctx) / sizeof(vm->ctx[0])`.

### Case 4: Verifying VSP Whitening in Decompiler Output (`pseudocode`)
- **Query via idasql**:
  ```sql
  SELECT line_num, line FROM pseudocode 
  WHERE func_addr = (SELECT address FROM funcs WHERE size > 2000 LIMIT 1)
    AND (line LIKE '%9E3779B97F4A7C15%' OR line LIKE '%61C8864680B583EB%');
  ```
- **Observed Result**:
  ```c
  v126[(unsigned int)v89] = (0x9E3779B97F4A7C15LL * v88 + v9) ^ v126[(unsigned int)v88] ^ v91;
  v128[v125] = v126[(unsigned int)v98] ^ (v97 - 0x61C8864680B583EBLL * v98);
  ```
- **Interpretation**: Confirms VSP whitening: `vkey + slot * 0x9E3779B97F4A7C15ULL` (represented in two's complement as `vkey - slot * 0x61C8864680B583EBLL`). The operand stack is fully whitened in memory, preventing static inspection of intermediate values.

### Case 5: Eliminating Plain Strings and dlsym via Runtime API Hashing
- **Symptom in `strings` and `funcs`**: Cleartext `_printf` was present in `__cstring`, along with imported references to `_dlsym` and `_snprintf`.
- **Fix**:
  1. Converted `g_external_symbols` to `asgard_ext_sym_t` structs storing 32-bit FNV-1a hashes (`hash`, `alt_hash`) and XOR-encrypted byte literals (`enc_bytes`).
  2. Implemented importless resolver `asgard_resolve_by_api_hash`, parsing `LC_DYLD_EXPORTS_TRIE` of loaded dyld images directly in memory.
  3. Replaced `snprintf` with stack buffer concatenation.
- **Verification via idasql**:
  ```sql
  SELECT * FROM strings WHERE content LIKE '%printf%';
  -- 0 row(s)
  SELECT address, name, size FROM funcs WHERE name LIKE '%dlsym%' OR name LIKE '%snprintf%';
  -- 0 row(s)
  ```
- **Interpretation**: Function names are absent from `.rodata` / `__cstring`. Static import of `_dlsym` is eliminated, blocking cross-reference analysis to dynamic resolution logic.

### Case 6: Decompiler CFG Disruption and `JUMPOUT` Semantics
- **Symptom in `pseudocode`**: Hex-Rays emits `JUMPOUT(...)` macros instead of standard control-flow constructs:
  ```c
  if ( *(_DWORD *)(v11 + 40) || a10 > 0x97E7 )
  LABEL_8:
    JUMPOUT(0x100000B04LL);
  ```
- **Significance of `JUMPOUT` in Hex-Rays**:
  1. **Control-Flow Graph Breakdown**: Hex-Rays cannot map execution transitions to standard C constructs (`if/while/switch/goto`), typically occurring when branching across function bounds `[start_ea, end_ea)` or into disconnected chunks.
  2. **CFF and Spaghetti Dispatch**: Transitions between the VPC dispatcher, operational handlers, and decoy traps are fragmented. The branch to `0x100000B04` routes execution to an isolated fail-closed trap handler.
  3. **Data-Flow Blinding**: Hex-Rays cannot propagate types or variables through `JUMPOUT`. The AST (c-tree) terminates, neutralizing automated deobfuscation scripts.
- **Verification via idasql**:
  ```sql
  SELECT line_num, line FROM pseudocode 
  WHERE func_addr = (SELECT address FROM funcs WHERE size > 2000 LIMIT 1)
    AND line LIKE '%JUMPOUT%';
  ```

### Case 7: Constant Name Masking and In-Memory Constant Encryption
- **Symptom in `strings` and `names`**: Strings matching `asg_c_340df373` and `asg_c_26c6128d` were visible, and constant bytes were exposed in `__const`. Furthermore, `_strcmp` and `_strlen` were imported.
- **Fix**:
  1. Converted `AsgardConstantEntry` in Stack-VM and Native VM to 32-bit FNV-1a hashes (`hash`, `alt_hash`).
  2. Encrypted constant payloads using rolling XOR keys `(xor_key >> ((j & 3) * 8)) ^ (j * 0x5D + 0x33)` with lazy decryption into `dec_data` on first access.
  3. Replaced `strcmp` and `strlen` with inline `asg_strcmp` and byte-by-byte trie hashing.
- **Verification via idasql**:
  ```sql
  SELECT count(*) FROM strings WHERE content LIKE 'asg_c_%';
  -- 0 row(s)
  SELECT count(*) FROM funcs WHERE name = '_strcmp' OR name = '_strlen';
  -- 0 row(s)
  ```
- **Interpretation**: 100% of constant identifier strings are eliminated. Constant bodies are fully encrypted in memory, and standard string APIs are stripped from Mach-O imports.

---

## 8. Automated CI/CD Regression Audit Script

```bash
#!/usr/bin/env bash
set -euo pipefail

BINARY_PATH="${1:-_build/clean_test_stack/protected_app}"
IDAT_PATH="${IDAT_PATH:-/Applications/IDA Professional 9.2.app/Contents/MacOS/idat}"
IDASQL_PATH="${IDASQL_PATH:-idasql}"

echo "[*] Generating IDA database for ${BINARY_PATH}..."
"${IDAT_PATH}" -A -B "${BINARY_PATH}"

DB_PATH="${BINARY_PATH}.i64"
if [[ ! -f "${DB_PATH}" ]]; then
    DB_PATH="${BINARY_PATH}.idb"
fi

echo "[*] Running idasql security audit on ${DB_PATH}..."

# 1. Verify absence of cleartext strings
STR_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM strings WHERE content LIKE '%license%' OR content LIKE '%serial%' OR content LIKE '%valid%';" | tail -n 1 | tr -d ' ')
if [[ "${STR_COUNT}" != "0" ]]; then
    echo "[-] FAILED: Sensitive strings leaked in binary (${STR_COUNT} found)!"
    exit 1
fi
echo "[+] PASSED: No sensitive strings leaked."

# 2. Verify elimination of protected function symbols
FN_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM funcs WHERE name LIKE '%verify_serial%' OR name LIKE '%license%';" | tail -n 1 | tr -d ' ')
if [[ "${FN_COUNT}" != "0" ]]; then
    echo "[-] FAILED: Protected function names exposed in symbol table (${FN_COUNT} found)!"
    exit 1
fi
echo "[+] PASSED: Protected symbols successfully eliminated."

# 3. Verify absence of extraneous imports
DLSYM_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM funcs WHERE name = '_dlsym';" | tail -n 1 | tr -d ' ')
if [[ "${DLSYM_COUNT}" != "0" ]]; then
    echo "[-] WARNING: Unnecessary _dlsym import present in binary!"
fi

echo "[+] All idasql security assertions verified successfully."
```

---

## 9. Limitations

1. `idasql` requires a pre-generated `.i64` or `.idb` database. It does not perform direct binary disassembly without an existing IDA database.
2. Decompilation queries targeting `pseudocode` and `ctree` rely on the Hex-Rays API and require an active decompiler license within the IDA environment.

---

## 10. Related Documents

- [`Stack-VM.md`](Stack-VM.md) — ASGARD-5877 Stack-VM Execution Engine Specification.
- [`../VM_PROTECTOR.md`](../VM_PROTECTOR.md) — Architecture of Virtualization and Opcode Randomization.
- [`../C_MACRO_OBF.md`](../C_MACRO_OBF.md) — Documentation on String and Constant Macro Obfuscation.
