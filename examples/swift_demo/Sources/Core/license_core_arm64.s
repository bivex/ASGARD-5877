.globl check_license_core
// ASGARD-5877 ARM64 Security Core for Swift Applications
//
// Arguments (ARM64 ABI mapped to ASGARD Guest VM):
//   x0 (Guest REG_RAX): License Key / Serial token
//   x1 (Guest REG_RCX): Expected Hardware Signature / Hash
//
// Returns:
//   x0: 1 if validation passes, 0 otherwise
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
