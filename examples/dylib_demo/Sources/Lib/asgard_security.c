#include "asgard_security.h"
#include "asgard_obf.h"
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==============================================================================
// ASGARD-5877: Shared Dynamic Library Implementation (.dylib / .so)
//
// Demonstrates how macros and the virtual machine operate inside a dynamic library:
// 1. MACRO LAYER:
//    - ASGARD_BEGIN_VIRTUALIZE / ASGARD_END delimit code blocks for virtualization.
//    - ASG_MBA_ADD / ASG_MBA_XOR perform non-linear arithmetic obfuscation.
//    - ASG_STR decrypts strings on a volatile stack buffer to defeat `strings`.
// 2. VIRTUAL MACHINE LAYER:
//    - The functions below are translated into encrypted bytecode chunks.
//    - At runtime, the caller's arguments are loaded into guest VM registers.
//    - The execution runs inside the ASGARD VM dispatcher with rolling XOR keys.
// ==============================================================================

ASGARD_API uint64_t asgard_verify_license(uint64_t license_key, uint64_t hwid) {
    uint64_t result = 0;

    // --- Virtualized Region 1: License Verification Algorithm ---
    ASGARD_BEGIN_VIRTUALIZE("VerifyLicense");

    uint64_t secret = 0x5877ULL;
    uint64_t mult = 42ULL;
    uint64_t salt = 0x1337ULL;

    uint64_t hash = ASG_MBA_ADD((license_key ^ secret) * mult, salt);
    if (hash == hwid) {
        result = 1;
    } else {
        result = 0;
    }

    ASGARD_END();
    return result;
}

ASGARD_API uint64_t asgard_derive_token(uint64_t session_id, uint64_t nonce) {
    uint64_t token = 0;

    // --- Virtualized Region 2: Token Derivation Algorithm ---
    ASGARD_BEGIN_VIRTUALIZE("DeriveToken");

    uint64_t key1 = 0x5877ULL;
    uint64_t factor = 31ULL;
    uint64_t key2 = 0xCAFEULL;

    token = ((session_id ^ key1) * factor) + nonce + key2;
    __asm__ volatile("" : "+r"(token));

    ASGARD_END();
    return token;
}
#ifdef __cplusplus
}
#endif
