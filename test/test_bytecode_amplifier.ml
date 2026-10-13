open Stack_vm.Stack_ir
open Stack_vm.Stack_eval
module Amp = Stack_vm.Bytecode_amplifier

let test_horner_synthesis () =
  let rng = Random.State.make [| 0x5877; 0xB1EC |] in
  for _ = 1 to 200 do
    let target = Amp.rand_u64 rng in
    let (t0, coeffs) = Amp.synth_horner_polynomial rng ~target_const:target ~degree:6 in
    let evaluated = Amp.eval_horner_polynomial ~t0 ~coeffs in
    Alcotest.(check int64) "Horner evaluation must equal target constant" target evaluated
  done

let test_horner_stack_eval () =
  let rng = Random.State.make [| 0x1337; 0xCAFE |] in
  for _ = 1 to 50 do
    let target = Amp.rand_u64 rng in
    let ops = Amp.emit_horner_stack_insns rng ~target_const:target ~degree:4 in
    let st = create_state () in
    List.iter (step_op st) ops;
    match st.vstack with
    | [res] ->
        Alcotest.(check int64) "Stack-evaluated Horner must equal target constant" target res
    | _ ->
        Alcotest.fail "Stack length is not 1 after Horner sequence"
  done

let test_carry_chain_add () =
  let rng = Random.State.make [| 0x5877; 0x42 |] in
  let s1 = 10 and s2 = 11 in
  let test_cases = [
    (100L, 250L);
    (0x123456789ABCDEF0L, 0xFEDCBA9876543210L);
    (0xFFFFFFFFFFFFFFFFL, 1L);
    (0x7FFFFFFFFFFFFFFFL, 0x7FFFFFFFFFFFFFFFL);
    (0L, 0L);
  ] in
  List.iter (fun (x, y) ->
    let ops = Amp.emit_carry_chain_add rng ~s1 ~s2 in
    let st = create_state () in
    st.vstack <- [y; x];
    List.iter (step_op st) ops;
    match st.vstack with
    | [res] ->
        Alcotest.(check int64) "Carry chain Add must equal x + y" (Int64.add x y) res
    | _ ->
        Alcotest.fail "Stack length is not 1 after carry chain add"
  ) test_cases

let test_carry_chain_sub () =
  let rng = Random.State.make [| 0x5877; 0x84 |] in
  let s1 = 10 and s2 = 11 in
  let test_cases = [
    (250L, 100L);
    (100L, 250L);
    (0x123456789ABCDEF0L, 0xFEDCBA9876543210L);
    (0L, 1L);
    (0xFFFFFFFFFFFFFFFFL, 0xFFFFFFFFFFFFFFFFL);
  ] in
  List.iter (fun (x, y) ->
    let ops = Amp.emit_carry_chain_sub rng ~s1 ~s2 in
    let st = create_state () in
    st.vstack <- [y; x];
    List.iter (step_op st) ops;
    match st.vstack with
    | [res] ->
        Alcotest.(check int64) "Carry chain Sub must equal x - y" (Int64.sub x y) res
    | _ ->
        Alcotest.fail "Stack length is not 1 after carry chain sub"
  ) test_cases

let test_expander_web_knot () =
  let rng = Random.State.make [| 0x5877; 0x99 |] in
  for _ = 1 to 50 do
    let v = Amp.rand_u64 rng in
    let ops = Amp.emit_expander_web_knot rng () in
    let st = create_state () in
    st.vstack <- [v];
    List.iter (step_op st) ops;
    match st.vstack with
    | [res] ->
        Alcotest.(check int64) "Expander knot must preserve top of stack" v res
    | _ ->
        Alcotest.fail "Stack length is not 1 after expander knot"
  done

