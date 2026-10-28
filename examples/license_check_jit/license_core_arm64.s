.globl check_license_core
// ASGARD-5877 Register-Driven JIT license core (ARM64 dialect for the lifter).
//
// The RD-JIT engine executes straight-line ALU regions only - its opcode
// contract has no data-dependent branches - so the core derives the license
// token and the harness compares it:
//     token = ((key ^ 0x5877) * 42 + 0x1337) mod 2^64
// The key arrives as argv[1] of the protected runner (virtual register 0);
// the derived token is printed as REG 0.
//
// Shipped valid key: 22647 (0x5877) -> token 0x1337.
check_license_core:
    eor x0, x0, #0x5877
    mul x0, x0, #42
    add x0, x0, #0x1337
    ret
