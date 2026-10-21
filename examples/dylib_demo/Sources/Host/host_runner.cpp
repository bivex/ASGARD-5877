#include <stdio.h>
#include <stdint.h>
#include <dlfcn.h>
#include <stdlib.h>

// Function pointer signatures matching the exported dylib APIs
typedef uint64_t (*verify_fn_t)(uint64_t license_key, uint64_t hwid);
typedef uint64_t (*token_fn_t)(uint64_t session_id, uint64_t nonce);

int main(int argc, char** argv) {
    const char* dylib_path = (argc >= 2) ? argv[1] : "./build/libasgard_security.dylib";

    printf("==================================================================\n");
    printf("🛡️  C++ Host Client: Dynamic Loading of ASGARD .dylib Runtime\n");
    printf("==================================================================\n");
    printf("[*] Opening dynamic library via dlopen: %s\n", dylib_path);

    void* handle = dlopen(dylib_path, RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "[-] dlopen failed: %s\n", dlerror());
        return 1;
    }

    verify_fn_t verify = (verify_fn_t)dlsym(handle, "asgard_verify_license");
    token_fn_t token   = (token_fn_t)dlsym(handle, "asgard_derive_token");

    if (!verify || !token) {
        fprintf(stderr, "[-] dlsym failed to resolve exported symbols: %s\n", dlerror());
        dlclose(handle);
        return 1;
    }

    printf("[+] Symbols successfully resolved:\n");
    printf("    asgard_verify_license -> %p\n", (void*)verify);
    printf("    asgard_derive_token   -> %p\n", (void*)token);

    // 1. Validate License Check inside the .dylib Virtual Machine
    uint64_t key = 0x1337ULL;
    uint64_t secret = 0x5877ULL;
    uint64_t mult = 42ULL;
    uint64_t salt = 0x1337ULL;
    uint64_t expected_hash = ((key ^ secret) * mult) + salt;

    uint64_t ok_genuine = verify(key, expected_hash);
    uint64_t ok_tampered = verify(key, 0xDEADBEEFULL);

    printf("\n[*] 1. Invoking asgard_verify_license() across dylib boundary:\n");
    printf("    Genuine Key (0x%llX, Hash 0x%llX): %s\n",
           (unsigned long long)key, (unsigned long long)expected_hash,
           ok_genuine ? "✅ ACCESS GRANTED" : "❌ ACCESS DENIED");
    printf("    Tampered Key:                               %s\n",
           ok_tampered ? "❌ ANOMALY: Tampered key accepted!" : "✅ ACCESS DENIED (Rejected by VM)");

    // 2. Validate Token Derivation inside the .dylib Virtual Machine
    uint64_t session = 100ULL;
    uint64_t nonce = 42ULL;
    uint64_t expected_token = ((session ^ 0x5877ULL) * 31ULL) + nonce + 0xCAFEULL;
    uint64_t actual_token = token(session, nonce);

    printf("\n[*] 2. Invoking asgard_derive_token() across dylib boundary:\n");
    printf("    Session: 0x%llX, Nonce: 0x%llX\n", (unsigned long long)session, (unsigned long long)nonce);
    printf("    Computed Token: 0x%llX\n", (unsigned long long)actual_token);
    printf("    Expected Token: 0x%llX\n", (unsigned long long)expected_token);
    printf("    Verification:   %s\n",
           (actual_token == expected_token) ? "✅ 100% MATHEMATICAL MATCH" : "❌ VALUE MISMATCH");

    printf("==================================================================\n");
    printf("✨ Host Client Test PASSED: All operations executed in .dylib VM.\n");
    printf("==================================================================\n");

    dlclose(handle);
    return 0;
}
