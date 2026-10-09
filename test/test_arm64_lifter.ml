open Alcotest
open Vm_ir
open Arm64_lifter

let test_arm64_lift_arithmetic () =
  let asm = {|
    mov x0, #42
    mov x1, #58
    add x0, x0, x1
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_add" } asm with
  | Error err -> fail ("Failed to lift ARM64 add: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 42 + 58 = 100" 100L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_branch_abs () =
  let asm = {|
    mov x0, #-42
    cmp x0, #0
    b.ge .Lpos
    neg x0, x0
.Lpos:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_abs" } asm with
  | Error err -> fail ("Failed to lift ARM64 abs: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 abs(-42) = 42" 42L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_loop_factorial () =
  let asm = {|
    mov x0, #1
    mov x1, #5
.Lloop:
    cmp x1, #1
    b.le .Ldone
    mul x0, x0, x1
    sub x1, x1, #1
    b .Lloop
.Ldone:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_factorial" } asm with
  | Error err -> fail ("Failed to lift ARM64 factorial: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 5! = 120" 120L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_cbz_cbnz () =
  let asm = {|
    mov x0, #0
    cbz x0, .Lis_zero
    mov x0, #999
    b .Lexit
.Lis_zero:
    mov x0, #777
.Lexit:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_cbz" } asm with
  | Error err -> fail ("Failed to lift ARM64 cbz: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 cbz branches to 777" 777L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_byte_memory () =
  let asm = {|
    mov x1, #0x1000
    mov w2, #0x42
    strb w2, [x1, #1]
    sturb wzr, [x1, #2]
    mov w3, #0x7F
    strb w3, [x1, #3]
    ldrb w0, [x1, #1]
    ldurb w4, [x1, #2]
    add x0, x0, x4
    ldrsb w5, [x1, #3]
    add x0, x0, x5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_byte_mem" } asm with
  | Error err -> fail ("Failed to lift ARM64 byte memory: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 byte memory 0x42 + 0 + 0x7F = 0xC1 (193)" 193L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_halfword_memory () =
  let asm = {|
    mov x1, #0x1000
    mov w2, #0xBEEF
    strh w2, [x1, #2]
    ldrh w0, [x1, #2]
    ldrb w4, [x1, #3]
    add x0, x0, x4
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_halfword_mem" } asm with
  | Error err -> fail ("Failed to lift ARM64 halfword memory: " ^ err)
  | Ok f ->
      (* Pin the lifted widths: strh/ldrh must produce B16 mem operands — the
         original bug collapsed them into byte loads/stores via the catch-all. *)
      let b16_stores = ref 0 and b16_loads = ref 0 in
      Hashtbl.iter
        (fun _ (b : Ir.basic_block) ->
          List.iter
            (function
              | Ir.Mov { dst = Ir.Mem { width = Register.B16; _ }; _ } -> incr b16_stores
              | Ir.Mov { src = Ir.Mem { width = Register.B16; _ }; _ } -> incr b16_loads
              | _ -> ())
            b.instrs)
        f.cfg.blocks;
      check int "strh lifted as B16 store" 1 !b16_stores;
      check int "ldrh lifted as B16 load" 1 !b16_loads;
      (match Reference_vm.evaluate f with
       | Ok snap -> check int64 "ARM64 halfword 0xBEEF + high byte 0xBE = 0xBFAD (49069)" 49069L snap.final_rax
       | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_pre_post_writeback () =
  let asm = {|
    mov x1, #0x2000
    mov x2, #100
    mov x3, #200
    str x2, [x1, #8]!
    str x3, [x1, #8]!
    mov x4, #0x2000
    ldr x5, [x4, #8]!
    ldr x6, [x4, #8]!
    add x0, x5, x6
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_pre_post" } asm with
  | Error err -> fail ("Failed to lift ARM64 pre-index: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 pre-index writeback 100 + 200 = 300" 300L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_post_index () =
  let asm = {|
    mov x1, #0x3000
    mov x2, #55
    str x2, [x1], #16
    mov x3, #77
    str x3, [x1], #16
    mov x4, #0x3000
    ldr x5, [x4], #16
    ldr x6, [x4], #16
    add x0, x5, x6
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_post_idx" } asm with
  | Error err -> fail ("Failed to lift ARM64 post-index: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 post-index writeback 55 + 77 = 132" 132L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_pair_stp_ldp () =
  let asm = {|
    mov x1, #0x4000
    mov x2, #111
    mov x3, #222
    stp x2, x3, [x1, #-16]!
    ldp x4, x5, [x1], #16
    add x0, x4, x5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_pair_mem" } asm with
  | Error err -> fail ("Failed to lift ARM64 stp/ldp: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 stp/ldp writeback 111 + 222 = 333" 333L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_signed_memory () =
  let asm = {|
    mov x1, #0x1000
    mov w2, #0xFB
    strb w2, [x1, #1]
    mov w2, #0xFED4
    strh w2, [x1, #2]
    mov w2, #0xFFFE7960
    str w2, [x1, #4]
    ldrsb x0, [x1, #1]
    ldrsh x4, [x1, #2]
    add x0, x0, x4
    ldrsw x5, [x1, #4]
    add x0, x0, x5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_signed_mem" } asm with
  | Error err -> fail ("Failed to lift ARM64 signed memory: " ^ err)
  | Ok f ->
      let signed_loads = ref 0 in
      Hashtbl.iter
        (fun _ (b : Ir.basic_block) ->
          List.iter
            (function
              | Ir.Mov { src = Ir.Mem { is_signed = true; _ }; _ } -> incr signed_loads
              | _ -> ())
            b.instrs)
        f.cfg.blocks;
      check int "3 signed loads lifted with is_signed=true" 3 !signed_loads;
      (match Reference_vm.evaluate f with
      | Ok snap ->
          (* (-5) + (-300) + (-100000) = -100305 *)
          check int64 "ARM64 signed memory sum = -100305" (-100305L) snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_3addr_madd_msub_sdiv_bic () =
  let asm = {|
    mov x1, #7
    mov x2, #6
    mov x3, #100
    madd x4, x1, x2, x3
    msub x5, x1, x2, x3
    sdiv x6, x3, x1
    bic x7, x3, x1
    add x0, x4, x5
    add x0, x0, x6
    add x0, x0, x7
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_3addr" } asm with
  | Error err -> fail ("Failed to lift ARM64 3-address ALU: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          (* madd: 100 + 7 * 6 = 142
             msub: 100 - 7 * 6 = 58
             sdiv: 100 / 7 = 14
             bic:  100 & ~7 = 96
             sum:  142 + 58 + 14 + 96 = 310 *)
          check int64 "ARM64 3-addr ALU sum = 310" 310L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_w18_b32_zero_extension () =
  let asm = {|
    mov w18, #-1
    mov x0, x18
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_w18_zext" } asm with
  | Error err -> fail ("Failed to lift ARM64 w18: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 w18 zero-extends to 0xffffffff" 0xFFFFFFFFL snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_movz_movk () =
  let asm = {|
    mov w0, #46593
    movk w0, #30384, lsl #16
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_movk" } asm with
  | Error err -> fail ("Failed to lift ARM64 movk: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ARM64 movk 30384<<16 | 46593 = 0x76B0B601" 0x76B0B601L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_shifted_alu () =
  let asm = {|
    mov x1, #10
    mov x2, #3
    add x0, x1, x2, lsl #2
    sub x0, x0, x2, lsl #1
    and x0, x0, x1, lsl #1
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_shifted_alu" } asm with
  | Error err -> fail ("Failed to lift ARM64 shifted alu: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          (* 10 + (3 << 2) = 22
             22 - (3 << 1) = 16
             16 & (10 << 1) = 16 & 20 = 16 *)
          check int64 "ARM64 shifted alu = 16" 16L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_bitmanip () =
  let asm = {|
    mov x1, #0x123456789abcdef0
    rev x0, x1
    clz x2, x1
    rbit x3, x1
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_bitmanip" } asm with
  | Error err -> fail ("Failed to lift ARM64 bitmanip: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 rev = 0xf0debc9a78563412" (-1090226688147180526L) snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_fp_scalar () =
  let asm = {|
    mov x1, #10
    scvtf d0, x1
    mov x2, #4
    scvtf d1, x2
    fadd d2, d0, d1
    fmul d3, d0, d1
    fdiv d4, d0, d1
    fcvtzs x0, d2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_fp_scalar" } asm with
  | Error err -> fail ("Failed to lift ARM64 fp scalar: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 fp add (10 + 4) = 14" 14L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_bitfields () =
  let asm = {|
    mov x1, #0x1234
    mov x0, #0
    bfi x0, x1, #8, #16
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_bfi" } asm with
  | Error err -> fail ("Failed to lift ARM64 bfi: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 bfi 0x1234 at 8 = 0x123400" 0x123400L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_mult_accum () =
  let asm = {|
    mov x1, #100
    mov x2, #20
    mov x3, #5
    smaddl x0, w1, w2, x3
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_smaddl" } asm with
  | Error err -> fail ("Failed to lift ARM64 smaddl: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 smaddl (5 + 100*20) = 2005" 2005L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_conditionals () =
  let asm = {|
    mov x1, #10
    mov x2, #20
    cmp x1, #10
    csinc x0, x1, x2, eq
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_csinc" } asm with
  | Error err -> fail ("Failed to lift ARM64 csinc: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 csinc eq = 10" 10L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_adc_sbc () =
  let asm = {|
    mov x1, #-1
    adds x2, x1, #1
    mov x3, #10
    mov x4, #20
    adc x0, x3, x4
    subs x5, x3, #15
    sbc x6, x4, x3
    add x0, x0, x6
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_adc_sbc" } asm with
  | Error err -> fail ("Failed to lift ARM64 adc/sbc: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          (* x1 = -1
             adds x2, x1, #1 -> x2 = 0, carry = 1
             adc x0, 10, 20 -> 10 + 20 + 1 = 31
             subs x5, 10, 15 -> 10 - 15 = -5, borrow = 1
             sbc x6, 20, 10 -> 20 - 10 - 1 = 9
             add x0, x0, x6 -> 31 + 9 = 40 *)
          check int64 "ARM64 adc/sbc sum = 40" 40L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_ccmp_ccmn () =
  let asm = {|
    mov x1, #10
    mov x2, #20
    cmp x1, #10
    ccmp x2, #20, #0, eq
    cset x0, eq
    cmp x1, #99
    ccmp x2, #20, #0, eq
    cset x3, eq
    add x0, x0, x3
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_ccmp" } asm with
  | Error err -> fail ("Failed to lift ARM64 ccmp: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          (* 1st: x1 == 10 is true -> cmp x2, #20 runs -> x2 == 20 is true -> eq is true -> x0 = 1
             2nd: x1 == 99 is false -> flags set to nzcv=#0 -> eq is false -> x3 = 0
             x0 + x3 = 1 *)
          check int64 "ARM64 ccmp condition select = 1" 1L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_atomics () =
  let asm = {|
    mov x1, #0x2000
    mov x2, #42
    stlr x2, [x1]
    ldar x0, [x1]
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_ldar_stlr" } asm with
  | Error err -> fail ("Failed to lift ARM64 ldar/stlr: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ldar reads 42" 42L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_lse_atomics () =
  let asm = {|
    mov x1, #0x3000
    mov x2, #160
    str x2, [x1]
    mov x4, #2
    ldset x4, x3, [x1]
    mov x6, #32
    ldclr x6, x5, [x1]
    mov x8, #1
    ldeor x8, x7, [x1]
    ldr x0, [x1]
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_lse" } asm with
  | Error err -> fail ("Failed to lift ARM64 LSE: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "LSE final mem = 131" 131L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_exclusive () =
  let asm = {|
    mov x1, #0x4000
    mov x2, #99
    str x2, [x1]
    ldxr x3, [x1]
    mov x4, #123
    stxr w5, x4, [x1]
    ldr x0, [x1]
    add x0, x0, x5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_excl" } asm with
  | Error err -> fail ("Failed to lift ARM64 exclusive: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "stxr status 0 + 123 = 123" 123L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_ldnp_stnp () =
  let asm = {|
    mov x1, #0x2000
    mov x2, #100
    mov x3, #200
    stnp x2, x3, [x1]
    ldnp x4, x5, [x1]
    add x0, x4, x5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_np" } asm with
  | Error err -> fail ("Failed to lift ARM64 ldnp/stnp: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ldnp/stnp 100 + 200 = 300" 300L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_unprivileged_ldtr_sttr () =
  let asm = {|
    mov x1, #0x3000
    mov x2, #77
    sttr x2, [x1]
    ldtr x0, [x1]
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_tr" } asm with
  | Error err -> fail ("Failed to lift ARM64 ldtr/sttr: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ldtr/sttr = 77" 77L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_ubfm_sbfm () =
  let asm = {|
    mov x1, #0xABCD
    ubfm x0, x1, #4, #11
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_bfm" } asm with
  | Error err -> fail ("Failed to lift ARM64 ubfm: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "ubfm 0xABCD[4..11] = 0xBC (188)" 188L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_fp_fma_fneg_fabs () =
  let asm = {|
    mov x1, #3
    scvtf d1, x1
    mov x2, #4
    scvtf d2, x2
    mov x3, #5
    scvtf d3, x3
    fmadd d0, d1, d2, d3
    fcvtzs x0, d0
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_fma" } asm with
  | Error err -> fail ("Failed to lift ARM64 fmadd: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "fmadd 3*4 + 5 = 17" 17L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_fcsel_fmin_fmax () =
  let asm = {|
    mov x1, #10
    scvtf d1, x1
    mov x2, #20
    scvtf d2, x2
    fcmp d1, d2
    fcsel d0, d1, d2, lt
    fmin d3, d1, d2
    fmax d4, d1, d2
    fcvtzs x0, d0
    fcvtzs x3, d3
    fcvtzs x4, d4
    add x0, x0, x3
    add x0, x0, x4
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_fcsel" } asm with
  | Error err -> fail ("Failed to lift ARM64 fcsel/fmin/fmax: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 fcsel + fmin + fmax = 40" 40L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_fsqrt () =
  let asm = {|
    mov x1, #81
    scvtf d0, x1
    fsqrt d1, d0
    fcvtzs x0, d1
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_fsqrt" } asm with
  | Error err -> fail ("Failed to lift ARM64 fsqrt: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 fsqrt(81) = 9" 9L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_fcmp_zero () =
  let asm = {|
    mov x1, #10
    scvtf d0, x1
    fcmp d0, #0.0
    b.gt .Lpositive
    mov x0, #1
    b .Lend
.Lpositive:
    mov x0, #2
.Lend:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_fcmp_zero" } asm with
  | Error err -> fail ("Failed to lift ARM64 fcmp zero: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 fcmp d0, #0.0 > 0 -> 2" 2L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_fp_conversions () =
  let asm = {|
    mov x1, #42
    ucvtf d0, x1
    fcvt s1, d0
    fcvt d2, s1
    fcvtzu x0, d2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_fp_conversions" } asm with
  | Error err -> fail ("Failed to lift ARM64 fp conversions: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 ucvtf -> fcvt -> fcvtzu = 42" 42L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_arithmetic () =
  let asm = {|
    mov x1, #10
    mov x2, #20
    dup v1.2d, x1
    dup v2.2d, x2
    add v0.2d, v1.2d, v2.2d
    sub v3.2d, v2.2d, v1.2d
    mul v4.2d, v1.2d, v2.2d
    mov x0, v0.d[0]
    mov x1, v3.d[0]
    mov x2, v4.d[0]
    add x0, x0, x1
    add x0, x0, x2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_arithmetic" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon arithmetic: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon add + sub + mul = 240" 240L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_bitwise () =
  let asm = {|
    mov x1, #0xF0
    mov x2, #0x0F
    dup v1.2d, x1
    dup v2.2d, x2
    orr v3.2d, v1.2d, v2.2d
    and v4.2d, v3.2d, v1.2d
    eor v5.2d, v3.2d, v2.2d
    bic v6.2d, v1.2d, v2.2d
    mov x1, v3.d[0]
    mov x2, v4.d[0]
    mov x3, v5.d[0]
    mov x4, v6.d[0]
    add x0, x1, x2
    add x0, x0, x3
    add x0, x0, x4
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_bitwise" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon bitwise: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon orr/and/eor/bic sum = 975" 975L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_shifts_min_max () =
  let asm = {|
    mov x1, #16
    mov x2, #32
    dup v1.2d, x1
    dup v2.2d, x2
    shl v3.2d, v1.2d, #2
    ushr v4.2d, v2.2d, #1
    smin v5.2d, v1.2d, v2.2d
    smax v6.2d, v1.2d, v2.2d
    mov x1, v3.d[0]
    mov x2, v4.d[0]
    mov x3, v5.d[0]
    mov x4, v6.d[0]
    add x0, x1, x2
    add x0, x0, x3
    add x0, x0, x4
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_shifts_min_max" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon shifts and min/max: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon shl/ushr/smin/smax sum = 128" 128L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_mem_ld_st () =
  let asm = {|
    mov x1, #12345
    dup v1.2d, x1
    mov v2.16b, v1.16b
    str q2, [sp, #-16]!
    ldr q3, [sp], #16
    st1 {v3.16b}, [sp, #-16]!
    ld1 {v0.16b}, [sp], #16
    mov x0, v0.d[0]
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_mem_ld_st" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon ld1/st1/ldr/str: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon ld1/st1/ldr/str roundtrip = 12345" 12345L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_zip_uzp_trn () =
  let asm = {|
    mov x1, #10
    mov x2, #20
    dup v1.2d, x1
    dup v2.2d, x2
    zip1 v0.2d, v1.2d, v2.2d
    uzp1 v3.2d, v1.2d, v2.2d
    trn1 v4.2d, v1.2d, v2.2d
    mov x0, v0.d[0]
    mov x1, v3.d[0]
    mov x2, v4.d[0]
    add x0, x0, x1
    add x0, x0, x2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_zip_uzp_trn" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon zip/uzp/trn: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon zip1 + uzp1 + trn1 = 30" 30L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_tbl () =
  let asm = {|
    mov x1, #0x03020100
    dup v1.2d, x1
    mov x2, #0x00010203
    dup v2.2d, x2
    tbl v0.16b, {v1.16b}, v2.16b
    mov x0, v0.d[0]
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_tbl" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon tbl: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon tbl byte permutation = 0x00010203" 0x00010203L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_neon_ext () =
  let asm = {|
    mov x1, #0x1111111122222222
    dup v1.2d, x1
    mov x2, #0x3333333344444444
    dup v2.2d, x2
    ext v0.16b, v1.16b, v2.16b, #8
    mov x0, v0.d[0]
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_neon_ext" } asm with
  | Error err -> fail ("Failed to lift ARM64 neon ext: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 neon ext #8 = 0x1111111122222222" 0x1111111122222222L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_tbz_tbnz () =
  let asm = {|
    mov x1, #4
    tbz x1, #2, .Lbit2_is_zero
    mov x0, #100
    b .Lcheck_tbnz
  .Lbit2_is_zero:
    mov x0, #1
  .Lcheck_tbnz:
    tbnz x1, #2, .Lbit2_is_set
    mov x2, #999
    b .Ldone
  .Lbit2_is_set:
    mov x2, #200
  .Ldone:
    add x0, x0, x2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_tbz_tbnz" } asm with
  | Error err -> fail ("Failed to lift ARM64 tbz/tbnz: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 tbz/tbnz result = 300" 300L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_b_al_nv () =
  let asm = {|
    mov x0, #10
    b.nv .Lshould_not_jump
    b.al .Ljumped
    mov x0, #999
  .Lshould_not_jump:
    mov x0, #888
  .Ljumped:
    add x0, x0, #5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_b_al_nv" } asm with
  | Error err -> fail ("Failed to lift ARM64 b.al/nv: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 b.al/b.nv result = 15" 15L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_subs_adds_flags_and_xzr () =
  let asm = {|
    mov x1, #42
    mov x2, #42
    subs xzr, x1, x2
    b.eq .Lsub_is_zero
    mov x0, #100
    b .Lnext
  .Lsub_is_zero:
    mov x0, #50
  .Lnext:
    mov x3, #15
    adds x4, x3, #-15
    b.eq .Ladd_is_zero
    mov x5, #999
    b .Lstore_pair
  .Ladd_is_zero:
    mov x5, #25
  .Lstore_pair:
    stp xzr, xzr, [sp, #-16]!
    ldp x6, x7, [sp], #16
    add x0, x0, x4
    add x0, x0, x5
    add x0, x0, x6
    add x0, x0, x7
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_subs_xzr" } asm with
  | Error err -> fail ("Failed to lift ARM64 subs/xzr: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 subs/adds flags and xzr result = 75" 75L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_extensions_sxt_uxt () =
  let asm = {|
    mov x1, #0xFF
    sxtb x2, x1
    uxtb x3, x1
    mov x4, #0xFFFF
    sxth x5, x4
    uxth x6, x4
    mov x7, #-1
    uxtw x8, x7
    sxtw x9, x8
    add x0, x2, #2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_extensions" } asm with
  | Error err -> fail ("Failed to lift ARM64 extensions: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 sxtb/uxtb result = 1" 1L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_arm64_lift_register_shifts () =
  let asm = {|
    mov x1, #1
    mov x2, #4
    lsl x0, x1, x2
    mov x3, #32
    mov x4, #2
    lsrv x5, x3, x4
    add x0, x0, x5
    ret
  |} in
  match lift_function ~options:{ function_name = "test_arm64_reg_shifts" } asm with
  | Error err -> fail ("Failed to lift ARM64 reg shifts: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap ->
          check int64 "ARM64 reg shifts result = 24" 24L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))
let test_arm64_lift_conditional_zero_reg () =
  let asm = {|
    mov x1, #10
    cmp x1, #10
    cset wzr, eq
    csel wzr, w1, wzr, eq
    cinc wzr, w1, eq
    cset x0, eq
    ret
  |} in
  match lift_function ~options:{ function_name = "test_cond_xzr" } asm with
  | Error err -> fail ("Failed to lift: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "cset x0, eq = 1" 1L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let tests = [
  ("ARM64 Lift Arithmetic (add)", `Quick, test_arm64_lift_arithmetic);
  ("ARM64 Lift Branching (abs)", `Quick, test_arm64_lift_branch_abs);
  ("ARM64 Lift Loop (5! factorial)", `Quick, test_arm64_lift_loop_factorial);
  ("ARM64 Lift Compare & Branch (cbz)", `Quick, test_arm64_lift_cbz_cbnz);
  ("ARM64 Lift Byte Memory (strb/sturb/ldrb/ldrsb)", `Quick, test_arm64_lift_byte_memory);
  ("ARM64 Lift Halfword Memory (strh/ldrh)", `Quick, test_arm64_lift_halfword_memory);
  ("ARM64 Lift Signed Memory (ldrsb/ldrsh/ldrsw)", `Quick, test_arm64_lift_signed_memory);
  ("ARM64 Lift Pre-index Writeback (!)", `Quick, test_arm64_lift_pre_post_writeback);
  ("ARM64 Lift Post-index Writeback ([x], #imm)", `Quick, test_arm64_lift_post_index);
  ("ARM64 Lift Pair stp/ldp Writeback", `Quick, test_arm64_lift_pair_stp_ldp);
  ("ARM64 Lift 3-Address ALU (madd/msub/sdiv/bic)", `Quick, test_arm64_lift_3addr_madd_msub_sdiv_bic);
  ("ARM64 Lift w18 B32 zero-extension", `Quick, test_arm64_w18_b32_zero_extension);
  ("ARM64 Lift movz/movk with shift", `Quick, test_arm64_lift_movz_movk);
  ("ARM64 Lift Shifted ALU (lsl/lsr)", `Quick, test_arm64_lift_shifted_alu);
  ("ARM64 Lift Bit Manipulation (rev/clz/rbit)", `Quick, test_arm64_lift_bitmanip);
  ("ARM64 Lift Scalar FP (scvtf/fadd/fcvtzs)", `Quick, test_arm64_lift_fp_scalar);
  ("ARM64 Lift Bitfields (bfi/bfxil/extr)", `Quick, test_arm64_lift_bitfields);
  ("ARM64 Lift Multiply-Accumulate (smaddl/smulh)", `Quick, test_arm64_lift_mult_accum);
  ("ARM64 Lift Conditionals (csinc/csinv/csneg)", `Quick, test_arm64_lift_conditionals);
  ("ARM64 Lift Adc/Sbc", `Quick, test_arm64_lift_adc_sbc);
  ("ARM64 Lift Ccmp/Ccmn", `Quick, test_arm64_lift_ccmp_ccmn);
  ("ARM64 Lift Atomics (ldar/stlr)", `Quick, test_arm64_lift_atomics);
  ("ARM64 Lift LSE (ldset/ldclr/ldeor)", `Quick, test_arm64_lift_lse_atomics);
  ("ARM64 Lift Exclusive (ldxr/stxr)", `Quick, test_arm64_lift_exclusive);
  ("ARM64 Lift Non-Temporal Pair (ldnp/stnp)", `Quick, test_arm64_lift_ldnp_stnp);
  ("ARM64 Lift Unprivileged Mem (ldtr/sttr)", `Quick, test_arm64_lift_unprivileged_ldtr_sttr);
  ("ARM64 Lift Bitfield Move (ubfm/sbfm)", `Quick, test_arm64_lift_ubfm_sbfm);
  ("ARM64 Lift FP FMA (fmadd)", `Quick, test_arm64_lift_fp_fma_fneg_fabs);
  ("ARM64 Lift FP Cond/Min/Max (fcsel/fmin/fmax)", `Quick, test_arm64_lift_fcsel_fmin_fmax);
  ("ARM64 Lift FP Square Root (fsqrt)", `Quick, test_arm64_lift_fsqrt);
  ("ARM64 Lift FP Compare Zero (fcmp #0.0)", `Quick, test_arm64_lift_fcmp_zero);
  ("ARM64 Lift FP Conversions (ucvtf/fcvt/fcvtzu)", `Quick, test_arm64_lift_fp_conversions);
  ("ARM64 Lift NEON Arithmetic (add/sub/mul)", `Quick, test_arm64_lift_neon_arithmetic);
  ("ARM64 Lift NEON Bitwise (orr/and/eor/bic)", `Quick, test_arm64_lift_neon_bitwise);
  ("ARM64 Lift NEON Shifts/Min/Max (shl/ushr/smin/smax)", `Quick, test_arm64_lift_neon_shifts_min_max);
  ("ARM64 Lift NEON Mem (ld1/st1/ldr/str)", `Quick, test_arm64_lift_neon_mem_ld_st);
  ("ARM64 Lift NEON Permutations (zip/uzp/trn)", `Quick, test_arm64_lift_neon_zip_uzp_trn);
  ("ARM64 Lift NEON Tbl", `Quick, test_arm64_lift_neon_tbl);
  ("ARM64 Lift NEON Ext", `Quick, test_arm64_lift_neon_ext);
  ("ARM64 Lift tbz/tbnz bit branch", `Quick, test_arm64_lift_tbz_tbnz);
  ("ARM64 Lift b.al / b.nv", `Quick, test_arm64_lift_b_al_nv);
  ("ARM64 Lift subs/adds with flags and xzr", `Quick, test_arm64_lift_subs_adds_flags_and_xzr);
  ("ARM64 Lift extensions (sxt/uxt)", `Quick, test_arm64_lift_extensions_sxt_uxt);
  ("ARM64 Lift register shifts (lsl/lsr/asr)", `Quick, test_arm64_lift_register_shifts);
  ("ARM64 Lift conditional zero reg (wzr/xzr)", `Quick, test_arm64_lift_conditional_zero_reg);
]


