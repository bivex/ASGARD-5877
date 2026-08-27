binary_search_step:
    mov rax, rdi
    add rax, rsi
    shr rax, 1
    cmp rax, rdx
    jge .Lhigh
    add rax, 1
    ret
.Lhigh:
    sub rax, 1
    ret
