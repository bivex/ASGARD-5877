.globl check_license_core
check_license_core:
    mov rax, rdi
    xor rax, 0x5877
    imul rax, 42
    add rax, 0x1337
    cmp rax, rsi
    je .Lvalid
    mov rax, 0
    ret
.Lvalid:
    mov rax, 1
    ret
