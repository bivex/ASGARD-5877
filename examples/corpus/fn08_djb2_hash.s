djb2_hash:
    mov rax, 5381
    mov r8, rax
    shl r8, 5
    add r8, rax
    xor r8, rdi
    mov rax, r8
    ret
