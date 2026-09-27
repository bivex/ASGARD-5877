/* Debug driver: loads protected.vanguard, runs the VM manually (same setup as
   stack_vm_call) and dumps halted / vip / ctx so we can see WHERE it stops. */
#include "stack_vm_runtime.hpp"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    const char* path = argc >= 2 ? argv[1] : "protected.vanguard";
    FILE* f = fopen(path, "rb");
    if (!f) { perror(path); return 2; }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    size_t words = (size_t)sz / 8;
    uint64_t* bc = (uint64_t*)malloc((size_t)sz);
    if (fread(bc, 8, words, f) != words) { fprintf(stderr, "short read\n"); return 2; }
    fclose(f);
    printf("loaded %s: %ld bytes, %zu words\n", path, sz, words);

    /* stored seed_key (effective 0x0BD0C0C5184524AD ^ D 0x1467BA69FA35F98F) */
    const uint64_t seed_key = 0x1FB77AACE270DD22ULL;

    asgard_stack_vm::stack_vm_t vm;
    memset(&vm, 0, sizeof(vm));
    vm.addr_key = asgard_stack_vm::derive_addr_key();
    vm.vkey = seed_key ^ vm.addr_key;
    vm.vsp_key = vm.vkey ^ UINT64_C(0x9E3779B97F4A7C15);
    const uint64_t hwid = 100;
    const uint64_t valid_serial = ((hwid ^ 0x5877ULL) * 42ULL) + 0x1337ULL;
    vm.ctx[7] = hwid;        /* RDI */
    vm.ctx[6] = valid_serial;/* RSI */

    asgard_stack_vm::stack_vm_run(&vm, (const uint8_t*)bc, words * 8);

    printf("halted=%d  ctx[0..9]:\n", vm.halted);
    for (int i = 0; i < 10; i++)
        printf("  ctx[%d] = %llu (0x%llX)\n", i,
               (unsigned long long)vm.ctx[i], (unsigned long long)vm.ctx[i]);
    printf("result (RAX) = %llu, expected 1\n", (unsigned long long)vm.ctx[0]);
    return vm.ctx[0] == 1 ? 0 : 1;
}
