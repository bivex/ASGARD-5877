.globl check_license_core
// The ARM64 flavour of the demo core.  The ARM64 lifter reads the x/w
// register names, so the demo core is written in the AArch64 dialect: the key
// arrives in x0 and the expected value in x1, and the result is 1 when
// ((key ^ 0x5877) * 42 + 0x1337) matches.
check_license_core:
    eor x0, x0, #0x5877
    mul x0, x0, #42
    add x0, x0, #0x1337
    cmp x0, x1
    b.eq .Lvalid
    mov x0, #0
    ret
.Lvalid:
    mov x0, #1
    ret
