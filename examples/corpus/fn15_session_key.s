session_key:
    mov rax, rdi
    imul rax, 0x9E3779B97F4A7C15
    xor rax, rsi
    rol rax, 13
    xor rax, 0xA5A5A5A55A5A5A5A
    ret
