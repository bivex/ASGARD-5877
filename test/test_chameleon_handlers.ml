open Int64
module Cham = Native_vm.Chameleon_handlers

let test_chameleon_weights_morphing () =
  let rng = Random.State.make [| 0x5877; 0xC4A3 |] in
  for _ = 1 to 200 do
    let x = Cham.rand_u64 rng in
    let y = Cham.rand_u64 rng in

    let w_add1 = Cham.synth_chameleon_weights rng Cham.SemAdd in
    let w_add2 = Cham.synth_chameleon_weights rng Cham.SemAdd in
    Alcotest.(check bool) "Weights of two ADD syntheses should be distinct" true (w_add1.w_xor <> w_add2.w_xor);
    Alcotest.(check int64) "Chameleon kernel ADD 1" (add x y) (Cham.eval_chameleon_kernel w_add1 x y);
    Alcotest.(check int64) "Chameleon kernel ADD 2" (add x y) (Cham.eval_chameleon_kernel w_add2 x y);

    let w_xor = Cham.synth_chameleon_weights rng Cham.SemXor in
    Alcotest.(check int64) "Chameleon kernel XOR" (logxor x y) (Cham.eval_chameleon_kernel w_xor x y);

    let w_and = Cham.synth_chameleon_weights rng Cham.SemAnd in
    Alcotest.(check int64) "Chameleon kernel AND" (logand x y) (Cham.eval_chameleon_kernel w_and x y);

    let w_or = Cham.synth_chameleon_weights rng Cham.SemOr in
    Alcotest.(check int64) "Chameleon kernel OR" (logor x y) (Cham.eval_chameleon_kernel w_or x y);
  done

let test_delayed_commit_pipeline () =
  let pipe = Cham.create_pipeline_state () in
  let regs = Array.make 8 0L in

  (* Шаг 1: вычисляем для R1 значение 0x1111, но в R1 оно ЕЩЕ НЕ ДОЛЖНО появиться! *)
  Cham.step_delayed_commit_handler pipe regs ~dst_reg:1 ~new_result:0x1111L ~next_mask:0xAAAA5555L;
  Alcotest.(check int64) "R1 should be 0 on step 1 (oracle blinded)" 0L regs.(1);

  (* Шаг 2: вычисляем для R2 значение 0x2222 -> теперь в R1 автоматически коммитится 0x1111! *)
  Cham.step_delayed_commit_handler pipe regs ~dst_reg:2 ~new_result:0x2222L ~next_mask:0x12345678L;
  Alcotest.(check int64) "R1 should be committed on step 2" 0x1111L regs.(1);
  Alcotest.(check int64) "R2 should still be 0 on step 2 (delayed)" 0L regs.(2);

  (* Финальный Flush перед выходом из VM *)
  Cham.flush_delayed_commit pipe regs;
  Alcotest.(check int64) "R2 should be committed on flush" 0x2222L regs.(2)

let test_emitted_cpp_header () =
  let rng = Random.State.make [| 0x5877; 0xDEAD |] in
  let hpp = Cham.emit_chameleon_handlers_hpp rng in
  Alcotest.(check bool) "Header should not be empty" true (String.length hpp > 200);
  Alcotest.(check bool) "Header should contain DelayedCommitCtx" true (String.contains hpp 'D');
  Printf.printf "\n[PASS] Typed C++20 EDSL emitted Chameleon Header (%d bytes).\n" (String.length hpp)

let () =
  let open Alcotest in
  run "Chameleon & Delayed-Commit Handlers" [
    ( "chameleon_weights",
      [
        test_case "Polymorphic ALU morphing in Z_{2^64}" `Quick test_chameleon_weights_morphing;
      ] );
    ( "delayed_commit",
      [
        test_case "Delayed-commit pipeline queue" `Quick test_delayed_commit_pipeline;
      ] );
    ( "cpp_codegen",
      [
        test_case "Typed C++20 EDSL header generation" `Quick test_emitted_cpp_header;
      ] );
  ]
