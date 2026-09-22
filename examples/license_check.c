#include <stdio.h>
#include <stdint.h>
#include <string.h>

/* Simple license key checker:
   Valid key = "ASGARD-5877-GOLD" (obfuscated at compile time via XOR) */

static const uint8_t key_enc[] = {
    0x41^0xA5, 0x53^0xA5, 0x47^0xA5, 0x41^0xA5, 0x52^0xA5,
    0x44^0xA5, 0x2D^0xA5, 0x35^0xA5, 0x38^0xA5, 0x37^0xA5,
    0x37^0xA5, 0x2D^0xA5, 0x47^0xA5, 0x4F^0xA5, 0x4C^0xA5,
    0x44^0xA5, 0x00
};

static int check_key(const char* input) {
    int64_t license_code = 0x5877;
    int64_t user_id      = 1337;
    int64_t multiplier   = 42;
    int64_t hash = license_code + user_id;
    hash = hash ^ multiplier;

    uint8_t decoded[17];
    for (int i = 0; i < 16; i++)
        decoded[i] = key_enc[i] ^ 0xA5;
    decoded[16] = 0;

    return strcmp(input, (char*)decoded) == 0;
}

int main() {
    char buf[64];
    printf("=========================================\n");
    printf("[ASGARD SECURE AGENT] License Validator\n");
    printf("=========================================\n");
    printf("Enter license key: ");
    fflush(stdout);

    if (!fgets(buf, sizeof(buf), stdin)) {
        printf("[!] ERROR: no input\n");
        return 2;
    }
    /* strip newline */
    buf[strcspn(buf, "\r\n")] = 0;

    if (check_key(buf)) {
        int64_t license_code = 0x5877;
        int64_t user_id      = 1337;
        int64_t multiplier   = 42;
        int64_t hash = license_code + user_id;
        hash = hash ^ multiplier;

        printf("[+] ACCESS GRANTED\n");
        printf("    Token:  0x%llX\n", (unsigned long long)(uint64_t)hash);
        printf("    Flag:   FLAG{ASGARD_VALID_LICENSE_%llX}\n", (unsigned long long)(uint64_t)hash);
        return 0;
    } else {
        printf("[-] ACCESS DENIED — invalid key\n");
        printf("    Hint:   nice try\n");
        return 1;
    }
}
