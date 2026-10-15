#include "multi_vm_runtime.hpp"

#include <iostream>

#include <vector>

#include <chrono>

extern "C" __attribute__((weak)) const uint64_t embedded_bytecode[] = {
    0x495adb44d0fc25baULL,
    0x3671652fb7344700ULL,
    0x4b94dc402de9a1acULL,
    0xe97986f7c05736b2ULL,
    0xb46c34beb83976dfULL,
    0xcb305644552c353eULL,
    0x09efff5c47809f3fULL,
    0x9d5edcc0a4aa1c01ULL,
    0x0a5612a5d542f0bfULL,
    0x1cf007fc657692d6ULL,
    0x9fb2560b1b775a0cULL,
    0x4e63cc23f7c94d38ULL,
    0xa5dec96ed9a61538ULL,
    0xa40fb5e3e1887088ULL,
    0xa00d25f8eaf6941dULL,
    0x56948d476f40f77fULL,
    0xbc9b6f3ccdf204bcULL,
    0x49a3d97a8eac6762ULL,
    0x2b192d657073d6c7ULL,
    0x37b6e7d855c0b1cfULL,
    0x1080c980ca4c9356ULL,
    0xea680ff1772d619bULL,
    0x2603e0a8c2fc7d19ULL,
    0xf0b560438db020d8ULL,
    0xe9c532d44d769873ULL,
    0x0298943c3716f719ULL,
    0xa2c573711c2dcb0cULL,
    0xfd82b1285fca83c0ULL,
    0x3bdb2a773c2b0366ULL,
    0x888e7ec8c393f472ULL,
    0x0aab0220316131f9ULL,
    0x1ac09b0bf6d90c69ULL,
    0x54cf85cf319e96b2ULL,
    0xb371ae879fb71f18ULL,
    0x93a614181bcd7d27ULL,
    0x43af1d3a202d8479ULL,
    0x4520624618efa179ULL,
    0x6f42f10496a84d70ULL,
    0x99a5d334a5e6959eULL,
    0x08ef8b5cb207d376ULL,
    0x7d78df82887b07e6ULL,
    0xe88c36c0e075ee8eULL,
    0x24ec345019dfcc01ULL,
    0x5418d39e74adc566ULL,
    0xdd60346fa8926375ULL,
    0xed5ecd542901cb5dULL,
    0xeb0107678d3f8f53ULL,
    0x3bc264d5d7b59945ULL,
    0xcd1cf8c9ea3a45c7ULL,
    0xf59a0f3c3f4a8fe9ULL,
    0x9c69019ba43f68f6ULL,
    0xb73cfbda573a1ff4ULL,
    0x42a25c1a9738a936ULL,
    0xe34b9e2f52af5aa9ULL,
    0x9494d723db9f3decULL,
    0x59f930d89a97efffULL,
    0x7558440c78024f43ULL,
    0x20ccf94595fc9aeeULL,
    0xa52afc757c2940deULL,
    0xb98f13c9283aec91ULL,
    0x928e376a2614e1b1ULL,
    0xa7bc38bdb7bab966ULL,
    0xc4be2701757f7256ULL,
    0x52414a8b7071ceefULL,
    0x69ce8bd569d8457bULL,
    0x92b3ed200c4b032cULL,
    0x7d59cbc2462389adULL,
    0x70df35312a2215bfULL,
    0xc7222089111a2297ULL,
    0x617702ac0b95592aULL,
    0x65f8f816e56b9fbaULL,
    0x59ebc988b7bb4410ULL,
    0x715a337e4f1a47feULL,
    0xa7cfcca5880e7e7bULL,
    0x66de6196ebc02491ULL,
    0x98ba6519d8e18fc6ULL,
    0x43fddea42f4985deULL,
    0x9b79b87b1a96d2f7ULL,
    0x32c1e139fc9531e6ULL,
    0xc1c1e2fe991c835fULL,
    0x4b16f90545d983caULL,
    0xedb5003308625fe2ULL,
    0x6d26f2b475736c5eULL,
    0xf97dd4410626ffa7ULL,
    0x42dea50f9d4a912aULL,
    0x8ff0ad092b32c7a0ULL,
    0x80f39dc5ba02eb8bULL,
    0x9852d9a944f21fd5ULL,
    0x4abcad90e01b6f49ULL,
    0x62d9a602bdea3da6ULL,
    0xe11f013ffa9afdb7ULL,
    0x4880f3018f1431aaULL,
    0xc134eb841b42022eULL,
    0x3c310d42077fc575ULL,
    0x83e068536f8e0971ULL,
    0xe584e7c283852e56ULL,
    0x4eee046d77905f07ULL,
    0x0859cda21e23a136ULL,
    0xec9f5827728dc573ULL,
    0x1761a37fe76b2d37ULL,
    0x74cbfddbd0d82eb0ULL,
    0xc7fcac12cdbff22bULL,
    0xb683186912fcf424ULL,
    0x50a1aeba1203b71dULL,
    0xa5a5dc198ed4fca7ULL,
    0xe7f2b9a9122617a2ULL,
    0x4b609142e2c44f4dULL,
    0x6ce88a0dd1c93705ULL,
    0x30c74abce61c7736ULL,
    0x6dd8dd2f2975fffaULL,
    0xeb33fbd04fd37dcaULL,
    0x669504b66c3691e6ULL,
    0xa0dfcf0d23bdfcefULL,
    0xa29bc626e4dfd329ULL,
    0x5a68ae86d31f86d7ULL,
    0xdf021ee7d151a35eULL,
    0xa5af3e5b02deb4aeULL,
    0xded8d59272dfcdc9ULL,
    0x961f871a55c116b6ULL,
    0x17971d21e83901c2ULL,
    0xd7d09719a1fc347dULL,
    0x982dfa5b5346ef98ULL,
    0x15a2767773b61be2ULL,
    0x1c9a0f3ee1052edaULL,
    0xb7ea9c3e31544f42ULL,
    0xd9608e215072058bULL,
    0xf564a75d02df87f6ULL,
    0xfd9a86db0e5c98a9ULL,
    0xa0a1ed44e5be8d84ULL,
    0x67f7bb54b01b0b3bULL,
    0x8ef7a744cf58dcd3ULL,
    0xd492d696957f6335ULL,
    0x046dc19cfb195402ULL,
    0x237acc85640e1694ULL,
    0x6f18c8ef2840d8a5ULL,
    0x513217fe87db7859ULL,
    0x1b4b911c87105c28ULL,
    0x1c091e9b41800bf8ULL,
    0x37dc4144b8d4fa8dULL,
    0x3c2998e30b10641fULL,
    0xa728083715504484ULL,
    0x7200d2b191b6664bULL
};

