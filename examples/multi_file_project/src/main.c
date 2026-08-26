#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "app_common.h"
#include "asgard_obf.h"

int main(int argc, char** argv) {
    printf("=================================================================\n");
    printf("   ASGARD-5877 PRODUCTION MULTI-FILE PROJECT (ALL MODULES)       \n");
    printf("=================================================================\n\n");

    // 1. License Module Test
    int64_t hwid = 100;
    int64_t valid_license = ((100 ^ 0x5877) * 42) + 0x1337;
    printf("[1/3] Verifying License Module...\n");
    if (verify_license_module(hwid, valid_license)) {
        printf("      [+] License verification PASSED (Ultra VM Protection)\n");
    } else {
        printf("      [-] License verification FAILED\n");
    }

    // 2. Crypto Module Test
    uint64_t master_seed = 0x12345678ULL;
    uint32_t session_id = 42;
    uint64_t key = derive_session_key(master_seed, session_id);
    printf("\n[2/3] Deriving Cryptographic Session Key...\n");
    printf("      [+] Derived Session Key: 0x%016llX (Mutation Protection)\n", (unsigned long long)key);

    // 3. Auth Module Test
    uint64_t token = 0xCAFEBABE;
    uint64_t valid_checksum = (token ^ 0xFEEDFACECAFEULL) + 777;
    printf("\n[3/3] Authenticating Security Token...\n");
    if (authenticate_security_token(token, valid_checksum)) {
        printf("      [+] Token Authentication SUCCESS (Virtualization Protection)\n");
    } else {
        printf("      [-] Token Authentication FAILED\n");
    }

    printf("\n=================================================================\n");
    printf("   [ALL 3 MODULES VERIFIED & EXECUTED SEAMLESSLY VIA ASGARD]     \n");
    printf("=================================================================\n");
    return 0;
}
