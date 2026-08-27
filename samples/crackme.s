	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 26, 0	sdk_version 26, 5
	.globl	_main                           ; -- Begin function main
	.p2align	2
_main:                                  ; @main
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #288
	stp	x28, x27, [sp, #224]            ; 16-byte Folded Spill
	stp	x22, x21, [sp, #240]            ; 16-byte Folded Spill
	stp	x20, x19, [sp, #256]            ; 16-byte Folded Spill
	stp	x29, x30, [sp, #272]            ; 16-byte Folded Spill
	add	x29, sp, #272
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	.cfi_offset w27, -56
	.cfi_offset w28, -64
	mov	x19, x1
	mov	x20, x0
Lloh0:
	adrp	x21, l_str.15@PAGE
Lloh1:
	add	x21, x21, l_str.15@PAGEOFF
	mov	x0, x21
	bl	_puts
Lloh2:
	adrp	x0, l_str.11@PAGE
Lloh3:
	add	x0, x0, l_str.11@PAGEOFF
	bl	_puts
	mov	x0, x21
	bl	_puts
	stp	xzr, xzr, [sp, #208]
	stp	xzr, xzr, [sp, #192]
	stp	xzr, xzr, [sp, #176]
	stp	xzr, xzr, [sp, #160]
	stp	xzr, xzr, [sp, #144]
	stp	xzr, xzr, [sp, #128]
	stp	xzr, xzr, [sp, #112]
	stp	xzr, xzr, [sp, #96]
	cmp	w20, #2
	b.lt	LBB0_2
; %bb.1:
	ldr	x1, [x19, #8]
	add	x0, sp, #96
	mov	w2, #127                        ; =0x7f
	bl	_strncpy
	b	LBB0_7
LBB0_2:
Lloh4:
	adrp	x0, l_.str.2@PAGE
Lloh5:
	add	x0, x0, l_.str.2@PAGEOFF
	bl	_printf
Lloh6:
	adrp	x8, ___stdoutp@GOTPAGE
Lloh7:
	ldr	x8, [x8, ___stdoutp@GOTPAGEOFF]
Lloh8:
	ldr	x0, [x8]
	bl	_fflush
Lloh9:
	adrp	x8, ___stdinp@GOTPAGE
Lloh10:
	ldr	x8, [x8, ___stdinp@GOTPAGEOFF]
Lloh11:
	ldr	x2, [x8]
	add	x0, sp, #96
	mov	w1, #128                        ; =0x80
	bl	_fgets
	cbz	x0, LBB0_10
; %bb.3:
	add	x19, sp, #96
	add	x0, sp, #96
	bl	_strlen
	cbz	x0, LBB0_7
; %bb.4:
	sub	x8, x19, #1
LBB0_5:                                 ; =>This Inner Loop Header: Depth=1
	ldrb	w9, [x8, x0]
	cmp	w9, #13
	ccmp	w9, #10, #4, ne
	b.ne	LBB0_7
; %bb.6:                                ;   in Loop: Header=BB0_5 Depth=1
	strb	wzr, [x8, x0]
	sub	x9, x0, #1
	mov	x0, x9
	cbnz	x9, LBB0_5
LBB0_7:
	add	x0, sp, #96
	bl	_strlen
	cmp	x0, #26
	b.ne	LBB0_9
; %bb.8:
	ldr	w8, [sp, #96]
	ldur	w9, [sp, #99]
	mov	w10, #21313                     ; =0x5341
	movk	w10, #16711, lsl #16
	cmp	w8, w10
	mov	w8, #21057                      ; =0x5241
	movk	w8, #11588, lsl #16
	ccmp	w9, w8, #0, eq
	b.eq	LBB0_11
LBB0_9:
Lloh12:
	adrp	x0, l_str.17@PAGE
Lloh13:
	add	x0, x0, l_str.17@PAGEOFF
	b	LBB0_18
LBB0_10:
Lloh14:
	adrp	x0, l_str.13@PAGE
Lloh15:
	add	x0, x0, l_str.13@PAGEOFF
	b	LBB0_18
LBB0_11:
	stp	xzr, xzr, [sp, #80]
	add	x8, sp, #96
	add	x9, sp, #80
	add	x10, sp, #84
	stp	x10, x9, [sp, #16]
	add	x9, sp, #88
	add	x10, sp, #92
	stp	x10, x9, [sp]
Lloh16:
	adrp	x1, l_.str.6@PAGE
Lloh17:
	add	x1, x1, l_.str.6@PAGEOFF
	orr	x0, x8, #0x7
	bl	_sscanf
	cmp	w0, #4
	b.ne	LBB0_16
; %bb.12:
	ldp	w22, w20, [sp, #88]
	ldp	w21, w19, [sp, #80]
	and	w0, w20, #0xffff
	and	w1, w22, #0xffff
	and	w2, w19, #0xffff
	and	w3, w21, #0xffff
	bl	_verify_key_core
	tbz	w0, #0, LBB0_17
; %bb.13:
	mov	x8, #0                          ; =0x0
	mov	x9, #31765                      ; =0x7c15
	movk	x9, #32586, lsl #16
	movk	x9, #31161, lsl #32
	movk	x9, #40503, lsl #48
	lsl	x10, x22, #32
	orr	x10, x10, x20, lsl #48
	stur	xzr, [sp, #70]
	stp	xzr, xzr, [sp, #56]
	orr	x10, x10, x19, lsl #16
	orr	x10, x10, x21
	stp	xzr, xzr, [sp, #40]
	str	xzr, [sp, #32]
	add	x11, x10, x9
	mov	x12, #58809                     ; =0xe5b9
	movk	x12, #7396, lsl #16
	movk	x12, #18285, lsl #32
	movk	x12, #48984, lsl #48
	mov	x13, #4587                      ; =0x11eb
	movk	x13, #4913, lsl #16
	movk	x13, #18875, lsl #32
	movk	x13, #38096, lsl #48
Lloh18:
	adrp	x14, _g_cipher_flag@PAGE
Lloh19:
	add	x14, x14, _g_cipher_flag@PAGEOFF
	add	x15, sp, #32
LBB0_14:                                ; =>This Inner Loop Header: Depth=1
	eor	x16, x11, x11, lsr #30
	mul	x16, x16, x12
	eor	x16, x16, x16, lsr #27
	mul	x16, x16, x13
	lsr	x17, x16, #31
	ldrb	w0, [x14, x8]
	eor	w16, w0, w16
	eor	w16, w16, w17
	strb	w16, [x15, x8]
	add	x8, x8, #1
	add	x11, x11, x9
	cmp	x8, #45
	b.ne	LBB0_14
; %bb.15:
	strb	wzr, [sp, #77]
	str	x10, [sp]
Lloh20:
	adrp	x0, l_.str.9@PAGE
Lloh21:
	add	x0, x0, l_.str.9@PAGEOFF
	bl	_printf
	add	x8, sp, #32
	str	x8, [sp]
Lloh22:
	adrp	x0, l_.str.10@PAGE
Lloh23:
	add	x0, x0, l_.str.10@PAGEOFF
	bl	_printf
Lloh24:
	adrp	x0, l_str.15@PAGE
Lloh25:
	add	x0, x0, l_str.15@PAGEOFF
	bl	_puts
	mov	w0, #0                          ; =0x0
	b	LBB0_19
LBB0_16:
Lloh26:
	adrp	x0, l_str.16@PAGE
Lloh27:
	add	x0, x0, l_str.16@PAGEOFF
	b	LBB0_18
LBB0_17:
Lloh28:
	adrp	x0, l_str.14@PAGE
Lloh29:
	add	x0, x0, l_str.14@PAGEOFF
LBB0_18:
	bl	_puts
	mov	w0, #1                          ; =0x1
LBB0_19:
	ldp	x29, x30, [sp, #272]            ; 16-byte Folded Reload
	ldp	x20, x19, [sp, #256]            ; 16-byte Folded Reload
	ldp	x22, x21, [sp, #240]            ; 16-byte Folded Reload
	ldp	x28, x27, [sp, #224]            ; 16-byte Folded Reload
	add	sp, sp, #288
	ret
	.loh AdrpAdd	Lloh2, Lloh3
	.loh AdrpAdd	Lloh0, Lloh1
	.loh AdrpLdrGotLdr	Lloh9, Lloh10, Lloh11
	.loh AdrpLdrGotLdr	Lloh6, Lloh7, Lloh8
	.loh AdrpAdd	Lloh4, Lloh5
	.loh AdrpAdd	Lloh12, Lloh13
	.loh AdrpAdd	Lloh14, Lloh15
	.loh AdrpAdd	Lloh16, Lloh17
	.loh AdrpAdd	Lloh18, Lloh19
	.loh AdrpAdd	Lloh24, Lloh25
	.loh AdrpAdd	Lloh22, Lloh23
	.loh AdrpAdd	Lloh20, Lloh21
	.loh AdrpAdd	Lloh26, Lloh27
	.loh AdrpAdd	Lloh28, Lloh29
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function verify_key_core
_verify_key_core:                       ; @verify_key_core
	.cfi_startproc
; %bb.0:
	eor	w8, w1, w0
	mov	w9, #51941                      ; =0xcae5
	cmp	w8, w9
	cset	w8, eq
	mov	w9, #-25033                     ; =0xffff9e37
	madd	w9, w1, w9, w2
	mov	w10, #1                         ; =0x1
	cinc	w10, w10, eq
	mov	w11, #44181                     ; =0xac95
	cmp	w11, w9, uxth
	csel	w8, w10, w8, eq
	lsr	w9, w3, #11
	orr	w9, w9, w3, lsl #5
	eor	w9, w9, w2
	add	w10, w1, w0
	add	w11, w2, w3
	add	w10, w10, w11
	mov	w11, #51518                     ; =0xc93e
	cmp	w11, w10, uxth
	cinc	w8, w8, eq
	mov	w10, #19694                     ; =0x4cee
	cmp	w10, w9, uxth
	cinc	w8, w8, eq
	cmp	w8, #4
	cset	w0, eq
	ret
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__cstring,cstring_literals
l_.str.2:                               ; @.str.2
	.asciz	"[?] Enter License Key (format: ASGARD-XXXX-XXXX-XXXX-XXXX): "

l_.str.4:                               ; @.str.4
	.asciz	"ASGARD-"

l_.str.6:                               ; @.str.6
	.asciz	"%04x-%04x-%04x-%04x"

	.section	__TEXT,__const
_g_cipher_flag:                         ; @g_cipher_flag
	.ascii	"\242\254q\001\262?\327\371\351\213ePNl\326\f\207\021,<+\2331:\371-\023\244\027\317\317\t\303\017\327}\373\021\375\354\320%\301(T"

	.section	__TEXT,__cstring,cstring_literals
l_.str.9:                               ; @.str.9
	.asciz	"\n[+] SUCCESS! LICENSE VALIDATED (Hardware Token: 0x%016llX)\n"

l_.str.10:                              ; @.str.10
	.asciz	"[+] UNLOCKED FLAG: %s\n"

l_str.11:                               ; @str.11
	.asciz	"     ASGARD-5877: HARDENED CTF CRACKME CHALLENGE (ARM64 vISA)            "

l_str.13:                               ; @str.13
	.asciz	"\n[-] Failed to read input."

l_str.14:                               ; @str.14
	.asciz	"\n[-] ACCESS DENIED: Mathematical Invariants Failed! Key is Invalid."

l_str.15:                               ; @str.15
	.asciz	"========================================================================="

l_str.16:                               ; @str.16
	.asciz	"\n[-] Access Denied: Hex Parsing Error."

l_str.17:                               ; @str.17
	.asciz	"\n[-] Access Denied: Invalid Key Format (Expected: ASGARD-XXXX-XXXX-XXXX-XXXX)"

.subsections_via_symbols