extern "C" __attribute__((weak)) const size_t embedded_bytecode_len = (sizeof(embedded_bytecode) / sizeof(embedded_bytecode[0]));

int32_t main(int32_t argc, char** argv) {
                                             std::cout << "[ASGARD-MULTI-VM] Initializing In-Place Heterogeneous Dual-VM Runtime...\n";
                                             std::cout << "  Engine 1: Math-VM (Register/RNS Oriented, " << 3 << " blocks)\n";
                                             std::cout << "  Engine 2: Flow-VM (Stack/CFF Markov Oriented, " << 0 << " blocks)\n";
                                             std::cout << "  Zero-Bridge Transitions: " << 2 << " affine morphing junctions\n";
                                             asgard_multi_vm::SharedVMContext shared_ctx = {};
                                             shared_ctx.math.init(ASGARD_INITIAL_DIGEST);
                                             vanguard_threaded_vm::VMContext base_ctx = {};
                                             base_ctx.init();
                                             uint64_t init_rdi = ((argc > 1) ? ((uint64_t)(atoll(argv[1]))) : 0x000000000000002aULL);
                                             base_ctx.set_rdi(init_rdi);
                                             auto t0 = std::chrono::high_resolution_clock::now();
                                             vanguard_threaded_vm::execute_threaded(base_ctx, embedded_bytecode, embedded_bytecode_len);
                                             auto t1 = std::chrono::high_resolution_clock::now();
                                             double elapsed_us = std::chrono::duration<double, std::micro>(t1 - t0).count();
                                             uint64_t res = base_ctx.get_rax();
                                             std::cout << "[ASGARD-MULTI-VM] Execution Successful!\n";
                                             std::cout << "  Result (RAX): " << res << " (0x" << std::hex << res << std::dec << ")\n";
                                             std::cout << "  Execution Time: " << elapsed_us << " us\n";
                                             return 0;
}

