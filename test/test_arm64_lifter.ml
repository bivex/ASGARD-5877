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

let tests = [
  ("ARM64 Lift Arithmetic (add)", `Quick, test_arm64_lift_arithmetic);
  ("ARM64 Lift Branching (abs)", `Quick, test_arm64_lift_branch_abs);
  ("ARM64 Lift Loop (5! factorial)", `Quick, test_arm64_lift_loop_factorial);
  ("ARM64 Lift Compare & Branch (cbz)", `Quick, test_arm64_lift_cbz_cbnz);
  ("ARM64 Lift Byte Memory (strb/sturb/ldrb/ldrsb)", `Quick, test_arm64_lift_byte_memory);
  ("ARM64 Lift Halfword Memory (strh/ldrh)", `Quick, test_arm64_lift_halfword_memory);
  ("ARM64 Lift Pre-index Writeback (!)", `Quick, test_arm64_lift_pre_post_writeback);
  ("ARM64 Lift Post-index Writeback ([x], #imm)", `Quick, test_arm64_lift_post_index);
  ("ARM64 Lift Pair stp/ldp Writeback", `Quick, test_arm64_lift_pair_stp_ldp);
]


