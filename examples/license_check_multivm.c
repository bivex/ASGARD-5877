#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "asgard_obf.h"

/*
 * ASGARD-5877 Multi-VM Nested Stack License Validator:
 * Pure computational verification running inside the Heterogeneous Dual-VM
 * (Math-VM & Flow-VM) with affine zero-bridge state morphing and nested stack scheduling.
 */

__attribute__((noinline))
int64_t verify_license_nested(uint64_t part1, uint64_t part2) {
    ASGARD_BEGIN_VIRTUALIZE("verify_license_nested");

    /* "ASGARD-5" = 0x4153474152442D35ULL */
    /* "877-GOLD" = 0x3837372D474F4C44ULL */
    if (part1 == 0x4153474152442D35ULL && part2 == 0x3837372D474F4C44ULL) {
        int64_t license_code = 0x5877;
        int64_t user_id = 1337;
        int64_t multiplier = 42;
        int64_t token = (license_code + user_id) ^ multiplier;
        return token;
    }

    return 0;
    ASGARD_END();
}

int main(void) {
    char buf[64];

    puts("=========================================");
    puts("[ASGARD SECURE AGENT] Multi-VM License Validator");
    puts("=========================================");
    printf("Enter license key: ");
    fflush(stdout);

    buf[0] = '\0';
    if (!fgets(buf, (int)sizeof(buf), stdin)) {
        return 1;
    }
    buf[strcspn(buf, "\r\n")] = '\0';

    if (strlen(buf) != 16) {
        printf("[-] ACCESS DENIED — invalid key\n");
        printf("    Hint:   nice try\n");
        return 1;
    }

    uint64_t part1 = 0, part2 = 0;
    for (int i = 0; i < 8; i++) {
        part1 = (part1 << 8) | (uint8_t)buf[i];
        part2 = (part2 << 8) | (uint8_t)buf[i + 8];
    }

    int64_t token = verify_license_nested(part1, part2);

    if (token != 0) {
        printf("[+] ACCESS GRANTED\n");
        printf("    Token:  0x%llX\n", (unsigned long long)token);
        printf("    Flag:   FLAG{ASGARD_VALID_LICENSE_%llX}\n", (unsigned long long)token);
        return 0;
    } else {
        printf("[-] ACCESS DENIED — invalid key\n");
        printf("    Hint:   nice try\n");
        return 1;
    }
}
