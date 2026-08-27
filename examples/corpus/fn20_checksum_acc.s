checksum_acc:
    mov rax, rdi
    add rax, rsi
    imul rax, 31
    xor rax, rdx
    rol rax, 7
    add rax, rcx
    ret
