fixed_mul:
    mov rax, rdi
    imul rax, rsi
    shr rax, 16
    ret
