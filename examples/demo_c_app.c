#include <stdio.h>
#include <stdint.h>

// Example proprietary algorithm in C
int main() {
    const char* flag = "FLAG{ASGARD_POLYMORPHIC_C_MACRO_OBFUSCATION_2026}";
    const char* status = "VERIFIED_LICENSE_KEY_VALID";

    int64_t license_code = 0x5877;
    int64_t user_id = 1337;
    int64_t multiplier = 42;

    int64_t hash = license_code + user_id;
    hash = hash ^ multiplier;

    printf("=========================================\n");
    printf("[ASGARD SECURE AGENT]\n");
    printf("  Status:       %s\n", status);
    printf("  Secret Flag:  %s\n", flag);
    printf("  Computed Hash: 0x%llX (%lld)\n", (unsigned long long)hash, (long long)hash);
    printf("=========================================\n");

    return 0;
}
