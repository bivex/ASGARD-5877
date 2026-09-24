	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 26, 0	sdk_version 26, 5
	.globl	_main                           ; -- Begin function main
	.p2align	2
_main:                                  ; @main
	.cfi_startproc
; %bb.0:
	stp	x20, x19, [sp, #-32]!           ; 16-byte Folded Spill
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	sub	sp, sp, #112
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #3095                      ; =0xc17
	movk	w10, #24233, lsl #16
	stur	w10, [x29, #-80]
Lloh0:
	adrp	x10, _main._enc@PAGE
Lloh1:
	add	x10, x10, _main._enc@PAGEOFF
	sub	x11, x29, #128
LBB0_1:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w12, [x29, #-80]
	eor	w12, w12, w8
	ldrb	w13, [x10, x9]
	eor	w12, w13, w12
	strb	w12, [x11, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #41
	b.ne	LBB0_1
; %bb.2:
	sturb	wzr, [x29, #-87]
	sub	x0, x29, #128
	; InlineAsm Start
	; InlineAsm End
	bl	_puts
	sub	x0, sp, #48
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #17904                     ; =0x45f0
	movk	w10, #25246, lsl #16
	stur	w10, [x29, #-80]
Lloh2:
	adrp	x10, _main._enc.1@PAGE
Lloh3:
	add	x10, x10, _main._enc.1@PAGEOFF
LBB0_3:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-80]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #39
	b.ne	LBB0_3
; %bb.4:
	strb	wzr, [x0, #39]
	; InlineAsm Start
	; InlineAsm End
	bl	_puts
	sub	x0, sp, #48
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #61885                     ; =0xf1bd
	movk	w10, #5401, lsl #16
	stur	w10, [x29, #-80]
Lloh4:
	adrp	x10, _main._enc.2@PAGE
Lloh5:
	add	x10, x10, _main._enc.2@PAGEOFF
LBB0_5:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-80]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #41
	b.ne	LBB0_5
; %bb.6:
	strb	wzr, [x0, #41]
	; InlineAsm Start
	; InlineAsm End
	bl	_puts
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #14217                     ; =0x3789
	movk	w10, #30887, lsl #16
	stur	w10, [x29, #-80]
Lloh6:
	adrp	x10, _main._enc.3@PAGE
Lloh7:
	add	x10, x10, _main._enc.3@PAGEOFF
LBB0_7:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-80]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #19
	b.ne	LBB0_7
; %bb.8:
	strb	wzr, [x0, #19]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
Lloh8:
	adrp	x8, ___stdoutp@GOTPAGE
Lloh9:
	ldr	x8, [x8, ___stdoutp@GOTPAGEOFF]
Lloh10:
	ldr	x0, [x8]
	bl	_fflush
	sturb	wzr, [x29, #-80]
Lloh11:
	adrp	x8, ___stdinp@GOTPAGE
Lloh12:
	ldr	x8, [x8, ___stdinp@GOTPAGEOFF]
Lloh13:
	ldr	x2, [x8]
	sub	x0, x29, #80
	mov	w1, #64                         ; =0x40
	bl	_fgets
	cbz	x0, LBB0_12
; %bb.9:
	sub	x1, sp, #16
	mov	sp, x1
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #23303                     ; =0x5b07
	movk	w10, #28792, lsl #16
	stur	w10, [x29, #-84]
Lloh14:
	adrp	x10, _main._enc.4@PAGE
Lloh15:
	add	x10, x10, _main._enc.4@PAGEOFF
LBB0_10:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-84]
	ldrb	w12, [x10, x9]
	eor	w11, w11, w8
	eor	w11, w12, w11
	strb	w11, [x1, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #1
	b.eq	LBB0_10
; %bb.11:
	strb	wzr, [x1, #2]
	; InlineAsm Start
	; InlineAsm End
	sub	x19, x29, #80
	sub	x0, x29, #80
	bl	_strcspn
	strb	wzr, [x19, x0]
	sub	x0, x29, #80
	bl	_verify_license
	eor	w0, w0, #0x1
	b	LBB0_13
LBB0_12:
	mov	w0, #2                          ; =0x2
LBB0_13:
	sub	sp, x29, #16
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp], #32             ; 16-byte Folded Reload
	ret
	.loh AdrpAdd	Lloh0, Lloh1
	.loh AdrpAdd	Lloh2, Lloh3
	.loh AdrpAdd	Lloh4, Lloh5
	.loh AdrpAdd	Lloh6, Lloh7
	.loh AdrpLdrGotLdr	Lloh11, Lloh12, Lloh13
	.loh AdrpLdrGotLdr	Lloh8, Lloh9, Lloh10
	.loh AdrpAdd	Lloh14, Lloh15
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function verify_license
_verify_license:                        ; @verify_license
	.cfi_startproc
; %bb.0:
	stp	x20, x19, [sp, #-32]!           ; 16-byte Folded Spill
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	sub	sp, sp, #32
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	; InlineAsm Start
	b	Ltmp0
	.ascii	"ASGARD_BEG_V____"
	.p2align	2
Ltmp0:

	; InlineAsm End
	mov	w10, #2383                      ; =0x94f
	movk	w10, #8468, lsl #16
	stur	w10, [x29, #-20]
Lloh16:
	adrp	x10, _verify_license._enc@PAGE
Lloh17:
	add	x10, x10, _verify_license._enc@PAGEOFF
	sub	x11, x29, #40
LBB1_1:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w12, [x29, #-20]
	eor	w12, w12, w8
	ldrb	w13, [x10, x9]
	eor	w12, w13, w12
	strb	w12, [x11, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #16
	b.ne	LBB1_1
; %bb.2:
	mov	x8, #0                          ; =0x0
	sturb	wzr, [x29, #-24]
	sub	x9, x29, #40
	; InlineAsm Start
	; InlineAsm End
	mov	w10, #1                         ; =0x1
LBB1_3:                                 ; =>This Inner Loop Header: Depth=1
	ldrb	w11, [x0, x8]
	ldrb	w12, [x9, x8]
	cmp	w11, w12
	csel	w10, w10, wzr, eq
	add	x8, x8, #1
	cmp	x8, #16
	b.ne	LBB1_3
; %bb.4:
	ldrb	w8, [x0, #16]
	cmp	w8, #0
	csel	w19, w10, wzr, eq
	cbz	w19, LBB1_12
; %bb.5:
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #55535                     ; =0xd8ef
	movk	w10, #11870, lsl #16
	stur	w10, [x29, #-20]
Lloh18:
	adrp	x10, _verify_license._enc.5@PAGE
Lloh19:
	add	x10, x10, _verify_license._enc.5@PAGEOFF
LBB1_6:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #19
	b.ne	LBB1_6
; %bb.7:
	strb	wzr, [x0, #19]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #20508                     ; =0x501c
	movk	w10, #23029, lsl #16
	stur	w10, [x29, #-20]
Lloh20:
	adrp	x10, _verify_license._enc.6@PAGE
Lloh21:
	add	x10, x10, _verify_license._enc.6@PAGEOFF
LBB1_8:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #19
	b.ne	LBB1_8
; %bb.9:
	strb	wzr, [x0, #19]
	; InlineAsm Start
	; InlineAsm End
	mov	w8, #23962                      ; =0x5d9a
	str	x8, [sp, #-16]!
	bl	_printf
	add	sp, sp, #16
	sub	x0, sp, #48
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #34589                     ; =0x871d
	movk	w10, #29204, lsl #16
	stur	w10, [x29, #-20]
Lloh22:
	adrp	x10, _verify_license._enc.7@PAGE
Lloh23:
	add	x10, x10, _verify_license._enc.7@PAGEOFF
LBB1_10:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #44
	b.ne	LBB1_10
; %bb.11:
	strb	wzr, [x0, #44]
	; InlineAsm Start
	; InlineAsm End
	mov	w8, #23962                      ; =0x5d9a
	str	x8, [sp, #-16]!
	bl	_printf
	add	sp, sp, #16
	b	LBB1_17
LBB1_12:
	sub	x0, sp, #48
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #57006                     ; =0xdeae
	movk	w10, #15909, lsl #16
	stur	w10, [x29, #-20]
Lloh24:
	adrp	x10, _verify_license._enc.8@PAGE
Lloh25:
	add	x10, x10, _verify_license._enc.8@PAGEOFF
LBB1_13:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #34
	b.ne	LBB1_13
; %bb.14:
	strb	wzr, [x0, #34]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #32320                     ; =0x7e40
	movk	w10, #13815, lsl #16
	stur	w10, [x29, #-20]
Lloh26:
	adrp	x10, _verify_license._enc.9@PAGE
Lloh27:
	add	x10, x10, _verify_license._enc.9@PAGEOFF
LBB1_15:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #21
	b.ne	LBB1_15
; %bb.16:
	strb	wzr, [x0, #21]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
LBB1_17:
	; InlineAsm Start
	b	Ltmp1
	.ascii	"ASGARD_END______"
	.p2align	2
Ltmp1:

	; InlineAsm End
	mov	x0, x19
	sub	sp, x29, #16
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp], #32             ; 16-byte Folded Reload
	ret
	.loh AdrpAdd	Lloh16, Lloh17
	.loh AdrpAdd	Lloh18, Lloh19
	.loh AdrpAdd	Lloh20, Lloh21
	.loh AdrpAdd	Lloh22, Lloh23
	.loh AdrpAdd	Lloh24, Lloh25
	.loh AdrpAdd	Lloh26, Lloh27
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__const
_main._enc:                             ; @main._enc
	.ascii	"*w\220=^\373\004\241\302o\210\325v\223<Y\372\007\240\315n\213\324q\222?X\345\006\243\314i\212\327p\235>[\344\001\242"

_main._enc.1:                           ; @main._enc.1
	.ascii	"\253\354\031\240\305s\232[K\360\021Z\376\f\306\302g\2304C\351qB\302+\200\354L\271Y@\322<d\316&\220\356L"

_main._enc.2:                           ; @main._enc.2
	.ascii	"\200\335:\227\364Q\256\013h\305\"\177\3349\226\363P\255\ng\304!~\3338\225\362O\254\tf\303 }\3327\224\361N\253\b"

_main._enc.3:                           ; @main._enc.3
	.ascii	"\314\272G\373\217x\313k\002\251E\005\260\020\364\237 \236#"

_main._enc.4:                           ; @main._enc.4
	.ascii	"\nP"

_verify_license._enc:                   ; @verify_license._enc
	.ascii	"\016A\262\031i\332L\361\237=\332\235T\271\025x"

_verify_license._enc.5:                 ; @verify_license._enc.5
	.ascii	"\264\231\b\330\332}\202!T\371mW\341\027\267\310z\206o"

_verify_license._enc.6:                 ; @verify_license._enc.6
	.ascii	"<a\206+<\242Y\362\232c\236\303p\335/\003\240i\234"

_verify_license._enc.7:                 ; @verify_license._enc.7
	.ascii	"=`\207*/\240R\361\317x\237\302\007\350J)\266q\304\275\030\356\247\031\363I#\233u\313\267\027\376\245\t\371L3\366Z\371\240\"\210"

_verify_license._enc.8:                 ; @verify_license._enc.8
	.ascii	"\365\336I\231\233<\303`\025\270,\025\267Y\361\230:\243\306\311~/9\233`\332\260\b\346\007#\210wY"

_verify_license._enc.9:                 ; @verify_license._enc.9
	.ascii	"`=\332w|\370\000\277\222%\302\237r\2205V\260\031\270\336\016"

.subsections_via_symbols
