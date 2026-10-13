open Vm_ir

let make_simple_func name =
  let entry = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 42L };
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax;
             src2 = Ir.Imm 1L; set_flags = false };
    Ir.Jmp (Ir.BlockId 1);
  ] in
  let compute = Ir.make_block ~id:1 ~label:"compute" ~instrs:[
    Ir.Alu { op = Ir.Mul; dst = Register.rax; src1 = Ir.Reg Register.rax;
             src2 = Ir.Imm 3L; set_flags = false };
    Ir.Mov { dst = Ir.Reg Register.rcx; src = Ir.Imm 7L };
    Ir.Alu { op = Ir.Sub; dst = Register.rax; src1 = Ir.Reg Register.rax;
             src2 = Ir.Reg Register.rcx; set_flags = false };
    Ir.Jmp (Ir.BlockId 2);
  ] in
  let exit_b = Ir.make_block ~id:2 ~label:"exit" ~instrs:[ Ir.Ret ] in
  Ir.make_func ~name ~entry_id:0 ~blocks:[entry; compute; exit_b]

let test_cross_seed_divergence () =
  let func = make_simple_func "test_fn" in
  let seed1 = Seed.create ~master_seed:0x1111_1111_1111_1111L () in
  let seed2 = Seed.create ~master_seed:0x2222_2222_2222_2222L () in
  let result1 = Ir_pipeline.compile ~seed:seed1 ~verify_equivalence:false func in
  let result2 = Ir_pipeline.compile ~seed:seed2 ~verify_equivalence:false func in
  match result1, result2 with
  | Ok r1, Ok r2 ->
      let report = Native_vm.Cross_seed_metrics.compare_builds
        ~f1:r1.Ir_pipeline.diversified_func
        ~f2:r2.Ir_pipeline.diversified_func in
      let _ = Native_vm.Cross_seed_metrics.report_to_string report in
      (* Same seed = high similarity *)
      let result_same = Ir_pipeline.compile ~seed:seed1 ~verify_equivalence:false func in
      (match result_same with
      | Ok rs ->
          let report_same = Native_vm.Cross_seed_metrics.compare_builds
            ~f1:r1.Ir_pipeline.diversified_func
            ~f2:rs.Ir_pipeline.diversified_func in
          Alcotest.(check bool) "same seed high similarity" true (report_same.ngram3_jaccard >= 0.8)
      | Error e -> Alcotest.fail ("Same-seed compile error: " ^ e))
  | Error e, _ | _, Error e ->
      Alcotest.fail ("Compile error: " ^ e)

let test_disjointness_gate () =
  let func = make_simple_func "test_gate" in
  let seed1 = Seed.create ~master_seed:0x3333_3333_3333_3333L () in
  let seed2 = Seed.create ~master_seed:0x4444_4444_4444_4444L () in
  let result1 = Ir_pipeline.compile ~seed:seed1 ~verify_equivalence:false func in
  let result2 = Ir_pipeline.compile ~seed:seed2 ~verify_equivalence:false func in
  match result1, result2 with
  | Ok r1, Ok r2 ->
      let report = Native_vm.Cross_seed_metrics.compare_builds
        ~f1:r1.Ir_pipeline.diversified_func
        ~f2:r2.Ir_pipeline.diversified_func in
      Alcotest.(check bool) "different seeds produce non-identical ngrams" true (report.ngram3_jaccard < 1.0)
  | Error e, _ | _, Error e ->
      Alcotest.fail ("Compile error: " ^ e)

let tests = [
  Alcotest.test_case "cross_seed_divergence" `Quick test_cross_seed_divergence;
  Alcotest.test_case "disjointness_gate" `Quick test_disjointness_gate;
]
