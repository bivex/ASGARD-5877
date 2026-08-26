#include <stdio.h>
#include <stdint.h>
#include "asgard_obf.h"

/**
 * Real-world License & Feature Verification Routine
 * Wrapped with ASGARD-5877 VMProtect-style delimiters.
 * 
 * When protected with:
 *   ./random_visa protect -i examples/app.c -o ./dist --cff --mba --compile true
 * 
 * The marked region is automatically extracted, compiled to IR,
 * flattened with Control-Flow Flattening (CFF), scrambled with MBA,
 * and encrypted into a Direct-Threaded VM with rolling positional PRF keys.
 */
int64_t verify_license(int64_t hwid, int64_t user_serial) {
    int64_t is_valid = 0;

    // =========================================================================
    // 🔒 ASGARD PROTECTED REGION (VIRTUALIZED IN VM)
    // =========================================================================
    ASGARD_BEGIN_ULTRA("LicenseValidation");

    int64_t secret_mult = 0x5877;
    int64_t secret_bias = 0x1337;
    int64_t expected_key = ((hwid ^ secret_mult) * 42) + secret_bias;

    if (user_serial == expected_key) {
        is_valid = 1;
    } else {
        is_valid = 0;
    }

    ASGARD_END();
    // =========================================================================
    // 🔓 END OF PROTECTED REGION
    // =========================================================================

    return is_valid;
}

int main(int argc, char** argv) {
    printf("=================================================================\n");
    printf("        ASGARD-5877 1-CLICK MARKER OBFUSCATION DEMO              \n");
    printf("=================================================================\n\n");

    int64_t current_hwid = 100;
    int64_t valid_key    = ((100 ^ 0x5877) * 42) + 0x1337;
    int64_t invalid_key  = 0xDEADBEEFCAFE0001;

    printf("[*] Machine HWID: %lld\n", (long long)current_hwid);

    // Test 1: Genuine Key
    printf("\n[1] Testing Genuine License Key (0x%llX)...\n", (unsigned long long)valid_key);
    if (verify_license(current_hwid, valid_key)) {
        printf("    [+] SUCCESS: License Key is VALID! Full product unlocked.\n");
    } else {
        printf("    [-] ERROR: License Check FAILED!\n");
    }

    // Test 2: Pirate / Modified Key
    printf("\n[2] Testing Pirate / Cracked Key (0x%llX)...\n", (unsigned long long)invalid_key);
    if (verify_license(current_hwid, invalid_key)) {
        printf("    [+] SUCCESS: License Key is VALID!\n");
    } else {
        printf("    [-] REJECTED: Invalid License Key!\n");
    }

    printf("\n=================================================================\n");
    return 0;
}
