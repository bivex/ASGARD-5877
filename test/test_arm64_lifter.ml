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

let tests = [
  ("ARM64 Lift Arithmetic (add)", `Quick, test_arm64_lift_arithmetic);
  ("ARM64 Lift Branching (abs)", `Quick, test_arm64_lift_branch_abs);
  ("ARM64 Lift Loop (5! factorial)", `Quick, test_arm64_lift_loop_factorial);
  ("ARM64 Lift Compare & Branch (cbz)", `Quick, test_arm64_lift_cbz_cbnz);
]
