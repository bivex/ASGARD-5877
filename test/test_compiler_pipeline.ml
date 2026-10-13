open Alcotest
open Vm_ir

let make_sample_func () =
  let b1 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 58L; set_flags = false };
    Ir.Ret;
  ] in
  Ir.make_func ~name:"test_sample" ~entry_id:0 ~blocks:[ b1 ]

let test_seed_determinism () =
  let s1 = Seed.create ~master_seed:0x123456789ABCDEFL () in
  let s2 = Seed.create ~master_seed:0x123456789ABCDEFL () in
  check int64 "Master seed match" (Seed.master_seed s1) (Seed.master_seed s2);
  check int64 "Opcode seed match" (Seed.opcode_seed s1) (Seed.opcode_seed s2);
  check int64 "Register seed match" (Seed.register_seed s1) (Seed.register_seed s2);
  check int64 "CFG seed match" (Seed.cfg_seed s1) (Seed.cfg_seed s2)

let test_ir_verify_success () =
  let f = make_sample_func () in
  match Ir_verify.verify_func f with
  | Ok () -> ()
  | Error err -> fail ("Expected IR verify to succeed: " ^ Ir_verify.error_to_string err)

let test_ir_verify_missing_terminator () =
  let b_bad = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
  ] in
  let f_bad = Ir.make_func ~name:"bad_func" ~entry_id:0 ~blocks:[ b_bad ] in
  match Ir_verify.verify_func f_bad with
  | Error (Ir_verify.MissingTerminator 0) -> ()
  | _ -> fail "Expected MissingTerminator error"

let test_reference_vm_evaluation () =
  let f = make_sample_func () in
  match Reference_vm.evaluate f with
  | Ok snap ->
      check int64 "RAX output = 42 + 58 = 100" 100L snap.final_rax
  | Error msg -> fail ("Reference VM evaluation failed: " ^ msg)

let test_semantic_diversification_equivalence () =
  let f = make_sample_func () in
  let seed = Seed.create ~master_seed:0xCAFE13375877AABBL () in
  let trans_f = Semantic_transform.transform_func ~seed f in
  match Equivalence.assert_equivalent ~trials:20 f trans_f with
  | Ok () -> ()
  | Error disc -> fail ("Semantic equivalence assertion failed: " ^ disc.details)

let test_end_to_end_pipeline () =
  let f = make_sample_func () in
  let seed = Seed.create ~master_seed:0x9999888877776666L () in
  match Ir_pipeline.compile ~seed ~strategy:Register_allocator.Randomized f with
  | Ok res ->
      check bool "Equivalence verified" true res.equivalence_verified;
      (match Reference_vm.evaluate res.diversified_func with
      | Ok snap -> check int64 "Final diversified output matches golden 100L" 100L snap.final_rax
      | Error msg -> fail msg)
  | Error msg -> fail ("Pipeline compilation failed: " ^ msg)

let test_rns_roundtrip () =
  let test_vals = [
    0L; 1L; 2L; 42L; 1337L; 0x13375877L;
    0x5555555555555555L;
    0x123456789ABCDEF0L;
    0x7FFFFFFFFFFFFFFFL;
  ] in
  List.iter (fun x ->
    let enc = Rns.encode x in
    let dec = Rns.decode enc in
    check int64 (Printf.sprintf "RNS Roundtrip 0x%016LX" x) x dec
  ) test_vals;
  (* Randomized 100 positive values *)
  let rng = Random.State.make [| 0x5877 |] in
  for _ = 1 to 100 do
    let x = Random.State.int64 rng Int64.max_int in
    let enc = Rns.encode x in
    let dec = Rns.decode enc in
    check int64 (Printf.sprintf "RNS Random Roundtrip 0x%016LX" x) x dec
  done

