matrix_dot:
    mov rax, rdi
    imul rax, rsi
    mov r8, rdx
    imul r8, rcx
    add rax, r8
    ret
