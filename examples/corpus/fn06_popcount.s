popcount_calc:
    mov rax, rdi
    mov r8, rax
    shr r8, 1
    and r8, 0x5555555555555555
    sub rax, r8
    mov r9, rax
    shr r9, 2
    and r9, 0x3333333333333333
    and rax, 0x3333333333333333
    add rax, r9
    ret
