#include "vm_out/threaded_vm.hpp"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// ----------------------------------------------------------------------------
// 1. Embedded Encrypted Bytecode for License Checking Algorithm
// (Synthesized by ASGARD-5877 VM Protector with MBA + CFF + Positional PRF)
// ----------------------------------------------------------------------------
static const uint64_t license_bytecode[] = {
    0xFFFF0AD840A0A3FCULL,
    0xFFFFFFFFCC24FA31ULL,
    0xFFFFFFFFB610C4BFULL,
    0x000000017C2FDFD4ULL,
    0x0000000042599923ULL,
    0x0000000067B3161DULL,
    0x0000000015262FF3ULL,
    0x0000CA4BE77E6462ULL,
    0xFFFE52F6A8BA7317ULL,
    0x00000000168FB36AULL,
    0x00000000781D4F56ULL,
    0xFFFFFFFFA2ACBBD0ULL,
    0x00000000049C0F11ULL,
    0x000000007790B663ULL,
    0xFFFFFFFFAC4939E1ULL,
    0xFFFFFFFF87038341ULL,
    0x0000000078859535ULL,
    0x0000F527FF2ECDC9ULL,
    0x00000013035A15F1ULL,
    0xFFFE52F6F4CDCED7ULL,
    0xFFFFFFEADDFFA874ULL,
    0xFFFF35B4224529AFULL,
    0x000000106880A7A3ULL,
};


// ----------------------------------------------------------------------------
// 2. Hardware ID (HWID) Helper
// ----------------------------------------------------------------------------
uint64_t get_machine_hwid() {
    // In production: Hash of CPUID + Motherboard Serial + MAC Address
    // Deterministic hardware anchor for demonstration
    return 100ULL;
}


// ----------------------------------------------------------------------------
// 3. Virtualized License Verification Routine
// ----------------------------------------------------------------------------
bool verify_license_in_vm(uint64_t hwid, uint64_t user_serial) {
    vanguard_threaded_vm::VMContext ctx = {};

    // Standard x86_64 Calling Convention in ASGARD-5877 VM:
    // RAX = ctx.gprs[0] (Return Value)
    // RSI = ctx.gprs[6] (Arg 2: Serial Key)
    // RDI = ctx.gprs[7] (Arg 1: HWID)
    ctx.gprs[0] = 0;           // RAX
    ctx.gprs[7] = hwid;        // RDI (HWID)
    ctx.gprs[6] = user_serial; // RSI (Serial Key)

    // Execute in Direct Threaded VM with rolling key decryption
    bool success = vanguard_threaded_vm::execute_threaded(
        ctx,
        license_bytecode,
        sizeof(license_bytecode) / sizeof(license_bytecode[0])
    );

    // printf("DEBUG: VM success=%d, RAX=%llu, ctx.gprs[7]=%llu, ctx.gprs[6]=%llu\n", (int)success, (unsigned long long)ctx.gprs[0], (unsigned long long)ctx.gprs[7], (unsigned long long)ctx.gprs[6]);

    // Return true if VM executed successfully and returned RAX == 1
    return success && (ctx.gprs[0] == 1ULL);


}


// ----------------------------------------------------------------------------
// 4. Application Entry Point
// ----------------------------------------------------------------------------
int main(int argc, char** argv) {
    printf("=================================================================\n");
    printf("     ASGARD-5877 HARDENED LICENSING DEMO (VM PROTECTED)          \n");
    printf("=================================================================\n\n");

    uint64_t current_hwid = get_machine_hwid();
    printf("[*] Detected Machine HWID : 0x%016llX\n", (unsigned long long)current_hwid);

    // Secret algorithm in VM: expected = ((hwid ^ 0x5877) * 42) + 0x1337
    uint64_t valid_serial = ((current_hwid ^ 0x5877ULL) * 42ULL) + 0x1337ULL;
    uint64_t fake_serial  = 0xDEADBEEFCAFE0001ULL;

    if (argc >= 2) {
        uint64_t user_key = strtoull(argv[1], NULL, 0);
        printf("[*] Testing user supplied key: 0x%016llX\n", (unsigned long long)user_key);
        if (verify_license_in_vm(current_hwid, user_key)) {
            printf("[+] SUCCESS: License Key is VALID! Full features unlocked.\n");
            return 0;
        } else {
            printf("[-] ERROR: Invalid License Key for this machine!\n");
            return 1;
        }
    }

    // Automated Demonstration Mode:
    printf("\n--- Test 1: Testing Genuine Serial Key ---\n");
    printf("    Serial: 0x%016llX\n", (unsigned long long)valid_serial);
    if (verify_license_in_vm(current_hwid, valid_serial)) {
        printf("    Result: [+] VALID! Access Granted.\n");
    } else {
        printf("    Result: [-] FAILED! Access Denied.\n");
    }

    printf("\n--- Test 2: Testing Pirate / Cracked Serial Key ---\n");
    printf("    Serial: 0x%016llX\n", (unsigned long long)fake_serial);
    if (verify_license_in_vm(current_hwid, fake_serial)) {
        printf("    Result: [+] VALID! Access Granted.\n");
    } else {
        printf("    Result: [-] INVALID! Access Denied (VM Trap / Mismatch).\n");
    }

    printf("\n--- Test 3: Testing Valid Key on Different HWID (Key Sharing) ---\n");
    uint64_t foreign_hwid = 0x9999888877776666ULL;
    printf("    Foreign HWID: 0x%016llX\n", (unsigned long long)foreign_hwid);
    if (verify_license_in_vm(foreign_hwid, valid_serial)) {
        printf("    Result: [+] VALID! Access Granted.\n");
    } else {
        printf("    Result: [-] INVALID! License tied to original HWID only.\n");
    }

    printf("\n=================================================================\n");
    return 0;
}
