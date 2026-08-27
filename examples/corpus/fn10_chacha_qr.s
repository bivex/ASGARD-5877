chacha_qr:
    add rdi, rsi
    xor rdx, rdi
    rol rdx, 16
    add rcx, rdx
    xor rsi, rcx
    rol rsi, 12
    mov rax, rdi
    add rax, rsi
    ret
