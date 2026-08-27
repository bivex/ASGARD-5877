	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 26, 0	sdk_version 26, 5
	.globl	_vm_verify_key                  ; -- Begin function vm_verify_key
	.p2align	2
_vm_verify_key:                         ; @vm_verify_key
	.cfi_startproc
; %bb.0:
	eor	w8, w1, w0
	mov	w9, #57635                      ; =0xe123
	cmp	x9, w8, uxth
	b.ne	LBB0_3
; %bb.1:
	mov	w8, #40503                      ; =0x9e37
	madd	w8, w1, w8, w2
	mov	w9, #59538                      ; =0xe892
	cmp	x9, w8, uxth
	b.ne	LBB0_3
; %bb.2:
	ubfx	w8, w3, #11, #5
	orr	w8, w8, w3, lsl #5
	eor	w8, w8, w2
	mov	w9, #32971                      ; =0x80cb
	add	w10, w1, w0
	add	w11, w2, w3
	add	w10, w10, w11
	mov	w11, #37203                     ; =0x9153
	cmp	x11, w10, uxth
	lsl	x10, x1, #32
	orr	x10, x10, x0, lsl #48
	orr	x10, x10, x2, lsl #16
	orr	x10, x10, x3
	csel	x10, xzr, x10, ne
	cmp	w9, w8, uxth
	csel	x0, xzr, x10, ne
	ret
LBB0_3:
	mov	x0, #0                          ; =0x0
	ret
	.cfi_endproc
                                        ; -- End function
.subsections_via_symbols
