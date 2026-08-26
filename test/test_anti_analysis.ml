open Vm_ir
open X86_lifter
open Mba_engine
open Vm_eval

let test_mba_eval_and_soundness () =
  let rng = Random.State.make [| 42 |] in
  let env_fn x y var_name =
    if var_name = "a" then x
    else if var_name = "b" then y
    else 0L
  in

  let test_pairs = [
    (10L, 4L);
    (0L, 0L);
    (100L, -50L);
    (-1L, 1L);
    (0x7FFFFFFFFFFFFFFFL, 1L);
    (0x1234567890ABCDEFL, 0xFEDCBA0987654321L);
  ] in

  List.iter
    (fun (x, y) ->
      let env = env_fn x y in

      (* 1. Add *)
      let expr_add = Mba.Add (Mba.Var "a", Mba.Var "b") in
      let rewritten_add = Mba.rewrite ~rng ~depth:2 expr_add in
      let expected_add = Int64.add x y in
      let actual_add = Mba.eval env rewritten_add in
      Alcotest.(check int64) "mba add matches" expected_add actual_add;

      (* 2. Sub *)
      let expr_sub = Mba.Sub (Mba.Var "a", Mba.Var "b") in
      let rewritten_sub = Mba.rewrite ~rng ~depth:2 expr_sub in
      let expected_sub = Int64.sub x y in
      let actual_sub = Mba.eval env rewritten_sub in
      Alcotest.(check int64) "mba sub matches" expected_sub actual_sub;

      (* 3. Xor *)
      let expr_xor = Mba.Xor (Mba.Var "a", Mba.Var "b") in
      let rewritten_xor = Mba.rewrite ~rng ~depth:2 expr_xor in
      let expected_xor = Int64.logxor x y in
      let actual_xor = Mba.eval env rewritten_xor in
      Alcotest.(check int64) "mba xor matches" expected_xor actual_xor;

      (* 4. And *)
      let expr_and = Mba.And (Mba.Var "a", Mba.Var "b") in
      let rewritten_and = Mba.rewrite ~rng ~depth:2 expr_and in
      let expected_and = Int64.logand x y in
      let actual_and = Mba.eval env rewritten_and in
      Alcotest.(check int64) "mba and matches" expected_and actual_and;

      (* 5. Or *)
      let expr_or = Mba.Or (Mba.Var "a", Mba.Var "b") in
      let rewritten_or = Mba.rewrite ~rng ~depth:2 expr_or in
      let expected_or = Int64.logor x y in
      let actual_or = Mba.eval env rewritten_or in
      Alcotest.(check int64) "mba or matches" expected_or actual_or;

      (* 6. Mul (NLMBA) *)
      let expr_mul = Mba.Mul (Mba.Var "a", Mba.Var "b") in
      let rewritten_mul = Mba.rewrite ~rng ~depth:2 expr_mul in
      let expected_mul = Int64.mul x y in
      let actual_mul = Mba.eval env rewritten_mul in
      Alcotest.(check int64) "mba mul matches" expected_mul actual_mul)
    test_pairs


let test_mba_lowering_to_vm_ir () =
  let rng = Random.State.make [| 777 |] in
  (* Obfuscate Add to depth 2 *)
  let instrs = Mba.obfuscate_alu ~rng ~depth:2 ~dst:Register.rax ~src1:(Ir.Reg Register.rdi) ~src2:(Ir.Reg Register.rsi) Ir.Add in

  (* Verify lowering produced non-trivial sequence *)
  Alcotest.(check bool) "lowered into multiple instructions" true (List.length instrs > 5);

  (* Execute lowered instructions in Vm_eval *)
  let block = Ir.make_block ~id:0 ~label:"mba_test" ~instrs:(instrs @ [ Ir.Vm_exit ]) in
  let func = Ir.make_func ~name:"mba_func" ~entry_id:0 ~blocks:[ block ] in

  let state = make_state () in
  set_reg state Register.rdi 25L;
  set_reg state Register.rsi 17L;
  match run_func state func with
  | Error e -> Alcotest.fail e
  | Ok () ->
      (* 25 + 17 = 42 *)
      Alcotest.(check int64) "mba lowered add result" 42L (get_reg state Register.rax)

