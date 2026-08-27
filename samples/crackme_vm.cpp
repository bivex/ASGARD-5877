#include "threaded_vm.hpp"
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

static inline uint64_t splitmix64(uint64_t* state) {
    *state += 0x9E3779B97F4A7C15ULL;
    uint64_t z = *state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

/* Embedded Encrypted Bytecode executed inside Vanguard Virtual Machine */
static const uint64_t embedded_bytecode[] = {
    0x0A6A36F70F5C622CULL,
    0x4E75B7404E65813DULL,
    0xF8301313FB96B07BULL,
    0xE2A5B079470B5FAEULL,
    0x44DB8DA02F8E5583ULL,
    0x303C50815232BFE8ULL,
    0x869FCF292BE8420DULL,
    0x74D332E49F1D4D76ULL,
    0x19BA63AE12A255CCULL,
    0x958A99233DC7BE6FULL,
    0x445E3F38E1A0B1FCULL,
    0xED8A7EECA979C5A8ULL,
    0x3CBC022C689AA279ULL,
    0x63CCE9D58BB954ACULL,
    0x8CDC3758312D0C32ULL,
    0x413DCE7922A8D49EULL,
    0x11230B314FBFEF23ULL,
    0xB477209E250C4C0AULL,
    0xC94FF26B630F5DE0ULL,
    0x7A7CD80DCA3906EAULL,
    0xD883552075A64C0CULL,
    0x966C90CB3ABA2152ULL,
    0x5222D8A700DD43A6ULL,
    0x0B871502C4D5D787ULL,
    0x09B599C347C1E99CULL,
    0x12DC8390550FC00DULL,
    0x6F778E92E15EE41BULL,
    0xBB3689328E7F86DBULL,
    0x6DC2C45D15A84E0DULL,
    0x81CF5B116649E6DEULL,
    0xFECC9E5504B88139ULL,
    0xF05D88B9E2BE3D7FULL,
    0xD34D116F28CE70FCULL,
    0x8604A467E2D7DB89ULL,
    0x8374285D15EB9A87ULL,
    0xEA4B64AFCCA3766AULL,
    0x1F6C06913BFF323BULL,
    0x1D34A208B5A67AF5ULL,
    0x2F39E4D3271A7DDAULL,
    0xF7D7ADDD3E25A488ULL,
    0xF883DAD92AA056ADULL,
    0x8DE475B2C3027A6AULL,
    0x883566B1F21AAB28ULL,
    0x0253D3C0B7E95A70ULL,
    0x940D60831631701EULL,
    0xF40379536202D05EULL,
    0xA9ED3D22CACF8C03ULL,
    0xDAB9BBC1B5E0E1BAULL,
    0x8FA1778304E576A7ULL,
    0x85303DE32AE53150ULL,
    0xCC51A549CC615576ULL,
    0x6A5B086EE7D685FEULL,
    0xD444AD25FF720BC1ULL,
    0x01DC734165B56A4DULL,
    0xC453BFBCC3A47C9DULL,
    0x48A64CEA3A230093ULL,
    0x6CED6150CE59FC62ULL,
    0x323803858DCBC075ULL,
    0x295372E7169A587DULL,
    0x7C899D58CA469C26ULL,
    0x8993DED38250C587ULL,
    0x53A3A56C3CD1BCACULL,
    0x87A4F626DCDE381CULL,
    0x77A1273B8ACBAB8AULL,
    0x7F6E5C5BB06C5522ULL,
    0x18993ED3884A4C7CULL,
    0x3AE29F6808A3AF3FULL,
    0x0F15E31994D7AE16ULL,
    0x20156B329503884FULL,
    0x3E2663D89D1EA50FULL,
    0x8DB2314C21F22627ULL,
    0xB6900FF89C2F83BDULL,
    0x8161A414EEDE20CCULL,
    0x36D35DFD6624EC21ULL,
    0x329F984E622EB49DULL,
    0x8420931F54A08658ULL,
    0xD84F8AF87B8017BAULL,
    0x114FACEFA0C7684DULL,
    0x3CFAE8F59A3E4B06ULL,
    0x1B1B36BDF2F2999EULL,
    0x32076A5857DF4CEBULL,
    0xA1043CCF71A11A78ULL,
    0xEB00F7B26861C6C2ULL,
    0x2D0700CD45031A10ULL,
    0x436E3A1DB3BED4DCULL,
    0x22C0ED8F65CC8762ULL,
    0x5F1D4FEFE1DF5C9CULL,
    0xB4E4C80E6199C3FAULL,
    0xA78D4DB881D8919DULL,
    0xC5819404C7D73F7AULL,
    0x4B20523DB537877CULL,
    0x7991D164C3A2D65BULL,
    0x1AAE8F1B47EE7747ULL,
    0x6A82424815E6C236ULL,
    0xC0A8355FAE6F7B59ULL,
    0x9D2423409441E5D6ULL,
    0x7C3BEBE07D06AA74ULL
};

int main(int argc, char** argv) {
    printf("=========================================================================\n");
    printf("               REVERSE ENGINEERING CRACKME CHALLENGE                     \n");
    printf("=========================================================================\n");

    if (argc < 2) {
        printf("[*] Expected format: FLAG-XXXX-XXXX-XXXX-XXXX\n");
        return 1;
    }

    const char* key = argv[1];
    if (strlen(key) != 24) {
        printf("\n[-] ACCESS DENIED: Invalid Key Length\n");
        return 1;
    }

    if (strncmp(key, "FLAG-", 5) != 0) {
        printf("\n[-] ACCESS DENIED: Invalid Key Prefix\n");
        return 1;
    }

    unsigned int b1 = 0, b2 = 0, b3 = 0, b4 = 0;
    int parsed = sscanf(key + 5, "%04x-%04x-%04x-%04x", &b1, &b2, &b3, &b4);
    if (parsed != 4) {
        printf("\n[-] ACCESS DENIED: Hex Parsing Error\n");
        return 1;
    }

    // Initialize Vanguard Virtual Machine Context
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();
    ctx.set_rdi((uint64_t)b1);
    ctx.set_rsi((uint64_t)b2);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, (uint64_t)b3);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, (uint64_t)b4);

    // Execute Virtual Machine Bytecode
    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    bool vm_ok = vanguard_threaded_vm::execute_threaded(ctx, embedded_bytecode, bc_len);

    uint64_t vm_result_token = ctx.get_rax();

    if (!vm_ok || vm_result_token == 0) {
        printf("\n[-] ACCESS DENIED: Verification Failed! Incorrect Key.\n");
        return 1;
    }

    // Decrypt the internal Flag with the token computed inside the Virtual Machine
    uint64_t state = vm_result_token;
    char flag_out[48];
    for (int i = 0; i < FLAG_LEN; i++) {
        uint64_t k = splitmix64(&state);
        flag_out[i] = (char)(g_cipher_payload[i] ^ (k & 0xFF));
    }
    flag_out[FLAG_LEN] = '\0';

    printf("\n[+] SUCCESS! KEY VALIDATED (Token: 0x%016llX)\n", (unsigned long long)vm_result_token);
    printf("[+] %s\n", flag_out);
    printf("=========================================================================\n");

    return 0;
}
