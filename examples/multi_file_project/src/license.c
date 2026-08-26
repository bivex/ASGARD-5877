#include <stdio.h>
#include <stdint.h>
#include "app_common.h"
#include "asgard_obf.h"

int64_t verify_license_module(int64_t hwid, int64_t user_serial) {
    int64_t valid = 0;

    // 🔒 ASGARD MARKER: ULTRA VM PROTECTION
    ASGARD_BEGIN_ULTRA("LicenseCore");

    int64_t mult = 0x5877;
    int64_t bias = 0x1337;
    int64_t expected = ((hwid ^ mult) * 42) + bias;

    if (user_serial == expected) {
        valid = 1;
    } else {
        valid = 0;
    }

    ASGARD_END();
    // 🔓 END MARKER

    return valid;
}
