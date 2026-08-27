open Random_visa_domain

let test_dispatch_strategy_invariants () =
  let rng = Random.State.make [| 42 |] in
  let strategy = Dispatch_strategy.generate ~rng ~total_opcodes:256 ~num_domains:4 () in
  
  Alcotest.(check int) "num_domains" 4 strategy.num_domains;
  Alcotest.(check int) "domains list length" 4 (List.length strategy.domains);
  
  (* Invariant 1: Coprimality gcd(a, frame_size) == 1 *)
  let a = strategy.context_layout.affine_a in
  let m = strategy.context_layout.frame_size in
  let rec gcd x y = if y = 0 then x else gcd y (x mod y) in
  Alcotest.(check int) "gcd(a, frame_size) is 1" 1 (gcd a m);
  
  (* Invariant 2: Scrambling is a complete bijection (no collisions) *)
  let domain = List.init m (fun i -> i) in
  let mapped = List.map (Dispatch_strategy.scramble_index strategy.context_layout) domain in
  let unique_mapped = List.sort_uniq Int.compare mapped in
  Alcotest.(check int) "scramble bijection length" m (List.length unique_mapped);
  
  (* Invariant 3: Total opcodes across domains covers 256 exactly *)
  let total_ops = List.fold_left (fun acc (d : Dispatch_strategy.thread_domain) -> acc + List.length d.opcode_subset) 0 strategy.domains in
  Alcotest.(check int) "total opcodes partitioned" 256 total_ops

let test_mutation_profile_invariants () =
  let rng = Random.State.make [| 1337 |] in
  let profile = Mutation_profile.generate ~rng ~total_opcodes:256 () in
  
  Alcotest.(check int) "mutations count" 256 (Hashtbl.length profile.op_mutations);
  
  (* Invariant: every opcode has a valid mutation *)
  for op = 0 to 255 do
    let m = Mutation_profile.get_mutation profile op in
    match m.alu_variant with
    | Mutation_profile.LinearStandard
    | Mutation_profile.MbaZhouEyrolles _
    | Mutation_profile.MaskedSemiLinear _
    | Mutation_profile.PolynomialOpaqueZero -> ()
  done

let test_vm_runtime_profile_reproducibility () =
  let p1 = Vm_runtime_profile.generate ~seed:0x12345678L ~total_opcodes:256 () in
  let p2 = Vm_runtime_profile.generate ~seed:0x12345678L ~total_opcodes:256 () in
  
  Alcotest.(check int) "identical affine_a" p1.dispatch.context_layout.affine_a p2.dispatch.context_layout.affine_a;
  Alcotest.(check int) "identical affine_b" p1.dispatch.context_layout.affine_b p2.dispatch.context_layout.affine_b;
  Alcotest.(check int) "identical cff_depth" p1.cff_depth p2.cff_depth

let tests = [
  Alcotest.test_case "dispatch_strategy_invariants" `Quick test_dispatch_strategy_invariants;
  Alcotest.test_case "mutation_profile_invariants" `Quick test_mutation_profile_invariants;
  Alcotest.test_case "reproducibility" `Quick test_vm_runtime_profile_reproducibility;
]

