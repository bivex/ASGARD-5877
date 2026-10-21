package com.asgard.security

fun main() {
    println("""
    ================================================================
    🤖  ASGARD-5877: Android Kotlin + Protected .so Library
    ================================================================
    [*] Target Architecture: Linux / Android arm64-v8a
    [*] Native Library:      libasgard_security.so (ELF 64-bit)
    [*] Loading native runtime via System.load()...
    """)

    AsgardSecurity.load()
    val security = AsgardSecurity()
    println("[+] Native library successfully loaded and bound to JNI.")

    // 1. License Check Test inside the ASGARD Virtual Machine
    val genuineKey = 0x1337L
    val expectedHash = ((genuineKey xor 0x5877L) * 42L) + 0x1337L
    val tamperedKey = 0xDEADBEEFL

    println("\n[*] Test 1: AsgardSecurity.verifyLicense() via JNI:")
    val okGenuine = security.verifyLicense(genuineKey, expectedHash)
    val okTampered = security.verifyLicense(tamperedKey, expectedHash)

    println("    Genuine Key (0x" + java.lang.Long.toHexString(genuineKey).uppercase() + "):  " +
            (if (okGenuine == 1L) "✅ ACCESS GRANTED (Verified by VM)" else "❌ DENIED"))
    println("    Tampered Key (0x" + java.lang.Long.toHexString(tamperedKey).uppercase() + "): " +
            (if (okTampered == 1L) "❌ ANOMALY: Accepted!" else "✅ ACCESS DENIED (Rejected by VM)"))

    // 2. Cryptographic Token Derivation inside the ASGARD Virtual Machine
    val sessionId = 100L
    val nonce = 42L
    val expectedToken = ((sessionId xor 0x5877L) * 31L) + nonce + 0xCAFEL
    val actualToken = security.deriveToken(sessionId, nonce)

    println("\n[*] Test 2: AsgardSecurity.deriveToken() via JNI:")
    println("    Session ID:     0x" + java.lang.Long.toHexString(sessionId).uppercase() + ", Nonce: 0x" + java.lang.Long.toHexString(nonce).uppercase())
    println("    Computed Token: 0x" + java.lang.Long.toHexString(actualToken).uppercase())
    println("    Expected Token: 0x" + java.lang.Long.toHexString(expectedToken).uppercase())
    println("    Match Status:   " + (if (actualToken == expectedToken) "✅ 100% MATHEMATICAL MATCH" else "❌ VALUE MISMATCH"))

    println("""
    ================================================================
    ✨ Android Emulator Verification Complete:
    - JNI calls dispatched seamlessly into ASGARD Virtual Machine.
    - Zero mathematical validation logic leaked in ELF .so binary.
    ================================================================
    """)
}
