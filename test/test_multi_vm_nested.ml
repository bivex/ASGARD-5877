(** Multi-VM Nested Stack Tests:
    Verifies OEIS sequences (A000108, A004001, A005228/A030124, A061775, A287654/A249569),
    Stack_balance_pass well-nestedness, and bisimulation erasure differential. *)

open Alcotest
module NS = Multi_vm.Nested_stack
open Stack_vm
open Stack_ir

let contains_sub (s : string) (sub : string) : bool =
  let n = String.length s and m = String.length sub in
  if m = 0 then true
  else
    let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
    go 0

(* 1. OEIS A000108: Catalan Numbers & Dyck Words *)
let test_catalan_numbers () =
  let expected = [ (0, 1L); (1, 1L); (2, 2L); (3, 5L); (4, 14L); (5, 42L); (6, 132L) ] in
  List.iter
    (fun (n, exp) ->
      check int64 (Printf.sprintf "Catalan C_%d" n) exp (NS.catalan n))
    expected

let test_dyck_word_well_nestedness () =
  check bool "empty is Dyck" true (NS.is_dyck []);
  check bool "() is Dyck" true (NS.is_dyck [ true; false ]);
  check bool "(()) is Dyck" true (NS.is_dyck [ true; true; false; false ]);
  check bool "()() is Dyck" true (NS.is_dyck [ true; false; true; false ]);
  check bool "(()()) is Dyck" true (NS.is_dyck [ true; true; false; true; false; false ]);
  check bool ")( is not Dyck" false (NS.is_dyck [ false; true ]);
  check bool "(( is not Dyck" false (NS.is_dyck [ true; true ]);
  check bool "(() is not Dyck" false (NS.is_dyck [ true; true; false ]);
  check bool "()) is not Dyck" false (NS.is_dyck [ true; false; false ])