let test_cff_flatten_fibonacci () =
  let rng = Random.State.make [| 999 |] in
  (* Original Fibonacci func from Stage 1 *)
  let b0 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 0L };
    Ir.Mov { dst = Ir.Reg Register.rbx; src = Ir.Imm 1L };
    Ir.Mov { dst = Ir.Reg Register.rcx; src = Ir.Imm 10L };
    Ir.Jmp (Ir.BlockId 1);
  ] in
  let b1 = Ir.make_block ~id:1 ~label:"loop_header" ~instrs:[
    Ir.Cmp { src1 = Ir.Reg Register.rcx; src2 = Ir.Imm 0L };
    Ir.Jcc { cond = Flags.LE; target_true = Ir.BlockId 3; target_false = Ir.BlockId 2 };
  ] in
  let b2 = Ir.make_block ~id:2 ~label:"loop_body" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Reg Register.rax };
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Reg Register.rbx; set_flags = false };
    Ir.Mov { dst = Ir.Reg Register.rbx; src = Ir.Reg Register.rdx };
    Ir.Unary { op = Ir.Dec; dst = Register.rcx; src = Ir.Reg Register.rcx; set_flags = true };
    Ir.Jmp (Ir.BlockId 1);
  ] in
  let b3 = Ir.make_block ~id:3 ~label:"done" ~instrs:[
    Ir.Vm_exit;
  ] in
  let orig_func = Ir.make_func ~name:"fib" ~entry_id:0 ~blocks:[ b0; b1; b2; b3 ] in

  (* Flatten control flow *)
  match Cff.flatten_func ~rng orig_func with
  | Error e -> Alcotest.fail e
  | Ok flattened_func ->
      (* Check that block count grew with dispatcher & entry *)
      let num_blocks = Hashtbl.length flattened_func.cfg.blocks in
      Alcotest.(check bool) "flattened has more blocks" true (num_blocks >= 6);

      (* Execute flattened CFG in Vm_eval *)
      let state = make_state () in
      match run_func state flattened_func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check bool) "halted" true state.halted;
          (* fib(10) is 55 *)
          Alcotest.(check int64) "flattened fib(10) is 55" 55L (get_reg state Register.rax)

let test_cff_flatten_lifted_factorial () =
  let rng = Random.State.make [| 12345 |] in
  let asm = {|
factorial:
    mov rax, 1
.Lloop:
    cmp rdi, 1
    jle .Lexit
    imul rax, rdi
    dec rdi
    jmp .Lloop
.Lexit:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok lifted_func -> (
      match Cff.flatten_func ~rng lifted_func with
      | Error e -> Alcotest.fail e
      | Ok flattened_func ->
          let state = make_state () in
          set_reg state Register.rdi 5L; (* 5! = 120 *)
          match run_func state flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              Alcotest.(check int64) "flattened 5! = 120" 120L (get_reg state Register.rax))

let test_cff_flatten_lifted_abs () =
  let rng = Random.State.make [| 54321 |] in
  let asm = {|
func_abs:
    mov rax, rdi
    cmp rax, 0
    jge .Ldone
    neg rax
.Ldone:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok lifted_func -> (
      match Cff.flatten_func ~rng lifted_func with
      | Error e -> Alcotest.fail e
      | Ok flattened_func ->
          (* Test negative input *)
          let state_neg = make_state () in
          set_reg state_neg Register.rdi (-77L);
          (match run_func state_neg flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              Alcotest.(check int64) "flattened abs(-77) = 77" 77L (get_reg state_neg Register.rax));

          (* Test positive input *)
          let state_pos = make_state () in
          set_reg state_pos Register.rdi 42L;
          (match run_func state_pos flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              Alcotest.(check int64) "flattened abs(42) = 42" 42L (get_reg state_pos Register.rax)))

(** Property test: 1,000 random pairs verifying MBA rewriting preserves exact 64-bit integer arithmetic *)
let prop_mba_equivalence_1000 =
  QCheck.Test.make
    ~name:"mba_equivalence_depth2_1000_seeds"
    ~count:1000
    (QCheck.pair QCheck.int64 QCheck.int64)
    (fun (x, y) ->
      let rng = Random.State.make [| Int64.to_int (Int64.logxor x y) |] in
      let env v = if v = "a" then x else y in

      let add_tree = Mba.rewrite ~rng ~depth:2 (Mba.Add (Mba.Var "a", Mba.Var "b")) in
      let sub_tree = Mba.rewrite ~rng ~depth:2 (Mba.Sub (Mba.Var "a", Mba.Var "b")) in
      let xor_tree = Mba.rewrite ~rng ~depth:2 (Mba.Xor (Mba.Var "a", Mba.Var "b")) in
      let mul_tree = Mba.rewrite ~rng ~depth:2 (Mba.Mul (Mba.Var "a", Mba.Var "b")) in

      let ok_add = Mba.eval env add_tree = Int64.add x y in
      let ok_sub = Mba.eval env sub_tree = Int64.sub x y in
      let ok_xor = Mba.eval env xor_tree = Int64.logxor x y in
      let ok_mul = Mba.eval env mul_tree = Int64.mul x y in

      ok_add && ok_sub && ok_xor && ok_mul)


let tests = [
  Alcotest.test_case "mba_eval_and_soundness" `Quick test_mba_eval_and_soundness;
  Alcotest.test_case "mba_lowering_to_vm_ir" `Quick test_mba_lowering_to_vm_ir;
  Alcotest.test_case "cff_flatten_fibonacci" `Quick test_cff_flatten_fibonacci;
  Alcotest.test_case "cff_flatten_lifted_factorial" `Quick test_cff_flatten_lifted_factorial;
  Alcotest.test_case "cff_flatten_lifted_abs" `Quick test_cff_flatten_lifted_abs;
  QCheck_alcotest.to_alcotest prop_mba_equivalence_1000;
]
