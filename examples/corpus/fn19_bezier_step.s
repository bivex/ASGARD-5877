bezier_step:
    mov rax, 100
    sub rax, rdi
    imul rax, rsi
    mov r8, rdi
    imul r8, rdx
    add rax, r8
    ret