let test_dyck_lexicographical_rank () =
  (* Semilength 2: (()) -> 0, ()() -> 1 *)
  check int64 "rank of (())" 0L (NS.dyck_rank [ true; true; false; false ]);
  check int64 "rank of ()()" 1L (NS.dyck_rank [ true; false; true; false ]);
  (* Semilength 3 has 5 Dyck words in lex order:
     ((())), (()()), (())(), ()(()), ()()() *)
  let words_3 = [
    [ true; true; true; false; false; false ]; (* ((())) *)
    [ true; true; false; true; false; false ]; (* (()()) *)
    [ true; true; false; false; true; false ]; (* (())( *)
    [ true; false; true; true; false; false ]; (* ()(()) *)
    [ true; false; true; false; true; false ]; (* ()()() *)
  ] in
  List.iteri
    (fun i w ->
      check int64 (Printf.sprintf "rank of word_3 #%d" i) (Int64.of_int i) (NS.dyck_rank w))
    words_3

(* 2. OEIS A004001: Hofstadter-Conway Tier Dispatch *)
let test_a004001_dispatch () =
  let exp_16 = [| 1; 1; 2; 2; 3; 4; 4; 4; 5; 6; 7; 7; 8; 8; 8; 8 |] in
  let table = NS.precompute_a004001 16 in
  Array.iteri
    (fun i exp ->
      check int (Printf.sprintf "A004001 a(%d)" (i + 1)) exp table.(i))
    exp_16;
  (* Tier dispatch modulo depth *)
  for depth = 2 to 5 do
    for step = 0 to 50 do
      let tier = NS.dispatch_tier ~depth ~step in
      check bool "tier in range" true (tier >= 0 && tier < depth)
    done
  done;
  check int "depth 1 is 0" 0 (NS.dispatch_tier ~depth:1 ~step:42)

(* 3. OEIS A005228 / A030124: Hofstadter Figure-Figure Partition *)
let test_figure_figure_partition () =
  let r_exp = [ 1; 3; 7; 12; 18; 26; 35; 45; 56; 69 ] in
  let s_exp = [ 2; 4; 5; 6; 8; 9; 10; 11; 13; 14 ] in
  let r_act, s_act = NS.figure_figure_lists 10 in
  check (list int) "A005228 R(1..10)" r_exp r_act;
  check (list int) "A030124 S(1..10)" s_exp s_act;
  (* Disjointness check for 64 elements *)
  let r_64, s_64 = NS.figure_figure_lists 64 in
  let r_tbl = Hashtbl.create 64 in
  List.iter (fun x -> Hashtbl.replace r_tbl x true) r_64;
  List.iter
    (fun s ->
      check bool (Printf.sprintf "S=%d not in R" s) false (Hashtbl.mem r_tbl s))
    s_64;
  check bool "is_tier_slot 0 (val=1)" true (NS.is_tier_slot 0);
  check bool "is_tier_slot 1 (val=2)" false (NS.is_tier_slot 1);
  check bool "is_tier_slot 2 (val=3)" true (NS.is_tier_slot 2)

(* 4. OEIS A061775: Matula-Goebel Topology Digest *)
let test_matula_topology_digest () =
  check int "Leaf matula" 1 (NS.matula_number (NS.Leaf 0));
  (* Linear chains: depth 1 -> 1; depth 2 -> 2 (p_1); depth 3 -> 3 (p_2); depth 4 -> 5 (p_3) *)
  check int "Chain depth 1" 1 (NS.matula_number (NS.chain_topology ~depth:1));
  check int "Chain depth 2" 2 (NS.matula_number (NS.chain_topology ~depth:2));
  check int "Chain depth 3" 3 (NS.matula_number (NS.chain_topology ~depth:3));
  check int "Chain depth 4" 5 (NS.matula_number (NS.chain_topology ~depth:4));
  (* Star with 3 leaf children = p_1 * p_1 * p_1 = 2^3 = 8 *)
  let star_3 = NS.Branch (0, [ NS.Leaf 0; NS.Leaf 1; NS.Leaf 2 ]) in
  check int "Star 3 leaves" 8 (NS.matula_number star_3);
  (* Digest properties *)
  let d2 = NS.topology_digest (NS.chain_topology ~depth:2) in
  let d3 = NS.topology_digest (NS.chain_topology ~depth:3) in
  check bool "Different depth -> different digest" true (d2 <> d3);
  let d2_alt_salt = NS.topology_digest ~salt:0x123456789ABCDEF0L (NS.chain_topology ~depth:2) in
  check bool "Different salt -> different digest" true (d2 <> d2_alt_salt)

(* 5. OEIS A287654 / A249569: Meta-Fibonacci Handoff Jitter *)
let test_metafibonacci_jitter () =
  let seed = 0x5877A000108L in
  let seen = Hashtbl.create 16 in
  for step = 0 to 64 do
    let j = NS.handoff_jitter ~seed ~step in
    check bool "jitter in [0, 15]" true (j >= 0 && j <= 15);
    Hashtbl.replace seen j true
  done;
  check bool "jitter hits multiple distinct values" true (Hashtbl.length seen > 4)

(* 6. Stack_balance_pass: check_nesting well-nestedness enforcement *)
let test_stack_balance_nesting () =
  (* Well-nested program *)
  (* Well-nested program *)
  let good_b = {
    id = 0;
    label = "good";
    ops = [
      EnterVM 1;
      PushImm 42L;
      EnterVM 2;
      PushImm 10L;
      ExitVM 2;
      ExitVM 1;
      Exit;
    ];
  } in
  let good_prog = {
    entry_id = 0;
    blocks = (let t = Hashtbl.create 1 in Hashtbl.replace t 0 good_b; t);
    context_slots = 0;
  } in
  check (list string) "good program has 0 nesting errors" [] (Stack_balance_pass.check_nesting good_prog);

  (* Mismatched ExitVM *)
  let mismatch_b = {
    id = 0;
    label = "mismatch";
    ops = [
      EnterVM 1;
      EnterVM 2;
      ExitVM 1; (* expected 2 *)
      ExitVM 2;
      Exit;
    ];
  } in
  let mismatch_prog = {
    entry_id = 0;
    blocks = (let t = Hashtbl.create 1 in Hashtbl.replace t 0 mismatch_b; t);
    context_slots = 0;
  } in
  let errs = Stack_balance_pass.check_nesting mismatch_prog in
  check bool "detected tier mismatch" true (List.exists (fun e -> String.contains e 'm') errs);

  (* Unclosed EnterVM *)
  let unclosed_b = {
    id = 0;
    label = "unclosed";
    ops = [ EnterVM 1; PushImm 42L; Exit ];
  } in
  let unclosed_prog = {
    entry_id = 0;
    blocks = (let t = Hashtbl.create 1 in Hashtbl.replace t 0 unclosed_b; t);
    context_slots = 0;
  } in
  let errs_unclosed = Stack_balance_pass.check_nesting unclosed_prog in
  check bool "detected unclosed EnterVM" true (List.length errs_unclosed > 0)

(* 7. Bisimulation Erasure Differential (Reference vs Nested Execution) *)
let test_bisimulation_erasure () =
  (* Flat program *)
  (* Flat program *)
  let flat_ops = [
    PushImm 100L;
    PushImm 25L;
    Add;
    PushImm 5L;
    Mul;
    PopReg 0;
    Exit;
  ] in
  (* Same program wrapped in well-nested VM brackets at multiple tiers *)
  let nested_ops = [
    EnterVM 1;
    PushImm 100L;
    PushImm 25L;
    EnterVM 2;
    Add;
    ExitVM 2;
    PushImm 5L;
    EnterVM 3;
    Mul;
    ExitVM 3;
    PopReg 0;
    ExitVM 1;
    Exit;
  ] in
  let make_p ops =
    let b = { id = 0; label = "entry"; ops } in
    let tbl = Hashtbl.create 1 in
    Hashtbl.replace tbl 0 b;
    { entry_id = 0; blocks = tbl; context_slots = 1 }
  in
  let flat_prog = make_p flat_ops in
  let nested_prog = make_p nested_ops in
  let flat_state = Stack_eval.run_program flat_prog in
  let nested_state = Stack_eval.run_program nested_prog in
  check bool "flat halted" true flat_state.halted;
  check bool "nested halted" true nested_state.halted;
  check (list int64) "vstack identical" flat_state.vstack nested_state.vstack;
  check int64 "reg 0 identical" (Stack_eval.get_reg flat_state 0) (Stack_eval.get_reg nested_state 0);
  check int64 "expected 625L" 625L (Stack_eval.get_reg nested_state 0)

(* 8. C++ Codegen: verify multi_vm header contains nested namespace *)
let test_cpp_codegen_nested_runtime () =
  let source = Multi_vm.Multi_vm_context_emitter.emit_asgard_multi_vm_source () in
  check bool "contains g_nested_dispatch_a004001" true (contains_sub source "g_nested_dispatch_a004001");
  check bool "contains nested_tier_of_step" true (contains_sub source "nested_tier_of_step");
  check bool "contains g_nested_topology_salt" true (contains_sub source "g_nested_topology_salt");
  check bool "contains nested_topology_digest" true (contains_sub source "nested_topology_digest")

let test_lift_verify_license () =
  let asm = {|
    mov x8, #19524
    movk x8, #18255, lsl #16
    movk x8, #14125, lsl #32
    movk x8, #14391, lsl #48
    cmp x1, x8
    mov x8, #11573
    movk x8, #21060, lsl #16
    movk x8, #18241, lsl #32
    movk x8, #16723, lsl #48
    ccmp x0, x8, #0, eq
    mov w8, #23962
    csel x0, x8, xzr, eq
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error err -> fail ("Failed to lift: " ^ err)
  | Ok func ->
      check bool "has blocks" true (Hashtbl.length func.cfg.blocks >= 1)

let suite = [
  ("Catalan Numbers C_0..C_6", `Quick, test_catalan_numbers);
  ("Dyck Word Well-Nestedness", `Quick, test_dyck_word_well_nestedness);
  ("Dyck Lexicographical Rank", `Quick, test_dyck_lexicographical_rank);
  ("A004001 Hofstadter-Conway Dispatch", `Quick, test_a004001_dispatch);
  ("A005228/A030124 Figure-Figure Partition", `Quick, test_figure_figure_partition);
  ("A061775 Matula-Goebel Topology Digest", `Quick, test_matula_topology_digest);
  ("A287654/A249569 Meta-Fibonacci Jitter", `Quick, test_metafibonacci_jitter);
  ("Stack_balance_pass check_nesting", `Quick, test_stack_balance_nesting);
  ("Bisimulation Erasure Differential", `Quick, test_bisimulation_erasure);
  ("C++ Codegen Nested Runtime EDSL", `Quick, test_cpp_codegen_nested_runtime);
  ("Lift verify_license", `Quick, test_lift_verify_license);
]
