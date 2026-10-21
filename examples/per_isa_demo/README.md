# ASGARD-5877: Per-ISA Polymorphic Randomization Demo

This example demonstrates how to use the **Per-ISA Randomization Macros** to protect C/C++ source code with isolated, polymorphic virtual instruction set architectures (ISA).

---

## 1. Macros in `asgard_obf.h`

Developers can select between three specialized macro markers for per-ISA randomization:

```c
#include "asgard_obf.h"

// 1. Independent Polymorphic ISA Mapping
uint64_t verify_serial(uint64_t serial, uint64_t hardware_id) {
    ASGARD_BEGIN_PER_ISA("VerifySerial");
    /* ... code ... */
    ASGARD_END();
}

// 2. Randomized ISA with Dynamic Opcode Salting
uint64_t generate_session_key(uint64_t client_seed, uint64_t server_nonce) {
    ASGARD_BEGIN_RANDOM_ISA("GenerateSessionKey");
    /* ... code ... */
    ASGARD_END();
}

// 3. Metamorphic Multi-Layer Diversification
uint64_t validate_access_level(uint64_t user_role, uint64_t required_mask) {
    ASGARD_BEGIN_POLY_ISA("ValidateAccessLevel");
    /* ... code ... */
    ASGARD_END();
}
```

---

## 2. Technical Architecture: What Happens in C / C++

When ASGARD virtualizes functions marked with `ASGARD_BEGIN_PER_ISA`:

1. **Inline Marker Emission:**
   - **ARM64:** `b 1f \n .ascii "ASGARD_BEG_P____" \n .balign 4 \n 1:`
   - **x86-64:** `jmp 1f \n .ascii "ASGARD_BEG_P__" \n 1:`
   - **RISC-V:** `j 1f \n .ascii "ASGARD_BEG_P____" \n .balign 4 \n 1:`
2. **Lifter & IR Tagging:**
   The lifters (`arm64_parser`, `x86_parser`, `riscv_parser`) detect the `"ASGARD_BEG_P"` token and classify the region as `ModePerIsa`.
3. **Per-Function Polymorphic ISA Synthesis:**
   Each function is compiled with its own distinct `macro_salt`:
   $$\text{macro\_salt}_k = (\text{Hash}(\text{clean\_name}(F_k)) \mathbin{\&} 0x\text{FE}) \mid 1$$
   - In `app_virtualized.cpp`, each routine becomes a clean 56-byte dispatch thunk:
     ```cpp
     uint64_t verify_serial(uint64_t serial, uint64_t hardware_id) {
         embedded_bytecode_verify_serial_ensure_assembled();
         return vanguard_threaded_vm::asgard_vm_call_with_salt(
             77, /* Per-ISA Opcode Salt = 0x4D */
             embedded_bytecode_verify_serial,
             sizeof(embedded_bytecode_verify_serial) / sizeof(embedded_bytecode_verify_serial[0]),
             (uint64_t)serial, (uint64_t)hardware_id);
     }
     ```
4. **Dynamic Opcode Unmasking in VM Dispatcher:**
   $$\text{slot} = \text{op} \oplus \text{domain\_salt}[\text{domain}] \oplus \text{ctx.macro\_salt}$$
   Because `macro_salt` differs for each function, **no opcode mappings are shared or transferable**. Reversing one function yields zero valid mappings for any other function in the binary.

---

## 3. Building and Verification

```bash
./examples/per_isa_demo/build_and_run.sh
```

**Execution Output:**
```text
==================================================================
🛡️  ASGARD-5877: Per-ISA Polymorphic Randomization Demo
==================================================================
[1] verify_serial() [ASGARD_BEGIN_PER_ISA]:
    Genuine Serial:  ✅ VALID (res=1)
    Tampered Serial: ✅ REJECTED (res=0)

[2] generate_session_key() [ASGARD_BEGIN_RANDOM_ISA]:
    Computed Key: 0x3BC67, Expected: 0x3BC67 (✅ MATCH)

[3] validate_access_level() [ASGARD_BEGIN_POLY_ISA]:
    Authorized: ✅ GRANTED (got 0x5877134A, expected 0x5877134A)
    Denied:     ✅ DENIED (0) (got 0x0)
==================================================================
Result: 🎉 ALL PER-ISA MACROS PASSED
==================================================================
```

---

## 4. Automated idasql Decompiler Audit

```bash
./examples/per_isa_demo/audit_idasql.sh
```

Verifies:
- **0 metadata string leaks** (`VerifySerial`, `GenerateSessionKey`, `ValidateAccessLevel`).
- **Unique Per-ISA opcode salts** embedded in C++ dispatchers (`77`, `107`, `189`).
- Complete disappearance of native function logic into monolithic obfuscated VM handlers.
