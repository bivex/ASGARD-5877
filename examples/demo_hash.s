; Complex x86_64 algorithm: Hash & arithmetic check
demo_func:
    mov rax, 1337
    add rax, 42
    imul rax, 3
    cmp rax, 1000
    jge .Lhigh
    add rax, 50
    ret
.Lhigh:
    sub rax, 100
    ret
