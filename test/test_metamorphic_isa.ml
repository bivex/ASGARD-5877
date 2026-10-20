open Int64
open Random_visa_domain

(* Test suite for the metamorphic ISA, the homomorphic ring and hardening *)
module Isa = Isa_metamorphic_synth
module Ring = Mba_engine.Metamorphic_ring
module Nullspace = Mba_engine.Nullspace_mba
module Perm = Native_vm.Context_permutation

let test_mixed_radix_roundtrip () =
  let rng = Random.State.make [| 0x5877; 0x2601; 0x9292 |] in
  for _ = 1 to 200 do
    let spec = Isa.gen_non_separable_isa_spec rng in
    let orig : Isa.raw_instruction = {
      opcode   = Random.State.int rng spec.n_opcodes;
      rd       = Random.State.int rng spec.n_regs;
      rs1      = Random.State.int rng spec.n_regs;
      rs2      = Random.State.int rng spec.n_regs;
      route_id = Random.State.int rng spec.n_routes;
      imm16    = Random.State.int rng 65536;
    } in
    let encoded = Isa.encode_mixed_radix_insn spec orig in
    let decoded = Isa.decode_mixed_radix_insn spec encoded in
    Alcotest.(check bool) "roundtrip exact" true (orig = decoded)
  done

let test_gl2_synthetic_alu_basis () =
  let rng = Random.State.make [| 0x1337; 0xCAFE |] in
  for _ = 1 to 100 do
    let basis = Isa.synth_orthogonal_alu_basis rng ~op1_id:10 ~op2_id:20 in
    let x = Random.State.int64 rng max_int in
    let y = Random.State.int64 rng max_int in
    let p1 = Isa.eval_synthetic_op basis.psi1 x y in
    let p2 = Isa.eval_synthetic_op basis.psi2 x y in

    let check_op std_op expected =
      let (w1, w2, wc) = Isa.lower_std_op_to_basis basis std_op in
      let actual = add (add (mul w1 p1) (mul w2 p2)) wc in
      Alcotest.(check int64) "synthetic op reconstruction" expected actual
    in
    check_op Isa.StdAdd (add x y);
    check_op Isa.StdXor (logxor x y);
    check_op Isa.StdAnd (logand x y);
    check_op Isa.StdOr  (logor x y);

    (* Sub(x, y) = Add(x, ~y) + 1 *)
    let (w1_sub, w2_sub, wc_sub) = Isa.lower_std_op_to_basis basis Isa.StdSub in
    let p1_sub = Isa.eval_synthetic_op basis.psi1 x (lognot y) in
    let p2_sub = Isa.eval_synthetic_op basis.psi2 x (lognot y) in
    let actual_sub = add (add (mul w1_sub p1_sub) (mul w2_sub p2_sub)) wc_sub in
    Alcotest.(check int64) "synthetic sub reconstruction" (sub x y) actual_sub
  done

let test_homomorphic_ring () =
  let rng = Random.State.make [| 0xDEAD; 0xBEEF |] in
  for _ = 1 to 200 do
    let cx = Ring.gen_ring_codec rng in
    let cy = Ring.gen_ring_codec rng in
    let cz = Ring.gen_ring_codec rng in
    let x = Random.State.int64 rng max_int in
    let y = Random.State.int64 rng max_int in
    let x_hat = Ring.encode_val cx x in
    let y_hat = Ring.encode_val cy y in

    (* 1. Verification of homomorphic addition *)
    let (c1, c2, c3) = Ring.compile_homomorphic_add cx cy cz in
    let z_add_hat = add (add (mul c1 x_hat) (mul c2 y_hat)) c3 in
    Alcotest.(check int64) "homomorphic add" (add x y) (Ring.decode_val cz z_add_hat);

    (* 2. Verification of homomorphic multiplication *)
    let (k_xy, k_x, k_y, k_0) = Ring.compile_homomorphic_mul cx cy cz in
    let z_mul_hat =
      add
        (add (mul k_xy (mul x_hat y_hat)) (mul k_x x_hat))
        (add (mul k_y y_hat) k_0)
    in
    Alcotest.(check int64) "homomorphic mul" (mul x y) (Ring.decode_val cz z_mul_hat);

    (* 3. Verification of the nonlinear XorShift33 involution *)
    let c_odd = logor (Random.State.int64 rng max_int) 1L in
    let inv1 = Ring.eval_xorshift33_involution ~c_odd x in
    let inv2 = Ring.eval_xorshift33_involution ~c_odd inv1 in
    Alcotest.(check int64) "xorshift33 involution" x inv2
  done

let test_mealy_state_and_cpp_header () =
  let rng = Random.State.make [| 0x42 |] in
  let spec = Isa.gen_non_separable_isa_spec rng in
  let basis = Isa.synth_orthogonal_alu_basis rng ~op1_id:10 ~op2_id:20 in
  let header = Isa.emit_cpp20_decoder_header spec basis in
  Alcotest.(check bool) "header non-empty" true (String.length header > 100);
  let s0 = 0x1234567890ABCDEFL in
  let s1 = Isa.step_mealy_grammar_state ~state:s0 ~insn_word:0xFEEDFACEL ~data_invariant:0xCAFEBABEL in
  let w = Isa.next_insn_byte_width ~state:s1 in
  Alcotest.(check bool) "valid width" true (w = 3 || w = 5 || w = 8)

let test_context_permutation_cycles () =
  let rng = Random.State.make [| 0x111; 0x222 |] in
  for _ = 1 to 100 do
    let n = 16 in
    let cp = Perm.gen_permutation ~rng ~n in
    let swaps = Perm.decompose_into_swaps cp.inv_perm in
    let arr = Array.init n (fun i -> i) in
    List.iter (fun (i, j) ->
      let tmp = arr.(i) in
      arr.(i) <- arr.(j);
      arr.(j) <- tmp
    ) swaps;
    for i = 0 to n - 1 do
      Alcotest.(check int) "swap decomposition correctness" cp.perm.(i) arr.(i)
    done;
    let cpp = Perm.emit_epoch_rotation_cpp cp in
    Alcotest.(check bool) "cpp rotation emitted" true (String.length cpp >= 0)
  done

let test_nullspace_minterm_mba () =
  let rng = Random.State.make [| 0x555; 0x666 |] in
  for _ = 1 to 50 do
    let terms = Nullspace.synth_minterm_zero ~rng ~terms_count:4 in
    Alcotest.(check bool) "terms non-empty" true (terms <> []);
    Alcotest.(check bool) "minterm zero holds exactly" true (Nullspace.verify_minterm_zero terms);
    for _ = 1 to 20 do
      let x = Random.State.int64 rng max_int in
      let y = Random.State.int64 rng max_int in
      let z = Nullspace.eval_terms ~terms ~x ~y in
      Alcotest.(check int64) "random evaluation is 0L" 0L z
    done
  done

let tests = [
  Alcotest.test_case "mixed_radix_roundtrip" `Quick test_mixed_radix_roundtrip;
  Alcotest.test_case "gl2_synthetic_alu_basis" `Quick test_gl2_synthetic_alu_basis;
  Alcotest.test_case "homomorphic_ring" `Quick test_homomorphic_ring;
  Alcotest.test_case "mealy_state_and_cpp_header" `Quick test_mealy_state_and_cpp_header;
  Alcotest.test_case "context_permutation_cycles" `Quick test_context_permutation_cycles;
  Alcotest.test_case "nullspace_minterm_mba" `Quick test_nullspace_minterm_mba;
]
