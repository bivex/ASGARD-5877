tea_round:
    mov rax, rdi
    mov r8, rdi
    shl r8, 4
    add r8, rsi
    mov r9, rdi
    shr r9, 5
    add r9, rdx
    xor r8, r9
    add rax, r8
    ret
