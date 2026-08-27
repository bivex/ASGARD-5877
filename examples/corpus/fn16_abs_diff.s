abs_diff:
    mov rax, rdi
    sub rax, rsi
    cmp rax, 0
    jge .Lpos
    neg rax
.Lpos:
    ret
