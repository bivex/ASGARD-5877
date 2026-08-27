fibonacci:
    mov rax, 0
    mov rcx, 1
.Lfib_loop:
    cmp rdi, 0
    jle .Lfib_done
    mov r8, rax
    add r8, rcx
    mov rax, rcx
    mov rcx, r8
    sub rdi, 1
    jmp .Lfib_loop
.Lfib_done:
    ret
