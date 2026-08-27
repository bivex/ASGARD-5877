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
  check int64 "Master seed match" s1.master_seed s2.master_seed;
  check int64 "Opcode seed match" s1.opcode_seed s2.opcode_seed;
  check int64 "Register seed match" s1.register_seed s2.register_seed;
  check int64 "CFG seed match" s1.cfg_seed s2.cfg_seed

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
  match Pipeline.compile ~seed ~strategy:Register_allocator.Randomized f with
  | Ok res ->
      check bool "Equivalence verified" true res.equivalence_verified;
      (match Reference_vm.evaluate res.diversified_func with
      | Ok snap -> check int64 "Final diversified output matches golden 100L" 100L snap.final_rax
      | Error msg -> fail msg)
  | Error msg -> fail ("Pipeline compilation failed: " ^ msg)

let tests = [
  ("Seed Determinism", `Quick, test_seed_determinism);
  ("IR Verifier Success", `Quick, test_ir_verify_success);
  ("IR Verifier Catches Missing Terminator", `Quick, test_ir_verify_missing_terminator);
  ("Reference VM Evaluation", `Quick, test_reference_vm_evaluation);
  ("Semantic Transform Equivalence", `Quick, test_semantic_diversification_equivalence);
  ("End-to-End Compiler Pipeline", `Quick, test_end_to_end_pipeline);
]
