open Alcotest
open Vm_ir
open Riscv_lifter

let test_riscv_lift_arithmetic () =
  let asm = {|
    li a0, 42
    li a1, 58
    add a0, a0, a1
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_add" } asm with
  | Error err -> fail ("Failed to lift RISC-V add: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V 42 + 58 = 100" 100L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_sub_mul () =
  let asm = {|
    li a0, 100
    li a1, 30
    sub a0, a0, a1
    li a2, 2
    mul a0, a0, a2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_sub_mul" } asm with
  | Error err -> fail ("Failed to lift RISC-V sub/mul: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V (100 - 30) * 2 = 140" 140L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_div_rem () =
  let asm = {|
    li a0, 100
    li a1, 7
    rem a2, a0, a1
    div a0, a0, a1
    add a0, a0, a2
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_div_rem" } asm with
  | Error err -> fail ("Failed to lift RISC-V div/rem: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V 100 / 7 + 100 % 7 = 14 + 2 = 16" 16L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_branch_abs () =
  let asm = {|
    li a0, -42
    bgez a0, .Lpos
    neg a0, a0
.Lpos:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_abs" } asm with
  | Error err -> fail ("Failed to lift RISC-V abs: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V abs(-42) = 42" 42L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_loop_factorial () =
  let asm = {|
    li a0, 1
    li a1, 5
.Lloop:
    beqz a1, .Ldone
    mul a0, a0, a1
    addi a1, a1, -1
    j .Lloop
.Ldone:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_factorial" } asm with
  | Error err -> fail ("Failed to lift RISC-V factorial: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V 5! = 120" 120L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_memory () =
  let asm = {|
    li a1, 0x1000
    li a2, 0x42
    sb a2, 1(a1)
    li a3, 0x7F
    sb a3, 2(a1)
    lbu a0, 1(a1)
    lb a4, 2(a1)
    add a0, a0, a4
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_mem" } asm with
  | Error err -> fail ("Failed to lift RISC-V byte memory: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V memory 0x42 + 0x7F = 193" 193L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_slt () =
  let asm = {|
    li a1, 10
    li a2, 20
    slt a0, a1, a2
    slt a3, a2, a1
    add a0, a0, a3
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_slt" } asm with
  | Error err -> fail ("Failed to lift RISC-V slt: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V slt (10 < 20) + (20 < 10) = 1" 1L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let test_riscv_lift_atomics () =
  let asm = {|
    lr.d a0, 0(sp)
    sc.d a1, a2, 0(sp)
    amoswap.d a3, a4, 0(sp)
    amoadd.d a5, a6, 0(sp)
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_atomics" } asm with
  | Error err -> fail ("Failed to lift RISC-V atomics: " ^ err)
  | Ok f ->
      let atomic_count = ref 0 in
      Hashtbl.iter (fun _ (b : Ir.basic_block) ->
        List.iter (function
          | Ir.Atomic_mem _ -> incr atomic_count
          | _ -> ()
        ) b.instrs
      ) f.cfg.blocks;
      check int "4 atomic memory instructions lifted" 4 !atomic_count

let test_riscv_lift_fp () =
  let asm = {|
    fadd.d f0, f1, f2
    fsub.d f3, f4, f5
    fmul.d f6, f7, f8
    fdiv.d f9, f10, f11
    feq.d a0, f12, f13
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_fp" } asm with
  | Error err -> fail ("Failed to lift RISC-V FP: " ^ err)
  | Ok f ->
      let fp_binop_count = ref 0 in
      let fp_cmp_count = ref 0 in
      Hashtbl.iter (fun _ (b : Ir.basic_block) ->
        List.iter (function
          | Ir.Fp_binop _ -> incr fp_binop_count
          | Ir.Fp_cmp _ -> incr fp_cmp_count
          | _ -> ()
        ) b.instrs
      ) f.cfg.blocks;
      check int "4 FP binops lifted" 4 !fp_binop_count;
      check int "1 FP cmp lifted" 1 !fp_cmp_count

let test_riscv_lift_rvv () =
  let asm = {|
    vadd.vv v0, v1, v2
    vsub.vv v3, v4, v5
    vmul.vv v6, v7, v8
    vle8.v v9, 0(a0)
    vse8.v v10, 0(a1)
    vmv.v.v v11, v12
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_rvv" } asm with
  | Error err -> fail ("Failed to lift RISC-V RVV: " ^ err)
  | Ok f ->
      let vec_binop_count = ref 0 in
      let vec_load_count = ref 0 in
      let vec_store_count = ref 0 in
      let vec_mov_count = ref 0 in
      Hashtbl.iter (fun _ (b : Ir.basic_block) ->
        List.iter (function
          | Ir.Vec_binop _ -> incr vec_binop_count
          | Ir.Vec_load _ -> incr vec_load_count
          | Ir.Vec_store _ -> incr vec_store_count
          | Ir.Vec_mov _ -> incr vec_mov_count
          | _ -> ()
        ) b.instrs
      ) f.cfg.blocks;
      check int "3 RVV binops lifted" 3 !vec_binop_count;
      check int "1 RVV load lifted" 1 !vec_load_count;
      check int "1 RVV store lifted" 1 !vec_store_count;
      check int "1 RVV mov lifted" 1 !vec_mov_count

let test_riscv_pseudo_branches () =
  let asm = {|
    li a1, -5
    bltz a1, .Lnegative
    li a0, 0
    j .Lexit
.Lnegative:
    li a0, 1
.Lexit:
    ret
  |} in
  match lift_function ~options:{ function_name = "test_riscv_pseudo_branch" } asm with
  | Error err -> fail ("Failed to lift RISC-V pseudo branch: " ^ err)
  | Ok f ->
      (match Reference_vm.evaluate f with
      | Ok snap -> check int64 "RISC-V bltz branches correctly" 1L snap.final_rax
      | Error msg -> fail ("Reference VM evaluation error: " ^ msg))

let tests = [
  ("RISC-V Lift Arithmetic (add)", `Quick, test_riscv_lift_arithmetic);
  ("RISC-V Lift Sub & Mul", `Quick, test_riscv_lift_sub_mul);
  ("RISC-V Lift Div & Rem", `Quick, test_riscv_lift_div_rem);
  ("RISC-V Lift Branching (abs)", `Quick, test_riscv_lift_branch_abs);
  ("RISC-V Lift Loop (5! factorial)", `Quick, test_riscv_lift_loop_factorial);
  ("RISC-V Lift Byte Memory (sb/lb/lbu)", `Quick, test_riscv_lift_memory);
  ("RISC-V Lift Set Less Than (slt)", `Quick, test_riscv_lift_slt);
  ("RISC-V Lift Atomics (lr/sc/amoswap/amoadd)", `Quick, test_riscv_lift_atomics);
  ("RISC-V Lift Floating-Point (fadd/fsub/fmul/fdiv/feq)", `Quick, test_riscv_lift_fp);
  ("RISC-V Lift RVV Vector Operations (vadd/vsub/vle8/vse8/vmv)", `Quick, test_riscv_lift_rvv);
  ("RISC-V Lift Pseudo Branches (bltz)", `Quick, test_riscv_pseudo_branches);
]
