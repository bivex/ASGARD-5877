#include "vm_out/threaded_vm.hpp"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// ----------------------------------------------------------------------------
// 1. Embedded Encrypted Bytecode for License Checking Algorithm
// (Synthesized by ASGARD-5877 VM Protector with MBA + CFF + Positional PRF)
#include <vector>

static std::vector<uint64_t> g_loaded_bytecode;

static const uint64_t* get_license_bytecode(size_t* out_len) {
    if (!g_loaded_bytecode.empty()) {
        *out_len = g_loaded_bytecode.size();
        return g_loaded_bytecode.data();
    }
    const char* paths[] = {
        "examples/license_demo/vm_out/protected.vanguard",
        "vm_out/protected.vanguard",
        "protected.vanguard",
        nullptr
    };
    for (int i = 0; paths[i]; ++i) {
        FILE* f = fopen(paths[i], "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (sz > 0 && (sz % 8) == 0) {
                g_loaded_bytecode.resize(sz / 8);
                if (fread(g_loaded_bytecode.data(), 8, g_loaded_bytecode.size(), f) == g_loaded_bytecode.size()) {
                    fclose(f);
                    *out_len = g_loaded_bytecode.size();
                    return g_loaded_bytecode.data();
                }
            }
            fclose(f);
        }
    }
    *out_len = 0;
    return nullptr;
}

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
    size_t bc_len = 0;
    const uint64_t* bc_ptr = get_license_bytecode(&bc_len);
    if (!bc_ptr || bc_len == 0) {
        fprintf(stderr, "[-] Failed to load protected.vanguard bytecode\n");
        return false;
    }

    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    // Standard x86_64 Calling Convention with Randomized Register Mapping (π ∈ S_32):
    // RAX = ctx.get_rax() (Return Value)
    // RSI = ctx.get_rsi() (Arg 2: Serial Key)
    // RDI = ctx.get_rdi() (Arg 1: HWID)
    ctx.set_rax(0);           // RAX
    ctx.set_rdi(hwid);        // RDI (HWID)
    ctx.set_rsi(user_serial); // RSI (Serial Key)

    // Execute in Direct Threaded VM with rolling key decryption & blinded context
    bool success = vanguard_threaded_vm::execute_threaded(
        ctx,
        bc_ptr,
        bc_len
    );

    // Return true if VM executed successfully and returned RAX == 1
    return success && (ctx.get_rax() == 1ULL);
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
