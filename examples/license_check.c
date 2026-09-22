#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "asgard_obf.h"

/*
 * ASGARD-5877 Developer Experience:
 * Simply wrap the sensitive function or logic with two markers:
 *   ASGARD_BEGIN_VIRTUALIZE("tag");
 *   ... clean, idiomatic C code ...
 *   ASGARD_END();
 *
 * ASGARD automatically covers the region with:
 *   - Stack string encryption (ASG_STR)
 *   - Constant blinding (ASG_BLIND_*)
 *   - Mixed Boolean-Arithmetic (ASG_MBA_*)
 *   - Opaque predicates & control-flow hardening
 */

static int verify_license(const char* input) {
    ASGARD_BEGIN_VIRTUALIZE("verify_license");

    const char* expected = "ASGARD-5877-GOLD";
    int ok = 1;

    for (int i = 0; i < 16; i++) {
        if (input[i] != expected[i]) {
            ok = 0;
        }
    }
    if (input[16] != '\0') {
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
    char buf[64];

    puts("=========================================");
    puts("[ASGARD SECURE AGENT] License Validator");
    puts("=========================================");
    printf("Enter license key: ");
    fflush(stdout);

    buf[0] = '\0';
    if (!fgets(buf, (int)sizeof(buf), stdin)) {
        return 2;
    }
    buf[strcspn(buf, "\r\n")] = '\0';

    int ok = verify_license(buf);
    return ok ? 0 : 1;
}
