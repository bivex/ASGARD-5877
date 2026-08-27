fnv1a_hash:
    mov rax, 0xcbf29ce484222325
    xor rax, rdi
    imul rax, 0x100000001b3
    ret
