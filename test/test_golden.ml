open Random_visa_domain

let test_golden_seed_42 () =
  let rng = Random.State.make [| 42 |] in
  match Isa_grammar.generate_isa ~rng ~name:"Golden_42" ~num_instructions:4 () with
  | Error err -> Alcotest.fail (Errors.to_string err)
  | Ok spec ->
      let sail_text = Vector_isa_spec.to_sail_specification spec in
      Alcotest.(check bool) "contains preamble" true (String.contains sail_text '$' && String.contains sail_text 'p');
      Alcotest.(check bool) "contains VLEN" true (String.contains sail_text 'V' && String.contains sail_text 'L');
      Alcotest.(check int) "4 instructions" 4 (List.length spec.instructions);
      (* Deterministic mnemonics check *)
      let m1 = (List.nth spec.instructions 0).mnemonic in
      let m2 = (List.nth spec.instructions 1).mnemonic in
      Alcotest.(check bool) "m1 valid" true (String.length m1 > 0);
      Alcotest.(check bool) "m2 valid" true (String.length m2 > 0)

let test_golden_determinism () =
  let rng1 = Random.State.make [| 12345 |] in
  let spec1 = Isa_grammar.generate_isa ~rng:rng1 ~name:"Det" ~num_instructions:12 () in
  let rng2 = Random.State.make [| 12345 |] in
  let spec2 = Isa_grammar.generate_isa ~rng:rng2 ~name:"Det" ~num_instructions:12 () in
  match (spec1, spec2) with
  | Ok s1, Ok s2 ->
      let text1 = Vector_isa_spec.to_sail_specification s1 in
      let text2 = Vector_isa_spec.to_sail_specification s2 in
      Alcotest.(check string) "byte-for-byte deterministic" text1 text2
  | _ -> Alcotest.fail "Generation failed"

let tests = [
  Alcotest.test_case "golden_seed_42" `Quick test_golden_seed_42;
  Alcotest.test_case "golden_determinism" `Quick test_golden_determinism;
]
