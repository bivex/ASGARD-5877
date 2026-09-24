	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 26, 0	sdk_version 26, 5
	.p2align	2                               ; -- Begin function _asg_nanomite_auto_init_
__asg_nanomite_auto_init_:              ; @_asg_nanomite_auto_init_
	.cfi_startproc
; %bb.0:
	stp	x29, x30, [sp, #-16]!           ; 16-byte Folded Spill
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	bl	_ASG_install_nanomites
	ldp	x29, x30, [sp], #16             ; 16-byte Folded Reload
	b	_ASG_register_nanomite
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function ASG_install_nanomites
_ASG_install_nanomites:                 ; @ASG_install_nanomites
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #32
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
Lloh0:
	adrp	x8, _ASG_nanomite_trap_handler@PAGE
Lloh1:
	add	x8, x8, _ASG_nanomite_trap_handler@PAGEOFF
	mov	x9, #274877906944               ; =0x4000000000
	stp	x8, x9, [sp]
	mov	x1, sp
	mov	w0, #5                          ; =0x5
	mov	x2, #0                          ; =0x0
	bl	_sigaction
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	add	sp, sp, #32
	ret
	.loh AdrpAdd	Lloh0, Lloh1
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function ASG_register_nanomite
_ASG_register_nanomite:                 ; @ASG_register_nanomite
	.cfi_startproc
; %bb.0:
	adrp	x8, _ASG_nanomite_count@PAGE
	ldr	x9, [x8, _ASG_nanomite_count@PAGEOFF]
	cmp	x9, #63
	b.hi	LBB2_2
; %bb.1:
Lloh2:
	adrp	x10, _ASG_nanomite_table@PAGE
Lloh3:
	add	x10, x10, _ASG_nanomite_table@PAGEOFF
	add	x10, x10, x9, lsl #5
	mov	w11, #41973                     ; =0xa3f5
	str	w11, [x10]
Lloh4:
	adrp	x11, _ASG_asgbranch_t_238581@PAGE
Lloh5:
	add	x11, x11, _ASG_asgbranch_t_238581@PAGEOFF
	mov	w12, #54984                     ; =0xd6c8
	movk	w12, #29082, lsl #16
	eor	x11, x11, x12
Lloh6:
	adrp	x13, _ASG_asgbranch_f_238581@PAGE
Lloh7:
	add	x13, x13, _ASG_asgbranch_f_238581@PAGEOFF
	eor	x13, x13, x12
	stp	x11, x13, [x10, #8]
	str	w12, [x10, #24]
	add	x9, x9, #1
	str	x9, [x8, _ASG_nanomite_count@PAGEOFF]
LBB2_2:
	ret
	.loh AdrpAdd	Lloh6, Lloh7
	.loh AdrpAdd	Lloh4, Lloh5
	.loh AdrpAdd	Lloh2, Lloh3
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function ASG_asgbranch_t_238581
_ASG_asgbranch_t_238581:                ; @ASG_asgbranch_t_238581
	.cfi_startproc
; %bb.0:
	ret
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function ASG_asgbranch_f_238581
_ASG_asgbranch_f_238581:                ; @ASG_asgbranch_f_238581
	.cfi_startproc
; %bb.0:
	ret
	.cfi_endproc
                                        ; -- End function
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
	mov	w10, #16419                     ; =0x4023
	movk	w10, #4649, lsl #16
	stur	w10, [x29, #-80]
Lloh8:
	adrp	x10, _main._enc@PAGE
Lloh9:
	add	x10, x10, _main._enc@PAGEOFF
	sub	x11, x29, #128
LBB5_1:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w12, [x29, #-80]
	eor	w12, w12, w8
	ldrb	w13, [x10, x9]
	eor	w12, w13, w12
	strb	w12, [x11, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #41
	b.ne	LBB5_1
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
	mov	w10, #20650                     ; =0x50aa
	movk	w10, #9710, lsl #16
	stur	w10, [x29, #-80]
Lloh10:
	adrp	x10, _main._enc.1@PAGE
Lloh11:
	add	x10, x10, _main._enc.1@PAGEOFF
LBB5_3:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-80]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #39
	b.ne	LBB5_3
; %bb.4:
	strb	wzr, [x0, #39]
	; InlineAsm Start
	; InlineAsm End
	bl	_puts
	sub	x0, sp, #48
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #34517                     ; =0x86d5
	movk	w10, #16599, lsl #16
	stur	w10, [x29, #-80]
Lloh12:
	adrp	x10, _main._enc.2@PAGE
Lloh13:
	add	x10, x10, _main._enc.2@PAGEOFF
LBB5_5:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-80]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #41
	b.ne	LBB5_5
; %bb.6:
	strb	wzr, [x0, #41]
	; InlineAsm Start
	; InlineAsm End
	bl	_puts
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #1815                      ; =0x717
	movk	w10, #6510, lsl #16
	stur	w10, [x29, #-80]
Lloh14:
	adrp	x10, _main._enc.3@PAGE
Lloh15:
	add	x10, x10, _main._enc.3@PAGEOFF
LBB5_7:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-80]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #19
	b.ne	LBB5_7
; %bb.8:
	strb	wzr, [x0, #19]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
Lloh16:
	adrp	x8, ___stdoutp@GOTPAGE
Lloh17:
	ldr	x8, [x8, ___stdoutp@GOTPAGEOFF]
Lloh18:
	ldr	x0, [x8]
	bl	_fflush
	sturb	wzr, [x29, #-80]
	mov	w8, #41973                      ; =0xa3f5
	adrp	x9, _ASG_current_trap_id@PAGE
	str	w8, [x9, _ASG_current_trap_id@PAGEOFF]
Lloh19:
	adrp	x8, ___stdinp@GOTPAGE
Lloh20:
	ldr	x8, [x8, ___stdinp@GOTPAGEOFF]
Lloh21:
	ldr	x2, [x8]
	sub	x0, x29, #80
	mov	w1, #64                         ; =0x40
	bl	_fgets
	cmp	x0, #0
	cset	w8, eq
	adrp	x9, _ASG_current_condition@PAGE
	str	w8, [x9, _ASG_current_condition@PAGEOFF]
	mov	w0, #5                          ; =0x5
	bl	_raise
	sub	x1, sp, #16
	mov	sp, x1
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #59847                     ; =0xe9c7
	movk	w10, #3178, lsl #16
	stur	w10, [x29, #-84]
Lloh22:
	adrp	x10, _main._enc.4@PAGE
Lloh23:
	add	x10, x10, _main._enc.4@PAGEOFF
LBB5_9:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-84]
	ldrb	w12, [x10, x9]
	eor	w11, w11, w8
	eor	w11, w12, w11
	strb	w11, [x1, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #1
	b.eq	LBB5_9
; %bb.10:
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
	sub	sp, x29, #16
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	ldp	x20, x19, [sp], #32             ; 16-byte Folded Reload
	ret
	.loh AdrpAdd	Lloh8, Lloh9
	.loh AdrpAdd	Lloh10, Lloh11
	.loh AdrpAdd	Lloh12, Lloh13
	.loh AdrpAdd	Lloh14, Lloh15
	.loh AdrpAdd	Lloh22, Lloh23
	.loh AdrpLdrGotLdr	Lloh19, Lloh20, Lloh21
	.loh AdrpLdrGotLdr	Lloh16, Lloh17, Lloh18
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
	mov	w10, #41460                     ; =0xa1f4
	movk	w10, #24048, lsl #16
	stur	w10, [x29, #-20]
Lloh24:
	adrp	x10, _verify_license._enc@PAGE
Lloh25:
	add	x10, x10, _verify_license._enc@PAGEOFF
	sub	x11, x29, #40
LBB6_1:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w12, [x29, #-20]
	eor	w12, w12, w8
	ldrb	w13, [x10, x9]
	eor	w12, w13, w12
	strb	w12, [x11, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #16
	b.ne	LBB6_1
; %bb.2:
	mov	x8, #0                          ; =0x0
	sturb	wzr, [x29, #-24]
	sub	x9, x29, #40
	; InlineAsm Start
	; InlineAsm End
	mov	w10, #1                         ; =0x1
LBB6_3:                                 ; =>This Inner Loop Header: Depth=1
	ldrb	w11, [x0, x8]
	ldrb	w12, [x9, x8]
	cmp	w11, w12
	csel	w10, w10, wzr, eq
	add	x8, x8, #1
	cmp	x8, #16
	b.ne	LBB6_3
; %bb.4:
	ldrb	w8, [x0, #16]
	cmp	w8, #0
	csel	w19, w10, wzr, eq
	cbz	w19, LBB6_12
; %bb.5:
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #2094                      ; =0x82e
	movk	w10, #31453, lsl #16
	stur	w10, [x29, #-20]
Lloh26:
	adrp	x10, _verify_license._enc.5@PAGE
Lloh27:
	add	x10, x10, _verify_license._enc.5@PAGEOFF
LBB6_6:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #19
	b.ne	LBB6_6
; %bb.7:
	strb	wzr, [x0, #19]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #51163                     ; =0xc7db
	movk	w10, #10293, lsl #16
	stur	w10, [x29, #-20]
Lloh28:
	adrp	x10, _verify_license._enc.6@PAGE
Lloh29:
	add	x10, x10, _verify_license._enc.6@PAGEOFF
LBB6_8:                                 ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #19
	b.ne	LBB6_8
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
	mov	w10, #11681                     ; =0x2da1
	movk	w10, #29734, lsl #16
	stur	w10, [x29, #-20]
Lloh30:
	adrp	x10, _verify_license._enc.7@PAGE
Lloh31:
	add	x10, x10, _verify_license._enc.7@PAGEOFF
LBB6_10:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #44
	b.ne	LBB6_10
; %bb.11:
	strb	wzr, [x0, #44]
	; InlineAsm Start
	; InlineAsm End
	mov	w8, #23962                      ; =0x5d9a
	str	x8, [sp, #-16]!
	bl	_printf
	add	sp, sp, #16
	b	LBB6_17
LBB6_12:
	sub	x0, sp, #48
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #20261                     ; =0x4f25
	movk	w10, #21195, lsl #16
	stur	w10, [x29, #-20]
Lloh32:
	adrp	x10, _verify_license._enc.8@PAGE
Lloh33:
	add	x10, x10, _verify_license._enc.8@PAGEOFF
LBB6_13:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #34
	b.ne	LBB6_13
; %bb.14:
	strb	wzr, [x0, #34]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
	sub	x0, sp, #32
	mov	sp, x0
	mov	w8, #0                          ; =0x0
	mov	x9, #0                          ; =0x0
	mov	w10, #18313                     ; =0x4789
	movk	w10, #27407, lsl #16
	stur	w10, [x29, #-20]
Lloh34:
	adrp	x10, _verify_license._enc.9@PAGE
Lloh35:
	add	x10, x10, _verify_license._enc.9@PAGEOFF
LBB6_15:                                ; =>This Inner Loop Header: Depth=1
	ldur	w11, [x29, #-20]
	eor	w11, w11, w8
	ldrb	w12, [x10, x9]
	eor	w11, w12, w11
	strb	w11, [x0, x9]
	add	x9, x9, #1
	add	w8, w8, #93
	cmp	x9, #21
	b.ne	LBB6_15
; %bb.16:
	strb	wzr, [x0, #21]
	; InlineAsm Start
	; InlineAsm End
	bl	_printf
LBB6_17:
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
	.loh AdrpAdd	Lloh24, Lloh25
	.loh AdrpAdd	Lloh26, Lloh27
	.loh AdrpAdd	Lloh28, Lloh29
	.loh AdrpAdd	Lloh30, Lloh31
	.loh AdrpAdd	Lloh32, Lloh33
	.loh AdrpAdd	Lloh34, Lloh35
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function ASG_nanomite_trap_handler
_ASG_nanomite_trap_handler:             ; @ASG_nanomite_trap_handler
	.cfi_startproc
; %bb.0:
Lloh36:
	adrp	x8, _ASG_nanomite_count@PAGE
Lloh37:
	ldr	x10, [x8, _ASG_nanomite_count@PAGEOFF]
	cbz	x10, LBB7_4
; %bb.1:
Lloh38:
	adrp	x9, _ASG_nanomite_table@PAGE
Lloh39:
	add	x9, x9, _ASG_nanomite_table@PAGEOFF
	adrp	x8, _ASG_current_trap_id@PAGE
LBB7_2:                                 ; =>This Inner Loop Header: Depth=1
	ldr	w11, [x9]
	ldr	w12, [x8, _ASG_current_trap_id@PAGEOFF]
	cmp	w11, w12
	b.eq	LBB7_5
; %bb.3:                                ;   in Loop: Header=BB7_2 Depth=1
	add	x9, x9, #32
	subs	x10, x10, #1
	b.ne	LBB7_2
LBB7_4:
	ret
LBB7_5:
Lloh40:
	adrp	x10, _ASG_current_condition@PAGE
Lloh41:
	ldr	w10, [x10, _ASG_current_condition@PAGEOFF]
	cmp	w10, #0
	mov	w10, #8                         ; =0x8
	mov	w11, #16                        ; =0x10
	csel	x10, x11, x10, eq
	ldr	x10, [x9, x10]
	ldr	w9, [x9, #24]
	eor	x9, x10, x9
	ldr	x10, [x2, #48]
	str	x9, [x10, #272]
	str	wzr, [x8, _ASG_current_trap_id@PAGEOFF]
	ret
	.loh AdrpLdr	Lloh36, Lloh37
	.loh AdrpAdd	Lloh38, Lloh39
	.loh AdrpLdr	Lloh40, Lloh41
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__const
_main._enc:                             ; @main._enc
	.ascii	"\036C\244\tj\3170\225\366[\274\341B\247\bm\3163\224\371Z\277\340E\246\013l\3212\227\370]\276\343D\251\no\3205\226"

_main._enc.1:                           ; @main._enc.1
	.ascii	"\361\266C\372\237)\300\001\021\252K\000\244V\234\230=\302n\031\263+\030\230q\332\266\026\343\003\032\210f>\224|\312\264\026"

_main._enc.2:                           ; @main._enc.2
	.ascii	"\350\265R\377\2349\306c\000\255J\027\264Q\376\2338\305b\017\254I\026\263P\375\232'\304a\016\253H\025\262_\374\231&\303`"

_main._enc.3:                           ; @main._enc.3
	.ascii	"R$\331e\021\346U\365\2347\333\233.\216j\001\276\000\275"

.zerofill __DATA,__bss,_ASG_current_trap_id,4,2 ; @ASG_current_trap_id
.zerofill __DATA,__bss,_ASG_current_condition,4,2 ; @ASG_current_condition
_main._enc.4:                           ; @main._enc.4
	.ascii	"\312\220"

.zerofill __DATA,__bss,_ASG_nanomite_count,8,3 ; @ASG_nanomite_count
.zerofill __DATA,__bss,_ASG_nanomite_table,2048,3 ; @ASG_nanomite_table
_verify_license._enc:                   ; @verify_license._enc
	.ascii	"\265\372\t\242\322a\367J$\206a&\357\002\256\303"

_verify_license._enc.5:                 ; @verify_license._enc.5
	.ascii	"uX\311\031\033\274C\340\2258\254\226 \326v\t\273G\256"

_verify_license._enc.6:                 ; @verify_license._enc.6
	.ascii	"\373\246A\354\373e\2365]\244Y\004\267\032\350\304g\256["

_verify_license._enc.7:                 ; @verify_license._enc.7
	.ascii	"\201\334;\226\223\034\356Ms\304#~\273T\366\225\n\315x\001\244R\033\245O\365\237'\311w\013\253B\031\265E\360\217J\346E\034\2364"

_verify_license._enc.8:                 ; @verify_license._enc.8
	.ascii	"~U\302\022\020\267H\353\2363\247\236<\322z\023\261(MB\365\244\262\020\353Q;\203m\214\250\003\374\322"

_verify_license._enc.9:                 ; @verify_license._enc.9
	.ascii	"\251\364\023\276\2651\311v[\354\013V\273Y\374\237y\320q\027\307"

	.section	__DATA,__mod_init_func,mod_init_funcs
	.p2align	3, 0x0
	.quad	__asg_nanomite_auto_init_
.subsections_via_symbols