let test_rns_arithmetic () =
  let pairs = [
    (100L, 200L);
    (0x1337L, 0x5877L);
    (42L, 58L);
    (1000L, 500L);
    (0x10000000L, 0x20000000L);
  ] in
  List.iter (fun (a, b) ->
    let ea = Rns.encode a in
    let eb = Rns.encode b in
    let e_sum = Rns.add ea eb in
    let d_sum = Rns.decode e_sum in
    check int64 (Printf.sprintf "RNS Add %Ld + %Ld" a b) (Int64.add a b) d_sum;

    let e_sub = Rns.sub ea eb in
    let d_sub = Rns.decode e_sub in
    if a >= b then
      check int64 (Printf.sprintf "RNS Sub %Ld - %Ld" a b) (Int64.sub a b) d_sub;

    let e_mul = Rns.mul ea eb in
    let d_mul = Rns.decode e_mul in
    check int64 (Printf.sprintf "RNS Mul %Ld * %Ld" a b) (Int64.mul a b) d_mul;
  ) pairs;
  (* Randomized arithmetic pairs *)
  let rng = Random.State.make [| 0x9292 |] in
  for _ = 1 to 100 do
    let a = Random.State.int64 rng 0x3FFFFFFFFFFFFFFFL in
    let b = Random.State.int64 rng 0x3FFFFFFFFFFFFFFFL in
    let ea = Rns.encode a in
    let eb = Rns.encode b in
    let e_sum = Rns.add ea eb in
    check int64 "RNS randomized add" (Int64.add a b) (Rns.decode e_sum);
    let (high, low) = if a >= b then (a, b) else (b, a) in
    let e_sub = Rns.sub (Rns.encode high) (Rns.encode low) in
    check int64 "RNS randomized sub" (Int64.sub high low) (Rns.decode e_sub);
    (* Multiplication within RNS dynamic range a * b < M *)
    let ma = Random.State.int64 rng 0x7FFFFFFFL in
    let mb = Random.State.int64 rng 0x7FFFFFFFL in
    let e_mul = Rns.mul (Rns.encode ma) (Rns.encode mb) in
    check int64 "RNS randomized mul" (Int64.mul ma mb) (Rns.decode e_mul)
  done

let test_egraph_saturation () =
  let eg = Ir_egraph.create () in
  let e_init = Ir_egraph.Xor (Ir_egraph.Var Register.rax, Ir_egraph.Var Register.rbx) in
  let root = Ir_egraph.add eg e_init in
  Ir_egraph.saturate ~max_iters:2 eg;
  let extracted = Ir_egraph.extract_max_complexity eg root in
  let init_cost = Ir_egraph.complexity_of_expr e_init in
  let sat_cost = Ir_egraph.complexity_of_expr extracted in
  check bool "E-Graph saturation increases complexity" true (sat_cost >= init_cost)

let test_equivalence_memory_and_callee_saved () =
  let mem_target = {
    Ir.base = Some Register.rsp;
    index = None;
    disp = -8L;
    width = Register.B64;
    is_signed = false;
    segment = None;
  } in
  let b1 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 10L; set_flags = false };
    Ir.Mov { dst = Ir.Mem mem_target; src = Ir.Reg Register.rax };
    Ir.Ret;
  ] in
  let f_orig = Ir.make_func ~name:"mem_orig" ~entry_id:0 ~blocks:[ b1 ] in
  (* Equivalent function splitting add into 5 + 5 *)
  let b2 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 5L; set_flags = false };
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 5L; set_flags = false };
    Ir.Mov { dst = Ir.Mem mem_target; src = Ir.Reg Register.rax };
    Ir.Ret;
  ] in
  let f_trans = Ir.make_func ~name:"mem_trans" ~entry_id:0 ~blocks:[ b2 ] in
  match Equivalence.assert_equivalent ~trials:50 ~check_callee_saved:true ~check_memory:true f_orig f_trans with
  | Ok () -> ()
  | Error disc -> fail ("Expected memory & callee-saved equivalence to pass: " ^ disc.details)

