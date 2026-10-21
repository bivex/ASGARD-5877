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


let test_cff_ocamlgraph_cfg_metrics () =
  (* Construct a CFG with 4 blocks:
     0: entry -> jmp 1
     1: loop_header -> jcc cond, true -> 2, false -> 3
     2: body -> jmp 1 (loop back)
     3: exit -> ret
  *)
  let b0 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[ Ir.Jmp (Ir.BlockId 1) ] in
  let b1 = Ir.make_block ~id:1 ~label:"loop_header" ~instrs:[
    Ir.Cmp { src1 = Ir.Reg Register.rax; src2 = Ir.Imm 10L };
    Ir.Jcc { cond = Flags.L; target_true = Ir.BlockId 2; target_false = Ir.BlockId 3 };
  ] in
  let b2 = Ir.make_block ~id:2 ~label:"body" ~instrs:[
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 1L; set_flags = false };
    Ir.Jmp (Ir.BlockId 1);
  ] in
  let b3 = Ir.make_block ~id:3 ~label:"exit" ~instrs:[ Ir.Ret ] in
  let func = Ir.make_func ~name:"loop_test" ~entry_id:0 ~blocks:[ b0; b1; b2; b3 ] in

  let cfg = Cff.build_cfg func in
  let metrics = Cff.analyze_cfg ~entry_id:0 cfg in

  Alcotest.(check int) "num_vertices = 4" 4 metrics.num_vertices;
  Alcotest.(check int) "num_edges = 4" 4 metrics.num_edges;
  (* cyclomatic complexity = E - V + 2 = 4 - 4 + 2 = 2 *)
  Alcotest.(check int) "cyclomatic_complexity = 2" 2 metrics.cyclomatic_complexity;
  Alcotest.(check bool) "has_cycles = true" true metrics.has_cycles;
  Alcotest.(check int) "scc_count = 3 (entry, loop {1,2}, exit)" 3 metrics.scc_count;
  Alcotest.(check (list int)) "loop_headers contains 1" [1] metrics.loop_headers

let test_cff_ocamlgraph_dot_and_reachability () =
  let b0 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[ Ir.Jmp (Ir.BlockId 1) ] in
  let b1 = Ir.make_block ~id:1 ~label:"exit" ~instrs:[ Ir.Ret ] in
  let b2 = Ir.make_block ~id:2 ~label:"dead_block" ~instrs:[ Ir.Ret ] in
  let func = Ir.make_func ~name:"reach_test" ~entry_id:0 ~blocks:[ b0; b1; b2 ] in

  let cfg = Cff.build_cfg func in
  let reachable = Cff.reachable_blocks ~entry_id:0 cfg in
  Alcotest.(check bool) "entry reachable" true (List.mem 0 reachable);
  Alcotest.(check bool) "exit reachable" true (List.mem 1 reachable);
  Alcotest.(check bool) "dead_block not reachable" false (List.mem 2 reachable);

  let dot = Cff.export_dot ~func cfg in
  Alcotest.(check bool) "dot contains digraph" true (String.length dot > 0 && String.sub dot 0 7 = "digraph");
  Alcotest.(check bool) "dot contains node_0" true (String.contains dot '0')

