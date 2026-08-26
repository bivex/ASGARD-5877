#include <stdio.h>
#include <stdint.h>
#include "asgard_obf.h"

// Critical function with VMProtect-style marker delimiters
int64_t verify_serial(int64_t user_id, int64_t serial_key) {
    int64_t result = 0;

    // --- ONLY THIS REGION WILL BE VIRTUALIZED IN VM ---
    ASGARD_BEGIN_ULTRA("LicenseValidation");

    int64_t secret_mult = 0x5877;
    int64_t expected = (user_id ^ secret_mult) + 0x1337;

    if (serial_key == expected) {
        result = 1;
    } else {
        result = 0;
    }

    ASGARD_END();
    // --- END VIRTUALIZED REGION ---

    return result;
}

int main() {
    printf("Testing VMProtect-style marker delimiters in ASGARD-5877...\n");
    int64_t uid = 100;
    int64_t valid_key = (100 ^ 0x5877) + 0x1337;

    int64_t ok = verify_serial(uid, valid_key);
    printf("Verification result for key 0x%llX: %s\n", (unsigned long long)valid_key, ok ? "VALID" : "INVALID");
    return 0;
}
