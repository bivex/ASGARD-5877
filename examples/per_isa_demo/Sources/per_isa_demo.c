#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include "asgard_obf.h"

// ==============================================================================
// ASGARD-5877: Per-ISA Randomization & Polymorphic ISA Source Protection
//
// Shows how to protect security-critical routines with per-function randomized ISA:
//   - ASGARD_BEGIN_PER_ISA(tag):   Independent polymorphic ISA mapping
//   - ASGARD_BEGIN_RANDOM_ISA(tag): Dynamic per-macro opcode salting & permutation
//   - ASGARD_BEGIN_POLY_ISA(tag):   Metamorphic ISA diversification per routine
// ==============================================================================

// 1. License Verification with Per-ISA Randomization
uint64_t verify_serial(uint64_t serial, uint64_t hardware_id) {
    uint64_t result = 0;
    ASGARD_BEGIN_PER_ISA("VerifySerial");
    uint64_t expected = ASG_MBA_ADD((serial ^ 0x5877ULL) * 37ULL, 0x1337ULL);
    if (expected == hardware_id) {
        result = 1;
    } else {
        result = 0;
    }
    ASGARD_END();
    return result;
}

// 2. Cryptographic Session Key Generation with Random ISA
uint64_t generate_session_key(uint64_t client_seed, uint64_t server_nonce) {
    uint64_t key = 0;
    ASGARD_BEGIN_RANDOM_ISA("GenerateSessionKey");
    key = ((client_seed ^ server_nonce) * 63ULL) + (client_seed + 0xCAFEULL);
    __asm__ volatile("" : "+r"(key));
    ASGARD_END();
    return key;
}

// 3. Capability / Access Level Evaluator with Polymorphic ISA
uint64_t validate_access_level(uint64_t user_role, uint64_t required_mask) {
    uint64_t granted = 0;
    ASGARD_BEGIN_POLY_ISA("ValidateAccessLevel");
    if ((user_role & required_mask) == required_mask) {
        granted = (user_role ^ 0x58771337ULL) + 42ULL;
    } else {
        granted = 0;
    }
    ASGARD_END();
    return granted;
}

int main(void) {
    printf("==================================================================\n");
    printf("🛡️  ASGARD-5877: Per-ISA Polymorphic Randomization Demo\n");
    printf("==================================================================\n");

    // Test 1: verify_serial (ASGARD_BEGIN_PER_ISA)
    uint64_t serial = 0x2468ULL;
    uint64_t genuine_hwid = ((serial ^ 0x5877ULL) * 37ULL) + 0x1337ULL;
    uint64_t r1_ok = verify_serial(serial, genuine_hwid);
    uint64_t r1_bad = verify_serial(serial, 0xBAD1DEAULL);
    printf("[1] verify_serial() [ASGARD_BEGIN_PER_ISA]:\n");
    printf("    Genuine Serial:  %s (res=%llu)\n", r1_ok == 1 ? "✅ VALID" : "❌ INVALID", (unsigned long long)r1_ok);
    printf("    Tampered Serial: %s (res=%llu)\n", r1_bad == 0 ? "✅ REJECTED" : "❌ ANOMALY", (unsigned long long)r1_bad);

    // Test 2: generate_session_key (ASGARD_BEGIN_RANDOM_ISA)
    uint64_t seed = 0x1337ULL, nonce = 0x42ULL;
    uint64_t expected_key = ((seed ^ nonce) * 63ULL) + (seed + 0xCAFEULL);
    uint64_t r2 = generate_session_key(seed, nonce);
    printf("\n[2] generate_session_key() [ASGARD_BEGIN_RANDOM_ISA]:\n");
    printf("    Computed Key: 0x%llX, Expected: 0x%llX (%s)\n",
           (unsigned long long)r2, (unsigned long long)expected_key,
           r2 == expected_key ? "✅ MATCH" : "❌ MISMATCH");

    // Test 3: validate_access_level (ASGARD_BEGIN_POLY_ISA)
    uint64_t role = 0b11111ULL, mask = 0b00111ULL;
    uint64_t expected_access = (role ^ 0x58771337ULL) + 42ULL;
    uint64_t r3_ok = validate_access_level(role, mask);
    uint64_t r3_denied = validate_access_level(0b00010ULL, mask);
    printf("\n[3] validate_access_level() [ASGARD_BEGIN_POLY_ISA]:\n");
    printf("    Authorized: %s (got 0x%llX, expected 0x%llX)\n",
           r3_ok == expected_access ? "✅ GRANTED" : "❌ FAILED", (unsigned long long)r3_ok, (unsigned long long)expected_access);
    printf("    Denied:     %s (got 0x%llX)\n",
           r3_denied == 0 ? "✅ DENIED (0)" : "❌ FAILED", (unsigned long long)r3_denied);

    printf("==================================================================\n");
    int all_passed = (r1_ok == 1 && r1_bad == 0 && r2 == expected_key &&
                      r3_ok == expected_access && r3_denied == 0);
    printf("Result: %s\n", all_passed ? "🎉 ALL PER-ISA MACROS PASSED" : "💥 TEST FAILED");
    printf("==================================================================\n");
    return all_passed ? 0 : 1;
}