let test_mba_verified_rewriters () =
  let test_values = [
    (0L, 0L); (1L, 1L); (-1L, -1L); (100L, -50L);
    (Int64.min_int, Int64.max_int);
    (0x5555555555555555L, -0x5555555555555556L);
    (0x1234567890ABCDEFL, 0xFEDCBA0987654321L);
  ] in
  List.iter
    (fun (x, y) ->
      let env v = if v = "a" then x else if v = "b" then y else 0L in
      let a = Mba.Var "a" and b = Mba.Var "b" in
      (* Check rewrite_verified sound equivalence *)
      let e_add = Mba.rewrite_verified ~depth:2 (Mba.Add (a, b)) in
      let e_sub = Mba.rewrite_verified ~depth:2 (Mba.Sub (a, b)) in
      let e_xor = Mba.rewrite_verified ~depth:2 (Mba.Xor (a, b)) in
      let e_and = Mba.rewrite_verified ~depth:2 (Mba.And (a, b)) in
      let e_or  = Mba.rewrite_verified ~depth:2 (Mba.Or (a, b)) in
      let e_not = Mba.rewrite_verified ~depth:2 (Mba.Not a) in
      let e_neg = Mba.rewrite_verified ~depth:2 (Mba.Neg a) in

      Alcotest.(check int64) "verified add" (Int64.add x y) (Mba.eval env e_add);
      Alcotest.(check int64) "verified sub" (Int64.sub x y) (Mba.eval env e_sub);
      Alcotest.(check int64) "verified xor" (Int64.logxor x y) (Mba.eval env e_xor);
      Alcotest.(check int64) "verified and" (Int64.logand x y) (Mba.eval env e_and);
      Alcotest.(check int64) "verified or"  (Int64.logor x y) (Mba.eval env e_or);
      Alcotest.(check int64) "verified not" (Int64.lognot x) (Mba.eval env e_not);
      Alcotest.(check int64) "verified neg" (Int64.neg x) (Mba.eval env e_neg);

      (* Check rewrite_demorgan sound equivalence *)
      let d_and = Mba.rewrite_demorgan ~depth:2 (Mba.And (a, b)) in
      let d_or  = Mba.rewrite_demorgan ~depth:2 (Mba.Or (a, b)) in
      let d_xor = Mba.rewrite_demorgan ~depth:2 (Mba.Xor (a, b)) in

      Alcotest.(check int64) "demorgan and" (Int64.logand x y) (Mba.eval env d_and);
      Alcotest.(check int64) "demorgan or"  (Int64.logor x y) (Mba.eval env d_or);
      Alcotest.(check int64) "demorgan xor" (Int64.logxor x y) (Mba.eval env d_xor))
    test_values

let test_mba_zero_invariants () =
  let test_values = [
    (0L, 0L); (1L, 2L); (-1L, 1L); (42L, 99L);
    (Int64.min_int, Int64.max_int);
    (0x5555555555555555L, -0x5555555555555556L);
    (0xCAFEBABE12345678L, 0x0123456789ABCDEFL);
  ] in
  List.iter
    (fun (x, y) ->
      let env v = if v = "a" then x else if v = "b" then y else 0L in
      let a = Mba.Var "a" and b = Mba.Var "b" in

      Alcotest.(check int64) "zero_inv1 = 0" 0L (Mba.eval env (Mba.zero_inv1 a b));
      Alcotest.(check int64) "zero_inv2 = 0" 0L (Mba.eval env (Mba.zero_inv2 a b));
      Alcotest.(check int64) "zero_inv3 = 0" 0L (Mba.eval env (Mba.zero_inv3 a b));
      Alcotest.(check int64) "zero_inv4 = 0" 0L (Mba.eval env (Mba.zero_inv4 a b));
      Alcotest.(check int64) "zero_inv_demorgan_and = 0" 0L (Mba.eval env (Mba.zero_inv_demorgan_and a b));
      Alcotest.(check int64) "zero_inv_demorgan_or = 0" 0L (Mba.eval env (Mba.zero_inv_demorgan_or a b));
      Alcotest.(check int64) "zero_inv_sub_not = 0" 0L (Mba.eval env (Mba.zero_inv_sub_not a b));
      Alcotest.(check int64) "zero_inv5_poly = 0" 0L (Mba.eval env (Mba.zero_inv5_poly a));
      Alcotest.(check int64) "zero_inv5_nl = 0" 0L (Mba.eval env (Mba.zero_inv5_nl a b)))
    test_values

