#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

__attribute__((noinline))
uint64_t verify_license_key(uint64_t seed_id, uint64_t payload) {
    uint64_t h = seed_id ^ 0x5877CAFEBABE1337ULL;
    for (int i = 0; i < 8; i++) {
        h = (h + payload + (uint64_t)i) ^ (h >> 13);
        h = (h * 0x9E3779B97F4A7C15ULL) ^ (h << 7);
    }
    if ((h & 0xFF) == 0x77) {
        return h ^ 0x1337;
    } else {
        return (h + 0x42) ^ 0xDEADBEEF;
    }
}

int main(int argc, char** argv) {
    printf("[*] ASGARD-5877 Hardware-Protected Sample Application Launching...\n");
    uint64_t test_seed = 0x20260827ULL;
    uint64_t payload = 0xCAFEBEEFULL;
    uint64_t res = verify_license_key(test_seed, payload);
    printf("[+] Core Algorithm Computed Token: 0x%016llX\n", (unsigned long long)res);
    if (res != 0) {
        printf("[+] Verification Verdict: ACCESS GRANTED (Execution Authentic)\n");
        return 0;
    }
    return 1;
}
