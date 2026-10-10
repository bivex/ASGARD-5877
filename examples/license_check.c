#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "asgard_obf.h"

/*
 * ASGARD-5877 Developer Experience: Caller Assimilation Architecture
 * By wrapping the entire entrypoint workflow in the virtualization region:
 *   ASGARD_BEGIN_VIRTUALIZE("main");
 *   ...
 *   ASGARD_END();
 *
 * ASGARD automatically assimilates the caller:
 *   - The caller entrypoint becomes a direct jump to asgard_vm_call()
 *   - Input reading (fgets/strcspn) executes inside the VM via virtual FFI dispatch
 *   - The boolean validation barrier is eliminated: no hookable sub_XXXX symbol exists
 *   - Return code and conditional grants are computed and returned directly from VM-IR
 */

static int verify_license(void) {
    ASGARD_BEGIN_VIRTUALIZE("verify_license");

    char buf[64];

    puts("=========================================");
    puts("[ASGARD SECURE AGENT] License Validator");
    puts("=========================================");
    printf("Enter license key: ");
    fflush(stdout);

    buf[0] = '\0';
    if (!fgets(buf, (int)sizeof(buf), stdin)) {
        return 0;
    }
    buf[strcspn(buf, "\r\n")] = '\0';

    const char* expected = "ASGARD-5877-GOLD";
    int ok = 1;

    for (int i = 0; i < 16; i++) {
        if (buf[i] != expected[i]) {
            ok = 0;
        }
    }
    if (buf[16] != '\0') {
        ok = 0;
    }

    if (ok) {
        int64_t license_code = 0x5877;
        int64_t user_id = 1337;
        int64_t multiplier = 42;
        int64_t token = (license_code + user_id) ^ multiplier;

        printf("[+] ACCESS GRANTED\n");
        printf("    Token:  0x%llX\n", (unsigned long long)token);
        printf("    Flag:   FLAG{ASGARD_VALID_LICENSE_%llX}\n", (unsigned long long)token);
    } else {
        printf("[-] ACCESS DENIED — invalid key\n");
        printf("    Hint:   nice try\n");
    }

    ASGARD_END();
    return ok;
}

int main(void) {
    int ok = verify_license();
    /*
     * Key-Dependent Invariant:
     * When valid (ok == 1): (ok ^ 1) == 0.
     * When invalid (ok == 0): (ok ^ 1) == 1.
     * Replaces conditional branch (cbnz) with a branchless arithmetic transform.
     */
    return ok ^ 1;
}
