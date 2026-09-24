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
	mov	w10, #20453                     ; =0x4fe5
	movk	w10, #23144, lsl #16
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
	mov	w10, #13702                     ; =0x3586
	movk	w10, #11258, lsl #16
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
	mov	w10, #27937                     ; =0x6d21
	movk	w10, #205, lsl #16
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
	mov	w10, #46960                     ; =0xb770
	movk	w10, #29294, lsl #16
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
	mov	w10, #36715                     ; =0x8f6b
	movk	w10, #10756, lsl #16
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
	mov	w10, #40680                     ; =0x9ee8
	movk	w10, #26102, lsl #16
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
	mov	w10, #32858                     ; =0x805a
	movk	w10, #17654, lsl #16
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
	mov	w10, #45152                     ; =0xb060
	movk	w10, #15918, lsl #16
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
	mov	w10, #53302                     ; =0xd036
	movk	w10, #15161, lsl #16
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
	mov	w10, #34912                     ; =0x8860
	movk	w10, #4674, lsl #16
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
	mov	w10, #1368                      ; =0x558
	movk	w10, #2402, lsl #16
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
	.ascii	"\330\205b\317\254\t\366S0\235z'\204a\316\253\b\365R?\234y&\203`\315\252\027\364Q>\233x%\202o\314\251\026\363P"

_main._enc.1:                           ; @main._enc.1
	.ascii	"\335\232o\326\263\005\354-=\206g,\210z\260\264\021\356B5\237\0074\264]\366\232:\317/6\244J\022\270P\346\230:"

_main._enc.2:                           ; @main._enc.2
	.ascii	"\034A\246\013h\3152\227\364Y\276\343@\245\no\3141\226\373X\275\342G\244\tn\3230\225\372_\274\341F\253\bm\3227\224"

_main._enc.3:                           ; @main._enc.3
	.ascii	"5C\276\002v\2012\222\373P\274\374I\351\rf\331g\332"

_main._enc.4:                           ; @main._enc.4
	.ascii	"f<"

_verify_license._enc:                   ; @verify_license._enc
	.ascii	"\251\346\025\276\316}\353V8\232}:\363\036\262\337"

_verify_license._enc.5:                 ; @verify_license._enc.5
	.ascii	"\001,\275mo\3107\224\341L\330\342T\242\002}\3173\332"

_verify_license._enc.6:                 ; @verify_license._enc.6
	.ascii	"@\035\372W@\336%\216\346\037\342\277\f\241S\177\334\025\340"

_verify_license._enc.7:                 ; @verify_license._enc.7
	.ascii	"\026K\254\001\004\213y\332\344S\264\351,\303a\002\235Z\357\2263\305\2142\330b\b\260^\340\234<\325\216\"\322g\030\335q\322\213\t\243"

_verify_license._enc.8:                 ; @verify_license._enc.8
	.ascii	";\020\207WU\362\r\256\333v\342\333y\227?V\364m\b\007\260\341\367U\256\024~\306(\311\355F\271\227"

_verify_license._enc.9:                 ; @verify_license._enc.9
	.ascii	"x%\302od\340\030\247\212=\332\207j\210-N\250\001\240\306\026"

.subsections_via_symbols
