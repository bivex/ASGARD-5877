crc32_step:
    mov rax, rdi
    xor rax, rsi
    shr rax, 1
    cmp rax, 0x80000000
    jge .Lpoly
    xor rax, 0xEDB88320
    ret
.Lpoly:
    add rax, 1
    ret
