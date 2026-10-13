open Vm_ir

let test_synthesis_soundness () =
  let rng = Random.State.make [| 0x12_34_56; 0x78_9A_BC |] in
  for _ = 1 to 200 do
    let m = 6 + Random.State.int rng 4 in
    let terms = Mba_engine.Nullspace_synth.synth_zero ~rng ~m in
    if terms <> [] then begin
      let ok = Mba_engine.Nullspace_synth.verify_zero terms in
      Alcotest.(check bool) "verify_zero" true ok
    end
  done

let test_eval_equivalence () =
  let rng = Random.State.make [| 0xDE_AD_BE; 0xEF_00_11 |] in
  let ops = [ Ir.Add; Ir.Sub; Ir.Xor; Ir.Or; Ir.And ] in
  List.iter (fun op ->
    for _ = 1 to 20 do
      let v1 = Random.State.int64 rng Int64.max_int in
      let v2 = Random.State.int64 rng Int64.max_int in
      let dst = Register.rax in
      let src1 = Ir.Reg Register.rcx in
      let src2 = Ir.Reg Register.rdx in
      let instrs = Mba_engine.Nullspace_synth.obfuscate_alu ~rng ~dst ~src1 ~src2 op in
      let full_instrs = [
        Ir.Mov { dst = Ir.Reg Register.rcx; src = Ir.Imm v1 };
        Ir.Mov { dst = Ir.Reg Register.rdx; src = Ir.Imm v2 };
      ] @ instrs @ [ Ir.Ret ] in
      let bb = Ir.make_block ~id:0 ~label:"test" ~instrs:full_instrs in
      let func = Ir.make_func ~name:"test_eval" ~entry_id:0 ~blocks:[bb] in
      let state = Vm_eval.make_state () in
      match Vm_eval.run_func state func with
      | Ok () ->
          let res = Vm_eval.get_reg state Register.rax in
          let expected = match op with
            | Ir.Add -> Int64.add v1 v2
            | Ir.Sub -> Int64.sub v1 v2
            | Ir.Xor -> Int64.logxor v1 v2
            | Ir.Or  -> Int64.logor v1 v2
            | Ir.And -> Int64.logand v1 v2
            | _ -> 0L
          in
          Alcotest.(check int64) "eval matches expected" expected res
      | Error msg -> Alcotest.fail ("run_func failed: " ^ msg)
    done
  ) ops

let tests = [
  Alcotest.test_case "synthesis_soundness" `Quick test_synthesis_soundness;
  Alcotest.test_case "eval_equivalence" `Quick test_eval_equivalence;
]
