mod_exp_step:
    mov rax, rdi
    imul rax, rax
    cmp rsi, 0
    je .Lsqr_done
    imul rax, rdx
.Lsqr_done:
    ret
