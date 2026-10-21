package com.asgard.security

/**
 * Android security facade interfacing with the ASGARD-protected native .so library.
 */
class AsgardSecurity {
    companion object {
        const val DEFAULT_LIB_PATH = "/data/local/tmp/libasgard_security.so"

        fun load(path: String = DEFAULT_LIB_PATH) {
            System.load(path)
        }
    }

    /**
     * Executes the license verification algorithm entirely inside the ASGARD Virtual Machine.
     */
    external fun verifyLicense(licenseKey: Long, hwid: Long): Long

    /**
     * Derives a cryptographic session token inside the ASGARD Virtual Machine.
     */
    external fun deriveToken(sessionId: Long, nonce: Long): Long
}
