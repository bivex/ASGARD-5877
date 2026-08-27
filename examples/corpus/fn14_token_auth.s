token_auth:
    mov rax, 0xFEEDFACECAFE
    xor rax, rdi
    add rax, 777
    cmp rax, rsi
    sete al
    ret
