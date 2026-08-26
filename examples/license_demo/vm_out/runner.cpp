#include "threaded_vm.hpp"
#include <stdio.h>
#include <stdlib.h>

/* Self-contained embedded encrypted bytecode */
static const uint64_t embedded_bytecode[] = {
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

int main(int argc, char** argv) {
    const uint64_t* bc_ptr = embedded_bytecode;
    size_t bc_len = sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]);
    uint64_t* heap_bc = NULL;

    if (argc >= 2) {
        FILE* f = fopen(argv[1], "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (sz > 0 && (sz % 8) == 0) {
                size_t count = (size_t)sz / 8;
                heap_bc = (uint64_t*)malloc((size_t)sz);
                if (heap_bc && fread(heap_bc, 8, count, f) == count) {
                    bc_ptr = heap_bc;
                    bc_len = count;
                }
            }
            fclose(f);
        }
    }

    vanguard_threaded_vm::VMContext ctx = {};
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc_ptr, bc_len);
    if (heap_bc) free(heap_bc);

    if (!ok) return 2;
    printf("[VM] Execution SUCCESS! Verified %zu instructions. RAX: %llu\n",
           ctx.executed_instructions, (unsigned long long)ctx.gprs[0]);
    return 0;
}
