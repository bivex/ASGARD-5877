clamp_val:
    mov rax, rdi
    cmp rax, rsi
    jge .Lchk_max
    mov rax, rsi
    ret
.Lchk_max:
    cmp rax, rdx
    jle .Ldone
    mov rax, rdx
.Ldone:
    ret
