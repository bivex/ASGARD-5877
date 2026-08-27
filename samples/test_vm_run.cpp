
#include "threaded_vm.hpp"
#include <stdio.h>
#include <stdlib.h>

int main() {
    vanguard_threaded_vm::VMContext ctx = {};
    ctx.init();

    uint64_t b1 = 0x1111; // Wrong key!
    uint64_t b2 = 0x2222;
    uint64_t b3 = 0x3333;
    uint64_t b4 = 0x4444;

    ctx.set_rdi(b1);
    ctx.set_rsi(b2);
    ctx.set_reg(vanguard_threaded_vm::REG_RDX, b3);
    ctx.set_reg(vanguard_threaded_vm::REG_RCX, b4);

    FILE* f = fopen("/Volumes/External/Code/ASGARD-5877/binaries/crackme_arm64/protected.vanguard", "rb");
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    size_t count = sz / 8;
    uint64_t* bc = (uint64_t*)malloc(sz);
    fread(bc, 8, count, f);
    fclose(f);

    bool ok = vanguard_threaded_vm::execute_threaded(ctx, bc, count);
    printf("ok=%d, instrs=%zu, trapped=%d, rax=0x%016llX\n", ok, ctx.executed_instructions, ctx.trapped, (unsigned long long)ctx.get_rax());
    return 0;
}
