#include "threaded_vm.hpp"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define FLAG_LEN 50

static const uint8_t g_cipher_payload[FLAG_LEN] = {
    0xD2, 0xAA, 0x86, 0x55, 0x77, 0xAD, 0x9E, 0x70, 0x5C, 0x35, 0x94, 0xBD, 0x52, 0x46, 0x7A, 0xA9,
    0xDE, 0xC6, 0xA7, 0x53, 0x64, 0x87, 0xB8, 0x8B, 0x52, 0x3F, 0xC8, 0xD2, 0x0C, 0xCF, 0xEE, 0x80,
    0x11, 0x75, 0xB9, 0x76, 0x10, 0xF5, 0x37, 0xF3, 0x10, 0x64, 0x3B, 0x5C, 0x0C, 0x67, 0x22, 0x2C,
    0xDA, 0xF7
};

static inline uint64_t splitmix64(uint64_t* state) {
    *state += 0x9E3779B97F4A7C15ULL;
    uint64_t z = *state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

static uint64_t* load_bytecode(const char* filepath, size_t* out_len) {
    FILE* f = fopen(filepath, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0 || (sz % 8) != 0) {
        fclose(f);
        return NULL;
    }
    size_t count = (size_t)sz / 8;
    uint64_t* buf = (uint64_t*)malloc((size_t)sz);
    if (!buf || fread(buf, 8, count, f) != count) {
        if (buf) free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *out_len = count;
    return buf;
}

int main(int argc, char** argv) {
    printf("=========================================================================\n");
    printf("        ASGARD-5877 CRYPTOGRAPHIC HARDENED 128-BIT LICENSE VAULT         \n");
    printf("=========================================================================\n");

    if (argc < 2) {
        printf("[*] Usage: %s <LICENSE-KEY> [path/to/protected.vanguard]\n", argv[0]);
        printf("[*] Format: ASGARD-XXXXXXXXXXXXXXXX-XXXXXXXXXXXXXXXX (128-bit key)\n");
        return 1;
    }

    const char* key = argv[1];
    if (strncmp(key, "ASGARD-", 7) != 0) {
        printf("\n[-] ACCESS DENIED: Invalid Key Prefix (must start with ASGARD-)\n");
        return 1;
    }

    uint64_t k_hi = 0, k_lo = 0;
    int parsed = sscanf(key + 7, "%llx-%llx", (unsigned long long*)&k_hi, (unsigned long long*)&k_lo);
    if (parsed != 2) {
        // Try alternate 8-chunk format: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
        unsigned int p[8] = {0};
        int parsed8 = sscanf(key + 7, "%04x-%04x-%04x-%04x-%04x-%04x-%04x-%04x",
                             &p[0], &p[1], &p[2], &p[3], &p[4], &p[5], &p[6], &p[7]);
        if (parsed8 == 8) {
            k_hi = ((uint64_t)p[0] << 48) | ((uint64_t)p[1] << 32) | ((uint64_t)p[2] << 16) | (uint64_t)p[3];
            k_lo = ((uint64_t)p[4] << 48) | ((uint64_t)p[5] << 32) | ((uint64_t)p[6] << 16) | (uint64_t)p[7];
        } else {
            printf("\n[-] ACCESS DENIED: Hex Parsing Error for 128-bit Key\n");
            return 1;
        }
    }

    // Load Bytecode
    const char* bc_file = (argc >= 3) ? argv[2] : "protected.vanguard";
    size_t bc_len = 0;
    uint64_t* bc_ptr = load_bytecode(bc_file, &bc_len);
    if (!bc_ptr) {
        // Try loading from same directory as executable
        char fallback_path[512];
        snprintf(fallback_path, sizeof(fallback_path), "./binaries/crackme_arm64/protected.vanguard");
        bc_ptr = load_bytecode(fallback_path, &bc_len);
    }

    if (!bc_ptr) {
        printf("\n[-] Error: Could not locate protected.vanguard bytecode payload\n");
        return 1;
    }

    // Initialize Vanguard Virtual Machine Context
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi(k_hi);
    ctx.set_rsi(k_lo);

    // Execute Virtual Machine Bytecode
    bool vm_ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr, bc_len);
    free(bc_ptr);

    if (!vm_ok) {
        printf("\n[-] FATAL: Virtual Machine execution faulted (tampering detected)\n");
        return 1;
    }

    uint64_t vm_token = ctx.get_rax();

    // Decrypt Payload (Oracle-Free Trapdoor)
    uint64_t state = vm_token;
    char flag_out[FLAG_LEN + 1];
    for (int i = 0; i < FLAG_LEN; i++) {
        uint64_t k = splitmix64(&state);
        flag_out[i] = (char)(g_cipher_payload[i] ^ (k & 0xFF));
    }
    flag_out[FLAG_LEN] = '\0';

    // Verify header signature
    if (strncmp(flag_out, "FLAG{", 5) == 0 && flag_out[FLAG_LEN - 1] == '}') {
        printf("\n[+] SUCCESS! 128-BIT KEY VALIDATED (Derived Token: 0x%016llX)\n", (unsigned long long)vm_token);
        printf("[+] PAYLOAD UNLOCKED: %s\n", flag_out);
        printf("=========================================================================\n");
        return 0;
    } else {
        printf("\n[-] ACCESS DENIED: Invalid License Key! Decryption resulted in corrupt state.\n");
        return 1;
    }
}