let test_cff_flatten_with_opaque_predicates () =
  let rng = Random.State.make [| 9999 |] in
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
  let orig_func = Ir.make_func ~name:"fib_opaque" ~entry_id:0 ~blocks:[ b0; b1; b2; b3 ] in

  let options = { Cff.default_cff_options with inject_opaque_predicates = true; obfuscate_states = true; input_tainted_transitions = true } in

  match Cff.flatten_func ~options ~rng orig_func with
  | Error e -> Alcotest.fail e
  | Ok flattened_func ->
      let state = make_state () in
      match run_func state flattened_func with
      | Error e -> Alcotest.fail e
      | Ok () ->
          Alcotest.(check bool) "halted without trap" true state.halted;
          Alcotest.(check int64) "flattened fib(10) with opaque predicates is 55" 55L (get_reg state Register.rax)

let test_cff_opaque_parity_extremes () =
  let extremes = [
    0L; 1L; -1L; 2L; -2L; 42L; 0x5555555555555555L; -0x5555555555555556L;
    0x7FFFFFFFFFFFFFFFL; Int64.min_int; 0xCAFEBABE12345678L;
  ] in
  List.iter
    (fun x ->
      let res = Int64.logand (Int64.logand x (Int64.add x 1L)) 1L in
      Alcotest.(check int64) "parity predicate is always 0" 0L res)
    extremes

let prop_cff_opaque_parity_1000 =
  QCheck.Test.make
    ~name:"cff_opaque_parity_predicate_1000_seeds"
    ~count:1000
    QCheck.int64
    (fun x ->
      let res = Int64.logand (Int64.logand x (Int64.add x 1L)) 1L in
      res = 0L)

let test_non_linear_bijection () =
  let rng = Random.State.make [| 0x1337 |] in
  let params = Non_linear_bijection.random_params ~shift:33 rng in
  let test_vals = [
    0L; 1L; 42L; -1L; 0x7FFFFFFFFFFFFFFFL; 0x1234567890ABCDEFL; 0xCAFEBABE12345678L
  ] in
  List.iter (fun x ->
    let y = Non_linear_bijection.forward params x in
    let rec_x = Non_linear_bijection.inverse params y in
    Alcotest.(check int64) "non-linear bijection forward/inverse roundtrip" x rec_x;
    let dst = Register.rax in
    let ir = Non_linear_bijection.synth_xorshift_involution ~rng ~dst in
    let state = Vm_eval.make_state () in
    Vm_eval.set_reg state dst x;
    (match Vm_eval.run_block state { id = 0; label = "entry"; instrs = ir } with
     | Ok None -> ()
     | _ -> Alcotest.fail "IR execution failed");
    Alcotest.(check int64) "non-linear bijection IR preserves dst" x (Vm_eval.get_reg state dst)
  ) test_vals

let test_branch_invariant_poly_key_update () =
  let poly_const = 0x517CC1B727220A95L in
  let test_vals = [
    0L; 1L; -1L; 42L; 0x1234567890ABCDEFL; 0xCAFEBABE13375877L;
    0x7FFFFFFFFFFFFFFFL; Int64.min_int
  ] in
  (* 1. Verify poly_hash64 / poly_unhash64 bijectivity *)
  List.iter (fun x ->
    let h = Rolling_key.poly_hash64 x in
    let rec_x = Rolling_key.poly_unhash64 h in
    Alcotest.(check int64) "poly_hash64 roundtrip" x rec_x
  ) test_vals;

  (* 2. Verify CFG merge point convergence: two distinct paths converge to k_target *)
  let k_old_path1 = 0xAAAABBBBCCCCDDDDL in
  let k_old_path2 = 0x123456789ABCDEF0L in
  let k_target = 0x5877CAFEBABE1337L in
  let delta1 = Rolling_key.solve_path_delta ~k_old:k_old_path1 ~k_target ~poly_const in
  let delta2 = Rolling_key.solve_path_delta ~k_old:k_old_path2 ~k_target ~poly_const in
  let res1 = Rolling_key.branch_invariant_poly_update ~key:k_old_path1 ~path_delta:delta1 ~poly_const in
  let res2 = Rolling_key.branch_invariant_poly_update ~key:k_old_path2 ~path_delta:delta2 ~poly_const in
  Alcotest.(check int64) "path 1 converges to k_target" k_target res1;
  Alcotest.(check int64) "path 2 converges to k_target" k_target res2;
  Alcotest.(check bool) "deltas differ" true (delta1 <> delta2)

