murmur_hash:
    mov rax, rdi
    imul rax, 0xcc9e2d51
    rol rax, 15
    imul rax, 0x1b873593
    xor rax, rsi
    rol rax, 13
    imul rax, 5
    add rax, 0xe6546b64
    ret
