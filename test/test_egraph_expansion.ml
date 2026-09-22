open Vm_ir
open Mba_engine
open Vm_eval

(** Tests for [Egraph] — Scrambler-style Equality Expansion (arXiv:2603.03624):
    rules are identities by construction, so every expanded expression must be
    [Mba.eval]-equivalent to the original, grow in complexity, stay
    deterministic per seed, and stay polymorphic across seeds. *)

let eval2 x y e =
  Mba.eval (fun v -> if v = "a" then x else if v = "b" then y else 0L) e

let vectors =
  [| (0L, 0L); (0L, -1L); (-1L, 0L); (-1L, -1L);
     (Int64.min_int, Int64.max_int); (Int64.max_int, Int64.min_int);
     (Int64.max_int, 1L); (1L, Int64.max_int);
     (0x5555555555555555L, -0x5555555555555556L);
     (-0x5555555555555556L, 0x5555555555555555L);
     (0x0F0F0F0F0F0F0F0FL, 0xF0F0F0F0F0F0F0F0L);
     (0x123456789ABCDEFL, -0x123456789ABCDEFL) |]

let test_config =
  { Egraph.node_limit = 400; time_budget_s = 1.0; iter_limit = 16 }

let base_exprs =
  [ ("add", Mba.Add (Mba.Var "a", Mba.Var "b"), Int64.add);
    ("sub", Mba.Sub (Mba.Var "a", Mba.Var "b"), Int64.sub);
    ("xor", Mba.Xor (Mba.Var "a", Mba.Var "b"), Int64.logxor);
    ("and", Mba.And (Mba.Var "a", Mba.Var "b"), Int64.logand);
    ("or", Mba.Or (Mba.Var "a", Mba.Var "b"), Int64.logor);
    ("mul", Mba.Mul (Mba.Var "a", Mba.Var "b"), Int64.mul);
    ("not", Mba.Not (Mba.Var "a"), fun x _ -> Int64.lognot x);
    ("neg", Mba.Neg (Mba.Var "a"), fun x _ -> Int64.neg x) ]

let test_rule_verification () =
  let rng = Random.State.make [| 0xC0FFEE |] in
  Alcotest.(check bool) "all rules are identities over Z_2^64"
    true (Egraph.verify_rules ~rng ~trials:240);
  Alcotest.(check int) "rule corpus size" 24 Egraph.rule_count

