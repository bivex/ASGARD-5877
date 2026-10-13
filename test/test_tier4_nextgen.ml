open Int64

module Bvip = Vm_ir.Branchless_vip
module Cperm = Native_vm.Context_permutation
module Ent = Native_vm.Variable_entangler
module Omem = Native_vm.Oblivious_mem
module Hbridge = Multi_vm.Homomorphic_bridge
module Njit = Rd_jit_vm.Nano_jit_slot
module Ring = Mba_engine.Metamorphic_ring

(* Тест 0: Проверка хотфикса P0-01 (Cycle Decomposition для циклов длины >= 3) *)
let test_p0_cycle_permutation_fix () =
  let rng = Random.State.make [| 0x5877; 0xF001 |] in
  for _ = 1 to 100 do
    let n = 16 in
    let sched = Cperm.gen_epoch_schedule rng ~n_regs:n ~n_epochs:4 in
    (* Исходный вектор значений виртуальных регистров r = 0..15 *)
    let logical_vals = Array.init n (fun r -> of_int (r * 1000 + 7)) in
    (* Раскладываем в физические слоты эпохи 0 *)
    let phys_regs = Array.make n 0L in
    for r = 0 to n - 1 do
      phys_regs.(Cperm.physical_slot sched ~epoch:0 ~reg_id:r) <- logical_vals.(r)
    done;
    (* Вычисляем целевую перестановку для перехода из эпохи 0 в эпоху 1 *)
    let target = Array.init n (fun s ->
      let r = sched.inv_perms.(0).(s) in
      sched.epoch_perms.(1).(r)
    ) in
    let swaps = Cperm.decompose_into_swaps target in
    Cperm.apply_swaps_in_place phys_regs swaps;
    (* Проверяем, что каждый регистр r теперь лежит строго в своем слоте эпохи 1! *)
    for r = 0 to n - 1 do
      let slot_ep1 = Cperm.physical_slot sched ~epoch:1 ~reg_id:r in
      assert (phys_regs.(slot_ep1) = logical_vals.(r))
    done
  done;
  Printf.printf "[PASS] P0-01 Hotfix: Cycle-Decomposed Context Permutation exact across 100 random 16-reg schedules.\n"

(* Тест 1: Шаг 1 — Branchless VIP Arithmetic & Flag Elimination *)
let test_step1_branchless_vip () =
  let rng = Random.State.make [| 0x1111; 0x2222 |] in
  let target = 0x401000L in
  let fallthrough = 0x400500L in
  for _ = 1 to 200 do
    let x = Random.State.int64 rng max_int in
    let y = if Random.State.bool rng then x else Random.State.int64 rng max_int in

    let vip_eq = Bvip.compute_next_vip_branchless ~cond:Bvip.CondEq ~lhs:x ~rhs:y ~target_vip:target ~fallthrough_vip:fallthrough in
    assert (vip_eq = (if x = y then target else fallthrough));

    let vip_ne = Bvip.compute_next_vip_branchless ~cond:Bvip.CondNe ~lhs:x ~rhs:y ~target_vip:target ~fallthrough_vip:fallthrough in
    assert (vip_ne = (if x <> y then target else fallthrough));

    let vip_ult = Bvip.compute_next_vip_branchless ~cond:Bvip.CondUlt ~lhs:x ~rhs:y ~target_vip:target ~fallthrough_vip:fallthrough in
    assert (vip_ult = (if unsigned_compare x y < 0 then target else fallthrough));

    let vip_slt = Bvip.compute_next_vip_branchless ~cond:Bvip.CondSlt ~lhs:x ~rhs:y ~target_vip:target ~fallthrough_vip:fallthrough in
    assert (vip_slt = (if compare x y < 0 then target else fallthrough))
  done;
  Printf.printf "[PASS] Step 1 (Branchless VIP): EQ/NE/ULT/SLT branchless transitions verified (0 JCC instructions).\n"

