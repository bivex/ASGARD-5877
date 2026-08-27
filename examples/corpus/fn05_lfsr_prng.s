lfsr_prng:
    mov rax, rdi
    mov r8, rax
    shr r8, 1
    mov r9, rax
    shr r9, 2
    xor r8, r9
    mov r10, rax
    shr r10, 3
    xor r8, r10
    mov r11, rax
    shr r11, 5
    xor r8, r11
    and r8, 1
    shl rax, 1
    or rax, r8
    ret
