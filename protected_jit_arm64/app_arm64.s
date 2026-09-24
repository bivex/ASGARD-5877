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
	mov	w11, #48343                     ; =0xbcd7
	str	w11, [x10]
Lloh4:
	adrp	x11, _ASG_asgbranch_t_310487@PAGE
Lloh5:
	add	x11, x11, _ASG_asgbranch_t_310487@PAGEOFF
	mov	w12, #29532                     ; =0x735c
	movk	w12, #23020, lsl #16
	eor	x11, x11, x12
Lloh6:
	adrp	x13, _ASG_asgbranch_f_310487@PAGE
Lloh7:
	add	x13, x13, _ASG_asgbranch_f_310487@PAGEOFF
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
	.p2align	2                               ; -- Begin function ASG_asgbranch_t_310487
_ASG_asgbranch_t_310487:                ; @ASG_asgbranch_t_310487
	.cfi_startproc
; %bb.0:
	ret
	.cfi_endproc
                                        ; -- End function
	.p2align	2                               ; -- Begin function ASG_asgbranch_f_310487
_ASG_asgbranch_f_310487:                ; @ASG_asgbranch_f_310487
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
	mov	w10, #24421                     ; =0x5f65
	movk	w10, #17144, lsl #16
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
	mov	w10, #8241                      ; =0x2031
	movk	w10, #23551, lsl #16
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
	mov	w10, #1602                      ; =0x642
	movk	w10, #25437, lsl #16
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
	mov	w10, #48198                     ; =0xbc46
	movk	w10, #18289, lsl #16
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
	mov	w8, #48343                      ; =0xbcd7
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
	mov	w10, #60476                     ; =0xec3c
	movk	w10, #14948, lsl #16
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
	mov	w10, #21679                     ; =0x54af
	movk	w10, #14728, lsl #16
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
	mov	w10, #14208                     ; =0x3780
	movk	w10, #27026, lsl #16
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
	mov	w10, #29021                     ; =0x715d
	movk	w10, #7362, lsl #16
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
	mov	w10, #44745                     ; =0xaec9
	movk	w10, #8464, lsl #16
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
	mov	w10, #26441                     ; =0x6749
	movk	w10, #1466, lsl #16
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
	mov	w10, #24761                     ; =0x60b9
	movk	w10, #7623, lsl #16
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
	.ascii	"X\005\342O,\211v\323\260\035\372\247\004\341N+\210u\322\277\034\371\246\003\340M*\227t\321\276\033\370\245\002\357L)\226s\320"

_main._enc.1:                           ; @main._enc.1
	.ascii	"j-\330a\004\262[\232\2121\320\233?\315\007\003\246Y\365\202(\260\203\003\352A-\215x\230\201\023\375\245\017\347Q/\215"

_main._enc.2:                           ; @main._enc.2
	.ascii	"\177\"\305h\013\256Q\364\227:\335\200#\306i\f\257R\365\230;\336\201$\307j\r\260S\366\231<\337\202%\310k\016\261T\367"

_main._enc.3:                           ; @main._enc.3
	.ascii	"\003u\2104@\267\004\244\315f\212\312\177\337;P\357Q\354"

.zerofill __DATA,__bss,_ASG_current_trap_id,4,2 ; @ASG_current_trap_id
.zerofill __DATA,__bss,_ASG_current_condition,4,2 ; @ASG_current_condition
_main._enc.4:                           ; @main._enc.4
	.ascii	"1k"

.zerofill __DATA,__bss,_ASG_nanomite_count,8,3 ; @ASG_nanomite_count
.zerofill __DATA,__bss,_ASG_nanomite_table,2048,3 ; @ASG_nanomite_table
_verify_license._enc:                   ; @verify_license._enc
	.ascii	"\356\241R\371\211:\254\021\177\335:}\264Y\365\230"

_verify_license._enc.5:                 ; @verify_license._enc.5
	.asciz	"\333\366g\267\265\022\355N;\226\0028\216x\330\247\025\351"

_verify_license._enc.6:                 ; @verify_license._enc.6
	.ascii	"} \307j}\343\030\263\333\"\337\2021\234nB\341(\335"

_verify_license._enc.7:                 ; @verify_license._enc.7
	.ascii	"\351\264S\376\373t\206%\033\254K\026\323<\236\375b\245\020i\314:s\315'\235\367O\241\037c\303*q\335-\230\347\"\216-t\366\\"

_verify_license._enc.8:                 ; @verify_license._enc.8
	.ascii	"\0229\256~|\333$\207\362_\313\362P\276\026\177\335D!.\231\310\336|\207=W\357\001\340\304o\220\276"

_verify_license._enc.9:                 ; @verify_license._enc.9
	.ascii	"\231\304#\216\205\001\371Fk\334;f\213i\314\257I\340A'\367"

	.section	__DATA,__mod_init_func,mod_init_funcs
	.p2align	3, 0x0
	.quad	__asg_nanomite_auto_init_
.subsections_via_symbols
