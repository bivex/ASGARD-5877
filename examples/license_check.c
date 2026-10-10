#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "asgard_obf.h"

/*
 * ASGARD-5877 Complete Caller Assimilation Architecture:
 * The entire application entrypoint workflow runs inside the virtual machine:
 *   - Input reading (fgets/strcspn) executes inside the VM via virtual FFI dispatch
 *   - Validation logic and key verification execute purely in VM-IR bytecode
 *   - main() itself is fully virtualized; its native stub is a single jump to asgard_vm_call()
 *   - The boolean validation barrier is completely eliminated: no hookable sub_XXXX exists
 */

int main(void) {
    ASGARD_BEGIN_VIRTUALIZE("main");

    char buf[64];

    puts("=========================================");
    puts("[ASGARD SECURE AGENT] License Validator");
    puts("=========================================");
    printf("Enter license key: ");
    fflush(stdout);

    buf[0] = '\0';
    if (!fgets(buf, (int)sizeof(buf), stdin)) {
        return 1;
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
    return ok ? 0 : 1;
}
