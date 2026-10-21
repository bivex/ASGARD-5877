# ASGARD-5877: 5 Virtualized Macro Functions Demo

This example demonstrates how **5 distinct security-critical functions** are virtualized within a single application binary using the **ASGARD-5877 Polymorphic Protection Engine** and **Per-Macro Opcode Salting (`macro_salt`)**.

---

## 1. What Happens in C / C++ (`app_virtualized.cpp`)

When ASGARD virtualizes multiple marked functions in the same project, it achieves the optimal engineering trade-off:
1. **Shared Handler Table (No Code Explosion):** A single 256-slot dispatch domain table is compiled into the binary, avoiding $N \times$ bloat.
2. **Per-Macro Salting (Complete ISA Isolation):** Each of the 5 functions receives its own unique non-zero 8-bit salt:
   $$\text{macro\_salt}_k = (\text{Hash}(\text{clean\_name}(F_k)) \mathbin{\&} 0x\text{FE}) \mid 1$$
3. **Dedicated Bytecode & Canary Arrays:** Each function receives an isolated encrypted bytecode array:
   - `embedded_bytecode_validate_license[]`
   - `embedded_bytecode_derive_token[]`
   - `embedded_bytecode_compute_checksum[]`
   - `embedded_bytecode_scramble_hwid[]`
   - `embedded_bytecode_eval_permission[]`

### The 5 Generated C++ Trampolines in `app_virtualized.cpp`:

```c
// 1. License verification routine
uint64_t validate_license(uint64_t key, uint64_t hwid) {
    embedded_bytecode_validate_license_ensure_assembled();
    return vanguard_threaded_vm::asgard_vm_call_with_salt(
        159, /* macro_salt = 0x9F */
        embedded_bytecode_validate_license,
        sizeof(embedded_bytecode_validate_license) / sizeof(embedded_bytecode_validate_license[0]),
        (uint64_t)key, (uint64_t)hwid);
}

// 2. Token derivation routine
uint64_t derive_token(uint64_t session, uint64_t nonce) {
    embedded_bytecode_derive_token_ensure_assembled();
    return vanguard_threaded_vm::asgard_vm_call_with_salt(
        1,   /* macro_salt = 0x01 */
        embedded_bytecode_derive_token,
        sizeof(embedded_bytecode_derive_token) / sizeof(embedded_bytecode_derive_token[0]),
        (uint64_t)session, (uint64_t)nonce);
}

// 3. Cryptographic checksum calculation
uint64_t compute_checksum(uint64_t a, uint64_t b) {
    embedded_bytecode_compute_checksum_ensure_assembled();
    return vanguard_threaded_vm::asgard_vm_call_with_salt(
        41,  /* macro_salt = 0x29 */
        embedded_bytecode_compute_checksum,
        sizeof(embedded_bytecode_compute_checksum) / sizeof(embedded_bytecode_compute_checksum[0]),
        (uint64_t)a, (uint64_t)b);
}

// 4. Hardware ID scrambler
uint64_t scramble_hwid(uint64_t raw_id, uint64_t mask) {
    embedded_bytecode_scramble_hwid_ensure_assembled();
    return vanguard_threaded_vm::asgard_vm_call_with_salt(
        165, /* macro_salt = 0xA5 */
        embedded_bytecode_scramble_hwid,
        sizeof(embedded_bytecode_scramble_hwid) / sizeof(embedded_bytecode_scramble_hwid[0]),
        (uint64_t)raw_id, (uint64_t)mask);
}

// 5. Permission / capability evaluator
uint64_t eval_permission(uint64_t role_bits, uint64_t req_bits) {
    embedded_bytecode_eval_permission_ensure_assembled();
    return vanguard_threaded_vm::asgard_vm_call_with_salt(
        223, /* macro_salt = 0xDF */
        embedded_bytecode_eval_permission,
        sizeof(embedded_bytecode_eval_permission) / sizeof(embedded_bytecode_eval_permission[0]),
        (uint64_t)role_bits, (uint64_t)req_bits);
}
```

---

## 2. Why Per-Macro Salting Defeats Reverse Engineering

If an attacker analyzes `validate_license()` in IDA Pro and maps out that opcode `0x98` executes `ADD`:
- In `derive_token()`: $\text{macro\_salt} = 1 \ne 159$.
- At runtime:
  $$\text{slot} = 0x98 \oplus \text{domain\_salt} \oplus 1 \ne \text{base\_opcode}_{\text{ADD}}$$
- The opcode `0x98` in `derive_token()` routes to a **decoy trap (`H_DECOY_X`)** or completely different operation.
- Opcode maps **cannot be transferred** between functions. Breaking one function gives zero information for the remaining four.

---

## 3. Directory Layout

```
examples/five_macros_demo/
├── README.md                      # Documentation & C++ analysis
├── build_and_run.sh               # Automated build & native verification script
├── audit_idasql.sh                # Automated idasql & trampoline audit script
└── Sources/
    ├── five_macros.c              # C source with 5 virtualized macro functions
    └── asgard_obf.h               # ASGARD C/C++ macro obfuscation SDK
```

---

## 4. Building and Running

```bash
./examples/five_macros_demo/build_and_run.sh
```

**Observed Execution Output:**
```text
==================================================================
🛡️  ASGARD-5877: 5 Virtualized Macro Functions Test
==================================================================
[1] validate_license():
    Genuine Key:  ✅ VALID (res=1)
    Tampered Key: ✅ REJECTED (res=0)

[2] derive_token():
    Computed: 0x32235, Expected: 0x32235 (✅ MATCH)

[3] compute_checksum():
    Computed: 0x7AED99, Expected: 0x7AED99 (✅ MATCH)

[4] scramble_hwid():
    Computed: 0x3721FFE878, Expected: 0x3721FFE878 (✅ MATCH)

[5] eval_permission():
    Authorized: ✅ GRANTED (got 0xCAFE1329, expected 0xCAFE1329)
    Denied:     ✅ DENIED (0) (got 0x0)
==================================================================
Result: 🎉 ALL 5 MACROS PASSED
==================================================================
```

---

## 5. Automated idasql Security Audit

```bash
./examples/five_macros_demo/audit_idasql.sh
```

Verifies:
- **0 leaked strings or marker names** in the binary metadata.
- **5 distinct `macro_salt` arguments** in C++ trampolines (`159`, `1`, `41`, `165`, `223`).
- **5 separate obfuscated subroutines** in the binary disassembler (`funcs` virtual table).
