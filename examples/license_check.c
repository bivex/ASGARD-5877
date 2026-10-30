#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "asgard_obf.h"

/*
 * ASGARD-5877
 * Complete Caller Assimilation Architecture
 *
 * Application workflow:
 *   - Input reading through virtual FFI
 *   - License validation inside VM-IR
 *   - Character-by-character comparison
 *   - Token generation
 *   - Virtualized main()
 *
 * Valid license:
 *   ASGARD-5877-GOLD
 */

#define LICENSE_LENGTH 16

#define LICENSE_CODE  0x5877
#define USER_ID       1337
#define MULTIPLIER    42

static int validate_license(const char *input)
{
    ASGARD_BEGIN_VIRTUALIZE("validate_license");

    const char *expected = "ASGARD-5877-GOLD";

    int ok = 1;

    for (int i = 0; i < LICENSE_LENGTH; i++) {
        if (input[i] != expected[i]) {
            ok = 0;
        }
    }

    if (input[LICENSE_LENGTH] != '\0') {
        ok = 0;
    }

    ASGARD_END();

    return ok;
}

static uint64_t generate_token(void)
{
    ASGARD_BEGIN_VIRTUALIZE("generate_token");

    int64_t license_code = LICENSE_CODE;
    int64_t user_id = USER_ID;
    int64_t multiplier = MULTIPLIER;

    uint64_t token =
        (uint64_t)((license_code + user_id) ^ multiplier);

    ASGARD_END();

    return token;
}

int main(void)
{
    ASGARD_BEGIN_VIRTUALIZE("main");

    char buf[64] = {0};

    puts("=========================================");
    puts("[ASGARD SECURE AGENT] License Validator");
    puts("=========================================");

    printf("Enter license key: ");
    fflush(stdout);

    if (fgets(buf, sizeof(buf), stdin) == NULL) {
        ASGARD_END();
        return 1;
    }

    buf[strcspn(buf, "\r\n")] = '\0';

    int ok = validate_license(buf);

    if (ok) {
        uint64_t token = generate_token();

        printf("[+] ACCESS GRANTED\n");

        printf("    Token:  0x%llX\n",
            (unsigned long long)token);

        printf("    Flag:   FLAG{ASGARD_VALID_LICENSE_%llX}\n",
            (unsigned long long)token);

    } else {
        printf("[-] ACCESS DENIED — invalid key\n");
        printf("    Hint:   nice try\n");
    }

    int exit_code = ok ? 0 : 1;

    ASGARD_END();

    return exit_code;
}
