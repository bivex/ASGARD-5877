#include "jni.h"
#include "asgard_obf.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==============================================================================
// ASGARD-5877: Android NDK Shared Library (JNI)
//
// Demonstrates how the ASGARD Polymorphic Virtual Machine protects Android .so
// native libraries called from Kotlin:
//   - Package: com.asgard.security
//   - Class:   AsgardSecurity
//
// Both JNI entrypoints below are virtualized into bytecode chunks with
// instruction-by-instruction rolling key cipher decryption and dynamic canary
// integrity checks.
// ==============================================================================

// JNI binding for: external fun verifyLicense(licenseKey: Long, hwid: Long): Long
JNIEXPORT jlong JNICALL
Java_com_asgard_security_AsgardSecurity_verifyLicense(JNIEnv *env, jobject thiz, jlong license_key, jlong hwid) {
    (void)env;
    (void)thiz;
    uint64_t result = 0;

    // --- Virtualized Region 1: JNI License Verification ---
    ASGARD_BEGIN_VIRTUALIZE("JniVerifyLicense");

    uint64_t key = (uint64_t)license_key;
    uint64_t secret = 0x5877ULL;
    uint64_t mult = 42ULL;
    uint64_t salt = 0x1337ULL;

    uint64_t expected = ASG_MBA_ADD((key ^ secret) * mult, salt);
    if (expected == (uint64_t)hwid) {
        result = 1;
    } else {
        result = 0;
    }

    ASGARD_END();
    return (jlong)result;
}

// JNI binding for: external fun deriveToken(sessionId: Long, nonce: Long): Long
JNIEXPORT jlong JNICALL
Java_com_asgard_security_AsgardSecurity_deriveToken(JNIEnv *env, jobject thiz, jlong session_id, jlong nonce) {
    (void)env;
    (void)thiz;
    uint64_t token = 0;

    // --- Virtualized Region 2: JNI Cryptographic Token Derivation ---
    ASGARD_BEGIN_VIRTUALIZE("JniDeriveToken");

    uint64_t sess = (uint64_t)session_id;
    uint64_t n = (uint64_t)nonce;
    uint64_t key1 = 0x5877ULL;
    uint64_t factor = 31ULL;
    uint64_t key2 = 0xCAFEULL;

    token = ((sess ^ key1) * factor) + n + key2;
    __asm__ volatile("" : "+r"(token));

    ASGARD_END();
    return (jlong)token;
}

#ifdef __cplusplus
}
#endif