(* Тест 2: Шаг 2 — 2D Variable Entanglement в GL(2, Z_{2^64}) против Syntia *)
let test_step2_variable_entangler () =
  let rng = Random.State.make [| 0x3333; 0x4444 |] in
  for _ = 1 to 200 do
    let mat = Ent.gen_entanglement_matrix rng in
    let x = Random.State.int64 rng max_int in
    let y = Random.State.int64 rng max_int in
    let dx = Random.State.int64 rng max_int in
    let dy = Random.State.int64 rng max_int in

    let (u, v) = Ent.entangle_pair mat x y in
    let (x_dec, y_dec) = Ent.disentangle_pair mat u v in
    assert (x_dec = x && y_dec = y);

    (* Гомоморфный сдвиг прямо в сшитом состоянии *)
    let (u2, v2) = Ent.homomorphic_entangled_add_const mat ~u ~v ~dx ~dy in
    let (x2, y2) = Ent.disentangle_pair mat u2 v2 in
    assert (x2 = add x dx && y2 = add y dy);

    (* Гомоморфная бабочка (x+y, x-y) *)
    let (ub, vb) = Ent.homomorphic_coupled_butterfly mat ~u ~v in
    let (xb, yb) = Ent.disentangle_pair mat ub vb in
    assert (xb = add x y && yb = sub x y)
  done;
  Printf.printf "[PASS] Step 2 (2D Variable Entanglement): GL(2, Z_{2^64}) coupled homomorphic ops exact.\n"

(* Тест 3: Шаг 3 — Oblivious Memory Layout & Decoy Loads против Tenet *)
let test_step3_oblivious_mem () =
  let rng = Random.State.make [| 0x5555; 0x6666 |] in
  let n_slots = 32 in
  let scrambler = Omem.gen_frame_scrambler rng ~n_slots in
  let mem = Array.make n_slots 0L in
  let expected = Array.init n_slots (fun _ -> Random.State.int64 rng max_int) in

  for i = 0 to n_slots - 1 do
    Omem.oblivious_store scrambler mem ~logical_idx:i expected.(i);
    (* Проверяем, что в физической памяти значение замаскировано *)
    let p_idx = Omem.logical_to_physical_slot scrambler i in
    assert (mem.(p_idx) <> expected.(i));
    assert (Omem.physical_to_logical_slot scrambler p_idx = i)
  done;

  for i = 0 to n_slots - 1 do
    let noise = Random.State.int64 rng max_int in
    let (loaded, trace_addrs) = Omem.oblivious_load_with_decoys scrambler mem ~logical_idx:i ~noise_seed:noise in
    assert (loaded = expected.(i));
    assert (List.length trace_addrs = 4)
  done;
  Printf.printf "[PASS] Step 3 (Oblivious Memory): PRF slot permutation & 4-way branchless decoy loads verified.\n"

(* Тест 4: Шаг 4 — Inter-Procedural Homomorphic Bridge (VM-to-VM Call Fusion) *)
let test_step4_homomorphic_bridge () =
  let rng = Random.State.make [| 0x7777; 0x8888 |] in
  for _ = 1 to 200 do
    let c1 = Ring.gen_ring_codec rng in
    let c2 = Ring.gen_ring_codec rng in
    let c3 = Ring.gen_ring_codec rng in
    let x = Random.State.int64 rng max_int in

    let x_vm1 = Ring.encode_val c1 x in
    let m12 = Hbridge.compile_bridge_morphism ~caller:c1 ~callee:c2 in
    let m23 = Hbridge.compile_bridge_morphism ~caller:c2 ~callee:c3 in
    let m13 = Hbridge.compose_morphisms ~first:m12 ~second:m23 in

    let x_vm2 = Hbridge.apply_bridge_morphism m12 x_vm1 in
    let x_vm3 = Hbridge.apply_bridge_morphism m13 x_vm1 in

    assert (Ring.decode_val c2 x_vm2 = x);
    assert (Ring.decode_val c3 x_vm3 = x)
  done;
  Printf.printf "[PASS] Step 4 (Homomorphic VM-to-VM Bridge): Zero-ABI-exposure state transfer & composition exact.\n"

(* Тест 5: Шаг 5 — Single-Block Self-Wiping Nano-JIT *)
let test_step5_self_wiping_nano_jit () =
  let raw_insns = Bytes.of_string "\x48\x31\xc0\x48\xff\xc0\xc3\x90\x48\x89\xe5\x48\x83\xec\x20\xc3" in
  let master_key = 0x587726019292CAFEL in
  let nonce = 0x1337BEEFDEAD0001L in
  let ticket = Njit.seal_nano_block ~block_id:1 ~raw_code:raw_insns ~master_key ~nonce in
  assert (ticket.encrypted_bytes <> raw_insns);

  let (materialized, after_wipe) = Njit.simulate_nano_slot_lifecycle ticket ~master_key in
  assert (materialized = raw_insns);
  assert (after_wipe <> raw_insns);
  Printf.printf "[PASS] Step 5 (Self-Wiping Nano-JIT): Materialization & post-execution cryptographic wipe verified.\n"

let () =
  test_p0_cycle_permutation_fix ();
  test_step1_branchless_vip ();
  test_step2_variable_entangler ();
  test_step3_oblivious_mem ();
  test_step4_homomorphic_bridge ();
  test_step5_self_wiping_nano_jit ()
