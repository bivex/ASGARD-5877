#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "asgard_obf.h"

// ==============================================================================
// ASGARD-5877: 5 Virtualized Macro Functions in a Single Binary
//
// Demonstrates that when multiple functions are protected in the same project:
// 1. Each function gets its own isolated bytecode array (embedded_bytecode_<fn>[]).
// 2. Each function gets its own unique per-macro opcode salt (macro_salt).
// 3. An attacker recovering the opcode map for one function gets 0 useful data
//    for the other 4 functions, as opcodes are non-transferable across functions.
// ==============================================================================

// 1. License verification routine
uint64_t validate_license(uint64_t key, uint64_t hwid) {
    uint64_t result = 0;
    ASGARD_BEGIN_VIRTUALIZE("ValidateLicense");
    uint64_t expected = ASG_MBA_ADD((key ^ 0x5877ULL) * 42ULL, 0x1337ULL);
    if (expected == hwid) {
        result = 1;
    } else {
        result = 0;
    }
    ASGARD_END();
    return result;
}

// 2. Token derivation routine
uint64_t derive_token(uint64_t session, uint64_t nonce) {
    uint64_t token = 0;
    ASGARD_BEGIN_VIRTUALIZE("DeriveToken");
    token = ((session ^ 0x1337ULL) * 31ULL) + nonce + 0xCAFEULL;
    __asm__ volatile("" : "+r"(token));
    ASGARD_END();
    return token;
}

// 3. Cryptographic checksum calculation
uint64_t compute_checksum(uint64_t a, uint64_t b) {
    uint64_t res = 0;
    ASGARD_BEGIN_VIRTUALIZE("ComputeChecksum");
    res = ((a ^ b) * 17ULL) ^ (a + b + 0x5877ULL);
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}

// 4. Hardware ID scrambler
uint64_t scramble_hwid(uint64_t raw_id, uint64_t mask) {
    uint64_t res = 0;
    ASGARD_BEGIN_VIRTUALIZE("ScrambleHwid");
    res = (raw_id * 63ULL) + mask + 0x112233ULL;
    __asm__ volatile("" : "+r"(res));
    ASGARD_END();
    return res;
}
uint64_t eval_permission(uint64_t role_bits, uint64_t req_bits) {
    uint64_t res = 0;
    ASGARD_BEGIN_VIRTUALIZE("EvalPermission");
    if ((role_bits & req_bits) == req_bits) {
        res = (role_bits ^ 0xCAFE1337ULL) + 1ULL;
    } else {
        res = 0;
    }
    ASGARD_END();
    return res;
}

int main(void) {
    printf("==================================================================\n");
    printf("🛡️  ASGARD-5877: 5 Virtualized Macro Functions Test\n");
    printf("==================================================================\n");

    // Test 1: validate_license
    uint64_t key = 0x1337ULL;
    uint64_t expected_hwid = ((key ^ 0x5877ULL) * 42ULL) + 0x1337ULL;
    uint64_t r1_ok = validate_license(key, expected_hwid);
    uint64_t r1_bad = validate_license(key, 0xDEADBEEFULL);
    printf("[1] validate_license():\n");
    printf("    Genuine Key:  %s (res=%llu)\n", r1_ok == 1 ? "✅ VALID" : "❌ INVALID", (unsigned long long)r1_ok);
    printf("    Tampered Key: %s (res=%llu)\n", r1_bad == 0 ? "✅ REJECTED" : "❌ ANOMALY", (unsigned long long)r1_bad);

    // Test 2: derive_token
    uint64_t session = 100ULL, nonce = 42ULL;
    uint64_t expected_token = ((session ^ 0x1337ULL) * 31ULL) + nonce + 0xCAFEULL;
    uint64_t r2 = derive_token(session, nonce);
    printf("\n[2] derive_token():\n");
    printf("    Computed: 0x%llX, Expected: 0x%llX (%s)\n",
           (unsigned long long)r2, (unsigned long long)expected_token,
           r2 == expected_token ? "✅ MATCH" : "❌ MISMATCH");

    // Test 3: compute_checksum
    uint64_t a = 0x12345ULL, b = 0x6789AULL;
    uint64_t expected_chk = ((a ^ b) * 17ULL) ^ (a + b + 0x5877ULL);
    uint64_t r3 = compute_checksum(a, b);
    printf("\n[3] compute_checksum():\n");
    printf("    Computed: 0x%llX, Expected: 0x%llX (%s)\n",
           (unsigned long long)r3, (unsigned long long)expected_chk,
           r3 == expected_chk ? "✅ MATCH" : "❌ MISMATCH");

    // Test 4: scramble_hwid
    uint64_t raw_id = 0xDEADBEEFULL, mask = 0x55555555ULL;
    uint64_t r4 = scramble_hwid(raw_id, mask);
    uint64_t expected_hw = (raw_id * 63ULL) + mask + 0x112233ULL;
    printf("\n[4] scramble_hwid():\n");
    printf("    Computed: 0x%llX, Expected: 0x%llX (%s)\n",
           (unsigned long long)r4, (unsigned long long)expected_hw,
           r4 == expected_hw ? "✅ MATCH" : "❌ MISMATCH");

    // Test 5: eval_permission
    uint64_t role = 0b11111ULL, req = 0b00101ULL;
    uint64_t expected_perm = (role ^ 0xCAFE1337ULL) + 1ULL;
    uint64_t r5_ok = eval_permission(role, req);
    uint64_t r5_denied = eval_permission(0b00010ULL, req);
    printf("\n[5] eval_permission():\n");
    printf("    Authorized: %s (got 0x%llX, expected 0x%llX)\n",
           r5_ok == expected_perm ? "✅ GRANTED" : "❌ FAILED", (unsigned long long)r5_ok, (unsigned long long)expected_perm);
    printf("    Denied:     %s (got 0x%llX)\n",
           r5_denied == 0 ? "✅ DENIED (0)" : "❌ FAILED", (unsigned long long)r5_denied);

    printf("==================================================================\n");
    int all_passed = (r1_ok == 1 && r1_bad == 0 && r2 == expected_token &&
                      r3 == expected_chk && r4 == expected_hw &&
                      r5_ok == expected_perm && r5_denied == 0);
    printf("Result: %s\n", all_passed ? "🎉 ALL 5 MACROS PASSED" : "💥 TEST FAILED");
    printf("==================================================================\n");
    return all_passed ? 0 : 1;
}