let test_expansion_equivalence () =
  List.iter
    (fun (name, e, ref_fn) ->
      for seed = 1 to 5 do
        let rng = Random.State.make [| seed * 7919 + 13 |] in
        let e' = Egraph.expand ~rng ~config:test_config e in
        Array.iter
          (fun (x, y) ->
            Alcotest.(check int64)
              (Printf.sprintf "%s seed=%d edge (%Ld,%Ld)" name seed x y)
              (ref_fn x y) (eval2 x y e'))
          vectors;
        (* Randomized assignments, including the degenerate x = y case. *)
        let vrng = Random.State.make [| seed * 31 |] in
        for _ = 1 to 40 do
          let x = Random.State.int64 vrng Int64.max_int in
          let y =
            if Random.State.bool vrng then x
            else Random.State.int64 vrng Int64.max_int
          in
          let x = if Random.State.bool vrng then Int64.neg x else x in
          let y = if Random.State.bool vrng then Int64.neg y else y in
          Alcotest.(check int64)
            (Printf.sprintf "%s seed=%d random (%Ld,%Ld)" name seed x y)
            (ref_fn x y) (eval2 x y e')
        done
      done)
    base_exprs

let test_expansion_grows () =
  let e = Mba.Xor (Mba.Var "a", Mba.Var "b") in
  let rng = Random.State.make [| 4242 |] in
  let e', stats = Egraph.expand_full ~rng ~config:test_config e in
  Printf.eprintf
    "Egraph expansion: size %d -> %d, alternation %d -> %d (nodes=%d classes=%d unions=%d iters=%d)\n"
    (Egraph.ast_size e) (Egraph.ast_size e')
    (Egraph.alternation e) (Egraph.alternation e')
    stats.Egraph.nodes stats.Egraph.classes stats.Egraph.unions
    stats.Egraph.iterations;
  Alcotest.(check bool) "expanded AST is strictly larger"
    (Egraph.ast_size e' > Egraph.ast_size e) true;
  Alcotest.(check bool) "alternation is non-decreasing"
    (Egraph.alternation e' >= Egraph.alternation e) true

let test_determinism () =
  let e = Mba.Add (Mba.Var "a", Mba.Var "b") in
  let run () =
    let rng = Random.State.make [| 31337 |] in
    Mba.to_string (Egraph.expand ~rng ~config:test_config e)
  in
  Alcotest.(check string) "same seed yields identical expansion" (run ()) (run ())

let test_polymorphism () =
  let e = Mba.Sub (Mba.Var "a", Mba.Var "b") in
  let outputs =
    List.init 12 (fun i ->
        let rng = Random.State.make [| 1000 + i * 37 |] in
        Mba.to_string (Egraph.expand ~rng ~config:test_config e))
  in
  let distinct = List.sort_uniq compare outputs in
  Alcotest.(check bool) "at least 4 distinct expansions across 12 seeds"
    (List.length distinct >= 4) true

let test_budget_respected () =
  let rng = Random.State.make [| 2718 |] in
  let _, st =
    Egraph.expand_full ~rng ~config:test_config (Mba.Mul (Mba.Var "a", Mba.Var "b"))
  in
  Alcotest.(check bool) "iterations within limit"
    (st.Egraph.iterations <= test_config.Egraph.iter_limit) true;
  Alcotest.(check bool) "congruence closure actually merged classes"
    (st.Egraph.unions > 0) true;
  Alcotest.(check bool) "graph grew beyond the root" (st.Egraph.nodes > 3) true;
  Alcotest.(check bool) "extracted expression is non-trivial"
    (st.Egraph.extracted_size > 1) true

let test_vm_roundtrip () =
  let rng = Random.State.make [| 555 |] in
  (* 1. Register operands: rax = rdi + rsi after e-graph expansion. *)
  let instrs =
    Egraph.obfuscate_alu ~rng ~config:test_config ~dst:Register.rax
      ~src1:(Ir.Reg Register.rdi) ~src2:(Ir.Reg Register.rsi) Ir.Add
  in
  Alcotest.(check bool) "expansion lowers to a non-trivial instruction stream"
    (List.length instrs > 5) true;
  let block = Ir.make_block ~id:0 ~label:"egraph_add" ~instrs:(instrs @ [ Ir.Vm_exit ]) in
  let func = Ir.make_func ~name:"egraph_func" ~entry_id:0 ~blocks:[ block ] in
  let state = make_state () in
  set_reg state Register.rdi 25L;
  set_reg state Register.rsi 17L;
  (match run_func state func with
   | Error e -> Alcotest.fail e
   | Ok () ->
       Alcotest.(check int64) "expanded add 25 + 17 = 42" 42L
         (get_reg state Register.rax));
  (* 2. Immediate operands: rax = 0xF0F0 ^ 0x0FF0 = 0xFF00. *)
  let instrs2 =
    Egraph.obfuscate_alu ~rng ~config:test_config ~dst:Register.rax
      ~src1:(Ir.Imm 0xF0F0L) ~src2:(Ir.Imm 0x0FF0L) Ir.Xor
  in
  let block2 = Ir.make_block ~id:0 ~label:"egraph_xor" ~instrs:(instrs2 @ [ Ir.Vm_exit ]) in
  let func2 = Ir.make_func ~name:"egraph_func2" ~entry_id:0 ~blocks:[ block2 ] in
  let state2 = make_state () in
  (match run_func state2 func2 with
   | Error e -> Alcotest.fail e
   | Ok () ->
       Alcotest.(check int64) "expanded xor 0xF0F0 ^ 0x0FF0 = 0xFF00" 0xFF00L
         (get_reg state2 Register.rax))

(** Property: expansion preserves exact 64-bit semantics under random inputs. *)
let prop_egraph_equivalence =
  QCheck.Test.make
    ~name:"egraph_expansion_equivalence_50_seeds"
    ~count:50
    (QCheck.pair QCheck.int64 QCheck.int64)
    (fun (x, y) ->
      let rng =
        Random.State.make [| Int64.to_int (Int64.logxor x y) land 0x3FFFFFFF |]
      in
      let cfg =
        { Egraph.node_limit = 250; time_budget_s = 1.0; iter_limit = 12 }
      in
      let env v = if v = "a" then x else if v = "b" then y else 0L in
      let add' = Egraph.expand ~rng ~config:cfg (Mba.Add (Mba.Var "a", Mba.Var "b")) in
      let xor' = Egraph.expand ~rng ~config:cfg (Mba.Xor (Mba.Var "a", Mba.Var "b")) in
      Mba.eval env add' = Int64.add x y && Mba.eval env xor' = Int64.logxor x y)


(** E2E test: Egraph_cpp_emitter produces valid C++ that clang++ accepts and
    that evaluates correctly for ADD, SUB, XOR, AND, OR on known inputs. *)
let test_egraph_cpp_handler_expansion () =
  let rng = Random.State.make [| 0xE6BEEF |] in
  (* Generate saturated C++ expressions for each op *)
  let add_expr = Native_vm.Egraph_cpp_emitter.egraph_add_rr ~rng in
  let sub_expr = Native_vm.Egraph_cpp_emitter.egraph_sub_rr ~rng in
  let xor_expr = Native_vm.Egraph_cpp_emitter.egraph_xor_rr ~rng in
  let and_expr = Native_vm.Egraph_cpp_emitter.egraph_and_rr ~rng in
  let or_expr  = Native_vm.Egraph_cpp_emitter.egraph_or_rr  ~rng in

  (* All expressions must be non-trivial (egraph expanded, not just "a op b") *)
  Alcotest.(check bool) "add_expr is non-empty"  true (String.length add_expr > 0);
  Alcotest.(check bool) "sub_expr is non-empty"  true (String.length sub_expr > 0);
  Alcotest.(check bool) "xor_expr is non-empty"  true (String.length xor_expr > 0);
  Alcotest.(check bool) "and_expr is non-empty"  true (String.length and_expr > 0);
  Alcotest.(check bool) "or_expr is non-empty"   true (String.length or_expr > 0);

  (* Compile a C++ program that evaluates each expression with fixed inputs
     and checks correctness: a=100, b=37 *)
  let tmp_dir = Filename.temp_file "egraph_cpp_" "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  (try Sys.mkdir tmp_dir 0o755 with _ -> ());

  let cpp_file = Filename.concat tmp_dir "test_egraph_handlers.cpp" in
  let oc = open_out cpp_file in
  (* Replace ctx.get_reg(dst) → a, ctx.get_reg(src) → b for standalone test *)
  let subst_all needle replacement s =
    let nlen = String.length needle and slen = String.length s in
    let buf = Buffer.create (slen * 2) in
    let i = ref 0 in
    while !i <= slen - nlen do
      if String.sub s !i nlen = needle then begin
        Buffer.add_string buf replacement;
        i := !i + nlen
      end else begin
        Buffer.add_char buf s.[!i];
        incr i
      end
    done;
    if !i < slen then Buffer.add_substring buf s !i (slen - !i);
    Buffer.contents buf
  in
  let subst s =
    let s = subst_all "ctx.get_reg(dst)" "a" s in
    let s = subst_all "ctx.get_reg(src)" "b" s in
    s
  in
  let add_c = subst add_expr in
  let sub_c = subst sub_expr in
  let xor_c = subst xor_expr in
  let and_c = subst and_expr in
  let or_c  = subst or_expr  in
  output_string oc (Printf.sprintf {|
#include <stdint.h>
#include <stdio.h>
int main() {
    uint64_t a = 100ULL, b = 37ULL;
    uint64_t r_add = %s;
    uint64_t r_sub = %s;
    uint64_t r_xor = %s;
    uint64_t r_and = %s;
    uint64_t r_or  = %s;
    if (r_add != (a + b)) { printf("[FAIL] ADD: %%llu != %%llu\n", (unsigned long long)r_add, (unsigned long long)(a+b)); return 1; }
    if (r_sub != (a - b)) { printf("[FAIL] SUB: %%llu != %%llu\n", (unsigned long long)r_sub, (unsigned long long)(a-b)); return 2; }
    if (r_xor != (a ^ b)) { printf("[FAIL] XOR: %%llu != %%llu\n", (unsigned long long)r_xor, (unsigned long long)(a^b)); return 3; }
    if (r_and != (a & b)) { printf("[FAIL] AND: %%llu != %%llu\n", (unsigned long long)r_and, (unsigned long long)(a&b)); return 4; }
    if (r_or  != (a | b)) { printf("[FAIL]  OR: %%llu != %%llu\n", (unsigned long long)r_or,  (unsigned long long)(a|b)); return 5; }
    printf("[EGRAPH_HANDLER_OK] ADD=%%llu SUB=%%llu XOR=%%llu AND=%%llu OR=%%llu\n",
           (unsigned long long)r_add, (unsigned long long)r_sub,
           (unsigned long long)r_xor, (unsigned long long)r_and, (unsigned long long)r_or);
    return 0;
}
|} add_c sub_c xor_c and_c or_c);
  close_out oc;

  let bin_path = Filename.concat tmp_dir "test_egraph_handlers" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 %s -o %s 2>&1" cpp_file bin_path in
  let comp_status = Sys.command comp_cmd in
  Alcotest.(check int) "egraph handler C++ compiles under clang++" 0 comp_status;

  let ic = Unix.open_process_in bin_path in
  let out_buf = Buffer.create 128 in
  (try while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  Alcotest.(check bool) "egraph handler binary exits 0" true (status = Unix.WEXITED 0);
  let out = Buffer.contents out_buf in
  let needle = "EGRAPH_HANDLER_OK" in
  let n = String.length needle and h = String.length out in
  let found = ref false in
  for i = 0 to h - n do
    if String.sub out i n = needle then found := true
  done;
  Alcotest.(check bool) "output contains EGRAPH_HANDLER_OK" true !found

let tests = [
  Alcotest.test_case "rule_verification_24_identities" `Quick test_rule_verification;
  Alcotest.test_case "expansion_equivalence_all_ops" `Quick test_expansion_equivalence;
  Alcotest.test_case "expansion_grows_complexity" `Quick test_expansion_grows;
  Alcotest.test_case "determinism_same_seed" `Quick test_determinism;
  Alcotest.test_case "polymorphism_across_seeds" `Quick test_polymorphism;
  Alcotest.test_case "budget_respected" `Quick test_budget_respected;
  Alcotest.test_case "vm_roundtrip_obfuscate_alu" `Quick test_vm_roundtrip;
  Alcotest.test_case "egraph_cpp_handler_expansion_e2e" `Quick test_egraph_cpp_handler_expansion;
  QCheck_alcotest.to_alcotest prop_egraph_equivalence;
]