let test_equivalence_catches_callee_saved_clobber () =
  let b1 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
    Ir.Ret;
  ] in
  let f_good = Ir.make_func ~name:"good" ~entry_id:0 ~blocks:[ b1 ] in
  (* Mutant clobbers rbx *)
  let b_bad = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
    Ir.Mov { dst = Ir.Reg Register.rbx; src = Ir.Imm 0xDEADBEEFL };
    Ir.Ret;
  ] in
  let f_bad = Ir.make_func ~name:"bad" ~entry_id:0 ~blocks:[ b_bad ] in
  match Equivalence.assert_equivalent ~trials:10 ~check_callee_saved:true f_good f_bad with
  | Error { kind = Equivalence.CalleeSavedClobbered { reg; _ }; _ } ->
      check string "Clobbered register is rbx" "rbx" (Register.to_string reg)
  | Error disc -> fail ("Expected CalleeSavedClobbered error, got: " ^ disc.details)
  | Ok () -> fail "Expected equivalence failure when callee-saved register is clobbered"

let test_equivalence_catches_memory_mismatch () =
  let mem_target = {
    Ir.base = Some Register.rsp;
    index = None;
    disp = -8L;
    width = Register.B64;
    is_signed = false;
    segment = None;
  } in
  let b1 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Mem mem_target; src = Ir.Imm 0x1122334455667788L };
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 0L };
    Ir.Ret;
  ] in
  let f_good = Ir.make_func ~name:"mem_good" ~entry_id:0 ~blocks:[ b1 ] in
  (* Mutant writes wrong byte to memory *)
  let b_bad = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Mem mem_target; src = Ir.Imm 0x1122334455667799L };
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 0L };
    Ir.Ret;
  ] in
  let f_bad = Ir.make_func ~name:"mem_bad" ~entry_id:0 ~blocks:[ b_bad ] in
  match Equivalence.assert_equivalent ~trials:10 ~check_memory:true f_good f_bad with
  | Error { kind = Equivalence.MemoryMismatch _; _ } -> ()
  | Error disc -> fail ("Expected MemoryMismatch error, got: " ^ disc.details)
  | Ok () -> fail "Expected equivalence failure when memory contents differ"

let test_equivalence_catches_flags_mismatch () =
  let b1 = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Imm 0L; src2 = Ir.Imm 0L; set_flags = true };
    Ir.Ret;
  ] in
  let f_good = Ir.make_func ~name:"flags_good" ~entry_id:0 ~blocks:[ b1 ] in
  (* Mutant does not set ZF (set_flags = false) *)
  let b_bad = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Imm 0L; src2 = Ir.Imm 0L; set_flags = false };
    Ir.Ret;
  ] in
  let f_bad = Ir.make_func ~name:"flags_bad" ~entry_id:0 ~blocks:[ b_bad ] in
  match Equivalence.assert_equivalent ~trials:10 ~check_flags:true f_good f_bad with
  | Error { kind = Equivalence.FlagsMismatch _; _ } -> ()
  | Error disc -> fail ("Expected FlagsMismatch error, got: " ^ disc.details)
  | Ok () -> fail "Expected equivalence failure when flags differ"

let tests = [
  ("Seed Determinism", `Quick, test_seed_determinism);
  ("IR Verifier Success", `Quick, test_ir_verify_success);
  ("IR Verifier Catches Missing Terminator", `Quick, test_ir_verify_missing_terminator);
  ("Reference VM Evaluation", `Quick, test_reference_vm_evaluation);
  ("Semantic Transform Equivalence", `Quick, test_semantic_diversification_equivalence);
  ("End-to-End Compiler Pipeline", `Quick, test_end_to_end_pipeline);
  ("RNS Roundtrip & CRT", `Quick, test_rns_roundtrip);
  ("RNS Modular Arithmetic", `Quick, test_rns_arithmetic);
  ("E-Graph Equality Saturation", `Quick, test_egraph_saturation);
  ("Equivalence Memory & Callee-Saved", `Quick, test_equivalence_memory_and_callee_saved);
  ("Equivalence Catches Callee-Saved Clobber", `Quick, test_equivalence_catches_callee_saved_clobber);
  ("Equivalence Catches Memory Mismatch", `Quick, test_equivalence_catches_memory_mismatch);
  ("Equivalence Catches Flags Mismatch", `Quick, test_equivalence_catches_flags_mismatch);
]