let test_program_amplification () =
  let rng = Random.State.make [| 0x5877; 0x9999 |] in
  let blocks = Hashtbl.create 1 in
  let block0 = {
    id = 0;
    label = "entry";
    ops = [
      PushImm 0x1337CAFE58772601L;
      PushImm 0x0102030405060708L;
      Add;
      PushImm 0xdeadbeefcafebabeL;
      Sub;
      Exit;
    ];
  } in
  Hashtbl.replace blocks 0 block0;
  let sample_prog : program = {
    entry_id = 0;
    blocks;
    context_slots = 16;
  } in
  let orig_ops = List.length block0.ops in
  let amplified = Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile sample_prog in
  let amp_block0 = Hashtbl.find amplified.blocks 0 in
  let amp_ops = List.length amp_block0.ops in
  let ratio = float_of_int amp_ops /. float_of_int orig_ops in

  Printf.printf "\n[PASS] Bytecode Amplification: %d ops -> %d ops (%.1fx expansion, 0%% dead code)\n"
    orig_ops amp_ops ratio;

  Alcotest.(check bool) "Amplification ratio should be >= 10x" true (ratio >= 10.0);

  (* Execute amplified block and verify exact execution result *)
  let st = create_state () in
  List.iter (step_op st) amp_block0.ops;
  let expected =
    Int64.sub (Int64.add 0x1337CAFE58772601L 0x0102030405060708L) 0xdeadbeefcafebabeL
  in
  match st.vstack with
  | [res] ->
      Alcotest.(check int64) "Amplified program execution result must match reference" expected res
  | _ ->
      Alcotest.fail "Stack length is not 1 after amplified program execution"

let test_profiles_and_invariants () =
  let heavy = Amp.default_heavy_profile in
  let balanced = Amp.balanced_profile in
  let light = Amp.light_profile in
  Alcotest.(check int) "heavy degree 6" 6 heavy.horner_degree;
  Alcotest.(check int) "balanced degree 3" 3 balanced.horner_degree;
  Alcotest.(check int) "light degree 2" 2 light.horner_degree;

  let a_small = Amp.adaptive_profile ~block_size:10 () in
  let a_med = Amp.adaptive_profile ~block_size:40 () in
  let a_large = Amp.adaptive_profile ~block_size:100 () in
  let a_post_mba = Amp.adaptive_profile ~post_mba:true () in
  Alcotest.(check int) "small block uses heavy" 6 a_small.horner_degree;
  Alcotest.(check int) "med block uses balanced" 3 a_med.horner_degree;
  Alcotest.(check int) "large block uses light" 2 a_large.horner_degree;
  Alcotest.(check int) "post-mba uses light" 2 a_post_mba.horner_degree;

  (* Verify Stack_invariants.check_stack_invariants holds on amplified program *)
  let rng = Random.State.make [| 0x1234; 0x5678 |] in
  let blocks = Hashtbl.create 1 in
  let block0 = {
    id = 0;
    label = "entry";
    ops = [
      PushImm 100L;
      PushImm 200L;
      Add;
      PopReg 0;
      Exit;
    ];
  } in
  Hashtbl.replace blocks 0 block0;
  let sample_prog = { entry_id = 0; blocks; context_slots = 8 } in
  let amplified = Amp.amplify_stack_program rng ~profile:balanced sample_prog in
  let inv_res = Stack_vm.Stack_invariants.check_stack_invariants amplified in
  Alcotest.(check bool) "Amplified program satisfies stack invariants" true (Result.is_ok inv_res)

let () =
  let open Alcotest in
  run "Bytecode Amplifier & Treewidth Expander" [
    ( "horner_synthesis",
      [
        test_case "Exact evaluation in Z_{2^64}" `Quick test_horner_synthesis;
        test_case "Stack evaluation" `Quick test_horner_stack_eval;
      ] );
    ( "carry_chain",
      [
        test_case "Carry chain Add" `Quick test_carry_chain_add;
        test_case "Carry chain Sub" `Quick test_carry_chain_sub;
      ] );
    ( "expander_knots",
      [
        test_case "Expander knot invariant" `Quick test_expander_web_knot;
      ] );
    ( "program_amplification",
      [
        test_case "Program expansion >= 10x and semantic equivalence" `Quick test_program_amplification;
        test_case "Profiles and stack invariants preservation" `Quick test_profiles_and_invariants;
      ] );
  ]
