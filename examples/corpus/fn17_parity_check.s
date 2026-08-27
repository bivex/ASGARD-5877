parity_check:
    mov rax, rdi
    mov r8, rax
    shr r8, 32
    xor rax, r8
    mov r8, rax
    shr r8, 16
    xor rax, r8
    mov r8, rax
    shr r8, 8
    xor rax, r8
    and rax, 1
    ret