let test_cff_tainted_transitions_dynamic_input () =
  let rng = Random.State.make [| 9999 |] in
  let asm = {|
func_taint_test:
    mov rax, rdi
    cmp rdi, 10
    jle .Lle
    add rax, 100
    jmp .Lexit
.Lle:
    sub rax, 5
.Lexit:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok lifted_func ->
      let options = { Cff.default_cff_options with inject_opaque_predicates = false; obfuscate_states = true; input_tainted_transitions = true } in
      match Cff.flatten_func ~options ~rng lifted_func with
      | Error e -> Alcotest.fail e
      | Ok flattened_func ->
          (* Test standard 32-bit input with upper bits zero: 15L (> 10) *)
          let state1 = make_state () in
          set_reg state1 Register.rdi 15L;
          (match run_func state1 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              (* 15L + 100 = 115L *)
              Alcotest.(check int64) "flattened tainted branch 15 > 10" 115L (get_reg state1 Register.rax));

          (* Test standard 32-bit input with upper bits zero: 3L (<= 10) *)
          let state2 = make_state () in
          set_reg state2 Register.rdi 3L;
          (match run_func state2 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              (* 3 - 5 = -2 *)
              Alcotest.(check int64) "flattened tainted branch 3 <= 10" (-2L) (get_reg state2 Register.rax));

          (* Test 64-bit input with upper bits non-zero: 0x100000005L (> 10) *)
          let state3 = make_state () in
          set_reg state3 Register.rdi 0x100000005L;
          (match run_func state3 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              Alcotest.(check int64) "flattened tainted branch 64-bit > 10" 0x100000069L (get_reg state3 Register.rax))

let test_cff_tainted_transitions_pinned_clobber () =
  let rng = Random.State.make [| 12345 |] in
  let asm = {|
func_clobber_test:
    mov rax, rdi
    xor rdi, rdi
    cmp rax, 10
    jle .Lle
    add rax, 100
    jmp .Lexit
.Lle:
    sub rax, 5
.Lexit:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok lifted_func ->
      let options = { Cff.default_cff_options with inject_opaque_predicates = false; obfuscate_states = true; input_tainted_transitions = true } in
      match Cff.flatten_func ~options ~rng lifted_func with
      | Error e -> Alcotest.fail e
      | Ok flattened_func ->
          let state1 = make_state () in
          set_reg state1 Register.rdi 20L;
          (match run_func state1 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              Alcotest.(check int64) "flattened with clobbered rdi > 10" 120L (get_reg state1 Register.rax));
          let state2 = make_state () in
          set_reg state2 Register.rdi 4L;
          (match run_func state2 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () ->
              Alcotest.(check int64) "flattened with clobbered rdi <= 10" (-1L) (get_reg state2 Register.rax))

let test_cff_tainted_stack_vm () =
  let rng = Random.State.make [| 9999 |] in
  let asm = {|
func_taint_test:
    mov rax, rdi
    cmp rdi, 10
    jle .Lle
    add rax, 100
    jmp .Lexit
.Lle:
    sub rax, 5
.Lexit:
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok lifted_func ->
      let options = { Cff.default_cff_options with inject_opaque_predicates = false; obfuscate_states = true; input_tainted_transitions = true } in
      match Cff.flatten_func ~options ~rng lifted_func with
      | Error e -> Alcotest.fail e
      | Ok flattened_func ->
          let ext_syms = Hashtbl.create 16 in
          let ctx, prog = Stack_vm.Ir_to_stack.lower_func ~ext_syms flattened_func in
          let rdi_slot = Stack_vm.Context_allocator.slot_of_reg ctx Register.rdi in
          let rax_slot = Stack_vm.Context_allocator.slot_of_reg ctx Register.rax in
          let state1 = Stack_vm.Stack_eval.run_program ~initial_ctx:[ (rdi_slot, 15L) ] prog in
          let res1 = Stack_vm.Stack_eval.get_reg state1 rax_slot in
          Alcotest.(check int64) "stack_eval tainted branch 15 > 10" 115L res1;
          let state2 = Stack_vm.Stack_eval.run_program ~initial_ctx:[ (rdi_slot, 3L) ] prog in
          let res2 = Stack_vm.Stack_eval.get_reg state2 rax_slot in
          Alcotest.(check int64) "stack_eval tainted branch 3 <= 10" (-2L) res2

let test_cff_multi_hub_partitioning () =
  let rng = Random.State.make [| 5555 |] in
  let asm = {|
func_multi_hub:
    mov rax, rdi
    cmp rdi, 10
    jl .L1
    cmp rdi, 20
    jl .L2
    add rax, 300
    ret
.L1:
    add rax, 100
    ret
.L2:
    add rax, 200
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok lifted_func ->
      let options = { Cff.default_cff_options with hub_count = 3; split_rate = 50 } in
      match Cff.flatten_func ~options ~rng lifted_func with
      | Error e -> Alcotest.fail e
      | Ok flattened_func ->
          let hub_count =
            Hashtbl.fold (fun _ (b : Ir.basic_block) acc ->
              if (let slen = String.length b.label and sublen = 9 in
                  let rec check i =
                    if i + sublen > slen then false
                    else if String.sub b.label i sublen = "disp_hub_" then true
                    else check (i + 1)
                  in check 0) then acc + 1 else acc
            ) flattened_func.cfg.blocks 0
          in
          Alcotest.(check bool) "multiple dispatcher hubs generated" (hub_count >= 2) true;
          let state = make_state () in
          set_reg state Register.rdi 5L;
          (match run_func state flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () -> Alcotest.(check int64) "branch < 10 through multi-hub" 105L (get_reg state Register.rax));
          let state2 = make_state () in
          set_reg state2 Register.rdi 15L;
          (match run_func state2 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () -> Alcotest.(check int64) "branch < 20 through multi-hub" 215L (get_reg state2 Register.rax));
          let state3 = make_state () in
          set_reg state3 Register.rdi 25L;
          (match run_func state3 flattened_func with
          | Error e -> Alcotest.fail e
          | Ok () -> Alcotest.(check int64) "branch >= 20 through multi-hub" 325L (get_reg state3 Register.rax))

let test_cff_topological_fallthrough () =
  let rng = Random.State.make [| 6666 |] in
  let b1 = Ir.make_block ~id:10 ~label:"blk10" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
  ] in
  let b2 = Ir.make_block ~id:99 ~label:"blk99" ~instrs:[
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 8L; set_flags = false };
    Ir.Ret;
  ] in
  let func = Ir.make_func ~name:"test_fallthrough" ~entry_id:10 ~blocks:[ b1; b2 ] in
  match Cff.flatten_func ~rng func with
  | Error e -> Alcotest.fail e
  | Ok flattened_func ->
      let state = make_state () in
      match run_func state flattened_func with
      | Error e -> Alcotest.fail e
      | Ok () -> Alcotest.(check int64) "non-consecutive fallthrough 42+8=50" 50L (get_reg state Register.rax)

let test_select_pinned_reg_exhaustion () =
  let instrs = [
    Ir.Mov { dst = Ir.Reg Register.rdi; src = Ir.Imm 10L };
    Ir.Mov { dst = Ir.Reg Register.vx19; src = Ir.Imm 1L };
    Ir.Mov { dst = Ir.Reg Register.vx20; src = Ir.Imm 2L };
    Ir.Mov { dst = Ir.Reg Register.vx21; src = Ir.Imm 3L };
    Ir.Mov { dst = Ir.Reg Register.vx22; src = Ir.Imm 4L };
    Ir.Mov { dst = Ir.Reg Register.vx23; src = Ir.Imm 5L };
    Ir.Mov { dst = Ir.Reg Register.vx24; src = Ir.Imm 6L };
    Ir.Mov { dst = Ir.Reg Register.r12; src = Ir.Imm 7L };
    Ir.Mov { dst = Ir.Reg Register.r13; src = Ir.Imm 8L };
    Ir.Mov { dst = Ir.Reg Register.r14; src = Ir.Imm 9L };
    Ir.Mov { dst = Ir.Reg Register.r15; src = Ir.Imm 10L };
    Ir.Mov { dst = Ir.Reg Register.rbx; src = Ir.Imm 11L };
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 999L };
    Ir.Ret;
  ] in
  let b = Ir.make_block ~id:1 ~label:"entry" ~instrs in
  let func = Ir.make_func ~name:"test_exhaustion" ~entry_id:1 ~blocks:[ b ] in
  let pinned = Cff.select_pinned_reg func in
  Alcotest.(check bool) "pinned reg exhausted" true (pinned = None)
let test_tmr_majority_truth_table () =
  (* Truth table for all 8 bit patterns *)
  Alcotest.(check int64) "000 -> 0" 0L (Mba_engine.Tmr_guard.evaluate_tmr_majority 0L 0L 0L);
  Alcotest.(check int64) "001 -> 0" 0L (Mba_engine.Tmr_guard.evaluate_tmr_majority 0L 0L 1L);
  Alcotest.(check int64) "010 -> 0" 0L (Mba_engine.Tmr_guard.evaluate_tmr_majority 0L 1L 0L);
  Alcotest.(check int64) "011 -> 1" 1L (Mba_engine.Tmr_guard.evaluate_tmr_majority 0L 1L 1L);
  Alcotest.(check int64) "100 -> 0" 0L (Mba_engine.Tmr_guard.evaluate_tmr_majority 1L 0L 0L);
  Alcotest.(check int64) "101 -> 1" 1L (Mba_engine.Tmr_guard.evaluate_tmr_majority 1L 0L 1L);
  Alcotest.(check int64) "110 -> 1" 1L (Mba_engine.Tmr_guard.evaluate_tmr_majority 1L 1L 0L);
  Alcotest.(check int64) "111 -> 1" 1L (Mba_engine.Tmr_guard.evaluate_tmr_majority 1L 1L 1L);
  (* Full 64-bit word majority *)
  let w1 = 0xAAAA_5555_AAAA_5555L in
  let w2 = 0xCCCC_3333_CCCC_3333L in
  let w3 = 0xF0F0_0F0F_F0F0_0F0FL in
  let maj = Mba_engine.Tmr_guard.evaluate_tmr_majority w1 w2 w3 in
  for bit = 0 to 63 do
    let b1 = Int64.logand (Int64.shift_right_logical w1 bit) 1L in
    let b2 = Int64.logand (Int64.shift_right_logical w2 bit) 1L in
    let b3 = Int64.logand (Int64.shift_right_logical w3 bit) 1L in
    let b_maj = Int64.logand (Int64.shift_right_logical maj bit) 1L in
    let sum = Int64.add (Int64.add b1 b2) b3 in
    let expected = if sum >= 2L then 1L else 0L in
    Alcotest.(check int64) (Printf.sprintf "bit %d majority" bit) expected b_maj
  done

let test_tmr_triplet_synthesis () =
  let rng = Random.State.make [| 9999 |] in
  let expr = Mba.Add (Mba.Var "x", Mba.Const 42L) in
  let (e1, e2, e3) = Mba_engine.Tmr_synth.synth_triplet_from_expr ~rng expr in
  (* Test mathematical equivalence across 20 randomized inputs *)
  for sample = 1 to 20 do
    let x_val = Int64.of_int (sample * 1337 + 7) in
    let env = (fun s -> if s = "x" then x_val else 0L) in
    let res_orig = Mba.eval env expr in
    let res1 = Mba.eval env e1 in
    let res2 = Mba.eval env e2 in
    let res3 = Mba.eval env e3 in
    Alcotest.(check int64) "lane 1 arith equivalence" res_orig res1;
    Alcotest.(check int64) "lane 2 bool equivalence" res_orig res2;
    Alcotest.(check int64) "lane 3 canonical equivalence" res_orig res3;
  done

let test_tmr_silent_anti_patching () =
  let rng = Random.State.make [| 8888 |] in
  let expr = Mba.Add (Mba.Var "a", Mba.Const 42L) in
  let (e1, e2, e3) = Mba_engine.Tmr_synth.synth_triplet_from_expr ~rng expr in
  let env = [ ("a", Ir.Reg Register.rdi) ] in

  (* 1. Normal unpatched execution *)
  let instrs =
    Mba_engine.Tmr_guard.emit_tmr_evaluation
      ~e1 ~e2 ~e3 ~env
      ~dst:Register.rax
      ~r1:Register.vx19
      ~r2:Register.vx20
      ~r3:Register.vx21
      ~scratch1:Register.vtmp0
      ~scratch2:Register.vtmp1
    @ [ Ir.Ret ]
  in
  let b = Ir.make_block ~id:1 ~label:"tmr_entry" ~instrs in
  let func = Ir.make_func ~name:"tmr_test" ~entry_id:1 ~blocks:[ b ] in
  let state = make_state () in
  set_reg state Register.rdi 100L;
  (match run_func state func with
  | Error e -> Alcotest.fail e
  | Ok () -> Alcotest.(check int64) "unpatched 100+42=142" 142L (get_reg state Register.rax));

  (* 2. Tampered / patched Lane 1: an attacker patched r1 to garbage 0xDEADBEEFL *)
  let instrs_tampered1 =
    (Mba.lower_to_ir ~dst:Register.vx19 ~env e1)
    @ [ Ir.Mov { dst = Ir.Reg Register.vx19; src = Ir.Imm 0xDEADBEEFL } ] (* attacker patch! *)
    @ (Mba.lower_to_ir ~dst:Register.vx20 ~env e2)
    @ (Mba.lower_to_ir ~dst:Register.vx21 ~env e3)
    @ (Mba_engine.Tmr_guard.emit_tmr_majority
         ~r1:Register.vx19 ~r2:Register.vx20 ~r3:Register.vx21
         ~dst:Register.rax ~scratch1:Register.vtmp0 ~scratch2:Register.vtmp1)
    @ [ Ir.Ret ]
  in
  let b_t1 = Ir.make_block ~id:1 ~label:"tmr_t1" ~instrs:instrs_tampered1 in
  let func_t1 = Ir.make_func ~name:"tmr_tampered1" ~entry_id:1 ~blocks:[ b_t1 ] in
  let state_t1 = make_state () in
  set_reg state_t1 Register.rdi 100L;
  (match run_func state_t1 func_t1 with
  | Error e -> Alcotest.fail e
  | Ok () ->
      (* Silent recovery: majority vote ignores tampered lane 1, producing correct 142 *)
      Alcotest.(check int64) "silent recovery under lane 1 patch" 142L (get_reg state_t1 Register.rax));

  (* 3. Tampered Lane 2: an attacker patched r2 to 0L *)
  let instrs_tampered2 =
    (Mba.lower_to_ir ~dst:Register.vx19 ~env e1)
    @ (Mba.lower_to_ir ~dst:Register.vx20 ~env e2)
    @ [ Ir.Mov { dst = Ir.Reg Register.vx20; src = Ir.Imm 0L } ] (* attacker patch! *)
    @ (Mba.lower_to_ir ~dst:Register.vx21 ~env e3)
    @ (Mba_engine.Tmr_guard.emit_tmr_majority
         ~r1:Register.vx19 ~r2:Register.vx20 ~r3:Register.vx21
         ~dst:Register.rax ~scratch1:Register.vtmp0 ~scratch2:Register.vtmp1)
    @ [ Ir.Ret ]
  in
  let b_t2 = Ir.make_block ~id:1 ~label:"tmr_t2" ~instrs:instrs_tampered2 in
  let func_t2 = Ir.make_func ~name:"tmr_tampered2" ~entry_id:1 ~blocks:[ b_t2 ] in
  let state_t2 = make_state () in
  set_reg state_t2 Register.rdi 100L;
  (match run_func state_t2 func_t2 with
  | Error e -> Alcotest.fail e
  | Ok () ->
      Alcotest.(check int64) "silent recovery under lane 2 patch" 142L (get_reg state_t2 Register.rax))


let tests = [
  Alcotest.test_case "cff_tainted_stack_vm" `Quick test_cff_tainted_stack_vm;
  Alcotest.test_case "mba_eval_and_soundness" `Quick test_mba_eval_and_soundness;
  Alcotest.test_case "mba_lowering_to_vm_ir" `Quick test_mba_lowering_to_vm_ir;
  Alcotest.test_case "mba_verified_rewriters" `Quick test_mba_verified_rewriters;
  Alcotest.test_case "mba_zero_invariants" `Quick test_mba_zero_invariants;
  Alcotest.test_case "non_linear_bijection_roundtrip" `Quick test_non_linear_bijection;
  Alcotest.test_case "branch_invariant_poly_key_update" `Quick test_branch_invariant_poly_key_update;
  Alcotest.test_case "cff_flatten_fibonacci" `Quick test_cff_flatten_fibonacci;
  Alcotest.test_case "cff_flatten_with_opaque_predicates" `Quick test_cff_flatten_with_opaque_predicates;
  Alcotest.test_case "cff_flatten_lifted_factorial" `Quick test_cff_flatten_lifted_factorial;
  Alcotest.test_case "cff_flatten_lifted_abs" `Quick test_cff_flatten_lifted_abs;
  Alcotest.test_case "cff_tainted_transitions_dynamic_input" `Quick test_cff_tainted_transitions_dynamic_input;
  Alcotest.test_case "cff_tainted_transitions_pinned_clobber" `Quick test_cff_tainted_transitions_pinned_clobber;
  Alcotest.test_case "cff_ocamlgraph_cfg_metrics" `Quick test_cff_ocamlgraph_cfg_metrics;
  Alcotest.test_case "cff_ocamlgraph_dot_and_reachability" `Quick test_cff_ocamlgraph_dot_and_reachability;
  Alcotest.test_case "cff_opaque_parity_extremes" `Quick test_cff_opaque_parity_extremes;
  QCheck_alcotest.to_alcotest prop_mba_equivalence_1000;
  QCheck_alcotest.to_alcotest prop_cff_opaque_parity_1000;
  Alcotest.test_case "cff_multi_hub_partitioning" `Quick test_cff_multi_hub_partitioning;
  Alcotest.test_case "cff_topological_fallthrough" `Quick test_cff_topological_fallthrough;
  Alcotest.test_case "select_pinned_reg_exhaustion" `Quick test_select_pinned_reg_exhaustion;
  Alcotest.test_case "tmr_majority_truth_table" `Quick test_tmr_majority_truth_table;
  Alcotest.test_case "tmr_triplet_synthesis" `Quick test_tmr_triplet_synthesis;
  Alcotest.test_case "tmr_silent_anti_patching" `Quick test_tmr_silent_anti_patching;
]
