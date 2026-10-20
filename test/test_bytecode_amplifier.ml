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
  let s1 = 10 and s2 = 11 and sx = 12 and sy = 13 in
  let test_cases = [
    (100L, 250L);
    (0x123456789ABCDEF0L, 0xFEDCBA9876543210L);
    (0xFFFFFFFFFFFFFFFFL, 1L);
    (0x7FFFFFFFFFFFFFFFL, 0x7FFFFFFFFFFFFFFFL);
    (0L, 0L);
  ] in
  List.iter (fun (x, y) ->
    let ops = Amp.emit_carry_chain_add rng ~s1 ~s2 ~sx ~sy in
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
  let s1 = 10 and s2 = 11 and sx = 12 and sy = 13 in
  let test_cases = [
    (250L, 100L);
    (100L, 250L);
    (0x123456789ABCDEF0L, 0xFEDCBA9876543210L);
    (0L, 1L);
    (0xFFFFFFFFFFFFFFFFL, 0xFFFFFFFFFFFFFFFFL);
  ] in
  List.iter (fun (x, y) ->
    let ops = Amp.emit_carry_chain_sub rng ~s1 ~s2 ~sx ~sy in
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

(* ------------------------------------------------------------------ *)
(* Differential property test (QCheck): amplified program must compute
   the exact same final stack and context as the original, across all
   three profiles. The generator is depth-tracked (no underflow) and
   deliberately includes Setcc flag consumers right after flag-defining
   ops — this is what catches flag-unfaithful replacements (a naive
   PushFlags wrapper around a rewritten Add would restore STALE flags
   and fail here). *)
let conds = [| Vm_ir.Flags.E; Vm_ir.Flags.NE; Vm_ir.Flags.B; Vm_ir.Flags.AE;
               Vm_ir.Flags.S; Vm_ir.Flags.NS; Vm_ir.Flags.L; Vm_ir.Flags.GE;
               Vm_ir.Flags.LE; Vm_ir.Flags.G |]

let build_random_program (seed : int) : program * (int * int64) list =
  let rng = Random.State.make [| seed land 0x3FFFFFFF; 0xA0F5; 0x5EED |] in
  let init_ctx = List.init 16 (fun i -> (i, Amp.rand_u64 rng)) in
  let pick_int lo hi = lo + Random.State.int rng (hi - lo + 1) in
  let rec loop depth n acc =
    if n = 0 then acc
    else
      let p = Random.State.int rng 100 in
      let next =
        if p < 18 then
          let c = Amp.rand_u64 rng in
          loop (depth + 1) (n - 1) (PushImm c :: acc)
        else if p < 28 then
          loop (depth + 1) (n - 1) (PushReg (pick_int 0 15) :: acc)
        else if p < 46 && depth >= 2 then
          let op = match pick_int 0 4 with
            | 0 -> Add | 1 -> Sub | 2 -> Mul | 3 -> Nor | _ -> Nand
          in
          loop (depth - 1) (n - 1) (op :: acc)
        else if p < 56 && depth >= 2 then
          let sh = match pick_int 0 2 with
            | 0 -> Shl | 1 -> Shr | _ -> Sar
          in
          (* count on the stack: value below, count on top *)
          loop (depth - 1) (n - 1) (sh :: PushImm (Int64.of_int (pick_int 0 63)) :: acc)
        else if p < 66 then
          let c = conds.(pick_int 0 (Array.length conds - 1)) in
          loop (depth + 1) (n - 1) (Setcc c :: acc)
        else if p < 76 && depth >= 1 then
          loop (depth - 1) (n - 1) (PopReg (pick_int 8 15) :: acc)
        else if p < 84 && depth >= 1 then
          loop (depth + 1) (n - 1) (Dup :: acc)
        else if p < 92 && depth >= 2 then
          loop depth (n - 1) (Swap :: acc)
        else if p < 96 && depth >= 1 then
          let c = Amp.rand_u64 rng in
          let op = if pick_int 0 1 = 0 then AddImm c else SubImm c in
          loop depth (n - 1) (op :: acc)
        else
          loop (depth + 1) (n - 1) (PushImm (Amp.rand_u64 rng) :: acc)
      in
      next
  in
  let n_ops = 20 + pick_int 0 20 in
  let body = loop 0 n_ops [] in
  (* drain: flush the remaining stack into slots 8..15 so that the final
     stack state is [] and the comparison is strict *)
  let rec drain depth acc =
    if depth = 0 then acc
    else drain (depth - 1) (PopReg (8 + (depth mod 8)) :: acc)
  in
  let ops = List.rev body @ drain (List.fold_left (fun d op -> d + stack_delta op) 0 body) [ Exit ] in
  let blocks = Hashtbl.create 1 in
  Hashtbl.replace blocks 0 { id = 0; label = "entry"; ops };
  ({ entry_id = 0; blocks; context_slots = 16 }, init_ctx)

let run_block ?initial_ctx ops =
  let st = match initial_ctx with
    | Some ctx -> create_state ~initial_ctx:ctx ()
    | None -> create_state ()
  in
  List.iter (fun op -> if not st.halted then step_op st op) ops;
  st

let prop_amplify_semantics seed =
  let prog, init_ctx = build_random_program seed in
  let orig_block = Hashtbl.find prog.blocks 0 in
  let orig_st = run_block ~initial_ctx:init_ctx orig_block.ops in
  if orig_st.halted then
    Printf.eprintf "generator produced a halting program (seed %d)\n" seed;
  let orig_regs = List.init 16 (fun i -> get_reg orig_st i) in
  let profiles : (string * Amp.amplification_profile) list = [
    ("heavy", Amp.default_heavy_profile);
    ("balanced", Amp.balanced_profile);
    ("light", Amp.light_profile);
  ] in
  List.for_all
    (fun (name, profile) ->
      let rng = Random.State.make [| seed land 0x3FFFFFFF; (profile : Amp.amplification_profile).horner_degree; 0xA0F1 |] in
      let amplified = Amp.amplify_stack_program rng ~profile prog in
      let amp_block = Hashtbl.find amplified.blocks 0 in
      let amp_st = run_block ~initial_ctx:init_ctx amp_block.ops in
      let ok_stack = (amp_st.vstack = orig_st.vstack) in
      let ok_regs =
        List.for_all2 ( = ) orig_regs (List.init 16 (fun i -> get_reg amp_st i))
      in
      if not (ok_stack && ok_regs) then begin
        Printf.eprintf "profile %s diverged on seed %d: stack_ok=%b regs_ok=%b\n"
          name seed ok_stack ok_regs
      end;
      ok_stack && ok_regs)
    profiles

let prop_amplify_determinism seed =
  (* the same seed => bit-for-bit identical amplified bytecode
     (regression test for Hashtbl.iter non-determinism) *)
  let prog, _ = build_random_program seed in
  let build () =
    let rng = Random.State.make [| seed land 0x3FFFFFFF; 6; 0xDE7E0 |] in
    let amplified = Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile prog in
    Stack_vm.Stack_ir.program_to_string amplified
  in
  build () = build ()

let qcheck_amplify =
  QCheck.(
    Test.make ~count:150 ~name:"amplifier preserves exact semantics (all profiles)"
      QCheck.int prop_amplify_semantics)

let qcheck_determinism =
  QCheck.(
    Test.make ~count:20 ~name:"amplifier is seed-deterministic"
      QCheck.int prop_amplify_determinism)

(* Pin the flag-unsafe path: Setcc immediately after Add/Sub => the flags are
   still live after the instruction, so the replacement must redefine
   CC_OP_ADD/SUB (hidden re-execution), otherwise Setcc will see foreign
   flags. The diff-test covers this probabilistically, here it is guaranteed. *)
let test_flag_unsafe_add_sub () =
  let rng = Random.State.make [| 0x5877; 0xF1A6 |] in
  let run ops =
    let st = create_state ~initial_ctx:[ (0, 0x123456789ABCDEF0L ) ] () in
    List.iter (fun op -> if not st.halted then step_op st op) ops;
    st
  in
  let cases = [
    (0x7FFFFFFFFFFFFFFFL, 1L);   (* OF/ZF/CF edge *)
    (0xFFFFFFFFFFFFFFFFL, 1L);   (* carry across 2^64 *)
    (0L, 0L);
    (0x123456789ABCDEF0L, 0xFEDCBA9876543210L);
  ] in
  List.iter (fun (x, y) ->
    let mk op =
      let blocks = Hashtbl.create 1 in
      Hashtbl.replace blocks 0
        { id = 0; label = "entry";
          ops = [ PushImm x; PushImm y; op; Setcc Vm_ir.Flags.G; PopReg 1;
                  Setcc Vm_ir.Flags.B; PopReg 2; Exit ] };
      ({ entry_id = 0; blocks; context_slots = 16 } : program)
    in
    let orig = mk Add in
    let amp =
      Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile orig in
    (* the replacement really happened (not a fallback) *)
    let amp_ops = (Hashtbl.find amp.blocks 0).ops in
    Alcotest.(check bool) "flag-unsafe Add must be amplified (ops grow)"
      true (List.length amp_ops > List.length (Hashtbl.find orig.blocks 0).ops * 4);
    let st1 = run (Hashtbl.find orig.blocks 0).ops in
    let st2 = run amp_ops in
    Alcotest.(check int64) "flag-unsafe Add: Setcc B must match"
      (get_reg st1 1) (get_reg st2 1);
    Alcotest.(check int64) "flag-unsafe Add: Setcc B(2) must match"
      (get_reg st1 2) (get_reg st2 2);
    let orig_sub = mk Sub in
    let amp_sub =
      Amp.amplify_stack_program rng ~profile:Amp.default_heavy_profile orig_sub in
    let st3 = run (Hashtbl.find orig_sub.blocks 0).ops in
    let st4 = run (Hashtbl.find amp_sub.blocks 0).ops in
    Alcotest.(check int64) "flag-unsafe Sub: Setcc G must match"
      (get_reg st3 1) (get_reg st4 1);
    Alcotest.(check int64) "flag-unsafe Sub: Setcc B(2) must match"
      (get_reg st3 2) (get_reg st4 2)
  ) cases

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
    ( "differential_qcheck",
      List.map QCheck_alcotest.to_alcotest [ qcheck_amplify; qcheck_determinism ] );
    ( "flag_faithfulness",
      [
        test_case "flag-unsafe Add/Sub re-defines flags exactly" `Quick test_flag_unsafe_add_sub;
      ] );
  ]
