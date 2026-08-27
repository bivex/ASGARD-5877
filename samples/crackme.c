#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define FLAG_LEN 45

static const uint8_t g_cipher_payload[FLAG_LEN] = {
    0x5F, 0xD4, 0x19, 0xEB, 0x75, 0xE9, 0x90, 0xF8, 0x36, 0x91, 0xD4, 0xC9, 0x43, 0x0D, 0x99, 0x49,
    0xAC, 0xA7, 0x97, 0x51, 0x6C, 0x17, 0xCF, 0x6F, 0xE0, 0x87, 0xF9, 0x98, 0x97, 0x03, 0x19, 0x4A,
    0x7A, 0x79, 0xD1, 0x9B, 0x66, 0x99, 0xB1, 0xB2, 0xBA, 0xEF, 0xBF, 0x2E, 0xB9
};

static inline uint16_t rol16(uint16_t v, unsigned int s) {
    s &= 15;
    return (uint16_t)((v << s) | (v >> (16 - s)));
}

static inline uint64_t splitmix64(uint64_t* state) {
    *state += 0x9E3779B97F4A7C15ULL;
    uint64_t z = *state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

__attribute__((noinline))
static int check_invariants(uint32_t b1, uint32_t b2, uint32_t b3, uint32_t b4) {
    uint32_t r1 = b1 ^ b2;
    if (r1 != 0xE123) return 0;

    uint32_t r2 = (b2 * 0x9E37 + b3) & 0xFFFF;
    if (r2 != 0xE892) return 0;

    uint32_t r3 = b3 ^ rol16((uint16_t)b4, 5);
    if (r3 != 0x80CB) return 0;

    uint32_t r4 = (b1 + b2 + b3 + b4) & 0xFFFF;
    if (r4 != 0x9153) return 0;

    return 1;
}

int main(int argc, char** argv) {
    printf("=========================================================================\n");
    printf("               REVERSE ENGINEERING CRACKME CHALLENGE                     \n");
    printf("=========================================================================\n");

    if (argc < 2) {
        printf("[*] Expected format: FLAG-XXXX-XXXX-XXXX-XXXX\n");
        exit(1);
    }

    const char* key = argv[1];
    if (strlen(key) != 24) {
        printf("\n[-] ACCESS DENIED: Invalid Key Length\n");
        exit(1);
    }

    if (strncmp(key, "FLAG-", 5) != 0) {
        printf("\n[-] ACCESS DENIED: Invalid Key Prefix\n");
        exit(1);
    }

    unsigned int b1 = 0, b2 = 0, b3 = 0, b4 = 0;
    int parsed = sscanf(key + 5, "%04x-%04x-%04x-%04x", &b1, &b2, &b3, &b4);
    if (parsed != 4) {
        printf("\n[-] ACCESS DENIED: Hex Parsing Error\n");
        exit(1);
    }

    int ok = check_invariants(b1, b2, b3, b4);
    if (!ok) {
        printf("\n[-] ACCESS DENIED: Verification Failed! Incorrect Key.\n");
        exit(1);
    }

    uint64_t full_key = ((uint64_t)b1 << 48) | ((uint64_t)b2 << 32) | ((uint64_t)b3 << 16) | (uint64_t)b4;
    uint64_t state = full_key;

    char flag_out[48];
    for (int i = 0; i < FLAG_LEN; i++) {
        uint64_t k = splitmix64(&state);
        flag_out[i] = (char)(g_cipher_payload[i] ^ (k & 0xFF));
    }
    flag_out[FLAG_LEN] = '\0';

    printf("\n[+] SUCCESS! KEY VALIDATED (Token: 0x%016llX)\n", (unsigned long long)full_key);
    printf("[+] %s\n", flag_out);
    printf("=========================================================================\n");

    return 0;
}
